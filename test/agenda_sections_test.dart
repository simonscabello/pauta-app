import 'dart:async';

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
import 'package:louvor_app/features/events/presentation/agenda_event_tile.dart';
import 'package:louvor_app/features/events/presentation/agenda_screen.dart';
import 'package:louvor_app/features/team/data/team_repository.dart';
import 'package:louvor_app/features/team/domain/service_template.dart';
import 'package:louvor_app/features/team/domain/team_models.dart';
import 'package:louvor_app/features/team_events/data/team_event_repository.dart';
import 'package:louvor_app/features/team_events/domain/team_event.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    await initializeDateFormatting('pt_BR');
  });

  testWidgets('abre no mês atual sem saudação, hero ou abas antigas',
      (tester) async {
    await _pumpAgenda(tester, const Size(400, 1400));
    expect(find.text('Agenda'), findsOneWidget);
    expect(find.text('Setembro 2026'), findsOneWidget);
    expect(find.text('PRÓXIMA ESCALA'), findsNothing);
    expect(find.text('Passadas'), findsNothing);
    expect(find.text('Depois dessa'), findsNothing);
    expect(find.textContaining(', Simon'), findsNothing);
    expect(find.text('Nada marcado para este dia.'), findsOneWidget);
  });

  testWidgets('a escala é escrita pela mesma linha da Home', (tester) async {
    await _pumpAgenda(tester, const Size(400, 1400));
    await tester.tap(find.byKey(const ValueKey('agenda-day-2026-09-10')));
    await tester.pumpAndSettle();

    // O widget, e não uma cópia parecida: é o que impede as duas telas de
    // divergirem no primeiro ajuste.
    expect(find.byKey(const ValueKey('selected-escala/e1')), findsOneWidget);
    expect(
      tester.widget(find.byKey(const ValueKey('selected-escala/e1'))),
      isA<CompactScheduleTile>(),
    );
    // A escala do dia não se repete nas próximas.
    expect(find.byKey(const ValueKey('upcoming-escala/e1')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('selected-escala/e1')),
        matching: find.textContaining('19:30'),
      ),
      findsOneWidget,
    );
    // A pílula da Home, com o mesmo texto.
    expect(find.text('VOCÊ: Vocal, Baixo'), findsOneWidget);
    expect(find.text('Nada marcado para este dia.'), findsNothing);
  });

  testWidgets('"Minhas escalas" recorta o mês, o dia e a lista',
      (tester) async {
    await _pumpAgenda(tester, const Size(400, 1400));

    // Um domingo da equipe em que Simon não entra.
    await tester.tap(find.byKey(const ValueKey('agenda-day-2026-09-13')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selected-escala/e2')), findsOneWidget);

    await tester.tap(find.text('Minhas escalas'));
    await tester.pumpAndSettle();

    // O dia sai da lista, mas a frase não diz que a equipe está livre --
    // esconder uma escala que existe seria o pior defeito do filtro.
    expect(find.byKey(const ValueKey('selected-escala/e2')), findsNothing);
    expect(find.text('Você não está escalado neste dia.'), findsOneWidget);
    expect(find.text('Nada marcado para este dia.'), findsNothing);

    // Nas próximas sobra a única escala dele.
    expect(find.byKey(const ValueKey('upcoming-escala/e1')), findsOneWidget);
    expect(find.byKey(const ValueKey('upcoming-escala/e3')), findsNothing);

    // E o ponto do calendário passa a significar outra coisa.
    expect(find.text('Seus compromissos'), findsOneWidget);
    expect(find.text('Com compromisso'), findsNothing);
  });

  testWidgets('sem nenhuma escala sua, o recorte diz isso e não some a tela',
      (tester) async {
    await _pumpAgenda(tester, const Size(400, 1400), semEquipe: true);
    await tester.tap(find.text('Minhas escalas'));
    await tester.pumpAndSettle();

    expect(find.text('Setembro 2026'), findsOneWidget);
    expect(find.text('Você não tem escala neste mês.'), findsOneWidget);
    expect(find.text('Nada seu por perto.'), findsOneWidget);
  });

  testWidgets('anterior, seguinte e Hoje mantêm seleção no mês visível',
      (tester) async {
    await _pumpAgenda(tester, const Size(400, 1400));
    await tester.tap(find.byTooltip('Mês anterior'));
    await tester.pumpAndSettle();
    expect(find.text('Agosto 2026'), findsOneWidget);
    expect(find.text('Nenhuma escala neste mês.'), findsOneWidget);
    await tester.tap(find.byTooltip('Próximo mês'));
    await tester.pumpAndSettle();
    expect(find.text('Setembro 2026'), findsOneWidget);
    await tester.tap(find.text('Hoje'));
    await tester.pumpAndSettle();
    expect(find.text('Quarta-feira, 9 de setembro'), findsOneWidget);
  });

  testWidgets('navega para detalhe e criação leva o dia selecionado',
      (tester) async {
    await _pumpAgenda(tester, const Size(400, 1400));
    await tester.tap(find.byKey(const ValueKey('agenda-day-2026-09-10')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selected-escala/e1')));
    await tester.pumpAndSettle();
    expect(find.text('detalhe e1'), findsOneWidget);
    final context = tester.element(find.text('detalhe e1'));
    GoRouter.of(context).pop();
    await tester.pumpAndSettle();
    // O botão flutuante leva o dia selecionado junto -- é o que a agenda tem
    // a mais do que a Home, que só sabe criar "uma escala nova". Ele abre o
    // menu com as duas naturezas de compromisso; a escala é uma delas.
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Nova'));
    await tester.pumpAndSettle();
    expect(find.text('Novo evento'), findsOneWidget);
    await tester.tap(find.text('Nova escala'));
    await tester.pumpAndSettle();
    expect(find.text('novo 2026-09-10'), findsOneWidget);
  });

  testWidgets('lista vazia mantém o calendário e oferece criação discreta',
      (tester) async {
    await _pumpAgenda(tester, const Size(400, 1400), take: 0);
    expect(find.text('Setembro 2026'), findsOneWidget);
    expect(find.text('Nada marcado para este dia.'), findsOneWidget);
    expect(find.text('Nada mais marcado por perto.'), findsOneWidget);
    // A agenda vazia continua oferecendo o caminho de criar.
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Criar escala'), findsOneWidget);
  });

  testWidgets('sem escalação, a linha não inventa o que a listagem não traz',
      (tester) async {
    await _pumpAgenda(tester, const Size(400, 1400), semEquipe: true);
    await tester.tap(find.byKey(const ValueKey('agenda-day-2026-09-10')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selected-escala/e1')), findsOneWidget);
    expect(find.textContaining('VOCÊ'), findsNothing);
    expect(find.textContaining('pessoa'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('histórico aparece ao selecionar uma data passada',
      (tester) async {
    await _pumpAgenda(
      tester,
      const Size(400, 1400),
      loadUpcoming: () async =>
          const CachedValue(data: <Event>[], fromCache: false),
      loadMonth: (month) async => CachedValue(
        data: month == DateTime(2026, 8)
            ? [
                Event.fromJson(
                  _eventJson(
                    id: 'old',
                    startsAt: '2026-08-31T22:30:00Z',
                  ),
                ),
              ]
            : <Event>[],
        fromCache: false,
      ),
    );
    await tester.tap(find.byTooltip('Mês anterior'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-day-2026-08-31')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selected-escala/old')), findsOneWidget);
    expect(find.textContaining('19:30'), findsOneWidget);
  });

  testWidgets('loading preserva calendário e erro oferece nova tentativa',
      (tester) async {
    final pendingUpcoming = Completer<CachedValue<List<Event>>>();
    final pendingMonth = Completer<CachedValue<List<Event>>>();
    var failed = true;
    await _pumpAgenda(
      tester,
      const Size(400, 1400),
      settle: false,
      loadUpcoming: () => failed
          ? pendingUpcoming.future
          : Future.value(
              const CachedValue(data: <Event>[], fromCache: false),
            ),
      loadMonth: (_) => failed
          ? pendingMonth.future
          : Future.value(
              const CachedValue(data: <Event>[], fromCache: false),
            ),
    );
    expect(find.text('Setembro 2026'), findsOneWidget);
    expect(find.text('Nada marcado para este dia.'), findsNothing);
    pendingUpcoming.completeError(Exception('offline'));
    pendingMonth.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Tentar novamente'), findsWidgets);
    failed = false;
    await tester.tap(find.text('Tentar novamente').first);
    await tester.pumpAndSettle();
    expect(find.text('Nada marcado para este dia.'), findsOneWidget);
  });

  testWidgets('fora do alcance do cache não afirma que dia ou mês estão vazios',
      (tester) async {
    await _pumpAgenda(
      tester,
      const Size(400, 1400),
      loadUpcoming: () async => CachedValue(
        data: const <Event>[],
        fromCache: true,
        cachedAt: DateTime.utc(2026, 9, 9, 12),
      ),
      loadMonth: (month) async {
        if (month == DateTime(2026, 9)) {
          return CachedValue(
            data: const <Event>[],
            fromCache: true,
            cachedAt: DateTime.utc(2026, 9, 9, 12),
          );
        }
        throw Exception('offline');
      },
    );
    await tester.tap(find.byTooltip('Mês anterior'));
    await tester.pumpAndSettle();
    expect(find.text('Nada marcado para este dia.'), findsNothing);
    expect(find.text('Nenhuma escala neste mês.'), findsNothing);
    // Trocar de mês sem cache não escolhe o dia 1 sozinho nem finge vazio.
    expect(find.text('Não carregou tudo deste dia.'), findsNothing);
    expect(find.textContaining('Sem conexão.'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });

  testWidgets(
      'mês passado sem escala em cache offline mantém selo Sem conexão',
      (tester) async {
    await _pumpAgenda(
      tester,
      const Size(400, 1400),
      loadUpcoming: () async => CachedValue(
        data: const <Event>[],
        fromCache: true,
        cachedAt: DateTime.utc(2026, 9, 9, 12),
      ),
      loadMonth: (_) async => CachedValue(
        data: const <Event>[],
        fromCache: true,
        cachedAt: DateTime.utc(2026, 9, 9, 12),
      ),
    );
    await tester.tap(find.byTooltip('Mês anterior'));
    await tester.pumpAndSettle();
    expect(find.text('Agosto 2026'), findsOneWidget);
    expect(find.text('Nenhuma escala neste mês.'), findsOneWidget);
    expect(find.textContaining('Sem conexão.'), findsOneWidget);
  });

  testWidgets(
      'tela pede no máximo duas consultas de escalas (upcoming + mês) mesmo com página cheia',
      (tester) async {
    final spy = _SpyEventRepository(
      upcoming: List.generate(
        20,
        (i) => Event.fromJson(
          _eventJson(
            id: 'u$i',
            startsAt: DateTime.utc(2026, 9, 10)
                .add(Duration(days: i * 3))
                .toIso8601String(),
          ),
        ),
      ),
      byRange: {
        '2026-09-01..2026-09-30': [
          Event.fromJson(
            _eventJson(id: 'u0', startsAt: '2026-09-10T22:30:00Z'),
          ),
        ],
        '2026-08-01..2026-08-31': [
          Event.fromJson(
            _eventJson(id: 'aug1', startsAt: '2026-08-23T12:00:00Z'),
          ),
        ],
      },
    );

    await _pumpAgendaWithRepository(
      tester,
      repository: spy,
      now: DateTime.utc(2026, 9, 9, 16),
    );

    // No máximo 2 consultas: 1 upcoming (limit 20) + 1 mês exibido.
    expect(spy.listCalls, hasLength(1));
    expect(spy.listCalls.single, (scope: 'upcoming', limit: 20));
    expect(spy.rangeCalls, [(from: '2026-09-01', to: '2026-09-30')]);
    expect(spy.totalScheduleQueries, 2);

    // Navegar para trás pede apenas o mês anterior, nunca scope=past.
    await tester.tap(find.byTooltip('Mês anterior'));
    await tester.pumpAndSettle();
    expect(spy.listCalls, hasLength(1));
    expect(spy.rangeCalls, [
      (from: '2026-09-01', to: '2026-09-30'),
      (from: '2026-08-01', to: '2026-08-31'),
    ]);
    expect(find.byKey(const ValueKey('selected-escala/aug1')), findsOneWidget);
  });

  testWidgets('virada de mês em São Paulo pede o mês local, não o de UTC',
      (tester) async {
    final spy = _SpyEventRepository(upcoming: const [], byRange: const {});
    // 2026-10-01 01:30 UTC == 2026-09-30 22:30 em America/Sao_Paulo.
    await _pumpAgendaWithRepository(
      tester,
      repository: spy,
      now: DateTime.utc(2026, 10, 1, 1, 30),
    );

    expect(find.text('Setembro 2026'), findsOneWidget);
    expect(spy.totalScheduleQueries, 2);
    expect(spy.listCalls.single.scope, 'upcoming');
    expect(spy.rangeCalls, [(from: '2026-09-01', to: '2026-09-30')]);
  });
}

Map<String, dynamic> _eventJson({
  required String id,
  required String startsAt,
  String status = 'PUBLISHED',
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
      'status': status,
      'timezone': 'America/Sao_Paulo',
      'assignments': assignments,
      'songs': const [],
    };

List<Map<String, dynamic>> _group(String name, List<String> people) => [
      {
        'positionId': 'p-$name',
        'positionName': name,
        'sortOrder': 0,
        'members': [
          for (final p in people)
            {
              'id': 'a-$name-$p',
              'membershipId': 'm-$p',
              'displayName': p,
              'note': null,
              'isRegisteredForPosition': true,
            },
        ],
      },
    ];

Future<void> _pumpAgenda(
  WidgetTester tester,
  Size size, {
  int take = 5,
  bool semEquipe = false,
  bool settle = true,
  Future<CachedValue<List<Event>>> Function()? loadUpcoming,
  Future<CachedValue<List<Event>>> Function(DateTime month)? loadMonth,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  final events = <Event>[
    Event.fromJson(
      _eventJson(
        id: 'e1',
        startsAt: '2026-09-10T22:30:00.000Z',
        assignments: semEquipe
            ? const []
            : [
                ..._group('Vocal', ['Simon', 'Maria']),
                ..._group('Baixo', ['Simon']),
                ..._group('Guitarra', ['Joao', 'Ana']),
              ],
      ),
    ),
    Event.fromJson(_eventJson(id: 'e2', startsAt: '2026-09-13T11:30:00.000Z')),
    Event.fromJson(_eventJson(id: 'e3', startsAt: '2026-09-17T22:30:00.000Z')),
    Event.fromJson(_eventJson(id: 'e4', startsAt: '2026-09-20T11:30:00.000Z')),
    Event.fromJson(_eventJson(id: 'e5', startsAt: '2026-09-24T22:30:00.000Z')),
  ].take(take).toList();

  final router = GoRouter(
    initialLocation: '/agenda',
    routes: [
      GoRoute(path: '/agenda', builder: (_, __) => const AgendaScreen()),
      GoRoute(
        path: '/agenda/novo',
        builder: (_, state) => Scaffold(
          body: Text('novo ${state.uri.queryParameters['data'] ?? ''}'),
        ),
      ),
      GoRoute(
        path: '/agenda/:id',
        builder: (_, state) =>
            Scaffold(body: Text('detalhe ${state.pathParameters['id']!}')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        agendaNowProvider.overrideWithValue(DateTime.utc(2026, 9, 9, 16)),
        eventsProvider.overrideWith(
          (ref, query) => loadUpcoming != null
              ? loadUpcoming()
              : Future.value(
                  CachedValue(
                    data: query.$2 == 'upcoming' ? events : <Event>[],
                    fromCache: false,
                  ),
                ),
        ),
        agendaMonthProvider.overrideWith(
          (ref, query) => loadMonth != null
              ? loadMonth(query.$2)
              : Future.value(
                  CachedValue(
                    data: query.$2 == DateTime(2026, 9) ? events : <Event>[],
                    fromCache: false,
                  ),
                ),
        ),
        teamEventsProvider.overrideWith(
          (ref, query) async =>
              const CachedValue(data: <TeamEvent>[], fromCache: false),
        ),
        // Grade vazia: estes testes são sobre a arrumação da lista, e as datas
        // em aberto mudam conforme o dia em que o teste roda.
        serviceTemplatesProvider.overrideWith(
          (ref, teamId) async => const <ServiceTemplate>[],
        ),
        teamProvider.overrideWith(
          (ref, teamId) async => const Team(
            id: 't1',
            name: 'Louvor SIBB',
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
              const [
                TeamSummary(
                  membershipId: 'm-Simon',
                  teamId: 't1',
                  name: 'Louvor SIBB',
                  role: 'OWNER',
                  displayName: 'Simon',
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
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}

Future<void> _pumpAgendaWithRepository(
  WidgetTester tester, {
  required _SpyEventRepository repository,
  required DateTime now,
}) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  final router = GoRouter(
    initialLocation: '/agenda',
    routes: [
      GoRoute(path: '/agenda', builder: (_, __) => const AgendaScreen()),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        agendaNowProvider.overrideWithValue(now),
        eventRepositoryProvider.overrideWithValue(repository),
        teamEventsProvider.overrideWith(
          (ref, query) async =>
              const CachedValue(data: <TeamEvent>[], fromCache: false),
        ),
        serviceTemplatesProvider.overrideWith(
          (ref, teamId) async => const <ServiceTemplate>[],
        ),
        teamProvider.overrideWith(
          (ref, teamId) async => const Team(
            id: 't1',
            name: 'Louvor SIBB',
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
              const [
                TeamSummary(
                  membershipId: 'm-Simon',
                  teamId: 't1',
                  name: 'Louvor SIBB',
                  role: 'OWNER',
                  displayName: 'Simon',
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

class _SpyEventRepository extends EventRepository {
  _SpyEventRepository({
    required this.upcoming,
    required this.byRange,
  }) : super(Dio(), _UnusedCache());

  final List<Event> upcoming;
  final Map<String, List<Event>> byRange;

  final List<({String scope, int limit})> listCalls = [];
  final List<({String from, String to})> rangeCalls = [];

  int get totalScheduleQueries => listCalls.length + rangeCalls.length;

  @override
  Future<CachedValue<List<Event>>> list(
    String teamId, {
    String scope = 'upcoming',
    int limit = 20,
  }) async {
    listCalls.add((scope: scope, limit: limit));
    return CachedValue(
      data: scope == 'upcoming' ? upcoming : const <Event>[],
      fromCache: false,
    );
  }

  @override
  Future<CachedValue<List<Event>>> listRange(
    String teamId, {
    required String from,
    required String to,
    bool cache = true,
  }) async {
    rangeCalls.add((from: from, to: to));
    return CachedValue(
      data: byRange['$from..$to'] ?? const <Event>[],
      fromCache: false,
    );
  }

  @override
  Future<CachedValue<Event>> find(String eventId) async {
    final event = upcoming.firstWhere(
      (e) => e.id == eventId,
      orElse: () => Event.fromJson(
        _eventJson(id: eventId, startsAt: '2026-09-10T22:30:00Z'),
      ),
    );
    return CachedValue(data: event, fromCache: true);
  }
}

class _UnusedCache implements ReadCache {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, this._initial);

  final AuthState _initial;

  @override
  Future<void> bootstrap() async {
    state = _initial;
  }
}
