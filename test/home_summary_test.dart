import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:louvor_app/features/home/domain/home_summary.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// A Home responde uma pergunta que a agenda não responde — "quando **eu**
/// toco?" — e a resposta é uma leitura da mesma lista de escalas que a agenda
/// já carregou. Estes testes travam essa leitura, que é a única regra nova que
/// a tela trouxe.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('a minha próxima escala', () {
    test('pula as escalas em que eu não entro', () {
      final resumo = HomeSummary.of(
        [
          _event(id: 'e1', startsAt: '2026-09-13T12:00:00.000Z'),
          _event(
            id: 'e2',
            startsAt: '2026-09-20T12:00:00.000Z',
            assignments: _group('Vocal', ['Simon']),
          ),
          _event(
            id: 'e3',
            startsAt: '2026-09-27T12:00:00.000Z',
            assignments: _group('Violão', ['Simon']),
          ),
        ],
        membershipId: 'm-Simon',
        canManage: false,
        now: DateTime.utc(2026, 9, 9, 12),
      );

      // A agenda destacaria `e1`, que é a próxima da equipe. A pergunta da
      // Home é outra.
      expect(resumo.myNext?.id, 'e2');
      expect(resumo.myPositions, ['Vocal']);
    });

    test('junta as funções quando eu entro em mais de uma', () {
      final resumo = HomeSummary.of(
        [
          _event(
            id: 'e1',
            startsAt: '2026-09-13T12:00:00.000Z',
            assignments: [
              ..._group('Vocal', ['Simon', 'Maria']),
              ..._group('Violão', ['Simon']),
            ],
          ),
        ],
        membershipId: 'm-Simon',
        canManage: false,
        now: DateTime.utc(2026, 9, 9, 12),
      );

      expect(resumo.myPositions, ['Vocal', 'Violão']);
    });

    test('escalado que não pode vira o primeiro aviso, com a substituição',
        () {
      final resumo = HomeSummary.of(
        [
          _event(id: 'e0', startsAt: '2026-09-13T12:00:00.000Z', status: 'DRAFT'),
          _event(
            id: 'e1',
            startsAt: '2026-10-04T12:00:00.000Z',
            assignments: [
              ..._group('Vocal', ['Maria']),
              ..._group('Violão', ['Maria']),
            ],
            minister: 'Maria',
            unavailable: ['Maria'],
          ),
        ],
        membershipId: 'm-Simon',
        canManage: true,
        now: DateTime.utc(2026, 9, 9, 12),
      );

      final aviso = resumo.notices.first;
      expect(aviso.kind, HomeNoticeKind.unavailableAssigned);
      expect(aviso.route, '/agenda/e1/escalar?substituir=m-Maria');
      expect(
        aviso.event!.rolesPhraseFor('m-Maria'),
        'ministra e está em Vocal e Violão',
      );
    });

    test('"Esta semana" do líder: sete dias, sem repetir a manchete', () {
      final resumo = HomeSummary.of(
        [
          _event(
            id: 'minha',
            startsAt: '2026-09-10T12:00:00.000Z',
            assignments: _group('Vocal', ['Simon']),
          ),
          _event(id: 'rascunho', startsAt: '2026-09-13T12:00:00.000Z', status: 'DRAFT'),
          _event(id: 'longe', startsAt: '2026-09-20T12:00:00.000Z'),
        ],
        membershipId: 'm-Simon',
        canManage: true,
        now: DateTime.utc(2026, 9, 9, 12),
      );

      expect(resumo.myNext?.id, 'minha');
      expect(resumo.teamWeek.map((e) => e.id), ['rascunho']);
    });

    test('quem ministra lê "Ministra" antes das funções', () {
      final resumo = HomeSummary.of(
        [
          _event(
            id: 'e1',
            startsAt: '2026-09-13T12:00:00.000Z',
            assignments: [
              ..._group('Vocal', ['Simon', 'Maria']),
              ..._group('Violão', ['Simon']),
            ],
            minister: 'Simon',
          ),
        ],
        membershipId: 'm-Simon',
        canManage: false,
        now: DateTime.utc(2026, 9, 9, 12),
      );

      expect(resumo.myPositions, ['Ministra', 'Vocal', 'Violão']);
    });

    test('sem participação, a manchete sabe que a equipe tem escalas', () {
      final resumo = HomeSummary.of(
        [_event(id: 'e1', startsAt: '2026-09-13T12:00:00.000Z')],
        membershipId: 'm-Simon',
        canManage: false,
        now: DateTime.utc(2026, 9, 9, 12),
      );

      // "Você está livre" e "não há nada marcado" são frases diferentes, e é
      // este par de campos que as separa.
      expect(resumo.myNext, isNull);
      expect(resumo.hasSchedules, isTrue);
    });

    test('equipe sem escala nenhuma não é "você está livre"', () {
      final resumo = HomeSummary.of(
        const [],
        membershipId: 'm-Simon',
        canManage: true,
        now: DateTime.utc(2026, 9, 9, 12),
      );

      expect(resumo.myNext, isNull);
      expect(resumo.hasSchedules, isFalse);
      expect(resumo.myFollowing, isNull);
    });
  });

  group('a minha escala seguinte', () {
    test('é a segunda EM QUE EU ENTRO, e não a segunda da equipe', () {
      final resumo = HomeSummary.of(
        [
          _event(
            id: 'e1',
            startsAt: '2026-09-13T12:00:00.000Z',
            assignments: _group('Vocal', ['Simon']),
          ),
          // A equipe toca no dia 20, e Simon não. Responder "e depois: dia
          // 20" seria continuar a manchete com a escala de outra pessoa.
          _event(id: 'e2', startsAt: '2026-09-20T12:00:00.000Z'),
          _event(
            id: 'e3',
            startsAt: '2026-09-27T12:00:00.000Z',
            assignments: _group('Baixo', ['Simon']),
          ),
        ],
        membershipId: 'm-Simon',
        canManage: false,
        now: DateTime.utc(2026, 9, 9, 12),
      );

      expect(resumo.myNext?.id, 'e1');
      expect(resumo.myFollowing?.id, 'e3');
    });

    test('entrando em uma só, não há linha de depois', () {
      final resumo = HomeSummary.of(
        [
          _event(
            id: 'e1',
            startsAt: '2026-09-13T12:00:00.000Z',
            assignments: _group('Vocal', ['Simon']),
          ),
          for (var i = 2; i <= 8; i++)
            _event(id: 'e$i', startsAt: '2026-09-2${i}T12:00:00.000Z'),
        ],
        membershipId: 'm-Simon',
        canManage: false,
        now: DateTime.utc(2026, 9, 9, 12),
      );

      expect(resumo.myNext?.id, 'e1');
      expect(resumo.myFollowing, isNull);
    });
  });

  group('o repertório contado', () {
    test('soma os cultos quando o servidor disse quantas são', () {
      final event = _event(
        id: 'e1',
        startsAt: '2026-09-13T12:00:00.000Z',
        services: [
          _service(id: 's1', label: 'Manhã', startsAt: '2026-09-13T12:00:00.000Z', songCount: 3),
          _service(id: 's2', label: 'Noite', startsAt: '2026-09-13T23:00:00.000Z', songCount: 2),
        ],
      );

      expect(scheduleSongCount(event), 5);
    });

    test('zero é resposta: "músicas a definir"', () {
      final event = _event(
        id: 'e1',
        startsAt: '2026-09-13T12:00:00.000Z',
        services: [
          _service(id: 's1', label: 'Culto', startsAt: '2026-09-13T12:00:00.000Z', songCount: 0),
        ],
      );

      expect(scheduleSongCount(event), 0);
    });

    test('sem saber, cala — cache gravado antes do campo existir', () {
      // `songCount` ausente é o cache antigo. Chutar "0" ali marcaria como
      // pendente toda escala montada que o app ainda não recarregou.
      final event = _event(
        id: 'e1',
        startsAt: '2026-09-13T12:00:00.000Z',
        services: [
          _service(id: 's1', label: 'Culto', startsAt: '2026-09-13T12:00:00.000Z'),
        ],
      );

      expect(scheduleSongCount(event), isNull);
    });
  });

  group('quantos dias faltam', () {
    test('conta dias civis no fuso da equipe, não horas', () {
      // Culto às 09:00 de 13/09 em São Paulo, consultado às 20:00 de 12/09:
      // faltam menos de 24 horas, e a resposta certa continua sendo "amanhã".
      final event = _event(id: 'e1', startsAt: '2026-09-13T12:00:00.000Z');

      expect(daysUntilEvent(event, DateTime.utc(2026, 9, 12, 23)), 1);
      expect(daysUntilEvent(event, DateTime.utc(2026, 9, 13, 3)), 0);
    });
  });

  group('os avisos logo abaixo da manchete', () {
    test('"é hoje" mora na manchete, e não num aviso que a repete', () {
      final resumo = HomeSummary.of(
        [
          _event(
            id: 'e1',
            startsAt: '2026-09-13T12:00:00.000Z',
            assignments: _group('Vocal', ['Simon']),
          ),
        ],
        membershipId: 'm-Simon',
        canManage: false,
        now: DateTime.utc(2026, 9, 13, 10),
      );

      expect(resumo.myNextDaysAway, 0);
      expect(resumo.notices, isEmpty);
    });

    test('escala distante não vira aviso nenhum', () {
      final resumo = HomeSummary.of(
        [
          _event(
            id: 'e1',
            startsAt: '2026-09-27T12:00:00.000Z',
            assignments: _group('Vocal', ['Simon']),
          ),
        ],
        membershipId: 'm-Simon',
        canManage: false,
        now: DateTime.utc(2026, 9, 9, 12),
      );

      // Sem aviso real o bloco não existe -- e é isso que o mantém digno de
      // ser lido quando aparece.
      expect(resumo.notices, isEmpty);
    });

    test('rascunho e escala vazia só existem para quem gerencia', () {
      final events = [
        _event(id: 'e1', startsAt: '2026-09-13T12:00:00.000Z', status: 'DRAFT'),
      ];

      final membro = HomeSummary.of(
        events,
        membershipId: 'm-Simon',
        canManage: false,
        now: DateTime.utc(2026, 9, 9, 12),
      );
      expect(membro.notices, isEmpty);

      final lider = HomeSummary.of(
        events,
        membershipId: 'm-Simon',
        canManage: true,
        now: DateTime.utc(2026, 9, 9, 12),
      );
      expect(
        lider.notices.map((n) => n.kind),
        [HomeNoticeKind.pendingDrafts, HomeNoticeKind.unstaffedSchedule],
      );
      expect(lider.notices.first.count, 1);
      expect(lider.notices.last.route, '/agenda/e1/escalar');
    });

    test('quem lidera e toca hoje não perde o aviso de escala vazia', () {
      // Era o defeito do aviso "é hoje": com o limite de dois, ele tomava a
      // vaga de "Ninguém escalado ainda" justamente de quem lidera e toca.
      final resumo = HomeSummary.of(
        [
          _event(
            id: 'e1',
            startsAt: '2026-09-13T12:00:00.000Z',
            status: 'DRAFT',
            assignments: _group('Vocal', ['Simon']),
          ),
          _event(id: 'e2', startsAt: '2026-09-20T12:00:00.000Z'),
        ],
        membershipId: 'm-Simon',
        canManage: true,
        now: DateTime.utc(2026, 9, 13, 10),
      );

      expect(resumo.notices, hasLength(HomeSummary.maxNotices));
      expect(
        resumo.notices.map((n) => n.kind),
        [HomeNoticeKind.pendingDrafts, HomeNoticeKind.unstaffedSchedule],
      );
      expect(resumo.myNextDaysAway, 0);
    });
  });
}

