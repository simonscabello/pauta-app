import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:louvor_app/features/copilots/data/copilot_repository.dart';
import 'package:louvor_app/features/copilots/domain/copilot_models.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:louvor_app/features/events/presentation/setlist_form_screen.dart';
import 'package:louvor_app/features/songs/data/song_repository.dart';
import 'package:louvor_app/features/songs/presentation/musical_key_picker.dart';
import 'package:louvor_app/features/suggestions/data/suggestion_repository.dart';
import 'package:louvor_app/features/suggestions/domain/song_suggestion.dart';
import 'package:louvor_app/shared/widgets/app_badge.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// A etiqueta "Nova" na tela de montar o repertório.
///
/// Ela é **só leitura aqui**: a marca pertence à música no repertório, e é lá
/// que se liga e se desliga. Uma escala não pode discordar das outras sobre se a
/// equipe está aprendendo uma canção — é o mesmo fato em todas.
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
        // Em aprendizado: a marca vem da música, e o servidor a repassa.
        {
          'songId': 's1',
          'serviceId': 'sv1',
          'title': 'Bondade de Deus',
          'artist': 'Isaias Saad',
          'key': 'G',
          'isNew': true,
        },
        {
          'songId': 's2',
          'serviceId': 'sv1',
          'title': 'Aclame ao Senhor',
          'artist': 'Diante do Trono',
          'key': 'A',
          'isNew': false,
        },
      ],
    });

    return ProviderScope(
      // A tela agora também mostra a faixa de sugestões da equipe, que sai à
      // rede. Sem este dublê o teste ficaria esperando um Dio de verdade e
      // falharia por timer pendente -- por um motivo que nada tem a ver com a
      // etiqueta que ele verifica.
      overrides: [
        // E pergunta se a equipe tem o Copiloto de Repertório.
        aiFeaturesProvider.overrideWith((ref, teamId) async => AiFeatures.none),
        eventSuggestionsProvider('e1')
            .overrideWith((ref) => const EventSuggestions(date: '2026-08-16')),
        // Pelo mesmo motivo: a montagem pede o histórico das músicas ao abrir.
        songHistoryProvider.overrideWith((ref, teamId) async => const {}),
      ],
      child: MaterialApp(
        home: SetlistFormScreen(teamId: 't1', eventId: 'e1', event: event),
      ),
    );
  }

  testWidgets('a etiqueta aparece só na música marcada', (tester) async {
    await tester.pumpWidget(repertorio());

    // Quem monta precisa ver quanta novidade está pedindo para um domingo só.
    expect(find.text('Nova'), findsOneWidget);
  });

  testWidgets('não há como marcar nem desmarcar pela escala', (tester) async {
    await tester.pumpWidget(repertorio());

    // Tocar na etiqueta não faz nada: ela não é um controle. Marcar por escala
    // deixava a mesma música ser novidade num domingo e não no outro.
    await tester.tap(find.text('Nova'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Nova'), findsOneWidget);

    // E o diálogo da linha cuida de tom e recado, e só disso. O toque é do
    // card inteiro; o título é só onde a gente mira.
    await tester.tap(find.text('Aclame ao Senhor'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Tom neste culto'), findsOneWidget);
    expect(find.text('Recado'), findsOneWidget);
    expect(find.textContaining('Música nova'), findsNothing);
  });

  testWidgets('o tom desta escala se escolhe na mesma folha da música',
      (tester) async {
    await tester.pumpWidget(repertorio());

    await tester.tap(find.text('Aclame ao Senhor'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Sem teclado: o campo abre a grade de tons.
    expect(find.byType(EditableText), findsNWidgets(1)); // só o recado
    await tester.tap(find.byType(MusicalKeyField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('D'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    // O tom desta escala vira a etiqueta à direita da linha.
    expect(find.widgetWithText(AppBadge, 'D'), findsOneWidget);
  });
}
