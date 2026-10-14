import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/copilots/data/copilot_repository.dart';
import 'package:louvor_app/features/copilots/domain/copilot_models.dart';
import 'package:louvor_app/features/copilots/presentation/repertoire_copilot_sheet.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';

// A folha do Copiloto de Repertório: um campo só, quantas músicas e quantos
// hinos; depois, tirar, trazer de volta, trocar e usar só as que ficaram.

Map<String, dynamic> _item(String id, {bool hymn = false}) => {
      'songId': id,
      'moment': null,
      'reason': 'Combina com o tema.',
      'concerns': <String>[],
      'song': {
        'id': id,
        'title': 'Música $id',
        if (hymn)
          'hymnals': [
            {
              'hymnalId': 'cc',
              'name': 'Cantor Cristão',
              'abbreviation': 'CC',
              'number': 100,
              'isPrimary': true,
            },
          ],
      },
    };

RepertoireSuggestion _suggestion(
  List<Map<String, dynamic>> songs, {
  int version = 1,
  int? hymns,
}) =>
    RepertoireSuggestion.fromJson({
      'id': 's1',
      'version': version,
      'theme': 'Fidelidade de Deus',
      'hymns': hymns,
      'songs': songs,
    });

class _FakeRepo extends CopilotRepository {
  _FakeRepo() : super(Dio());

  Map<String, Object?>? created;
  Map<String, Object?>? refined;

  @override
  Future<RepertoireDefaults> repertoireDefaults(
    String eventId, {
    required String serviceId,
  }) async =>
      const RepertoireDefaults(count: 3, maxCount: 15, hymnsAvailable: 2);

  @override
  Future<RepertoireSuggestion> suggestRepertoire(
    String eventId, {
    required String serviceId,
    required String theme,
    required int count,
    int? hymns,
  }) async {
    created = {'theme': theme, 'count': count, 'hymns': hymns};
    return _suggestion(
      [
        _item('a'),
        _item('b', hymn: true),
        _item('c'),
        _item('d'),
      ],
      hymns: hymns,
    );
  }

  @override
  Future<RepertoireSuggestion> refineRepertoire(
    String eventId,
    String sessionId, {
    required int baseVersion,
    required String instruction,
    required List<String> lockedSongIds,
    required List<String> excludedSongIds,
    required int count,
    int? hymns,
  }) async {
    refined = {
      'instruction': instruction,
      'locked': lockedSongIds,
      'excluded': excludedSongIds,
      'count': count,
      'hymns': hymns,
    };
    return _suggestion(
      [_item('e'), _item('b', hymn: true), _item('c')],
      version: 2,
      hymns: 1,
    );
  }

  @override
  Future<void> markApplied(
    String eventId,
    String sessionId,
    List<String> songIds,
  ) async {}
}

void main() {
  late _FakeRepo repo;
  List<SuggestedSong>? used;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repo = _FakeRepo();
    used = null;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [copilotRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  used = await showRepertoireCopilot(
                    context,
                    eventId: 'e1',
                    service: EventService(
                      id: 'sv1',
                      label: 'Manhã',
                      startsAt: DateTime.utc(2026, 11, 1, 12),
                    ),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('um campo só; a quantidade começa no de costume e vai além',
      (tester) async {
    await open(tester);
    expect(find.text('Tema e ideia central'), findsOneWidget);
    expect(find.textContaining('Contexto'), findsNothing);
    expect(find.textContaining('costuma ter 3'), findsOneWidget);

    await tester.tap(find.byTooltip('Uma a mais'));
    await tester.tap(find.byTooltip('Uma a mais'));
    await tester.pump();
    await tester.tap(find.text('1'));
    await tester.enterText(find.byType(TextField), 'Fidelidade de Deus');
    await tester.tap(find.text('Sugerir repertório').last);
    await tester.pumpAndSettle();

    expect(
      repo.created,
      {'theme': 'Fidelidade de Deus', 'count': 5, 'hymns': 1},
    );
    expect(find.text('Usar estas 4'), findsOneWidget);
    expect(find.textContaining('Fixe as que você quer manter'), findsOneWidget);
  });

  testWidgets('tirar, trazer de volta e usar só as que ficaram',
      (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Fidelidade de Deus');
    await tester.tap(find.text('Sugerir repertório').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tirar').first);
    await tester.pump();
    expect(find.text('Música a'), findsNothing);
    expect(find.text('1 música tirada'), findsOneWidget);
    expect(find.text('Usar estas 3'), findsOneWidget);

    await tester.tap(find.text('Trazer de volta'));
    await tester.pump();
    expect(find.text('Música a'), findsOneWidget);

    await tester.tap(find.text('Tirar').last);
    await tester.pump();
    await tester.tap(find.text('Usar estas 3'));
    await tester.pumpAndSettle();
    expect(used!.map((s) => s.song.id), ['a', 'b', 'c']);
  });

  testWidgets('"Trocar" fixa as outras, e a trocada e as tiradas não voltam',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('1'));
    await tester.enterText(find.byType(TextField), 'Fidelidade de Deus');
    await tester.tap(find.text('Sugerir repertório').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tirar').last); // d
    await tester.pump();
    await tester.tap(find.text('Trocar').first); // a
    await tester.pumpAndSettle();

    expect(repo.refined, {
      'instruction': 'Troque "Música a" por outra música.',
      'locked': ['b', 'c'],
      'excluded': ['d', 'a'],
      'count': 3,
      'hymns': 1,
    });
    expect(find.text('Música e'), findsOneWidget);
    // A tirada antes da troca não aparece para trazer de volta: ela saiu
    // da sugestão do servidor.
    expect(find.text('Trazer de volta'), findsNothing);
  });
}
