import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:louvor_app/core/storage/read_cache.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/auth/application/auth_controller.dart';
import 'package:louvor_app/features/auth/domain/auth_models.dart';
import 'package:louvor_app/features/events/data/event_repository.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:louvor_app/features/events/presentation/event_detail_screen.dart';
import 'package:louvor_app/shared/widgets/app_avatar.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// A seção de integrantes da escala.
///
/// Duas coisas se protegem aqui, e as duas existem pela **mesma** razão: o que
/// traz o músico a esta tela é o repertório. Uma banda completa com multimídia
/// passa de doze pessoas, e doze linhas de nome empurravam as músicas para
/// fora da tela — daí o "Ver mais". E reconhecer pelo rosto é mais rápido do
/// que ler oito nomes — daí a foto, com a inicial de sempre como reserva.
void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    await initializeDateFormatting('pt_BR');
  });

  testWidgets('escala pequena aparece inteira, sem "Ver mais"', (tester) async {
    await _pumpEscala(tester, _evento(nomes: ['Ana', 'Bruno', 'Caio']));

    for (final nome in ['Ana', 'Bruno', 'Caio']) {
      expect(find.text(nome), findsOneWidget);
    }
    expect(find.textContaining('Ver mais'), findsNothing);
    expect(find.text('Ver menos'), findsNothing);
  });

  /// Com **um** a mais que o limite, esconder essa pessoa gastaria a mesma
  /// linha que mostrá-la.
  testWidgets('seis integrantes ainda cabem sem recolher', (tester) async {
    await _pumpEscala(
      tester,
      _evento(nomes: ['Ana', 'Bruno', 'Caio', 'Davi', 'Elias', 'Fábio']),
    );

    expect(find.text('Fábio'), findsOneWidget);
    expect(find.textContaining('Ver mais'), findsNothing);
  });

  testWidgets('escala grande mostra cinco e diz quantos faltam',
      (tester) async {
    await _pumpEscala(tester, _evento(nomes: _nomes(12)));

    expect(find.text('Pessoa 1'), findsOneWidget);
    expect(find.text('Pessoa 5'), findsOneWidget);
    expect(find.text('Pessoa 6'), findsNothing);
    expect(find.text('Ver mais 7 integrantes'), findsOneWidget);

    // E as músicas continuam inteiras: o recolhimento é só dos nomes.
    expect(find.text('Meu Deus, meu Rei'), findsOneWidget);
  });

  testWidgets('mapa de tons avisa o salto, e a música tocada fica marcada',
      (tester) async {
    await _pumpEscala(
      tester,
      _evento(nomes: ['Ana'], musicas: {'Um': 'G', 'Dois': 'Bb', 'Três': 'C'}),
    );

    expect(
      find.textContaining('Tons: G → Bb → C', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Salto de tom: G → Bb', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Marcar como tocada').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Desmarcar como tocada'), findsOneWidget);
    await tester.tap(find.byTooltip('Desmarcar como tocada'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Marcar como tocada'), findsNWidgets(3));
  });

  testWidgets('"Ver mais" abre a lista e vira "Ver menos"', (tester) async {
    await _pumpEscala(tester, _evento(nomes: _nomes(12)));

    await tester.tap(find.text('Ver mais 7 integrantes'));
    await tester.pumpAndSettle();

    expect(find.text('Pessoa 12'), findsOneWidget);
    expect(find.text('Ver menos'), findsOneWidget);

    await tester.tap(find.text('Ver menos'));
    await tester.pumpAndSettle();

    expect(find.text('Pessoa 12'), findsNothing);
    expect(find.text('Ver mais 7 integrantes'), findsOneWidget);
  });

  testWidgets('o singular não vira "1 integrantes"', (tester) async {
    await _pumpEscala(tester, _evento(nomes: _nomes(7)));

    expect(find.text('Ver mais 2 integrantes'), findsOneWidget);

    await tester.tap(find.text('Ver mais 2 integrantes'));
    await tester.pumpAndSettle();
    expect(find.text('Pessoa 7'), findsOneWidget);
  });

  testWidgets('quem tem foto leva a foto; quem não tem fica com a inicial',
      (tester) async {
    await _pumpEscala(
      tester,
      _evento(
        nomes: ['Ana', 'Bruno'],
        fotos: {'Ana': '/uploads/avatars/ana.jpg'},
      ),
    );

    final avatares = tester
        .widgetList<AppAvatar>(find.byType(AppAvatar))
        .where((a) => a.name == 'Ana' || a.name == 'Bruno')
        .toList();

    expect(
      avatares.firstWhere((a) => a.name == 'Ana').imageUrl,
      '/uploads/avatars/ana.jpg',
    );
    expect(avatares.firstWhere((a) => a.name == 'Bruno').imageUrl, isNull);
  });

  /// O `HttpClient` do `flutter_test` recusa toda requisição, então esta é a
  /// própria situação de "a foto não carregou": o que não pode acontecer é a
  /// lista ficar com um buraco ou um ícone quebrado no lugar da pessoa.
  testWidgets('foto que não carrega volta para a inicial do nome',
      (tester) async {
    await _pumpEscala(
      tester,
      _evento(
        nomes: ['Ana'],
        fotos: {'Ana': '/uploads/avatars/inexistente.jpg'},
      ),
    );
    await tester.pump();

    expect(find.text('A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('confirmação de presença', () {
    final futuro =
        DateTime.now().toUtc().add(const Duration(days: 3)).toIso8601String();

    testWidgets('quem está escalado e não respondeu vê a pergunta',
        (tester) async {
      await _pumpEscala(
        tester,
        _evento(nomes: ['Ana', 'Bruno'], quando: futuro),
        souEu: 'm0',
        papel: 'MEMBER',
      );
      expect(find.text('Você confirma presença?'), findsOneWidget);
      expect(find.text('Confirmo'), findsOneWidget);
      expect(find.text('Não posso'), findsOneWidget);
    });

    testWidgets('quem respondeu vê a resposta, e a lista marca cada um',
        (tester) async {
      await _pumpEscala(
        tester,
        _evento(
          nomes: ['Ana', 'Bruno'],
          quando: futuro,
          respostas: {'m0': 'CONFIRMED', 'm1': 'DECLINED'},
        ),
        souEu: 'm0',
        papel: 'MEMBER',
      );
      expect(find.text('Você confirmou presença'), findsOneWidget);
      expect(find.byTooltip('Confirmou presença'), findsOneWidget);
      expect(find.text('Não pode'), findsOneWidget);
      // Trocar gente é de quem lidera.
      expect(find.text('Substituir Bruno'), findsNothing);
    });

    testWidgets('quem lidera vê a recusa com o atalho para substituir',
        (tester) async {
      await _pumpEscala(
        tester,
        _evento(
          nomes: ['Ana', 'Bruno'],
          quando: futuro,
          respostas: {'m1': 'DECLINED'},
        ),
      );
      expect(find.text('Bruno respondeu que não pode'), findsOneWidget);
      expect(find.text('Substituir Bruno'), findsOneWidget);
      // Fora da escala, ninguém pergunta se ele vem.
      expect(find.text('Você confirma presença?'), findsNothing);
    });

    testWidgets('quem está fora da escala pode se oferecer para cobrir',
        (tester) async {
      await _pumpEscala(
        tester,
        _evento(
          nomes: ['Ana', 'Bruno'],
          quando: futuro,
          respostas: {'m1': 'DECLINED'},
        ),
        papel: 'MEMBER',
      );
      expect(find.text('Bruno não pode servir neste dia'), findsOneWidget);
      expect(find.text('Posso cobrir'), findsOneWidget);
    });

    Event comOferta() => _evento(
          nomes: ['Ana', 'Bruno'],
          quando: futuro,
          respostas: {'m1': 'DECLINED'},
          cobre: {'m1': 'Carla'},
        );

    testWidgets('com oferta, quem lidera aprova', (tester) async {
      await _pumpEscala(tester, comOferta());
      expect(
        find.text('Carla se ofereceu para cobrir Vocalista.'),
        findsOneWidget,
      );
      expect(find.text('Aprovar Carla'), findsOneWidget);
      expect(find.text('Escolher outra pessoa'), findsOneWidget);

    });

    testWidgets('com oferta, os outros não são chamados', (tester) async {
      await _pumpEscala(tester, comOferta(), souEu: 'm-outro', papel: 'MEMBER');
      expect(find.text('Posso cobrir'), findsNothing);
    });

    testWidgets('quem se ofereceu pode desistir', (tester) async {
      await _pumpEscala(tester, comOferta(), souEu: 'm-Carla', papel: 'MEMBER');
      expect(find.text('Você se ofereceu para cobrir Bruno'), findsOneWidget);
      expect(find.text('Desistir'), findsOneWidget);
    });

    testWidgets('com ensaio por vir, pergunta do ensaio e mostra quem vai',
        (tester) async {
      final json = _evento(nomes: ['Ana', 'Bruno'], quando: futuro);
      final evento = Event.fromJson({
        'id': json.id,
        'teamId': json.teamId,
        'title': null,
        'startsAt': futuro,
        'rehearsalAt': DateTime.now()
            .toUtc()
            .add(const Duration(days: 2))
            .toIso8601String(),
        'location': null,
        'notes': null,
        'colorPalette': null,
        'status': 'PUBLISHED',
        'timezone': 'America/Sao_Paulo',
        'services': [
          {'id': 's1', 'label': 'Manhã', 'startsAt': futuro, 'sortOrder': 0},
        ],
        'assignments': [
          {
            'positionId': 'p1',
            'positionName': 'Vocalista',
            'sortOrder': 0,
            'members': [
              for (final (i, nome) in ['Ana', 'Bruno'].indexed)
                {
                  'id': 'a$i',
                  'membershipId': 'm$i',
                  'displayName': nome,
                  'note': null,
                  'isRegisteredForPosition': true,
                },
            ],
          },
        ],
        'songs': const <Object>[],
        'rehearsalAttendance': [
          {'membershipId': 'm1', 'attending': false},
        ],
      });
      await _pumpEscala(tester, evento, souEu: 'm0', papel: 'MEMBER');
      expect(find.text('Você vai ao ensaio?'), findsOneWidget);
      expect(find.text('Vou'), findsOneWidget);
      expect(find.text('Não vai: Bruno'), findsOneWidget);
    });

    testWidgets('escala que já passou não pergunta nada', (tester) async {
      await _pumpEscala(tester, _evento(nomes: ['Ana']), souEu: 'm0');
      expect(find.text('Você confirma presença?'), findsNothing);
    });
  });

  for (final width in [320.0, 375.0, 1280.0]) {
    testWidgets('não estoura em ${width.toInt()}px', (tester) async {
      await _pumpEscala(tester, _evento(nomes: _nomes(12)), size: Size(width, 900));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Ver mais 7 integrantes'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

List<String> _nomes(int quantos) =>
    [for (var i = 1; i <= quantos; i++) 'Pessoa $i'];

/// Uma escala com todo mundo na mesma função: o corte do "Ver mais" atravessa
/// os grupos, e um grupo só é o caso mais simples de conferir.
Event _evento({
  required List<String> nomes,
  Map<String, String> fotos = const {},
  Map<String, String> musicas = const {'Meu Deus, meu Rei': 'G'},
  String quando = '2026-08-09T12:00:00.000Z',
  Map<String, String> respostas = const {},
  Map<String, String> cobre = const {},
}) {
  return Event.fromJson({
    'id': 'e1',
    'teamId': 't1',
    'title': null,
    'startsAt': quando,
    'confirmations': [
      for (final r in respostas.entries)
        {
          'membershipId': r.key,
          'status': r.value,
          if (cobre[r.key] case final nome?)
            'coverOffer': {'membershipId': 'm-$nome', 'displayName': nome},
        },
    ],
    'rehearsalAt': null,
    'location': null,
    'notes': null,
    'colorPalette': null,
    'status': 'PUBLISHED',
    'timezone': 'America/Sao_Paulo',
    'services': [
      {
        'id': 's1',
        'label': 'Manhã',
        'startsAt': quando,
        'sortOrder': 0,
      },
    ],
    'assignments': [
      {
        'positionId': 'p1',
        'positionName': 'Vocalista',
        'sortOrder': 0,
        'members': [
          for (var i = 0; i < nomes.length; i++)
            {
              'id': 'a$i',
              'membershipId': 'm$i',
              'displayName': nomes[i],
              'note': null,
              'isRegisteredForPosition': true,
              'avatarUrl': fotos[nomes[i]],
            },
        ],
      },
    ],
    'songs': [
      for (final (i, musica) in musicas.entries.indexed)
        {
          'songId': 'mus${i + 1}',
          'serviceId': 's1',
          'title': musica.key,
          'artist': null,
          'key': musica.value,
          'note': null,
          'isNew': false,
        },
    ],
  });
}

Future<void> _pumpEscala(
  WidgetTester tester,
  Event event, {
  Size size = const Size(400, 1600),
  String souEu = 'm-lider',
  String papel = 'OWNER',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/agenda/e1',
    routes: [
      GoRoute(
        path: '/agenda/:id',
        builder: (_, __) => const EventDetailScreen(eventId: 'e1'),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eventProvider.overrideWith(
          (ref, id) async => CachedValue(data: event, fromCache: false),
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
                  // Fora da escala: o "(você)" da própria linha não entra
                  // nestes testes, que são sobre a lista.
                  membershipId: souEu,
                  teamId: 't1',
                  name: 'Ministerio de Louvor',
                  role: papel,
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
