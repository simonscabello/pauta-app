import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/features/events/data/event_repository.dart';
import 'package:louvor_app/features/team/domain/workload_report.dart';

void main() {
  test('lê contagem por escala sem confundir com duas funções', () {
    final report = WorkloadReport.fromJson({
      'weeks': 8,
      'since': '2026-07-01T00:00:00.000Z',
      'until': '2026-09-01T00:00:00.000Z',
      'members': [
        {
          'membershipId': 'm1',
          'displayName': 'Maria',
          'scheduleCount': 3,
          'assignmentCount': 5,
          'lastScheduledAt': '2026-08-30T12:00:00.000Z',
          'positions': [
            {'name': 'Vocal', 'count': 3},
            {'name': 'Violão', 'count': 2},
          ],
        },
      ],
    });

    expect(report.members.single.scheduleCount, 3);
    expect(report.members.single.assignmentCount, 5);
    expect(report.members.single.positions.first.name, 'Vocal');
  });

  group('participação por período', () {
    WorkloadReport relatorio() => WorkloadReport.fromJson({
          'weeks': null,
          'months': 3,
          'from': '2026-06-26',
          'to': '2026-09-26',
          'since': '2026-06-26T12:00:00.000Z',
          'until': '2026-09-26T12:00:00.000Z',
          'weekday': null,
          'weekdays': [
            {'weekday': 0, 'count': 9},
            {'weekday': 4, 'count': 3},
          ],
          'scheduleTotal': 12,
          'positions': [
            {'positionId': 'violao', 'name': 'Violão', 'category': 'INSTRUMENT'},
            {'positionId': 'vocal', 'name': 'Vocal', 'category': 'VOCAL'},
          ],
          'members': [
            {
              'membershipId': 'gerson',
              'displayName': 'Gerson',
              'scheduleCount': 8,
              'unavailableCount': 1,
              'freeCount': 3,
              'markedDays': 2,
              'positionIds': ['violao'],
              'positions': [
                {
                  'positionId': 'violao',
                  'name': 'Violão',
                  'count': 8,
                  'lastScheduledAt': '2026-09-20T12:00:00.000Z',
                },
              ],
            },
            {
              'membershipId': 'simon',
              'displayName': 'Simon',
              'onLeave': true,
              'scheduleCount': 2,
              'unavailableCount': 6,
              'freeCount': 4,
              'markedDays': 9,
              // Sabe tocar violão, e não tocou nenhuma vez.
              'positionIds': ['violao', 'vocal'],
              'positions': [
                {'positionId': 'vocal', 'name': 'Vocal', 'count': 2},
              ],
            },
            {
              'membershipId': 'josy',
              'displayName': 'Josy',
              'scheduleCount': 5,
              'unavailableCount': 0,
              'freeCount': 7,
              'positionIds': ['vocal'],
              'positions': [
                {'positionId': 'vocal', 'name': 'Vocal', 'count': 5},
              ],
            },
          ],
        });

    test('lê o período, as três situações e as funções', () {
      final report = relatorio();
      expect(report.weeks, isNull);
      expect(report.months, 3);
      expect(report.from, DateTime(2026, 6, 26));
      expect(report.scheduleTotal, 12);
      expect(report.weekdays.map((w) => w.weekday), [0, 4]);
      expect(report.positions.map((p) => p.name), ['Violão', 'Vocal']);
      final simon = report.members[1];
      expect(simon.onLeave, isTrue);
      expect(simon.unavailableCount, 6);
      expect(simon.freeCount, 4);
      expect(simon.markedDays, 9);
    });

    test('quem mais serviu vem primeiro, e o ⇅ inverte', () {
      final report = relatorio();
      expect(
        workloadRows(report).map((r) => r.member.displayName),
        ['Gerson', 'Josy', 'Simon'],
      );
      expect(
        workloadRows(report, order: WorkloadOrder.least)
            .map((r) => r.member.displayName),
        ['Simon', 'Josy', 'Gerson'],
      );
    });

    test('a função traz quem sabe tocar e não tocou, com zero', () {
      final rows = workloadRows(relatorio(), positionId: 'violao');
      expect(rows.map((r) => r.member.displayName), ['Gerson', 'Simon']);
      expect(rows.map((r) => r.count), [8, 0]);
      expect(rows.first.lastScheduledAt, DateTime.utc(2026, 9, 20, 12));
      expect(rows.last.lastScheduledAt, isNull);
    });

    test('ausências: quem mais avisou, quem menos, quem ficou livre', () {
      final report = relatorio();
      expect(
        absenceRanking(report).map((m) => m.displayName),
        ['Simon', 'Gerson', 'Josy'],
      );
      expect(
        absenceRanking(report, order: AbsenceOrder.leastAbsent)
            .map((m) => m.displayName),
        ['Josy', 'Gerson', 'Simon'],
      );
      expect(
        absenceRanking(report, order: AbsenceOrder.mostFree)
            .map((m) => m.displayName),
        ['Josy', 'Simon', 'Gerson'],
      );
    });
  });

  test('lê o resultado do planejamento em lote', () {
    final result = GeneratedSchedules.fromJson({
      'createdCount': 8,
      'skippedCount': 2,
    });

    expect(result.createdCount, 8);
    expect(result.skippedCount, 2);
  });
}
