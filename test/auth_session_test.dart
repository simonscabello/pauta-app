import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:louvor_app/core/storage/token_storage.dart';
import 'package:louvor_app/features/auth/application/auth_controller.dart';
import 'package:louvor_app/features/auth/application/biometric_service.dart';
import 'package:louvor_app/features/auth/data/auth_repository.dart';
import 'package:louvor_app/features/auth/domain/auth_models.dart';
import 'package:louvor_app/features/auth/domain/biometric_texts.dart';

class MemoryStorage extends FlutterSecureStorage {
  MemoryStorage();

  final values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sessao persiste e logout remove tokens e configuracao biometrica',
      () async {
    final secure = MemoryStorage();
    final storage = TokenStorage(secure);
    await storage.save(accessToken: 'acesso', refreshToken: 'renovacao');
    await storage.enableBiometrics('usuario-a');
    final restored = TokenStorage(secure);
    expect(await restored.readRefreshToken(), 'renovacao');
    expect(await restored.readBiometricUserId(), 'usuario-a');
    await restored.clear();
    expect(await TokenStorage(secure).readRefreshToken(), isNull);
    expect(await restored.readBiometricUserId(), isNull);
  });

  test('refresh antigo nao pode ressuscitar sessao apos logout', () async {
    final storage = TokenStorage(MemoryStorage());
    await storage.save(accessToken: 'a', refreshToken: 'r1');
    await storage.clear();
    expect(
      await storage.saveRotatedIfCurrent(
        previousRefreshToken: 'r1',
        accessToken: 'b',
        refreshToken: 'r2',
      ),
      isFalse,
    );
    expect(await storage.readRefreshToken(), isNull);
  });

  test('plataforma sem biometria nao mostra nem executa autenticacao',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final biometrics = BiometricService(LocalAuthentication());
      expect(await biometrics.available, isFalse);
      expect(await biometrics.confirm(), BiometricConfirmation.notConfirmed);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('confirm() no Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('pede em português, só biometria, sem toque extra no rosto',
        () async {
      final auth = _FakeLocalAuth(result: true);
      expect(
        await BiometricService(auth).confirm(),
        BiometricConfirmation.confirmed,
      );

      expect(auth.localizedReason, BiometricTexts.systemReason);
      expect(auth.biometricOnly, isTrue);
      expect(auth.sensitiveTransaction, isFalse);
      expect(auth.persistAcrossBackgrounding, isTrue);
      final android = auth.messages!.whereType<AndroidAuthMessages>().single;
      expect(android.signInTitle, 'Pauta');
      expect(android.signInHint, 'Confirme que é você');
      expect(android.cancelButton, 'Cancelar');
    });

    test('recusa sem exceção é não confirmada', () async {
      expect(
        await BiometricService(_FakeLocalAuth(result: false)).confirm(),
        BiometricConfirmation.notConfirmed,
      );
    });

    for (final code in [
      LocalAuthExceptionCode.temporaryLockout,
      LocalAuthExceptionCode.biometricLockout,
    ]) {
      test('${code.name} vira lockedOut', () async {
        final auth = _FakeLocalAuth(
          error: LocalAuthException(code: code),
        );
        expect(
          await BiometricService(auth).confirm(),
          BiometricConfirmation.lockedOut,
        );
      });
    }

    for (final error in <Object>[
      const LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
      const LocalAuthException(code: LocalAuthExceptionCode.noBiometricsEnrolled),
      StateError('qualquer outra'),
    ]) {
      test('$error vira notConfirmed', () async {
        expect(
          await BiometricService(_FakeLocalAuth(error: error)).confirm(),
          BiometricConfirmation.notConfirmed,
        );
      });
    }
  });

  group('trava da biometria no login por senha', () {
    Future<(MemoryStorage, ProviderContainer)> lockedSession({
      required bool biometricsAvailable,
      MemoryStorage? secure,
    }) async {
      secure ??= MemoryStorage();
      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(TokenStorage(secure)),
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          biometricServiceProvider.overrideWithValue(
            _FakeBiometrics(available: biometricsAvailable),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(authControllerProvider);
      await _settle();
      return (secure, container);
    }

    Future<MemoryStorage> lockedStorage() async {
      final secure = MemoryStorage();
      final storage = TokenStorage(secure);
      await storage.save(accessToken: 'a', refreshToken: 'r');
      await storage.enableBiometrics(_user.id);
      return secure;
    }

    test('sem biometria no celular, entrar com a mesma conta desliga a trava',
        () async {
      final (secure, container) = await lockedSession(
        biometricsAvailable: false,
        secure: await lockedStorage(),
      );
      expect(container.read(authControllerProvider).status, AuthStatus.locked);

      await container
          .read(authControllerProvider.notifier)
          .login(email: _user.email, password: 'senha');
      await _settle();
      expect(await TokenStorage(secure).readBiometricUserId(), isNull);

      // A próxima abertura não para mais na trava.
      final (_, reopened) =
          await lockedSession(biometricsAvailable: false, secure: secure);
      expect(
        reopened.read(authControllerProvider).status,
        AuthStatus.authenticated,
      );
    });

    test('com biometria no celular, a mesma conta mantém a trava', () async {
      final (secure, container) = await lockedSession(
        biometricsAvailable: true,
        secure: await lockedStorage(),
      );

      await container
          .read(authControllerProvider.notifier)
          .login(email: _user.email, password: 'senha');
      await _settle();
      expect(await TokenStorage(secure).readBiometricUserId(), _user.id);
    });

    test('bloqueio por tentativas mantém a trava e a sessão', () async {
      final (secure, container) = await lockedSession(
        biometricsAvailable: true,
        secure: await lockedStorage(),
      );
      container.read(biometricServiceProvider);
      final biometrics =
          container.read(biometricServiceProvider) as _FakeBiometrics;
      biometrics.result = BiometricConfirmation.lockedOut;

      final result = await container
          .read(authControllerProvider.notifier)
          .unlockWithBiometrics();

      expect(result, BiometricUnlock.lockedOut);
      expect(container.read(authControllerProvider).status, AuthStatus.locked);
      final storage = TokenStorage(secure);
      expect(await storage.readRefreshToken(), 'r');
      expect(await storage.readBiometricUserId(), _user.id);
    });
  });
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const _user = AuthUser(
  id: 'usuario-a',
  name: 'Samuel',
  email: 'samuel@teste.com',
  mustChangePassword: false,
);

class _FakeLocalAuth implements LocalAuthentication {
  _FakeLocalAuth({this.result = false, this.error});

  final bool result;
  final Object? error;

  String? localizedReason;
  Iterable<AuthMessages>? messages;
  bool? biometricOnly;
  bool? sensitiveTransaction;
  bool? persistAcrossBackgrounding;

  @override
  Future<bool> get canCheckBiometrics async => true;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async =>
      [BiometricType.fingerprint];

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<AuthMessages> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    this.localizedReason = localizedReason;
    messages = authMessages;
    this.biometricOnly = biometricOnly;
    this.sensitiveTransaction = sensitiveTransaction;
    this.persistAcrossBackgrounding = persistAcrossBackgrounding;
    if (error != null) throw error!;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBiometrics extends BiometricService {
  _FakeBiometrics({required bool available})
      : _available = available,
        super(_FakeLocalAuth());

  final bool _available;
  BiometricConfirmation result = BiometricConfirmation.notConfirmed;

  @override
  Future<bool> get available async => _available;

  @override
  Future<BiometricConfirmation> confirm() async => result;
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<Session> login({
    required String email,
    required String password,
  }) async =>
      const Session(accessToken: 'a2', refreshToken: 'r2', user: _user);

  @override
  Future<void> logout(String refreshToken) async {}

  @override
  Future<MeResult> me() async => const MeResult(user: _user, teams: []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
