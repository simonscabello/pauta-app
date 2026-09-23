import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:louvor_app/features/unavailability/domain/schedule_conflicts.dart';
import 'package:louvor_app/features/unavailability/presentation/multi_date_picker.dart';
import 'package:timezone/data/latest.dart' as tzdata;

Event _event({
  required String id,
  required String startsAt,
  List<String> people = const [],
  String? minister,
}) =>
    Event.fromJson({
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
      'assignments': [
        {
          'positionId': 'p-vocal',
          'positionName': 'Vocal',
          'sortOrder': 0,
          'members': [
            for (final p in people)
              {
                'id': 'a-$p',
                'membershipId': 'm-$p',
                'displayName': p,
                'note': null,
                'isRegisteredForPosition': true,
              },
          ],
        },
      ],
      'services': const [],
      'songs': const [],
      if (minister != null)
        'minister': {'membershipId': 'm-$minister', 'displayName': minister},
    });

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('dias em que já estou escalado', () {
    test('usa o dia civil da equipe, e não o de UTC', () {
      // 21h de domingo em São Paulo já é segunda em UTC.
      final dias = scheduledDaysFor(
        [
          _event(
            id: 'e1',
            startsAt: '2026-10-05T00:00:00.000Z',
            people: ['Maria'],
          ),
        ],
        'm-Maria',
      );

      expect(dias.keys, [DateTime(2026, 10, 4)]);
    });

    test('só as escalas em que a pessoa está', () {
      final dias = scheduledDaysFor(
        [
          _event(id: 'e1', startsAt: '2026-10-04T12:00:00.000Z'),
          _event(
            id: 'e2',
            startsAt: '2026-10-11T12:00:00.000Z',
            people: ['Maria'],
            minister: 'Maria',
          ),
        ],
        'm-Maria',
      );

      expect(dias.keys, [DateTime(2026, 10, 11)]);
      final dia = DateTime(2026, 10, 11);
      expect(
        scheduledDayPhrase(dia, dias[dia]!),
        'dom 11/10 (Ministra e Vocal)',
      );
    });
  });

  group('botão do seletor de dias', () {
    test('diz o que vai acontecer, nunca "Confirmar"', () {
      expect(multiDatePickerActionLabel(added: 1, removed: 0), 'Avisar 1 dia');
      expect(
        multiDatePickerActionLabel(added: 3, removed: 0),
        'Avisar 3 dias',
      );
      expect(
        multiDatePickerActionLabel(added: 0, removed: 2),
        'Liberar 2 dias',
      );
      expect(
        multiDatePickerActionLabel(added: 1, removed: 1),
        'Salvar os dias',
      );
      expect(
        multiDatePickerActionLabel(added: 0, removed: 0),
        'Manter como está',
      );
    });
  });
}
