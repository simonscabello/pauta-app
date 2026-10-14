import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/events/data/event_repository.dart';
import '../../features/team/data/team_repository.dart';
import '../../features/update/data/version_repository.dart';
import '../router/app_router.dart';
import 'push_service.dart';

/// Liga o aparelho a conta e o toque no aviso a tela certa.
///
/// Fica **fora** do [PushService] de proposito: o serviço cuida do aparelho, e
/// isto aqui cuida do produto -- registrar o token na entrada, esquece-lo na
/// saida e, no toque, trocar a equipe ativa antes de navegar.
///
/// Plano: docs/superpowers/plans/2026-09-08-notificacoes.md
class PushCoordinator {
  PushCoordinator(this._ref) {
    _ref.listen<AuthState>(
      authControllerProvider,
      (previous, next) {
        final antes = previous?.status == AuthStatus.authenticated;
        final agora = next.status == AuthStatus.authenticated;
        if (!antes && agora) unawaited(_onSignedIn());
      },
      fireImmediately: true,
    );
  }

  final Ref _ref;

  bool _started = false;
  StreamSubscription<String>? _refreshSubscription;
  StreamSubscription<PushTap>? _tapSubscription;

  PushService get _push => _ref.read(pushServiceProvider);

  Future<void> _onSignedIn() async {
    if (_started || !PushService.isSupported) return;
    _started = true;

    await _push.init();
    if (!_push.isReady) return;

    // Na Web, assinar exige a chave do servidor. Sem ela (servidor sem Web
    // Push), o navegador nao assina e nada mais acontece aqui.
    if (_push.platform == 'web') {
      try {
        _push.setWebPushKey(await _ref.read(authRepositoryProvider).webPushKey());
      } catch (error) {
        debugPrint('Falha ao buscar a chave do aviso no navegador: $error');
      }
    }

    await registerDevice();

    _refreshSubscription ??= _push.onTokenRefresh.listen((token) {
      unawaited(_send(token));
    });
    _tapSubscription ??= _push.onTap.listen(_open);

    // O aviso que abriu o app com ele fechado. Tratado **depois** de a sessao
    // existir: sem equipe carregada nao ha como trocar a equipe ativa, e o
    // roteador mandaria a pessoa para a agenda da equipe errada.
    final inicial = await _push.initialTap();
    if (inicial != null) _open(inicial);
  }

  /// Registra este aparelho na conta atual. Publico porque o interruptor do
  /// perfil o chama ao ser religado.
  Future<void> registerDevice() async {
    final token = await _push.currentToken();
    if (token != null) await _send(token);
  }

  Future<void> _send(String token) async {
    try {
      await _ref
          .read(authRepositoryProvider)
          .registerDevice(token: token, platform: _push.platform);
    } catch (error) {
      // Sem aviso e melhor do que sem app: a proxima entrada tenta de novo.
      debugPrint('Falha ao registrar o aparelho: $error');
    }
  }

  void _open(PushTap tap) {
    // **Trocar a equipe antes de navegar.** Quem serve em duas equipes tem uma
    // equipe ativa guardada no aparelho; abrir a escala da outra sem trocar
    // mostraria a agenda errada. `select` ignora equipe da qual a pessoa nao
    // faz mais parte, que e o comportamento certo para um aviso antigo.
    if (tap.teamId.isNotEmpty) {
      unawaited(_ref.read(activeTeamIdProvider.notifier).select(tap.teamId));
    }

    // O aviso existe porque **algo mudou**: mostrar o que esta em cache seria
    // mostrar exatamente a versao que deixou de valer.
    final eventId = _eventIdOf(tap.route);
    if (eventId != null) _ref.invalidate(eventProvider(eventId));

    // Pelo mesmo motivo: o aviso de atualização só aparece na Home se a
    // consulta a /version for refeita -- a da sessão é de antes da versão sair.
    if (tap.kind == 'APP_UPDATE_AVAILABLE') _ref.invalidate(appUpdateProvider);

    _ref.read(routerProvider).go(tap.route);
  }

  /// "/agenda/<id>" e "/agenda/<id>/escalar" -> o id. Qualquer outra rota nao
  /// tem escala para recarregar.
  static String? _eventIdOf(String route) {
    final partes = route.split('/').where((p) => p.isNotEmpty).toList();
    if (partes.length < 2 || partes.first != 'agenda') return null;
    final id = partes[1];
    return id == 'novo' ? null : id;
  }
}

/// Observado pelo widget raiz para existir durante a vida do app.
final pushCoordinatorProvider = Provider<PushCoordinator>((ref) {
  return PushCoordinator(ref);
});
