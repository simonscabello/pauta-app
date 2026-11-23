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
import 'package:louvor_app/features/events/data/event_repository.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:louvor_app/features/events/presentation/event_form_screen.dart';
import 'package:louvor_app/features/team/data/team_repository.dart';
import 'package:louvor_app/features/team/domain/service_template.dart';
import 'package:louvor_app/features/team/domain/team_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// A tela de criar escala.
///
/// Ela responde à pergunta que a liderança faz toda semana ("marcar o próximo
/// domingo") e cobrava três decisões antes disso: nomear um culto que não tem
/// nome, achar a data no calendário e, depois de criar, passar por uma tela de
/// repertório que nem toda escala usa.
///
/// **As asserções de data não olham o relógio da máquina.** A grade destes
/// testes tem um dia da semana só, então o dia proposto é sempre daquele dia —
/// rode a suíte na terça ou no sábado.
const _fuso = 'America/Sao_Paulo';

/// Só domingo de manhã: qualquer data proposta a partir dela é um domingo.
const _gradeDeDomingo = [
  ServiceTemplate(id: 'manha', label: 'Manhã', weekday: 0, startMinutes: 510),
];

void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    await initializeDateFormatting('pt_BR');
  });

  testWidgets('a escala nova já abre no próximo dia com culto na grade',
      (tester) async {
    await _pump(tester);

    expect(_domingoNoBotao(), findsOneWidget);
    // E o culto daquele dia já veio junto, como sempre veio.
    expect(find.text('Manhã'), findsOneWidget);
  });

  testWidgets('a data que veio pronta de outra tela não é trocada',
      (tester) async {
    // Uma quarta-feira: dia sem culto na grade, escolhido de propósito noutra
    // tela. Quem chegou dali já decidiu, e a grade não pode opinar.
    await _pump(tester, initialDate: DateTime(2026, 9, 2));

    // O ano só aparece fora do ano atual; o dia e a semana, sempre.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data?.startsWith('Quarta-feira, 2 de setembro') ?? false),
      ),
      findsOneWidget,
    );
  });

  testWidgets('sem grade cadastrada, a tela continua abrindo em hoje',
      (tester) async {
    await _pump(tester, templates: const []);

    expect(find.byType(EventFormScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      find.text('Não há grade para este dia da semana. Adicione o horário.'),
      findsOneWidget,
    );
  });

  testWidgets('o título sai da frente e vive em "Informações adicionais"',
      (tester) async {
    await _pump(tester);

    // A paleta continua na tela principal: é combinado da equipe para o dia.
    expect(find.text('Paleta de roupas (opcional)'), findsOneWidget);
    expect(find.text('Título (opcional)'), findsNothing);

    await tester.tap(find.text('Informações adicionais'));
    await tester.pumpAndSettle();

    expect(find.text('Título (opcional)'), findsOneWidget);
    expect(find.text('Local (opcional)'), findsOneWidget);
    expect(find.text('Observações (opcional)'), findsOneWidget);
  });

  testWidgets('criar uma escala comum manda repertório planejado',
      (tester) async {
    final harness = await _pump(tester);

    await tester.tap(find.text('Criar escala'));
    await tester.pumpAndSettle();

    expect(harness.repository.modoPedido, RepertoireMode.planned);
    expect(harness.rotaSeguinte, '/agenda/nova/escalar?novo=1');
  });

  testWidgets('escolher "Na hora" grava o modo e avisa o que ele desliga',
      (tester) async {
    final harness = await _pump(tester);

    await tester.tap(find.text('Na hora'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Quem ministra escolhe no culto'),
      findsOneWidget,
    );

    await tester.tap(find.text('Criar escala'));
    await tester.pumpAndSettle();

    expect(harness.repository.modoPedido, RepertoireMode.onTheFly);
    // A escalação continua sendo o passo seguinte; quem decide se depois vem
    // o repertório é ela, olhando a escala que acabou de ser gravada.
    expect(harness.rotaSeguinte, '/agenda/nova/escalar?novo=1');
  });

  testWidgets('editando, a seção abre sozinha quando há o que mostrar',
      (tester) async {
    await _pump(tester, eventId: 'e1');

    // Sem abrir nada: o que já foi escrito não pode ficar escondido.
    expect(find.text('Título (opcional)'), findsOneWidget);
    expect(find.text('Páscoa'), findsOneWidget);
  });
}

Finder _domingoNoBotao() => find.byWidgetPredicate(
      (widget) =>
          widget is Text && (widget.data?.startsWith('Domingo, ') ?? false),
      description: 'a data proposta é um domingo',
    );

class _Harness {
  _Harness(this.repository);

  final _RepositorioFake repository;

  /// Para onde a criação emendou.
  String? rotaSeguinte;
}

class _RepositorioFake extends EventRepository {
  _RepositorioFake(super.dio, super.cache);

  RepertoireMode? modoPedido;

  @override
  Future<Event> create(
    String teamId, {
    required String title,
    required List<Map<String, String?>> services,
    String? rehearsalAt,
    String? rehearsalNotes,
    String? location,
    String? notes,
    String? colorPalette,
    RepertoireMode repertoireMode = RepertoireMode.planned,
  }) async {
    modoPedido = repertoireMode;
    return Event.fromJson(_escalaJson(id: 'nova'));
  }
}

class _EquipeFake extends TeamRepository {
  _EquipeFake(super.dio);

  @override
  Future<Team> find(String teamId) async =>
      const Team(id: 't1', name: 'Ministério de Louvor', timezone: _fuso);
}

Map<String, dynamic> _escalaJson({required String id}) => {
      'id': id,
      'teamId': 't1',
      'title': 'Páscoa',
      'startsAt': '2026-09-06T11:30:00.000Z',
      'rehearsalAt': null,
      'location': null,
      'notes': null,
      'colorPalette': null,
      'status': 'DRAFT',
      'timezone': _fuso,
      'assignments': const [],
      'songs': const [],
      'services': [
        {'id': 's1', 'label': 'Manhã', 'startsAt': '2026-09-06T11:30:00.000Z'},
      ],
    };

Future<_Harness> _pump(
  WidgetTester tester, {
  List<ServiceTemplate> templates = _gradeDeDomingo,
  DateTime? initialDate,
  String? eventId,
}) async {
  tester.view.physicalSize = const Size(375, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  final harness = _Harness(_RepositorioFake(Dio(), ReadCache(prefs)));

  final router = GoRouter(
    initialLocation: '/agenda/novo',
    routes: [
      GoRoute(
        path: '/agenda/novo',
        builder: (_, __) =>
            EventFormScreen(eventId: eventId, initialDate: initialDate),
      ),
      GoRoute(
        path: '/agenda/:id/escalar',
        builder: (_, state) {
          harness.rotaSeguinte = '/agenda/${state.pathParameters['id']}'
              '/escalar?novo=${state.uri.queryParameters['novo']}';
          return const Scaffold(body: Text('escalar'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        eventRepositoryProvider.overrideWithValue(harness.repository),
        teamRepositoryProvider.overrideWithValue(_EquipeFake(Dio())),
        eventProvider.overrideWith(
          (ref, id) async => CachedValue(
            data: Event.fromJson(_escalaJson(id: id)),
            fromCache: false,
          ),
        ),
        serviceTemplatesProvider.overrideWith((ref, teamId) async => templates),
        teamProvider.overrideWith(
          (ref, teamId) async => const Team(
            id: 't1',
            name: 'Ministério de Louvor',
            timezone: _fuso,
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
              const [
                TeamSummary(
                  membershipId: 'm1',
                  teamId: 't1',
                  name: 'Ministério de Louvor',
                  role: 'OWNER',
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

  return harness;
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, this._initial);

  final AuthState _initial;

  @override
  Future<void> bootstrap() async {
    state = _initial;
  }
}
