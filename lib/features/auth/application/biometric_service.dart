import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

import '../domain/biometric_texts.dart';

/// O resultado do pedido de digital.
///
/// `lockedOut` existe à parte porque, depois de várias digitais erradas, o
/// Android recusa a biometria por um tempo (ou até o celular ser desbloqueado
/// pelo PIN): tratar isso como cancelamento deixava a tela sem explicação e o
/// botão "tentar de novo" sem efeito.
enum BiometricConfirmation { confirmed, notConfirmed, lockedOut }

/// O plugin nativo nunca e chamado na Web.
class BiometricService {
  BiometricService(this._auth);

  final LocalAuthentication _auth;

  Future<bool> get available async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<BiometricConfirmation> confirm() async {
    if (!await available) return BiometricConfirmation.notConfirmed;
    try {
      final ok = await _auth.authenticate(
        localizedReason: BiometricTexts.systemReason,
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: BiometricTexts.systemTitle,
            signInHint: BiometricTexts.systemHint,
            cancelButton: BiometricTexts.systemCancel,
          ),
        ],
        // Só digital/rosto: o PIN do celular abriria o app para qualquer um
        // que o conheça.
        biometricOnly: true,
        // Abrir o app não é pagamento: sem isto o Android pede um toque em
        // "Confirmar" depois de reconhecer o rosto.
        sensitiveTransaction: false,
        // O pedido sobrevive a uma ida rápida ao segundo plano.
        persistAcrossBackgrounding: true,
      );
      return ok
          ? BiometricConfirmation.confirmed
          : BiometricConfirmation.notConfirmed;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout =>
          BiometricConfirmation.lockedOut,
        _ => BiometricConfirmation.notConfirmed,
      };
    } catch (_) {
      // Cancelamento, remoção de digitais e indisponibilidade seguem todos
      // para o login por senha.
      return BiometricConfirmation.notConfirmed;
    }
  }
}

final biometricServiceProvider = Provider<BiometricService>(
  (_) => BiometricService(LocalAuthentication()),
);

/// Se o aparelho oferece biometria. A tela decide por aqui se a linha existe:
/// um [AppGroup] desenha divisor antes de cada filho, inclusive de um vazio.
final biometricsAvailableProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(biometricServiceProvider).available,
);
