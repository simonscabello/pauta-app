import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:louvor_app/features/events/presentation/agenda_event_tile.dart';
import 'package:louvor_app/features/events/presentation/event_schedule_facts.dart';
import 'package:timezone/data/latest.dart' as tzdata;

Event _event({String? rehearsalAt}) => Event.fromJson({
      'id': 'e1',
      'teamId': 't1',
      'title': null,
      'startsAt': '2026-09-24T12:00:00.000Z',
      'rehearsalAt': rehearsalAt,
      'location': null,
      'notes': null,
      'colorPalette': null,
      'status': 'PUBLISHED',
      'timezone': 'America/Sao_Paulo',
      'assignments': const [],
      'services': const [],
      'songs': const [],
    });

void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    await initializeDateFormatting('pt_BR');
  });

  test('a linha não repete o número que o bloco "QUI 24" já mostra', () {
    expect(
      scheduleRowHeading(
        DateTime.utc(2026, 9, 24, 12),
        'America/Sao_Paulo',
      ),
      'Quinta, setembro',
    );
  });

  test('"Sem ensaio" sai da linha da lista, e continua nos fatos', () {
    final facts = ScheduleFacts.of(_event(), 'America/Sao_Paulo');
    expect(facts.rehearsal, 'Sem ensaio');
    expect(facts.summary, isNot(contains('Sem ensaio')));

    final comEnsaio = ScheduleFacts.of(
      _event(rehearsalAt: '2026-09-23T22:00:00.000Z'),
      'America/Sao_Paulo',
    );
    expect(comEnsaio.summary, contains('Ensaio'));
  });
}
