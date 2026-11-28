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
import 'package:louvor_app/features/team/data/team_repository.dart';
import 'package:louvor_app/features/team/domain/service_template.dart';
import 'package:louvor_app/features/team/domain/team_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// A grade da igreja já dizia quais são os próximos domingos, mas isso só
/// existia dentro do formulário de nova escala. Aqui ela aparece na agenda: as
/// datas que ainda não viraram escala, para a liderança ver o mês inteiro sem
/// precisar criar nada antes.
///
/// A contagem destes testes é estável por construção: **vinte e oito dias
/// contêm exatamente quatro de cada dia da semana**, então uma grade com
/// domingo e quinta propõe oito datas em qualquer dia em que o teste rode.
void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    await initializeDateFormatting('pt_BR');
  });

  testWidgets('a agenda vazia mostra as datas que a grade prevê',
      (tester) async {
    await _pump(tester);

    await _abrirDatas(tester);
    expect(find.text('Datas sem escala'), findsOneWidget);
    expect(find.text('Criar os rascunhos destas 8 datas'), findsOneWidget);
    // E some o beco sem saída que estava ali antes.
    expect(find.text('Nenhuma escala marcada'), findsNothing);
  });

  for (final width in [375.0, 768.0, 1440.0]) {
    testWidgets('não estoura em ${width.toInt()}px', (tester) async {
      // Acima de 880px a linha vira colunas, como as escalas. Um
      // `RenderFlex overflow` aqui apareceria na primeira tela do app.
      //
      // As duas situações em que o grupo aparece, porque cada uma monta a
      // lista por um caminho: a agenda vazia e a agenda com escala.
      await _pump(tester, size: Size(width, 900));
      expect(tester.takeException(), isNull);
      await _abrirDatas(tester);
      expect(find.text('Datas sem escala'), findsOneWidget);

      final futura = DateTime.now().toUtc().add(const Duration(days: 200));
      await _pump(
        tester,
        size: Size(width, 900),
        events: [_evento(futura)],
      );
      expect(tester.takeException(), isNull);
      await _abrirDatas(tester);
      expect(find.text('Datas sem escala'), findsOneWidget);
    });
  }

  testWidgets('o recorte pessoal esconde as datas em aberto', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Minhas escalas'));
    await tester.pumpAndSettle();

    // Nenhuma data em aberto é "sua": não há ninguém escalado nela, e
    // deixá-las ali faria o recorte pessoal mentir.
    expect(find.textContaining('datas sem escala'), findsNothing);
    expect(find.text('Nada seu por perto.'), findsOneWidget);
  });

  testWidgets('quem não gerencia não vê datas em aberto', (tester) async {
    await _pump(tester, canManage: false);

    expect(find.textContaining('datas sem escala'), findsNothing);
    expect(find.text('Nada marcado para este dia.'), findsOneWidget);
  });

  testWidgets('sem grade cadastrada a agenda volta ao estado vazio de sempre',
      (tester) async {
    await _pump(tester, templates: const []);

    expect(find.textContaining('datas sem escala'), findsNothing);
    expect(find.text('Nada marcado para este dia.'), findsOneWidget);
  });

  testWidgets('as datas convivem com as escalas que já existem',
      (tester) async {
    // Uma escala fora da janela de quatro semanas: ela vira a manchete e não
    // tira nenhuma data da lista.
    final futura = DateTime.now().toUtc().add(const Duration(days: 200));
    final harness = await _pump(tester, events: [_evento(futura)]);

    expect(find.text('Agenda'), findsOneWidget);
    await _abrirDatas(tester);
    expect(find.text('Datas sem escala'), findsOneWidget);
    expect(find.text('Criar os rascunhos destas 8 datas'), findsOneWidget);
    expect(harness.dataPedida, isNull);
  });

  testWidgets('tocar numa data abre a nova escala já naquele dia',
      (tester) async {
    final harness = await _pump(tester);

    await _abrirDatas(tester);
    await tester
        .ensureVisible(find.byIcon(Icons.add_circle_outline_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('nova escala'), findsOneWidget);
    // A data vai na rota, no formato que o formulário entende.
    expect(harness.dataPedida, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    final pedida = DateTime.parse(harness.dataPedida!);
    // "Hoje" é o de São Paulo, e não o do relógio de quem roda o teste.
    //
    // `openDates` conta o dia civil no fuso da EQUIPE -- é a regra do produto,
    // e a mesma que separa "próximas" de "passadas" na agenda. Comparar com
    // `DateTime.now()` media o dia da MÁQUINA: passava no Brasil e reprovava
    // no CI, que roda em UTC, em toda execução entre 21h e meia-noite de
    // Brasília, quando lá já é o dia seguinte e aqui ainda não. O teste
    // falhava dizendo que a agenda propôs uma data no passado; ela tinha
    // proposto hoje.
    final hojeNaEquipe = tz.TZDateTime.from(
      DateTime.now(),
      tz.getLocation(_fusoDaEquipe),
    );
    expect(
      pedida.isBefore(
        DateTime(hojeNaEquipe.year, hojeNaEquipe.month, hojeNaEquipe.day),
      ),
      isFalse,
      reason: 'a primeira data em aberto não pode estar no passado',
    );
  });

  testWidgets('criar os rascunhos pergunta antes e usa a mesma janela',
      (tester) async {
    final harness = await _pump(tester);

    await _tocarEmCriar(tester);

    expect(find.text('Criar 8 rascunhos?'), findsOneWidget);
    expect(harness.repository.semanasPedidas, isNull);

    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();

    // A mesma janela que a lista mostrou: o botão não pode criar mais datas do
    // que as que estavam na tela.
    expect(harness.repository.semanasPedidas, 4);
    expect(find.text('8 rascunhos criados.'), findsOneWidget);
  });

  testWidgets('desistir da confirmação não cria nada', (tester) async {
    final harness = await _pump(tester);

    await _tocarEmCriar(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(harness.repository.semanasPedidas, isNull);
    // A lista continua aberta, com as mesmas datas.
    expect(
      find.text('Criar os rascunhos destas 8 datas', skipOffstage: false),
      findsOneWidget,
    );
  });
}

/// A linha de criar fecha o grupo, abaixo das oito datas: num celular ela
/// nasce fora da tela, e tocar sem rolar até lá erraria o alvo.
Future<void> _tocarEmCriar(WidgetTester tester) async {
  final botao = find.text('Criar os rascunhos destas 8 datas');
  await _abrirDatas(tester);
  await tester.ensureVisible(botao);
  await tester.pumpAndSettle();
  await tester.tap(botao);
  await tester.pumpAndSettle();
}

/// O fuso da equipe do teste. É o mesmo do `_evento` e o mesmo que a agenda
/// usa para contar os dias -- toda asserção sobre "hoje" tem de medir por
/// ele, não pelo relógio da máquina que roda a suíte.
const _fusoDaEquipe = 'America/Sao_Paulo';

/// Domingo de manhã e de noite, mais a quinta — a grade da igreja de verdade.
const _grade = [
  ServiceTemplate(
    id: 'manha',
    label: 'Manhã',
    weekday: 0,
    startMinutes: 510,
  ),
  ServiceTemplate(
    id: 'noite',
    label: 'Noite',
    weekday: 0,
    startMinutes: 1140,
  ),
  ServiceTemplate(
    id: 'oracao',
    label: 'Oração',
    weekday: 4,
    startMinutes: 1170,
  ),
];

Event _evento(DateTime startsAt) => Event.fromJson({
      'id': 'e1',
      'teamId': 't1',
      'title': null,
      'startsAt': startsAt.toIso8601String(),
      'rehearsalAt': null,
      'location': null,
      'notes': null,
      'colorPalette': null,
      'status': 'PUBLISHED',
      'timezone': _fusoDaEquipe,
      'assignments': const [],
      'songs': const [],
    });

class _Harness {
  _Harness(this.repository);

  final _RepositorioFake repository;

  /// A data que a rota de nova escala recebeu, quando alguém tocou numa linha.
  String? dataPedida;
}

class _RepositorioFake extends EventRepository {
  _RepositorioFake(super.dio, super.cache);

  int? semanasPedidas;

  @override
  Future<GeneratedSchedules> generate(
    String teamId, {
    required int weeks,
  }) async {
    semanasPedidas = weeks;
    return const GeneratedSchedules(createdCount: 8, skippedCount: 0);
  }
}

Future<_Harness> _pump(
  WidgetTester tester, {
  bool canManage = true,
  List<ServiceTemplate> templates = _grade,
  List<Event> events = const [],
  Size size = const Size(375, 812),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  final harness = _Harness(_RepositorioFake(Dio(), ReadCache(prefs)));

  final router = GoRouter(
    initialLocation: '/agenda',
    routes: [
      GoRoute(path: '/agenda', builder: (_, __) => const AgendaScreen()),
      GoRoute(
        path: '/agenda/novo',
        builder: (_, state) {
          harness.dataPedida = state.uri.queryParameters['data'];
          return const Scaffold(body: Text('nova escala'));
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
        eventsProvider.overrideWith(
          (ref, query) async => CachedValue(data: events, fromCache: false),
        ),
        agendaMonthProvider.overrideWith(
          (ref, query) async => CachedValue(data: events, fromCache: false),
        ),
        serviceTemplatesProvider.overrideWith((ref, teamId) async => templates),
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
                name: 'Samuel',
                email: 'samuel@teste.com',
                mustChangePassword: false,
              ),
              [
                TeamSummary(
                  membershipId: 'm1',
                  teamId: 't1',
                  name: 'Ministério de Louvor',
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
      ),
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

/// As datas em aberto moram recolhidas numa linha-resumo logo abaixo do dia
/// ("8 datas sem escala"); a lista abre ao tocar nela.
Future<void> _abrirDatas(WidgetTester tester) async {
  final resumo = find.textContaining('datas sem escala');
  await tester.scrollUntilVisible(
    resumo,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  if (find.text('Datas sem escala').evaluate().isEmpty) {
    await tester.tap(resumo);
    await tester.pumpAndSettle();
  }
  await tester.scrollUntilVisible(
    find.text('Datas sem escala'),
    250,
    scrollable: find.byType(Scrollable).first,
  );
}
