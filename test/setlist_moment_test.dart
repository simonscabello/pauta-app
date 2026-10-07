import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:louvor_app/features/copilots/data/copilot_repository.dart';
import 'package:louvor_app/features/copilots/domain/copilot_models.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:louvor_app/features/events/presentation/setlist_form_screen.dart';
import 'package:louvor_app/features/songs/data/song_repository.dart';
import 'package:louvor_app/features/suggestions/data/suggestion_repository.dart';
import 'package:louvor_app/features/suggestions/domain/song_suggestion.dart';
import 'package:louvor_app/shared/widgets/app_badge.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// O momento do culto na tela de montar o repertório.
///
/// É onde a escolha acontece: a mesma folha que ajusta o tom desta escala
/// ajusta o momento, porque os dois são da linha da escala e não do cadastro
/// da música — "Estou Seguro" é oferta num domingo e abertura no outro.
void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    await initializeDateFormatting('pt_BR');
  });

  Widget repertorio() {
    final event = Event.fromJson({
      'id': 'e1',
      'teamId': 't1',
      'startsAt': '2026-08-16T12:00:00.000Z',
      'status': 'PUBLISHED',
      'timezone': 'America/Sao_Paulo',
      'services': [
        {'id': 'sv1', 'label': 'Culto', 'startsAt': '2026-08-16T12:00:00.000Z'},
      ],
      'assignments': [],
      'songs': [
        {
          'songId': 's1',
          'serviceId': 'sv1',
          'title': 'Estou Seguro',
          'key': 'G',
          'moment': 'DIZIMOS_E_OFERTAS',
          'hymnals': [
            {
              'hymnalId': 'h-cc',
              'name': 'Cantor Cristão',
              'abbreviation': 'CC',
              'number': 314,
              'isPrimary': true,
            },
          ],
        },
        {
          'songId': 's2',
          'serviceId': 'sv1',
          'title': 'Alfa e Ômega',
          'key': 'A',
        },
      ],
    });

    return ProviderScope(
      overrides: [
        // E pergunta se a equipe tem o Copiloto de Repertório.
        aiFeaturesProvider.overrideWith((ref, teamId) async => AiFeatures.none),
        eventSuggestionsProvider('e1')
            .overrideWith((ref) => const EventSuggestions(date: '2026-08-16')),
        // A montagem pede o histórico das músicas ao abrir.
        songHistoryProvider.overrideWith((ref, teamId) async => const {}),
      ],
      child: MaterialApp(
        home: SetlistFormScreen(teamId: 't1', eventId: 'e1', event: event),
      ),
    );
  }

  testWidgets('a linha mostra "314 CC · Dízimos e Ofertas"', (tester) async {
    await tester.pumpWidget(repertorio());

    expect(
      find.textContaining('314 CC · Dízimos e Ofertas'),
      findsOneWidget,
    );
  });

  testWidgets('a música sem hinário e sem momento não ganha placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(repertorio());

    // A linha de apoio dela é só o tom. Nada de "—" nem de "Sem momento": a
    // maioria das músicas de uma escala é assim.
    expect(find.widgetWithText(AppBadge, 'A'), findsOneWidget);
    expect(find.textContaining('Sem momento'), findsNothing);
  });

  testWidgets('a folha da linha oferece os momentos, e nenhum vem marcado', (
    tester,
  ) async {
    await tester.pumpWidget(repertorio());

    await tester.tap(find.text('Alfa e Ômega'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Momento do culto (opcional)'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Abertura'), findsOneWidget);
    expect(
      find.widgetWithText(ChoiceChip, 'Dízimos e Ofertas'),
      findsOneWidget,
    );

    // Nenhum marcado: "Momento de Louvor" seria o palpite fácil, e poria na
    // escala uma decisão que ninguém tomou.
    final marcados = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .where((chip) => chip.selected);
    expect(marcados, isEmpty);
  });

  testWidgets('escolher o momento passa a mostrá-lo na linha', (tester) async {
    await tester.pumpWidget(repertorio());

    await tester.tap(find.text('Alfa e Ômega'), warnIfMissed: false);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Abertura'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Abertura'), findsOneWidget);
  });

  testWidgets('"Outro" pede o nome do momento', (tester) async {
    await tester.pumpWidget(repertorio());

    await tester.tap(find.text('Alfa e Ômega'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // O campo só existe depois da escolha: oferecê-lo sempre seria um campo
    // vazio a mais em toda música, para uma pergunta que quase nunca tem
    // resposta.
    expect(find.text('Qual momento'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Outro'));
    await tester.pumpAndSettle();
    expect(find.text('Qual momento'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Qual momento'),
      'Santa Ceia',
    );
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    // O que a pessoa escreveu, e não "Outro", que não diria nada.
    expect(find.textContaining('Santa Ceia'), findsOneWidget);
  });

  testWidgets('o momento se tira do mesmo jeito que se põe', (tester) async {
    await tester.pumpWidget(repertorio());

    await tester.tap(find.text('Estou Seguro'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Tocar no que já está marcado limpa: é como se volta atrás sem um chip
    // "nenhum" ocupando a primeira posição.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dízimos e Ofertas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dízimos e Ofertas'), findsNothing);
    // O hinário fica: ele é do cadastro da música, não desta escala.
    expect(find.textContaining('314 CC'), findsOneWidget);
  });
}
