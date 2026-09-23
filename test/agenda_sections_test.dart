import 'dart:async';

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
import 'package:louvor_app/features/events/data/event_repository.dart';
import 'package:louvor_app/features/events/data/agenda_provider.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:louvor_app/features/events/presentation/agenda_event_tile.dart';
import 'package:louvor_app/features/events/presentation/agenda_screen.dart';
import 'package:louvor_app/features/team/data/team_repository.dart';
import 'package:louvor_app/features/team/domain/service_template.dart';
import 'package:louvor_app/features/team/domain/team_models.dart';
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
      load: (scope) async => CachedValue(
        data: scope == 'past'
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
    final pending = Completer<CachedValue<List<Event>>>();
    var failed = true;
    await _pumpAgenda(
      tester,
      const Size(400, 1400),
      settle: false,
      load: (_) => failed
          ? pending.future
          : Future.value(
              const CachedValue(data: <Event>[], fromCache: false),
            ),
    );
    expect(find.text('Setembro 2026'), findsOneWidget);
    expect(find.text('Nada marcado para este dia.'), findsNothing);
    pending.completeError(Exception('offline'));
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
      load: (scope) async => CachedValue(
        data: scope == 'past'
            ? List.generate(
                20,
                (i) => Event.fromJson(
                  _eventJson(
                    id: 'p$i',
                    startsAt: '2026-09-08T22:30:00Z',
                  ),
                ),
              )
            : <Event>[],
        fromCache: true,
        cachedAt: DateTime.utc(2026, 9, 9, 12),
      ),
    );
    await tester.tap(find.byTooltip('Mês anterior'));
    await tester.pumpAndSettle();
    expect(find.text('Nada marcado para este dia.'), findsNothing);
    expect(find.text('Nenhum compromisso neste mês.'), findsNothing);
    // Trocar de mês não escolhe mais o dia 1 sozinho: sem compromisso
    // conhecido no mês, nenhum dia fica escolhido — e nada é afirmado sobre
    // um dia que ninguém pediu.
    expect(find.text('Não carregou tudo deste dia.'), findsNothing);
    expect(find.textContaining('Sem conexão.'), findsOneWidget);
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
  Future<CachedValue<List<Event>>> Function(String scope)? load,
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
        if (load != null)
          agendaEventsProvider.overrideWith((ref, query) => load(query.$2)),
        sharedPreferencesProvider.overrideWithValue(prefs),
        agendaNowProvider.overrideWithValue(DateTime.utc(2026, 9, 9, 16)),
        eventsProvider.overrideWith(
          (ref, query) async => CachedValue(
            data: query.$2 == 'upcoming' ? events : <Event>[],
            fromCache: false,
          ),
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

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, this._initial);

  final AuthState _initial;

  @override
  Future<void> bootstrap() async {
    state = _initial;
  }
}
