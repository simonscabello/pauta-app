import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:louvor_app/core/storage/shared_preferences_provider.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/auth/application/auth_controller.dart';
import 'package:louvor_app/features/auth/domain/auth_models.dart';
import 'package:louvor_app/features/help/domain/help_faq.dart';
import 'package:louvor_app/features/help/presentation/help_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A Central de Ajuda: o tour primeiro, as perguntas embaixo, e cada resposta
/// abrindo e fechando no lugar.
void main() {
  testWidgets('"Conhecer o Pauta" vem antes das perguntas', (tester) async {
    await _pump(tester);

    expect(find.text('Conhecer o Pauta'), findsOneWidget);
    expect(
      find.text(
        'Veja novamente como funcionam as principais áreas do aplicativo.',
      ),
      findsOneWidget,
    );
    expect(find.text('Perguntas frequentes'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Conhecer o Pauta')).dy,
      lessThan(tester.getTopLeft(find.text('Perguntas frequentes')).dy),
    );
  });

  testWidgets('quem lidera ganha o tour do líder e o guia do líder',
      (tester) async {
    await _pump(tester, role: 'OWNER', size: const Size(400, 3000));

    expect(find.text('Conhecer o Pauta, para quem lidera'), findsOneWidget);
    expect(find.text('Guia completo do líder'), findsOneWidget);
    // O do integrante é de todos.
    expect(find.text('Guia do integrante'), findsOneWidget);
  });

  testWidgets('integrante não vê o tour nem o guia do líder', (tester) async {
    await _pump(tester, role: 'MEMBER', size: const Size(400, 3000));

    expect(find.text('Conhecer o Pauta, para quem lidera'), findsNothing);
    expect(find.text('Guia completo do líder'), findsNothing);
    expect(find.text('Guia do integrante'), findsOneWidget);
  });

  testWidgets('a pergunta abre a resposta e fecha de novo', (tester) async {
    await _pump(tester);
    const pergunta = 'Como informo minha disponibilidade?';
    final resposta = find.textContaining('Escolher dias', findRichText: true);

    expect(resposta, findsNothing);

    await tester.tap(find.text(pergunta));
    await tester.pumpAndSettle();
    expect(resposta, findsOneWidget);

    await tester.tap(find.text(pergunta));
    await tester.pumpAndSettle();
    expect(resposta, findsNothing);
  });

  testWidgets('todas as perguntas aparecem, e a tela estreita não transborda',
      (tester) async {
    await _pump(tester, size: const Size(320, 3000));

    for (final entry in helpFaq) {
      expect(find.text(entry.question), findsOneWidget);
      await tester.ensureVisible(find.text(entry.question));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.question));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  test('o realce vira negrito, e só ele', () {
    final span = faqAnswerSpans(
      'Abra **Minha disponibilidade** e toque em **Escolher dias**.',
      bold: const TextStyle(fontWeight: FontWeight.w600),
    );
    final partes = span.children!.cast<TextSpan>();

    expect(partes.map((p) => p.text), [
      'Abra ',
      'Minha disponibilidade',
      ' e toque em ',
      'Escolher dias',
      '.',
    ]);
    expect(partes[1].style?.fontWeight, FontWeight.w600);
    expect(partes[0].style, isNull);
  });

  test('nenhuma resposta fica com realce aberto', () {
    for (final entry in [...helpFaq, ...leaderHelpFaq]) {
      expect(
        '**'.allMatches(entry.answer).length.isEven,
        isTrue,
        reason: entry.question,
      );
    }
  });
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(400, 1600),
  String? role,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/perfil/ajuda',
    routes: [
      GoRoute(path: '/perfil/ajuda', builder: (_, __) => const HelpScreen()),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (role != null)
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(
              ref,
              AuthState.signedIn(
                const AuthUser(
                  id: 'u1',
                  name: 'Samuel',
                  email: 'samuel@teste.com',
                  mustChangePassword: false,
                ),
                [
                  TeamSummary(
                    membershipId: 'm1',
                    teamId: 't1',
                    name: 'Ministério',
                    role: role,
                    displayName: 'Samuel',
                  ),
                ],
              ),
            ),
          ),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, this._initial);

  final AuthState _initial;

  @override
  Future<void> bootstrap() async {
    state = _initial;
  }
}
