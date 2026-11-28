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
import 'package:louvor_app/features/team/data/team_repository.dart';
import 'package:louvor_app/features/team/domain/service_template.dart';
import 'package:louvor_app/features/team/domain/team_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// A agenda tem duas arrumações: no celular o calendário e o dia empilhados;
/// no monitor, lado a lado, com a lista de escalas em colunas.
///
/// O que estes testes protegem não é a aparência — é que **nenhuma** das
/// larguras da lista de verificação estoure, e que o conteúdo continue o mesmo
/// nas duas. Um `RenderFlex overflow` aqui aparece na aba que a equipe mais
/// abre depois da Home.
void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    await initializeDateFormatting('pt_BR');
  });

  for (final width in [
    320.0,
    375.0,
    600.0,
    768.0,
    1024.0,
    1280.0,
    1440.0,
    1920.0,
  ]) {
    testWidgets('não estoura em ${width.toInt()}px', (tester) async {
      await _pumpAgenda(tester, Size(width, 900));
      expect(tester.takeException(), isNull);
      expect(find.text('Agenda'), findsOneWidget);

      // O recorte pessoal tem outra lista e outra legenda; o que ele não pode
      // ter é outra largura.
      await tester.tap(find.text('Minhas escalas'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Seus compromissos'), findsOneWidget);
    });
  }

  testWidgets('no celular a criação fica no polegar, como na Home',
      (tester) async {
    await _pumpAgenda(tester, const Size(375, 812));

    expect(find.widgetWithText(FloatingActionButton, 'Nova'), findsOneWidget);
    // E num lugar só: o botão do cabeçalho é o mesmo, e some no celular --
    // por isso o tooltip aparece uma vez, e não duas.
    expect(find.byTooltip('Criar escala ou evento'), findsOneWidget);
  });

  testWidgets('no monitor a ação principal sobe para o cabeçalho',
      (tester) async {
    await _pumpAgenda(tester, const Size(1440, 900));

    expect(find.byType(FloatingActionButton), findsNothing);
    // Continua existindo — mudou de lugar, não sumiu.
    expect(find.byTooltip('Criar escala ou evento'), findsOneWidget);
  });

  testWidgets('não repete painel da Home em nenhuma largura', (tester) async {
    await _pumpAgenda(tester, const Size(375, 812));
    expect(find.textContaining('escalas com você'), findsNothing);

    await _pumpAgenda(tester, const Size(1440, 900));
    expect(find.textContaining('escala com você'), findsNothing);
  });

  testWidgets('quem não gerencia não vê a contagem de rascunhos',
      (tester) async {
    await _pumpAgenda(tester, const Size(1440, 900), canManage: false);

    expect(find.textContaining('rascunho'), findsNothing);
    expect(find.byTooltip('Criar escala ou evento'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Criar escala'), findsNothing);
    expect(find.textContaining('escala com você'), findsNothing);
  });

  // A fonte do sistema aumentada é o segundo eixo do problema, e o mais fácil
  // de esquecer: quem usa o app está com o instrumento na mão, e "texto
  // grande" ligado no Android é comum nessa faixa. O que aperta aqui são as
  // 48 células do calendário e a linha da escala, com horários e a pílula
  // "VOCÊ" no mesmo bloco.
  for (final scale in [1.3, 1.6, 2.0]) {
    testWidgets('não estoura com a fonte do sistema em ${scale}x',
        (tester) async {
      await _pumpAgenda(tester, const Size(360, 900), textScale: scale);
      expect(tester.takeException(), isNull);

      await _pumpAgenda(tester, const Size(1280, 900), textScale: scale);
      expect(tester.takeException(), isNull);
    });
  }
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

Future<void> _pumpAgenda(
  WidgetTester tester,
  Size size, {
  bool canManage = true,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  final events = [
    Event.fromJson(
      _eventJson(
        id: 'e1',
        startsAt: '2026-08-09T12:00:00.000Z',
        assignments: [
          {
            'positionId': 'p1',
            'positionName': 'Guitarra',
            'sortOrder': 0,
            'members': [
              {
                'id': 'a1',
                'membershipId': 'm1',
                'displayName': 'Samuel',
                'note': null,
                'isRegisteredForPosition': true,
              },
            ],
          },
        ],
      ),
    ),
    Event.fromJson(
      _eventJson(
        id: 'e2',
        startsAt: '2026-08-16T12:00:00.000Z',
        status: 'DRAFT',
      ),
    ),
  ];

  final router = GoRouter(
    initialLocation: '/agenda',
    routes: [
      GoRoute(path: '/agenda', builder: (_, __) => const AgendaScreen()),
      GoRoute(
        path: '/agenda/novo',
        builder: (_, __) => const Scaffold(body: Text('novo')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        eventsProvider.overrideWith(
          (ref, query) async => CachedValue(data: events, fromCache: false),
        ),
        agendaMonthProvider.overrideWith(
          (ref, query) async => CachedValue(data: events, fromCache: false),
        ),
        // A agenda também consulta a grade de cultos, para propor as datas que
        // ainda não viraram escala. Aqui ela vai vazia de propósito: estes
        // testes são sobre a arrumação da lista, e uma grade cadastrada
        // acrescentaria linhas que mudam conforme o dia em que o teste roda.
        // Quem cobre as datas em aberto é `open_dates_agenda_test.dart`.
        serviceTemplatesProvider.overrideWith(
          (ref, teamId) async => const <ServiceTemplate>[],
        ),
        teamProvider.overrideWith(
          (ref, teamId) async => const Team(
            id: 't1',
            name: 'Ministerio de Louvor',
            timezone: 'America/Sao_Paulo',
          ),
        ),
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
                  role: canManage ? 'OWNER' : 'MEMBER',
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

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, this._initial);

  final AuthState _initial;

  @override
  Future<void> bootstrap() async {
    state = _initial;
  }
}
