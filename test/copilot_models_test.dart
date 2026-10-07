import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/features/copilots/domain/copilot_models.dart';

// A proposta do Copiloto de Escalas e a sugestão do de Repertório, como o
// servidor as devolve. A tela só desenha: o que importa é ler certo.

void main() {
  test('lê a proposta do mês: dias, vagas, equilíbrio e avisos', () {
    final session = ScheduleCopilotSession.fromJson({
      'id': 's1',
      'month': '2026-11',
      'status': 'OPEN',
      'version': 3,
      'versions': [{}, {}, {}],
      'days': [
        {
          'dateKey': '2026-11-01',
          'weekday': 0,
          'state': 'PUBLISHED',
          'generated': false,
          'services': [
            {'label': 'Manhã', 'time': '08:30'},
          ],
          'positions': [],
        },
        {
          'dateKey': '2026-11-08',
          'weekday': 0,
          'state': 'EMPTY',
          'generated': true,
          'locked': true,
          'changed': false,
          'services': [
            {'label': 'Manhã', 'time': '08:30'},
          ],
          'unavailable': ['m9'],
          'positions': [
            {
              'positionId': 'p1',
              'name': 'Baixo',
              'category': 'INSTRUMENT',
              'slots': [
                {
                  'index': 0,
                  'membershipId': 'm1',
                  'name': 'Joniel',
                  'locked': false,
                  'reason': 'Única pessoa com Baixo disponível neste dia.',
                  'candidates': ['m1'],
                  'warnings': [],
                },
                {
                  'index': 1,
                  'membershipId': null,
                  'name': null,
                  'locked': false,
                  'reason': null,
                  'candidates': [],
                  'warnings': [],
                },
              ],
            },
          ],
        },
      ],
      'members': [
        {
          'membershipId': 'm1',
          'name': 'Joniel',
          'positionIds': ['p1'],
          'isGuest': false,
          'onLeave': false,
          'monthCount': 2,
        },
      ],
      'balance': {
        'members': [
          {
            'membershipId': 'm1',
            'name': 'Joniel',
            'count': 4,
            'target': 2.5,
            'availableDays': 4,
            'unavailableDays': 0,
            'streak': 4,
            'positions': ['Baixo'],
            'status': 'HIGH',
            'note': 'Única pessoa com Baixo em 2 dias.',
          },
        ],
        'highlights': ['Joniel: 4 escalas.'],
      },
      'warnings': ['domingo 08/11: Baixo sem ninguém.'],
    });

    expect(session.isOpen, isTrue);
    expect(session.version, 3);
    expect(session.generatedDays.map((d) => d.dateKey), ['2026-11-08']);
    final day = session.generatedDays.single;
    expect(day.locked, isTrue);
    expect(day.filled, 1);
    expect(day.empty, 1);
    expect(day.positions.single.slots.first.reason, contains('Única'));
    expect(session.days.first.state, CopilotDayState.published);
    expect(session.balance.single.status, BalanceStatus.high);
    expect(session.balance.single.target, 2.5);
    expect(session.member('m1')?.monthCount, 2);
    expect(session.warnings, hasLength(1));
  });

  test('valor desconhecido do servidor não derruba a leitura', () {
    expect(CopilotDayState.fromJson('ALGO_NOVO'), CopilotDayState.empty);
    expect(BalanceStatus.fromJson(null), BalanceStatus.ok);
    expect(AiFeatures.fromJson(const {}).scheduleCopilot, isFalse);
  });

  test('lê a prévia do mês com a formação e a proposta aberta', () {
    final preview = MonthPreview.fromJson({
      'month': '2026-11',
      'days': [
        {
          'dateKey': '2026-11-05',
          'weekday': 4,
          'past': false,
          'state': 'DRAFT',
          'services': [],
        },
      ],
      'lineups': [
        {
          'weekday': 0,
          'weekdayName': 'domingo',
          'source': 'HISTORY',
          'positions': [
            {
              'positionId': 'p1',
              'name': 'Vocal',
              'category': 'VOCAL',
              'count': 3,
            },
            {
              'positionId': 'p2',
              'name': 'Baixo',
              'category': 'INSTRUMENT',
              'count': 1,
            },
          ],
        },
      ],
      'hints': [
        {'kind': 'TALENT', 'text': 'Fez Vocal 3 vezes.', 'membershipId': 'm1'},
      ],
      'openSession': {'id': 's9'},
    });
    expect(preview.days.single.state, CopilotDayState.draft);
    expect(preview.lineups.single.total, 4);
    expect(preview.hints.single.kind, 'TALENT');
    expect(preview.openSessionId, 's9');
  });
}
