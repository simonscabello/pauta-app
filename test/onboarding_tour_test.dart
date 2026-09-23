import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:louvor_app/core/router/app_router.dart';
import 'package:louvor_app/core/storage/read_cache.dart';
import 'package:louvor_app/core/storage/shared_preferences_provider.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/auth/application/auth_controller.dart';
import 'package:louvor_app/features/auth/domain/auth_models.dart';
import 'package:louvor_app/features/events/data/event_repository.dart';
import 'package:louvor_app/features/onboarding/application/tour_controller.dart';
import 'package:louvor_app/features/onboarding/data/onboarding_repository.dart';
import 'package:louvor_app/features/onboarding/domain/member_tour.dart';
import 'package:louvor_app/features/onboarding/domain/onboarding_models.dart';
import 'package:louvor_app/features/onboarding/presentation/tour_overlay.dart';
import 'package:louvor_app/features/onboarding/presentation/tour_target.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// O tour de ponta a ponta, com telas de mentira que têm os mesmos alvos.
///
/// O que se trava aqui é o combinado com o produto: avançar, voltar e pular
/// funcionam; o tour anda pelas telas certas; **pular e concluir gravam, e
/// rever pela Ajuda não grava nada.**
void main() {
  testWidgets('boas-vindas, avançar, voltar e pular — pular grava SKIPPED',
      (tester) async {
    final app = await _pumpApp(tester);
    app.tour.offerWelcome();
    await _settle(tester);

    expect(find.text('Boas-vindas ao Pauta 👋'), findsOneWidget);
    expect(find.text('Agora não'), findsOneWidget);

    await tester.tap(find.text('Conhecer o Pauta'));
    await _settle(tester);
    expect(find.text('1 DE 6'), findsOneWidget);
    expect(find.text('Sua próxima escala'), findsOneWidget);
    // A primeira parada não tem para onde voltar.
    expect(find.text('Voltar'), findsNothing);

    await tester.tap(find.text('Próximo'));
    await _settle(tester);
    expect(find.text('2 DE 6'), findsOneWidget);
    expect(find.text('Músicas da escala'), findsOneWidget);

    await tester.tap(find.text('Voltar'));
    await _settle(tester);
    expect(find.text('1 DE 6'), findsOneWidget);

    // A agenda é a quarta parada: a disponibilidade virou uma parada só, na
    // porta da Home.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Próximo'));
      await _settle(tester);
    }
    expect(find.text('4 DE 6'), findsOneWidget);
    expect(find.text('Agenda da equipe'), findsOneWidget);
    expect(app.location(), '/agenda');

    await tester.tap(find.text('Pular'));
    await _settle(tester);

    expect(find.text('4 DE 6'), findsNothing);
    expect(app.repository.recorded, [
      (OnboardingFlows.member, OnboardingOutcome.skipped),
    ]);
    // Volta para onde a pessoa estava, e diz onde achar o tour depois.
    expect(app.location(), '/inicio');
    expect(find.textContaining('Perfil › Ajuda'), findsOneWidget);
  });

  testWidgets('concluir passa pelas telas de verdade e grava COMPLETED',
      (tester) async {
    final app = await _pumpApp(tester);
    app.tour.offerWelcome();
    await _settle(tester);
    await tester.tap(find.text('Conhecer o Pauta'));
    await _settle(tester);

    final visited = <String>[];
    for (var i = 0; i < 6; i++) {
      visited.add(app.location());
      await tester.tap(find.text(i == 5 ? 'Concluir' : 'Próximo'));
      await _settle(tester);
    }
    expect(visited, [
      '/inicio',
      '/inicio',
      '/inicio',
      '/agenda',
      '/equipe',
      // O `flutter_test` finge ser Android: a parada dos avisos aponta para o
      // interruptor do Perfil. Na Web ela é um cartão sem destaque.
      '/perfil',
    ]);

    expect(find.text('Tudo pronto! 🎵'), findsOneWidget);
    // Da última tela ainda se volta.
    await tester.tap(find.text('Voltar'));
    await _settle(tester);
    expect(find.text('6 DE 6'), findsOneWidget);
    await tester.tap(find.text('Concluir'));
    await _settle(tester);

    await tester.tap(find.text('Começar'));
    await _settle(tester);

    expect(find.text('Tudo pronto! 🎵'), findsNothing);
    expect(app.location(), '/inicio');
    expect(app.repository.recorded, [
      (OnboardingFlows.member, OnboardingOutcome.completed),
    ]);
  });

  testWidgets('"Agora não" grava SKIPPED e não reoferece na mesma abertura',
      (tester) async {
    final app = await _pumpApp(tester);
    app.tour.offerWelcome();
    await _settle(tester);

    await tester.tap(find.text('Agora não'));
    await _settle(tester);

    expect(find.text('Boas-vindas ao Pauta 👋'), findsNothing);
    expect(app.repository.recorded, [
      (OnboardingFlows.member, OnboardingOutcome.skipped),
    ]);

    app.tour.offerWelcome();
    await _settle(tester);
    expect(find.text('Boas-vindas ao Pauta 👋'), findsNothing);
  });

  testWidgets('rever pela Ajuda não grava nada, nem pulando nem concluindo',
      (tester) async {
    final app = await _pumpApp(tester, initial: '/perfil');

    await tester.tap(find.text('Rever o tour'));
    await _settle(tester);
    expect(find.text('1 DE 6'), findsOneWidget);
    // Sem boas-vindas: quem pediu já disse que quer.
    expect(find.text('Agora não'), findsNothing);

    await tester.tap(find.text('Pular'));
    await _settle(tester);
    // Pular devolve para onde o tour foi aberto.
    expect(app.location(), '/perfil');

    await tester.tap(find.text('Rever o tour'));
    await _settle(tester);
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.text(i == 5 ? 'Concluir' : 'Próximo'));
      await _settle(tester);
    }
    await tester.tap(find.text('Começar'));
    await _settle(tester);

    expect(app.repository.recorded, isEmpty);
  });

  testWidgets('no teclado, setas andam e Esc pula', (tester) async {
    // Na Web a primeira versão ignorava as setas: o foco estava no botão, que
    // as consumia para andar entre botões.
    final app = await _pumpApp(tester);
    app.tour.offerWelcome();
    await _settle(tester);
    await tester.tap(find.text('Conhecer o Pauta'));
    await _settle(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(find.text('2 DE 6'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _settle(tester);
    expect(find.text('1 DE 6'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('1 DE 6'), findsNothing);
    expect(app.repository.recorded, [
      (OnboardingFlows.member, OnboardingOutcome.skipped),
    ]);
  });

  testWidgets('o destaque cai em cima do alvo da parada', (tester) async {
    final app = await _pumpApp(tester);
    app.tour.offerWelcome();
    await _settle(tester);
    await tester.tap(find.text('Conhecer o Pauta'));
    await _settle(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Próximo'));
      await _settle(tester);
    }
    expect(find.text('Informe sua disponibilidade'), findsOneWidget);

    // O cartão do tour não cobre o alvo destacado.
    final alvo =
        tester.getRect(find.byKey(const ValueKey('alvo-disponibilidade')));
    final cartao = tester.getRect(
      find
          .ancestor(
            of: find.text('Informe sua disponibilidade'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(alvo.overlaps(cartao), isFalse);
  });
}

class _FakeOnboardingRepository extends OnboardingRepository {
  _FakeOnboardingRepository() : super(Dio());

  final recorded = <(OnboardingFlow, OnboardingOutcome)>[];

  @override
  Future<List<OnboardingRecord>> list() async => const [];

  @override
  Future<void> record(OnboardingFlow flow, OnboardingOutcome outcome) async {
    recorded.add((flow, outcome));
  }
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, this._initial);

  final AuthState _initial;

  @override
  Future<void> bootstrap() async {
    state = _initial;
  }
}

class _App {
  _App(this.container, this.router, this.repository);

  final ProviderContainer container;
  final GoRouter router;
  final _FakeOnboardingRepository repository;

  TourController get tour => container.read(tourControllerProvider.notifier);

  String location() => router.routerDelegate.currentConfiguration.uri.path;
}

/// Os quadros do tour não "assentam" (ele mede o alvo a cada quadro), então
/// `pumpAndSettle` não serve: avança o relógio o bastante para as
/// transições e a rolagem terminarem.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _page(String title, List<Widget> children) => Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: children,
      ),
    );

Widget _block(String id, String label, {Key? key}) => TourTarget(
      id: id,
      child: SizedBox(
        key: key,
        height: 120,
        child: Card(child: Center(child: Text(label))),
      ),
    );

Future<_App> _pumpApp(WidgetTester tester, {String initial = '/inicio'}) async {
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final repository = _FakeOnboardingRepository();

  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/inicio',
        builder: (_, __) => _page('Início', [
          _block(TourTargetIds.homeNext, 'manchete'),
          const SizedBox(height: 16),
          _block(
            TourTargetIds.homeAvailability,
            'atalho disponibilidade',
            key: const ValueKey('alvo-disponibilidade'),
          ),
        ]),
      ),
      GoRoute(
        path: '/disponibilidade',
        builder: (_, __) => _page('Minha disponibilidade', [
          const Text('Escolher dias'),
        ]),
      ),
      GoRoute(
        path: '/agenda',
        builder: (_, __) => _page('Agenda', [
          _block(TourTargetIds.agendaCalendar, 'calendário'),
        ]),
      ),
      GoRoute(
        path: '/equipe',
        builder: (_, __) => _page('Equipe', [
          _block(TourTargetIds.teamRepertoire, 'Repertório'),
          const Text('Sugestões'),
        ]),
      ),
      GoRoute(
        path: '/perfil',
        builder: (_, __) => Consumer(
          builder: (context, ref, _) => _page('Perfil', [
            TextButton(
              onPressed: () => startTourManually(ref, context),
              child: const Text('Rever o tour'),
            ),
            _block(TourTargetIds.profilePush, 'Avisos no celular'),
          ]),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        routerProvider.overrideWithValue(router),
        onboardingRepositoryProvider.overrideWithValue(repository),
        eventsProvider.overrideWith(
          (ref, query) async => const CachedValue(data: [], fromCache: false),
        ),
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            AuthState.signedIn(
              const AuthUser(
                id: 'u1',
                name: 'Maria',
                email: 'maria@teste.com',
                mustChangePassword: false,
              ),
              const [
                TeamSummary(
                  membershipId: 'm1',
                  teamId: 't1',
                  name: 'Louvor',
                  role: 'MEMBER',
                  displayName: 'Maria',
                ),
              ],
            ),
          ),
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: ref.watch(routerProvider),
          builder: (context, child) =>
              OnboardingTourHost(child: child ?? const SizedBox.shrink()),
        ),
      ),
    ),
  );
  await _settle(tester);

  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  );
  return _App(container, router, repository);
}