Event _event({
  required String id,
  required String startsAt,
  String status = 'PUBLISHED',
  List<Map<String, dynamic>> assignments = const [],
  List<Map<String, dynamic>> services = const [],
  String? minister,
  List<String> unavailable = const [],
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
      'status': status,
      'timezone': 'America/Sao_Paulo',
      'assignments': assignments,
      'services': services,
      'songs': const [],
      if (minister != null)
        'minister': {'membershipId': 'm-$minister', 'displayName': minister},
      if (unavailable.isNotEmpty)
        'warnings': {
          'unavailableAssigned': [
            for (final p in unavailable)
              {'membershipId': 'm-$p', 'displayName': p, 'reason': null},
          ],
        },
    });

Map<String, dynamic> _service({
  required String id,
  required String label,
  required String startsAt,
  int? songCount,
}) =>
    {
      'id': id,
      'label': label,
      'startsAt': startsAt,
      if (songCount != null) 'songCount': songCount,
    };

List<Map<String, dynamic>> _group(String name, List<String> people) => [
      {
        'positionId': 'p-$name',
        'positionName': name,
        'sortOrder': 0,
        'members': [
          for (final p in people)
            {
              'id': 'a-$name-$p',
              'membershipId': 'm-$p',
              'displayName': p,
              'note': null,
              'isRegisteredForPosition': true,
            },
        ],
      },
    ];
