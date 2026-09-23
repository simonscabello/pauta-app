import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/push/push_service.dart';
import '../../../core/storage/read_cache.dart';
import '../../../core/storage/shared_preferences_provider.dart';
import '../../../core/storage/token_storage.dart';
import '../../../shared/domain/person_fields.dart';
import '../data/auth_repository.dart';
import '../domain/auth_models.dart';
import 'biometric_service.dart';

enum BiometricUnlock { success, cancelled, offline, expired }

enum AuthStatus {
  /// Ainda verificando se ha sessao salva -- estado da splash.
  unknown,
  locked,
  unauthenticated,

  /// Autenticado, mas obrigado a trocar a senha antes de usar o app
  /// (senha redefinida pelo líder -- regra 27).
  mustChangePassword,
  authenticated,
}

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.teams = const [],
  });

  const AuthState.unknown() : this(status: AuthStatus.unknown);
  const AuthState.signedOut() : this(status: AuthStatus.unauthenticated);

  final AuthStatus status;
  final AuthUser? user;
  final List<TeamSummary> teams;

  factory AuthState.signedIn(
    AuthUser user, [
    List<TeamSummary> teams = const [],
  ]) {
    return AuthState(
      status: user.mustChangePassword
          ? AuthStatus.mustChangePassword
          : AuthStatus.authenticated,
      user: user,
      teams: teams,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(const AuthState.unknown()) {
    _ref.listen<int>(sessionExpiredProvider, (_, __) => _signOutLocally());
    bootstrap();
  }

  final Ref _ref;

  AuthRepository get _repository => _ref.read(authRepositoryProvider);
  TokenStorage get _storage => _ref.read(tokenStorageProvider);
  BiometricService get _biometrics => _ref.read(biometricServiceProvider);

  /// Chamado no start: se ha token salvo, valida com o servidor.
  /// O interceptor renova a sessao sozinho se o access token tiver expirado.
  Future<void> bootstrap() async {
    // Sem timeout de proposito: um timeout curto aqui derruba a sessao de quem
    // esta em aparelho lento (aconteceu -- 5s não bastavam no emulador). Uma
    // falha real do armazenamento vira excecao e cai no catch; esperar mais e
    // melhor do que deslogar quem tinha sessao valida.
    String? refreshToken;
    try {
      refreshToken = await _storage.readRefreshToken();
    } catch (_) {
      refreshToken = null;
    }

    if (refreshToken == null) {
      await _storage.disableBiometrics();
      state = const AuthState.signedOut();
      return;
    }

    final biometricUserId = await _storage.readBiometricUserId();
    if (biometricUserId != null) {
      state = const AuthState(status: AuthStatus.locked);
      return;
    }

    try {
      final me = await _repository.me();
      state = AuthState.signedIn(me.user, me.teams);
    } on ApiException catch (e) {
      // Sem rede a sessao continua guardada: a proxima abertura a restaura.
      if (e.statusCode == 401) await _storage.clear();
      state = const AuthState.signedOut();
    }
  }

  Future<void> login({
    required String email,
    required String password,
    Future<void> Function(AuthUser user)? onAuthenticated,
  }) async {
    final session = await _repository.login(email: email, password: password);
    // Quem entra pela senha com uma sessao ainda guardada (tela bloqueada pela
    // biometria, ou sem rede na abertura) deixaria o refresh antigo valido no
    // servidor por semanas. Revoga antes de sobrescrever.
    final previous = await _storage.readRefreshToken();
    if (previous != null) await _repository.logout(previous);
    final biometricUserId = await _storage.readBiometricUserId();
    if (biometricUserId != null && biometricUserId != session.user.id) {
      await _storage.disableBiometrics();
    }
    if (onAuthenticated != null) await onAuthenticated(session.user);
    await _applySession(session);
  }

  Future<bool> get biometricsAvailable => _biometrics.available;

  Future<bool> get biometricsEnabled async =>
      state.user != null &&
      await _storage.readBiometricUserId() == state.user!.id;

  Future<bool> enableBiometrics() async {
    final user = state.user;
    if (user == null || !await _biometrics.confirm()) return false;
    await _storage.enableBiometrics(user.id);
    return true;
  }

  Future<bool> enableBiometricsFor(AuthUser user) async {
    if (!await _biometrics.confirm()) return false;
    await _storage.enableBiometrics(user.id);
    return true;
  }

  Future<void> disableBiometrics() => _storage.disableBiometrics();

  Future<bool> shouldOfferBiometrics(AuthUser user) async {
    return !user.mustChangePassword &&
        await _biometrics.available &&
        await _storage.readBiometricOfferUserId() != user.id &&
        await _storage.readBiometricUserId() != user.id;
  }

  Future<void> markBiometricOffer(AuthUser user) =>
      _storage.markBiometricOffer(user.id);

  /// A biometria so libera a sessao que ja esta guardada: o refresh token e
  /// rotacionado no servidor e so entao o app entra. Nenhuma senha e guardada.
  ///
  /// Cancelar ou falhar a biometria mantem a tela bloqueada, com o login por
  /// senha disponivel. Sem rede tambem: a sessao continua valida para a
  /// proxima tentativa. So a recusa do servidor (ou outra conta) a descarta.
  Future<BiometricUnlock> unlockWithBiometrics() async {
    if (!await _biometrics.confirm()) return BiometricUnlock.cancelled;
    try {
      final old = await _storage.readRefreshToken();
      if (old == null) throw StateError('Sessao ausente');
      final (access, refresh) = await _repository.refresh(old);
      await _storage.save(accessToken: access, refreshToken: refresh);
      final me = await _repository.me();
      final configured = await _storage.readBiometricUserId();
      if (configured != me.user.id) throw StateError('Conta diferente');
      state = AuthState.signedIn(me.user, me.teams);
      return BiometricUnlock.success;
    } on ApiException catch (e) {
      final refused = e.statusCode == 401 || e.statusCode == 400;
      if (!refused) return BiometricUnlock.offline;
      await _signOutLocally();
      return BiometricUnlock.expired;
    } catch (_) {
      await _signOutLocally();
      return BiometricUnlock.expired;
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final session = await _repository.register(
      name: name,
      email: email,
      password: password,
    );
    await _applySession(session);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final session = await _repository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    await _applySession(session);
  }

  /// Edicao dos proprios dados. Depois de mudar o nome recarrega as equipes:
  /// o backend acerta junto o nome exibido na equipe (quando ninguem o
  /// personalizou), e o menu do app mostra esse nome.
  Future<void> updateProfile({
    String? name,
    String? email,
    Patch<DateTime?>? birthDate,
    Patch<Gender?>? gender,
    bool? pushEnabled,
  }) async {
    final user = await _repository.updateProfile(
      name: name,
      email: email,
      birthDate: birthDate,
      gender: gender,
      pushEnabled: pushEnabled,
    );
    _replaceUser(user);
    if (name != null) {
      unawaited(_loadTeams());
    }
  }

  Future<void> updateAvatar({
    required List<int> bytes,
    required String filename,
  }) async {
    _replaceUser(
      await _repository.uploadAvatar(bytes: bytes, filename: filename),
    );
  }

  Future<void> removeAvatar() async {
    _replaceUser(await _repository.removeAvatar());
  }

  void _replaceUser(AuthUser user) {
    if (mounted) {
      state = AuthState.signedIn(user, state.teams);
    }
  }

  Future<void> logout() async {
    // **Antes de descartar o token de acesso.** O aparelho e do aparelho, nao
    // da conta: sem esta chamada o proximo a entrar neste celular receberia a
    // escala de quem saiu. Depois do `_signOutLocally` a requisicao sairia sem
    // autenticacao e o aparelho ficaria registrado.
    try {
      await _forgetDevice();
      final refreshToken = await _storage.readRefreshToken();
      if (refreshToken != null) await _repository.logout(refreshToken);
    } finally {
      await _signOutLocally();
    }
  }

  Future<AccountDeletionPreview> deletionPreview() =>
      _repository.deletionPreview();

  /// Exclui a conta e sai. Não passa por `_forgetDevice` nem pelo logout do
  /// servidor: a cascata do `DELETE /users/me` já levou os aparelhos e os
  /// refresh tokens. O que sobra é o que mora neste aparelho -- os tokens e
  /// o cache de leitura, que guarda nomes da equipe.
  Future<void> deleteAccount(String password) async {
    await _repository.deleteAccount(password);
    await ReadCache(_ref.read(sharedPreferencesProvider)).clearAll();
    await _signOutLocally();
  }

  /// Esquece este aparelho no servidor. Falhar aqui nao pode segurar a saida:
  /// quem tocou em "sair" precisa sair.
  ///
  /// A sessao que expira sozinha (`_signOutLocally`) **nao** passa por aqui --
  /// o token de acesso ja nao vale, e a chamada voltaria 401. A linha orfa se
  /// resolve na proxima entrada: registrar um token conhecido MOVE o aparelho
  /// para o novo dono.
  Future<void> _forgetDevice() async {
    try {
      final token = await _ref.read(pushServiceProvider).currentToken();
      if (token != null) await _repository.forgetDevice(token);
    } catch (_) {
      // Silencio proposital: ver o comentario acima.
    }
  }

  Future<void> _applySession(Session session) async {
    await _storage.save(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    state = AuthState.signedIn(session.user);

    // Carrega as equipes em segundo plano: a navegacao não precisa esperar.
    if (!session.user.mustChangePassword) {
      unawaited(_loadTeams());
    }
  }

  /// Recarrega usuario e equipes. Chamado depois de criar equipe ou aceitar
  /// convite, para o app saber que o usuario deixou de estar "sem equipe".
  Future<void> reloadTeams() => _loadTeams();

  Future<void> _loadTeams() async {
    try {
      final me = await _repository.me();
      if (mounted) {
        state = AuthState.signedIn(me.user, me.teams);
      }
    } on ApiException {
      // A tela seguinte recarrega quando precisar.
    }
  }

  Future<void> _signOutLocally() async {
    await _storage.clear();
    if (mounted) {
      state = const AuthState.signedOut();
    }
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref);
});
