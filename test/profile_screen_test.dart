import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/core/storage/shared_preferences_provider.dart';
import 'package:louvor_app/core/theme/theme_mode_controller.dart';
import 'package:louvor_app/features/auth/application/auth_controller.dart';
import 'package:louvor_app/features/auth/domain/auth_models.dart';
import 'package:louvor_app/features/profile/presentation/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('mostra nome, e-mail e botao sair', (tester) async {
    await _pumpPerfil(tester);

    expect(find.text('Samuel'), findsWidgets);
    expect(find.text('samuel@teste.com'), findsOneWidget);
    expect(find.text('Meus dados'), findsOneWidget);
    expect(find.text('Alterar senha'), findsOneWidget);

    // O seletor de tema empurrou "Sair" para fora da viewport padrao do
    // teste; ListView so monta o que esta visivel.
    await tester.scrollUntilVisible(
      find.text('Sair da conta'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Sair da conta'), findsOneWidget);
  });

  testWidgets('os assistentes de IA ficam em Segurança, depois da senha',
      (tester) async {
    await _pumpPerfil(tester);

    expect(find.text('Assistentes de IA'), findsOneWidget);
    expect(find.text('Claude e outros, só para consulta'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Alterar senha')).dy,
      lessThan(tester.getTopLeft(find.text('Assistentes de IA')).dy),
    );
  });

  testWidgets('a Ajuda fica no Perfil, junto do diagnóstico', (tester) async {
    await _pumpPerfil(tester);

    await tester.scrollUntilVisible(
      find.text('Ajuda'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Ajuda'), findsOneWidget);
    expect(
      find.text('Conhecer o Pauta e perguntas frequentes'),
      findsOneWidget,
    );
  });

  /// O seletor Claro/Escuro/Sistema era um `SegmentedButton`, e num celular
  /// estreito ele quebrava o rótulo em duas linhas dentro do segmento. O que
  /// se protege agora é o contrário disso: as três opções continuam inteiras e
  /// à vista, sem estouro, na faixa de largura em que o app de fato é usado --
  /// e com a fonte do sistema aumentada, que é o segundo eixo do problema.
  group('o seletor de tema em telas estreitas', () {
    for (final width in [320.0, 360.0, 375.0, 414.0, 768.0]) {
      for (final scale in [1.0, 1.3, 1.6]) {
        testWidgets('cabe em ${width.toInt()}px a ${scale}x', (tester) async {
          // Viewport alta de propósito: o que está sob teste é a **largura**,
          // e com a lista virtualizada o cartão de tema sairia de cena por
          // falta de altura, não por falta de espaço lateral.
          await _pumpPerfil(
            tester,
            size: Size(width, 2400),
            textScale: scale,
          );

          expect(tester.takeException(), isNull);
          // Nenhuma das três pode sumir: "Sistema" é o padrão, e é a mais
          // comprida -- é ela que rolava para fora quando a barra rolava.
          for (final rotulo in ['Claro', 'Escuro', 'Sistema']) {
            expect(find.text(rotulo), findsOneWidget, reason: rotulo);
          }
        });
      }
    }

    testWidgets('tocar numa opção troca o tema do aparelho', (tester) async {
      await _pumpPerfil(tester, size: const Size(360, 2400));

      await tester.tap(find.text('Escuro'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ProfileScreen)),
      );
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });
  });
}

Future<void> _pumpPerfil(
  WidgetTester tester, {
  Size size = const Size(800, 1200),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // O seletor de tema do perfil le a preferencia do aparelho.
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authControllerProvider.overrideWith(
          (ref) => FakeAuthController(
            ref,
            AuthState.signedIn(
              const AuthUser(
                id: '1',
                name: 'Samuel',
                email: 'samuel@teste.com',
                mustChangePassword: false,
              ),
              const [
                TeamSummary(
                  membershipId: 'm1',
                  teamId: 't1',
                  name: 'Ministerio de Louvor',
                  role: 'OWNER',
                  displayName: 'Samuel',
                ),
              ],
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const ProfileScreen(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class FakeAuthController extends AuthController {
  FakeAuthController(super.ref, this._initial);

  final AuthState _initial;

  @override
  Future<void> bootstrap() async {
    state = _initial;
  }
}
