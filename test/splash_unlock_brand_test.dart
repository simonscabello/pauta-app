import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/core/router/app_router.dart';
import 'package:louvor_app/features/auth/application/auth_controller.dart';
import 'package:louvor_app/features/auth/domain/biometric_texts.dart';
import 'package:louvor_app/features/auth/presentation/unlock_screen.dart';
import 'package:louvor_app/shared/widgets/app_brand_mark.dart';

/// A abertura vira desbloqueio sem a marca sair do lugar: as duas telas usam
/// o mesmo `SplashFrame`, e a rota do desbloqueio entra sem transição.
void main() {
  testWidgets('a marca não se move entre a splash e o pedido de digital',
      (tester) async {
    late _SlowLockedAuthController auth;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => auth = _SlowLockedAuthController(ref),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    );

    // Primeiro frame: a splash, com o estado ainda desconhecido.
    expect(find.byType(UnlockScreen), findsNothing);
    final glyph = tester.getRect(find.byType(AppBrandGlyph));
    final wordmark = tester.getRect(find.text('PAUTA'));

    // A sessão resolve como bloqueada; o pedido de digital fica aberto.
    auth.lock();
    await tester.pump();
    expect(find.byType(UnlockScreen), findsOneWidget);
    // No mesmo frame em que o desbloqueio assume, e não só depois de uma
    // animação: uma transição de página moveria a marca no meio do caminho.
    expect(tester.getRect(find.byType(AppBrandGlyph)), glyph);
    expect(tester.getRect(find.text('PAUTA')), wordmark);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(auth.unlocks, 1);
    expect(tester.getRect(find.byType(AppBrandGlyph)), glyph);
    expect(tester.getRect(find.text('PAUTA')), wordmark);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);

    // Cancelada a digital, as duas saídas aparecem.
    auth.pending.complete(BiometricUnlock.cancelled);
    await tester.pump();
    await tester.pump();
    expect(find.text(BiometricTexts.unlockButton), findsOneWidget);
    expect(find.text(BiometricTexts.usePassword), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('as saídas com erro cabem numa tela baixa', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late _SlowLockedAuthController auth;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => auth = _SlowLockedAuthController(ref),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    );
    auth.lock();
    await tester.pump();
    await tester.pump();
    auth.pending.complete(BiometricUnlock.lockedOut);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(BiometricTexts.unlockLockedOut), findsOneWidget);
  });
}

class _SlowLockedAuthController extends AuthController {
  _SlowLockedAuthController(super.ref);

  final pending = Completer<BiometricUnlock>();
  int unlocks = 0;

  @override
  Future<void> bootstrap() async {}

  void lock() => state = const AuthState(status: AuthStatus.locked);

  @override
  Future<bool> get biometricsAvailable async => true;

  @override
  Future<BiometricUnlock> unlockWithBiometrics() {
    unlocks += 1;
    return pending.future;
  }
}
