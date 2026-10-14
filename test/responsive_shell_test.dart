import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:louvor_app/core/responsive/app_breakpoints.dart';
import 'package:louvor_app/core/storage/shared_preferences_provider.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/auth/application/auth_controller.dart';
import 'package:louvor_app/features/auth/domain/auth_models.dart';
import 'package:louvor_app/features/events/presentation/main_shell.dart';
import 'package:louvor_app/shared/widgets/app_side_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A casca tem **duas** navegações e uma regra só para escolher entre elas: a
/// largura da janela. Estes testes travam essa regra nos dois sentidos.
///
/// O sentido que mais importa é o de baixo: a versão Android existia antes da
/// Web e não pode ter mudado. Em 375px a barra inferior precisa continuar
/// exatamente onde estava, e a barra lateral não pode existir.
///
/// A Home acrescentou uma quarta aba **na frente** das três, e é a única coisa
/// que mudou ali: Agenda, Equipe e Perfil continuam sendo abas, na mesma ordem
/// relativa. Os testes abaixo travam isso pelo rótulo e pelo índice, que é o
/// que o `context.go` da barra usa para escolher a rota.
void main() {
  group('AppSideNav.selectedRouteFor', () {
    const sections = [
      AppNavSection(
        destinations: [
          AppNavDestination(
            icon: Icons.calendar_today_outlined,
            selectedIcon: Icons.calendar_today_rounded,
            label: 'Agenda',
            route: '/agenda',
          ),
          AppNavDestination(
            icon: Icons.groups_outlined,
            selectedIcon: Icons.groups_rounded,
            label: 'Equipe',
            route: '/equipe',
          ),
          AppNavDestination(
            icon: Icons.library_music_outlined,
            selectedIcon: Icons.library_music_rounded,
            label: 'Repertório',
            route: '/equipe/musicas',
          ),
        ],
      ),
    ];

    test('acende a rota mais específica, não a que só prefixa', () {
      // `/equipe` prefixa `/equipe/musicas`. Sem a regra do prefixo mais longo
      // a barra acenderia "Equipe" enquanto a pessoa está no repertório.
      expect(
        AppSideNav.selectedRouteFor(sections, '/equipe/musicas/abc'),
        '/equipe/musicas',
      );
      expect(AppSideNav.selectedRouteFor(sections, '/equipe'), '/equipe');
      expect(
        AppSideNav.selectedRouteFor(sections, '/equipe/integrantes/novo'),
        '/equipe',
      );
    });

    test('sub-rota de uma escala mantém a agenda acesa', () {
      expect(
        AppSideNav.selectedRouteFor(sections, '/agenda/123/escalar'),
        '/agenda',
      );
    });

    test('o perfil acende pelo rodapé, fora das seções', () {
      expect(AppSideNav.selectedRouteFor(sections, '/perfil'), '/perfil');
      expect(AppSideNav.selectedRouteFor(sections, '/perfil/dados'), '/perfil');
    });

    test('a Home acende sozinha, sem prefixar nenhuma outra', () {
      final withHome = [
        const AppNavSection(
          destinations: [
            AppNavDestination(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: 'Início',
              route: '/inicio',
            ),
          ],
        ),
        ...sections,
      ];

      expect(AppSideNav.selectedRouteFor(withHome, '/inicio'), '/inicio');
      expect(AppSideNav.selectedRouteFor(withHome, '/agenda'), '/agenda');
    });

    test('rota que não está na barra não acende nada', () {
      expect(AppSideNav.selectedRouteFor(sections, '/diagnostico'), isNull);
    });
  });

  group('AppBreakpoints', () {
    test('as três faixas batem com os limites documentados', () {
      expect(AppBreakpoints.fromWidth(375), FormFactor.mobile);
      expect(AppBreakpoints.fromWidth(599), FormFactor.mobile);
      expect(AppBreakpoints.fromWidth(600), FormFactor.tablet);
      expect(AppBreakpoints.fromWidth(1023), FormFactor.tablet);
      expect(AppBreakpoints.fromWidth(1024), FormFactor.desktop);
      expect(AppBreakpoints.fromWidth(1920), FormFactor.desktop);
    });

    test('isWide cobre tablet e desktop, e só eles', () {
      expect(FormFactor.mobile.isWide, isFalse);
      expect(FormFactor.tablet.isWide, isTrue);
      expect(FormFactor.desktop.isWide, isTrue);
    });
  });

  group('MainShell', () {
    testWidgets('no celular mantém a barra inferior e nenhuma lateral',
        (tester) async {
      await _pumpShell(tester, const Size(375, 812), '/agenda');

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(AppSideNav), findsNothing);
      expect(find.text('Agenda'), findsOneWidget);
    });

    testWidgets('a barra abre em Início, com as três abas antigas atrás',
        (tester) async {
      await _pumpShell(tester, const Size(375, 812), '/inicio');

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 0);
      expect(
        bar.destinations.cast<NavigationDestination>().map((d) => d.label),
        ['Início', 'Agenda', 'Equipe', 'Perfil'],
      );
    });

    testWidgets('a agenda continua acesa como aba, agora a segunda',
        (tester) async {
      await _pumpShell(tester, const Size(375, 812), '/agenda');

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 1);
    });

    testWidgets('fora das três abas a barra inferior some, como sempre',
        (tester) async {
      await _pumpShell(tester, const Size(375, 812), '/equipe/musicas');

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(AppSideNav), findsNothing);
    });

    testWidgets('no tablet a lateral entra recolhida (sem rótulos)',
        (tester) async {
      await _pumpShell(tester, const Size(800, 900), '/agenda');

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(AppSideNav), findsOneWidget);
      // Recolhida: os rótulos vivem em `Tooltip`, não em texto na tela.
      expect(find.text('Repertório'), findsNothing);
      expect(
        tester.getSize(find.byType(AppSideNav)).width,
        AppBreakpoints.sideNavRailWidth,
      );
    });

    testWidgets('no monitor a lateral abre com os rótulos', (tester) async {
      await _pumpShell(tester, const Size(1440, 900), '/agenda');

      expect(find.byType(AppSideNav), findsOneWidget);
      expect(find.text('Agenda'), findsOneWidget);
      expect(find.text('Repertório'), findsOneWidget);
      expect(find.text('Minha disponibilidade'), findsOneWidget);
      expect(
        tester.getSize(find.byType(AppSideNav)).width,
        AppBreakpoints.sideNavWidth,
      );
    });

    testWidgets('quem não gerencia não vê a seção de gestão', (tester) async {
      await _pumpShell(tester, const Size(1440, 900), '/agenda', role: 'MEMBER');

      expect(find.text('Convites'), findsNothing);
      expect(find.text('Gerenciar equipe'), findsNothing);
      // O que todo integrante faz continua ali.
      expect(find.text('Minha disponibilidade'), findsOneWidget);
    });

    // As larguras da lista de verificação. Nenhuma delas pode estourar: um
    // `RenderFlex overflow` na casca aparece em **todas** as telas do app.
    for (final width in [375.0, 600.0, 768.0, 1024.0, 1280.0, 1440.0, 1920.0]) {
      testWidgets('a casca não estoura em ${width.toInt()}px', (tester) async {
        await _pumpShell(tester, Size(width, 800), '/agenda');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a lateral rola em janela baixa (celular deitado)',
        (tester) async {
      // 812x375: a barra lateral tem mais itens do que altura. Sem rolagem
      // isto seria um overflow — e é a situação de qualquer celular deitado.
      await _pumpShell(tester, const Size(812, 375), '/agenda');
      expect(tester.takeException(), isNull);
      expect(find.byType(AppSideNav), findsOneWidget);
    });
  });
}

Future<void> _pumpShell(
  WidgetTester tester,
  Size size,
  String location, {
  String role = 'OWNER',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  final router = GoRouter(
    initialLocation: location,
    routes: [
      ShellRoute(
        builder: (_, __, child) => MainShell(child: child),
        routes: [
          for (final path in const [
            '/inicio',
            '/agenda',
            '/equipe',
            '/perfil',
            '/equipe/musicas',
          ])
            GoRoute(
              path: path,
              builder: (_, __) => Scaffold(body: Text('tela $path')),
            ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            AuthState.signedIn(
              const AuthUser(
                id: '1',
                name: 'Samuel',
                email: 'samuel@teste.com',
                mustChangePassword: false,
              ),
              [
                TeamSummary(
                  membershipId: 'm1',
                  teamId: 't1',
                  name: 'Ministerio de Louvor',
                  role: role,
                  displayName: 'Samuel',
                ),
              ],
            ),
          ),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
      ),
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
