import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/core/router/app_router.dart';
import 'package:louvor_app/features/auth/application/auth_controller.dart';
import 'package:louvor_app/features/auth/domain/biometric_texts.dart';

/// Com a sessão guardada e a biometria ligada, o fundo do pedido de digital é
/// a tela de desbloqueio, e não o formulário de login -- que fazia parecer que
/// o app tinha deslogado.
void main() {
  testWidgets('sessão bloqueada abre o desbloqueio e já pede a digital',
      (tester) async {
    final auth = await _pumpApp(tester, BiometricUnlock.cancelled);

    expect(auth.unlocks, 1);
    expect(find.text('PAUTA'), findsOneWidget);
    // Nada de formulário por trás do pedido.
    expect(find.widgetWithText(TextFormField, 'E-mail'), findsNothing);
    // Cancelado, as duas saídas aparecem.
    expect(find.text('Confirme que é você para continuar.'), findsOneWidget);
    expect(find.text('Entrar com biometria'), findsOneWidget);
    expect(find.text('Usar e-mail e senha'), findsOneWidget);
  });

  testWidgets('tentar de novo pede a digital outra vez', (tester) async {
    final auth = await _pumpApp(tester, BiometricUnlock.cancelled);

    await tester.tap(find.text('Entrar com biometria'));
    await tester.pumpAndSettle();
    expect(auth.unlocks, 2);
  });

  testWidgets('"Usar e-mail e senha" leva ao login sem pedir a digital de novo',
      (tester) async {
    final auth = await _pumpApp(tester, BiometricUnlock.cancelled);

    await tester.tap(find.text('Usar e-mail e senha'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'E-mail'), findsOneWidget);
    expect(auth.unlocks, 1);
    // O login continua oferecendo a biometria enquanto a sessão existir.
    expect(find.text('Entrar com biometria'), findsOneWidget);
  });

  testWidgets('sem rede, o desbloqueio diz o motivo e fica', (tester) async {
    await _pumpApp(tester, BiometricUnlock.offline);

    expect(
      find.textContaining('Não foi possível conectar ao servidor'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'E-mail'), findsNothing);
  });

  testWidgets('bloqueio por tentativas explica e mantém as duas saídas',
      (tester) async {
    final auth = await _pumpApp(tester, BiometricUnlock.lockedOut);

    expect(find.text(BiometricTexts.unlockLockedOut), findsOneWidget);
    expect(find.text(BiometricTexts.unlockButton), findsOneWidget);
    expect(find.text(BiometricTexts.usePassword), findsOneWidget);
    // Continua no desbloqueio: a sessão não foi descartada.
    expect(auth.state.status, AuthStatus.locked);
    expect(find.widgetWithText(TextFormField, 'E-mail'), findsNothing);
  });

  testWidgets('sessão expirada vai para o login com o motivo', (tester) async {
    await _pumpApp(tester, BiometricUnlock.expired);

    expect(find.widgetWithText(TextFormField, 'E-mail'), findsOneWidget);
    expect(
      find.text('Sua sessão expirou. Entre com seu e-mail e senha.'),
      findsOneWidget,
    );
  });
}

Future<_LockedAuthController> _pumpApp(
  WidgetTester tester,
  BiometricUnlock result,
) async {
  late _LockedAuthController auth;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => auth = _LockedAuthController(ref, result),
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          routerConfig: ref.watch(routerProvider),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

class _LockedAuthController extends AuthController {
  _LockedAuthController(super.ref, this._result);

  final BiometricUnlock _result;
  int unlocks = 0;

  @override
  Future<void> bootstrap() async {
    state = const AuthState(status: AuthStatus.locked);
  }

  @override
  Future<bool> get biometricsAvailable async => true;

  @override
  Future<BiometricUnlock> unlockWithBiometrics() async {
    unlocks += 1;
    // Como o controller de verdade: recusada pelo servidor, a sessão cai.
    if (_result == BiometricUnlock.expired) {
      state = const AuthState.signedOut();
    }
    return _result;
  }
}
