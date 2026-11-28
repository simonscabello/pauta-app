import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:louvor_app/core/storage/read_cache.dart';
import 'package:louvor_app/core/storage/shared_preferences_provider.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/auth/application/auth_controller.dart';
import 'package:louvor_app/features/auth/domain/auth_models.dart';
import 'package:louvor_app/features/events/data/agenda_provider.dart';
import 'package:louvor_app/features/events/data/event_repository.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:louvor_app/features/events/presentation/agenda_screen.dart';
import 'package:louvor_app/features/home/presentation/home_screen.dart';
import 'package:louvor_app/features/suggestions/data/suggestion_repository.dart';
import 'package:louvor_app/features/team/data/team_repository.dart';
import 'package:louvor_app/features/team/domain/service_template.dart';
import 'package:louvor_app/features/team/domain/team_models.dart';
import 'package:louvor_app/features/team_events/data/team_event_repository.dart';
import 'package:louvor_app/features/team_events/domain/team_event.dart';
import 'package:louvor_app/features/team_events/presentation/team_event_form_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// O evento da equipe — reunião, churrasco, treinamento — na agenda e na Home.
///
/// O que estes testes protegem é a **convivência**: o evento entra na mesma
/// lista das escalas sem se disfarçar de uma, e sem empurrar nenhuma para
/// fora. Uma agenda que mostra churrasco como se fosse domingo é pior do que
/// uma agenda sem churrasco.
void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    await initializeDateFormatting('pt_BR');
  });

  group('na agenda', () {
    testWidgets('aparece na lista do dia, com selo e horário',
        (tester) async {
      await _pumpAgenda(tester);

      await tester.tap(find.byKey(const ValueKey('agenda-day-2026-09-12')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('selected-evento/ev1')),
        findsOneWidget,
      );
      expect(find.text('Churrasco da equipe'), findsWidgets);
      // O selo existe porque a linha começa com texto grande que não é uma
      // data — sem ele, leria-se como escala de culto especial.
      expect(find.text('Evento'), findsWidgets);
      expect(find.textContaining('12:00 às 18:00'), findsOneWidget);
    });

    testWidgets('divide a lista das próximas com as escalas, pelo relógio',
        (tester) async {
      await _pumpAgenda(tester);

      expect(find.text('Próximos compromissos'), findsOneWidget);
      expect(find.byKey(const ValueKey('upcoming-evento/ev1')), findsOneWidget);
      expect(find.byKey(const ValueKey('upcoming-escala/e1')), findsOneWidget);
    });

    testWidgets('o recorte pessoal não esconde o evento', (tester) async {
      await _pumpAgenda(tester);

      await tester.tap(find.text('Minhas escalas'));
      await tester.pumpAndSettle();

      // A escala do dia 13 não é do Simon e sai; o churrasco fica, porque um
      // evento é de todo mundo.
      expect(find.byKey(const ValueKey('upcoming-escala/e1')), findsNothing);
      expect(find.byKey(const ValueKey('upcoming-evento/ev1')), findsOneWidget);
    });

    // Criar evento e criar escala passaram a sair do **mesmo** botão: eram
    // dois pontos de partida, em dois cantos da tela, para a mesma intenção de
    // "quero marcar alguma coisa".
    testWidgets('quem lidera marca um evento pelo botão Nova', (tester) async {
      await _pumpAgenda(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Nova'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Novo evento'));
      await tester.pumpAndSettle();

      // Leva o dia selecionado junto, como o caminho da escala.
      expect(find.text('novo evento 2026-09-09'), findsOneWidget);
    });

    testWidgets('o mesmo botão leva à escala', (tester) async {
      await _pumpAgenda(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Nova'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nova escala'));
      await tester.pumpAndSettle();

      expect(find.text('nova escala 2026-09-09'), findsOneWidget);
    });

    testWidgets('quem não gerencia não vê o caminho de marcar', (tester) async {
      await _pumpAgenda(tester, canManage: false);

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Novo evento'), findsNothing);
      // Mas continua vendo o que já está marcado.
      expect(find.byKey(const ValueKey('upcoming-evento/ev1')), findsOneWidget);
    });

    testWidgets('tocar na linha abre o evento', (tester) async {
      await _pumpAgenda(tester);

      await tester.tap(find.byKey(const ValueKey('upcoming-evento/ev1')));
      await tester.pumpAndSettle();

      expect(find.text('detalhe do evento ev1'), findsOneWidget);
    });
  });

  group('o formulário', () {
    testWidgets('tirar a hora de término manda o pedido de apagar',
        (tester) async {
      final repo = _RepositorioFake();
      await _pumpFormulario(tester, repo);

      // O evento carregado tem término; o botão de limpar o remove.
      expect(find.text('18:00'), findsOneWidget);
      await tester.tap(find.byTooltip('Tirar a hora de término'));
      await tester.pumpAndSettle();
      expect(find.text('Sem hora definida'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
      await tester.pumpAndSettle();

      // Omitir preservaria no servidor. Sem este `true`, apagar a hora de
      // término no formulário não teria como ser dito -- e ela ficaria presa.
      expect(repo.removeuTermino, isTrue);
      expect(repo.terminoEnviado, isNull);
    });
  });

  group('na Home', () {
    testWidgets('o próximo evento ganha um bloco, e só um', (tester) async {
      await _pumpHome(tester);

      expect(find.text('Próximo evento'), findsOneWidget);
      expect(find.text('Churrasco da equipe'), findsOneWidget);
      // Um evento, e não uma lista: a Home acabou de deixar de repetir a
      // agenda, e repetir de novo com eventos seria o mesmo erro.
      expect(find.text('Reunião de liderança'), findsNothing);
    });

    testWidgets('sem evento marcado, o bloco não existe', (tester) async {
      await _pumpHome(tester, teamEvents: const []);

      expect(find.text('Próximo evento'), findsNothing);
    });
  });
}

// ------------------------------------------------------------------ dados

Map<String, dynamic> _escalaJson({
  required String id,
  required String startsAt,
  List<Map<String, dynamic>> assignments = const [],
}) =>
    {
      'id': id,
      'teamId': 't1',
      'title': null,
      'startsAt': startsAt,
      'rehearsalAt': null,
      'location': null,
      'notes': null,
      'colorPalette': null,
      'status': 'PUBLISHED',
      'timezone': 'America/Sao_Paulo',
      'assignments': assignments,
      'songs': const [],
    };

TeamEvent _evento({
  required String id,
  required String title,
  required String startsAt,
  String? endsAt,
  String? location,
}) =>
    TeamEvent.fromJson({
      'id': id,
      'teamId': 't1',
      'title': title,
      'startsAt': startsAt,
      'endsAt': endsAt,
      'location': location,
      'notes': null,
      'timezone': 'America/Sao_Paulo',
    });

final _eventosPadrao = [
  _evento(
    id: 'ev1',
    title: 'Churrasco da equipe',
    startsAt: '2026-09-12T15:00:00.000Z',
    endsAt: '2026-09-12T21:00:00.000Z',
    location: 'Chácara do Samuel',
  ),
  _evento(
    id: 'ev2',
    title: 'Reunião de liderança',
    startsAt: '2026-09-24T23:00:00.000Z',
  ),
];

// ----------------------------------------------------------------- agenda

Future<void> _pumpAgenda(
  WidgetTester tester, {
  bool canManage = true,
  Size size = const Size(400, 1600),
}) async {
  final router = GoRouter(
    initialLocation: '/agenda',
    routes: [
      GoRoute(path: '/agenda', builder: (_, __) => const AgendaScreen()),
      GoRoute(
        path: '/agenda/novo',
        builder: (_, state) => Scaffold(
          body: Text('nova escala ${state.uri.queryParameters['data']}'),
        ),
      ),
      GoRoute(
        path: '/eventos/novo',
        builder: (_, state) => Scaffold(
          body: Text('novo evento ${state.uri.queryParameters['data']}'),
        ),
      ),
      GoRoute(
        path: '/eventos/:id',
        builder: (_, state) => Scaffold(
          body: Text('detalhe do evento ${state.pathParameters['id']}'),
        ),
      ),
      GoRoute(
        path: '/agenda/:id',
        builder: (_, __) => const Scaffold(body: Text('detalhe da escala')),
      ),
    ],
  );

  await _pump(
    tester,
    size: size,
    canManage: canManage,
    router: router,
    teamEvents: _eventosPadrao,
  );
}

// ------------------------------------------------------------------- home

Future<void> _pumpHome(
  WidgetTester tester, {
  List<TeamEvent>? teamEvents,
}) async {
  final router = GoRouter(
    initialLocation: '/inicio',
    routes: [
      GoRoute(path: '/inicio', builder: (_, __) => const HomeScreen()),
      GoRoute(
        path: '/agenda',
        builder: (_, __) => const Scaffold(body: Text('agenda')),
      ),
      GoRoute(
        path: '/agenda/novo',
        builder: (_, state) => Scaffold(
          body: Text('nova escala ${state.uri.queryParameters['data']}'),
        ),
      ),
      GoRoute(
        path: '/eventos/:id',
        builder: (_, __) => const Scaffold(body: Text('detalhe do evento')),
      ),
    ],
  );

  await _pump(
    tester,
    size: const Size(400, 1600),
    canManage: true,
    router: router,
    teamEvents: teamEvents ?? _eventosPadrao,
  );
}

// ------------------------------------------------------------ formulario

Future<void> _pumpFormulario(
  WidgetTester tester,
  _RepositorioFake repo,
) async {
  final router = GoRouter(
    initialLocation: '/eventos/ev1/editar',
    routes: [
      GoRoute(
        path: '/eventos/ev1/editar',
        builder: (_, __) => const TeamEventFormScreen(eventId: 'ev1'),
      ),
      GoRoute(
        path: '/eventos/:id',
        builder: (_, __) => const Scaffold(body: Text('detalhe do evento')),
      ),
    ],
  );

  await _pump(
    tester,
    size: const Size(400, 1600),
    canManage: true,
    router: router,
    teamEvents: _eventosPadrao,
    repositorio: repo,
  );
}

class _RepositorioFake extends TeamEventRepository {
  _RepositorioFake() : super(Dio(), _cacheFake!);

  bool? removeuTermino;
  String? terminoEnviado;

  @override
  Future<TeamEvent> find(String id) async => _eventosPadrao.first;

  @override
  Future<TeamEvent> update(
    String id, {
    String? title,
    String? startsAt,
    String? endsAt,
    bool removeEndsAt = false,
    String? location,
    String? notes,
  }) async {
    removeuTermino = removeEndsAt;
    terminoEnviado = endsAt;
    return _eventosPadrao.first;
  }
}

ReadCache? _cacheFake;

// ---------------------------------------------------------------- harness

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required bool canManage,
  required GoRouter router,
  required List<TeamEvent> teamEvents,
  TeamEventRepository? repositorio,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(router.dispose);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  _cacheFake ??= ReadCache(prefs);

  final escalas = [
    Event.fromJson(
      _escalaJson(id: 'e1', startsAt: '2026-09-13T11:30:00.000Z'),
    ),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        agendaNowProvider.overrideWithValue(DateTime.utc(2026, 9, 9, 16)),
        if (repositorio != null)
          teamEventRepositoryProvider.overrideWithValue(repositorio),
        eventsProvider.overrideWith(
          (ref, query) async => CachedValue(
            data: query.$2 == 'upcoming' ? escalas : <Event>[],
            fromCache: false,
          ),
        ),
        agendaMonthProvider.overrideWith(
          (ref, query) async => CachedValue(
            data: query.$2 == DateTime(2026, 9) ? escalas : <Event>[],
            fromCache: false,
          ),
        ),
        teamEventsProvider.overrideWith(
          (ref, query) async => CachedValue(
            data: query.$2 == 'upcoming' ? teamEvents : <TeamEvent>[],
            fromCache: false,
          ),
        ),
        openSuggestionCountProvider.overrideWith((ref, teamId) async => 0),
        serviceTemplatesProvider.overrideWith(
          (ref, teamId) async => const <ServiceTemplate>[],
        ),
        teamProvider.overrideWith(
          (ref, teamId) async => const Team(
            id: 't1',
            name: 'Ministério de Louvor',
            timezone: 'America/Sao_Paulo',
          ),
        ),
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            AuthState.signedIn(
              const AuthUser(
                id: '1',
                name: 'Simon',
                email: 'simon@teste.com',
                mustChangePassword: false,
              ),
              [
                TeamSummary(
                  membershipId: 'm-Simon',
                  teamId: 't1',
                  name: 'Ministério de Louvor',
                  role: canManage ? 'OWNER' : 'MEMBER',
                  displayName: 'Simon',
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
