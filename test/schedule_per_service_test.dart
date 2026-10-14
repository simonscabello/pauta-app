import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:louvor_app/features/events/domain/event_datetime.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:louvor_app/features/events/domain/next_service_date.dart';
import 'package:louvor_app/features/events/domain/open_date.dart';
import 'package:louvor_app/features/events/domain/schedule_share_text.dart';
import 'package:louvor_app/features/events/presentation/event_schedule_facts.dart';
import 'package:louvor_app/features/home/domain/home_summary.dart';
import 'package:louvor_app/features/team/domain/service_template.dart';
import 'package:louvor_app/features/unavailability/domain/schedule_conflicts.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// A equipe que escala **por culto**: cada culto do domingo é uma escala.
///
/// O que se protege: a próxima escala proposta é o próximo **culto** sem
/// escala (e não o próximo dia), as linhas em aberto da agenda são cultos, e
/// a escala de um culto só diz qual culto é — na tela, no texto do WhatsApp.
/// Na equipe por dia, nada disso muda.
const _fuso = 'America/Sao_Paulo';

/// Quarta-feira, meio-dia em São Paulo.
final _quarta = DateTime.utc(2026, 9, 2, 15);

ServiceTemplate _grade(String label, int startMinutes) => ServiceTemplate(
      id: label,
      label: label,
      weekday: 0,
      startMinutes: startMinutes,
    );

final _quatroCultos = [
  _grade('Culto das 8h', 8 * 60),
  _grade('Culto das 10h30', 10 * 60 + 30),
  _grade('Culto das 18h', 18 * 60),
  _grade('Culto das 20h', 20 * 60),
];

/// Uma escala de um culto só, no domingo 6/9 às `hora` de São Paulo.
Event _escala(
  String label,
  String horaUtc, {
  String mode = 'SERVICE',
  List<Map<String, dynamic>> assignments = const [],
}) {
  final startsAt = '2026-09-06T$horaUtc:00.000Z';
  return Event.fromJson({
    'id': label,
    'teamId': 't1',
    'startsAt': startsAt,
    'status': 'PUBLISHED',
    'timezone': _fuso,
    'scheduleMode': mode,
    'services': [
      {'id': 's-$label', 'label': label, 'startsAt': startsAt},
    ],
    'assignments': assignments,
    'songs': const [],
  });
}

void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    await initializeDateFormatting('pt_BR');
  });

  group('a próxima escala é o próximo culto sem escala', () {
    test('com a das 8h montada, propõe a das 10h30 do mesmo domingo', () {
      final proximo = nextOpenService(
        templates: _quatroCultos,
        events: [_escala('Culto das 8h', '11:00')],
        timezone: _fuso,
        now: _quarta,
      );
      expect(proximo?.date, DateTime(2026, 9, 6));
      expect(proximo?.template.label, 'Culto das 10h30');
    });

    test('com o domingo inteiro montado, vai para o seguinte', () {
      final proximo = nextOpenService(
        templates: _quatroCultos,
        events: [
          _escala('Culto das 8h', '11:00'),
          _escala('Culto das 10h30', '13:30'),
          _escala('Culto das 18h', '21:00'),
          _escala('Culto das 20h', '23:00'),
        ],
        timezone: _fuso,
        now: _quarta,
      );
      expect(proximo?.date, DateTime(2026, 9, 13));
      expect(proximo?.template.label, 'Culto das 8h');
    });
  });

  group('as linhas em aberto da agenda', () {
    test('por culto, cada culto sem escala é uma linha', () {
      final abertas = openDates(
        templates: _quatroCultos,
        events: [_escala('Culto das 8h', '11:00')],
        timezone: _fuso,
        now: _quarta,
        weeks: 1,
        perService: true,
      );
      expect(abertas.map((a) => a.services.single.label), [
        'Culto das 10h30',
        'Culto das 18h',
        'Culto das 20h',
      ]);
      // O formulário recebe o culto, e não só o dia.
      expect(
        abertas.first.newScheduleRoute,
        '/agenda/novo?data=2026-09-06&culto=Culto das 10h30',
      );
    });

    test('por dia, o domingo com uma escala está montado', () {
      final abertas = openDates(
        templates: _quatroCultos,
        events: [_escala('Culto das 8h', '11:00', mode: 'DAY')],
        timezone: _fuso,
        now: _quarta,
        weeks: 1,
      );
      expect(abertas, isEmpty);
    });
  });

  group('a escala de um culto só diz qual culto é', () {
    test('por culto: no título, nos horários e no WhatsApp', () {
      final escala = _escala('Culto das 18h', '21:00');
      // O nome já diz a hora: ela não se repete ("Culto das 18h").
      expect(escala.serviceTag, 'Culto das 18h');
      expect(
        escala.dateAndTitle,
        'Domingo, 6 de setembro · Culto das 18h',
      );
      expect(ScheduleFacts.of(escala, _fuso).times, 'Culto das 18h');
      expect(
        buildScheduleShareText(escala).split('\n').first,
        '*Domingo 06/09 · Culto das 18h*',
      );
    });

    test('por dia: a hora limpa, como sempre', () {
      final escala = _escala('Culto', '21:00', mode: 'DAY');
      expect(escala.serviceTag, isNull);
      expect(escala.dateAndTitle, 'Domingo, 6 de setembro');
      expect(ScheduleFacts.of(escala, _fuso).times, '18:00');
    });
  });

  test('quem está em duas escalas do dia avisa o dia com as duas funções', () {
    Map<String, dynamic> grupo(String position, String name) => {
          'positionId': position,
          'positionName': name,
          'positionCategory': 'VOCAL',
          'sortOrder': 0,
          'members': [
            {
              'id': 'a-$position',
              'membershipId': 'm1',
              'displayName': 'Ana',
              'note': null,
              'isRegisteredForPosition': true,
            },
          ],
        };
    final dias = scheduledDaysFor(
      [
        _escala('Culto das 8h', '11:00', assignments: [grupo('p1', 'Vocal')]),
        _escala('Culto das 18h', '21:00', assignments: [grupo('p2', 'Violão')]),
      ],
      'm1',
    );

    expect(dias, hasLength(1));
    expect(dias.values.single.roles, ['Vocal', 'Violão']);
  });

  group('a hora não se repete quando o nome do culto já a diz', () {
    final oito = DateTime(2026, 9, 6, 8);
    final dezMeia = DateTime(2026, 9, 6, 10, 30);

    test('reconhece as formas comuns', () {
      for (final nome in [
        'Culto das 8h',
        'Culto 08h',
        '8:00',
        'Culto 08:00',
        'Culto das 8h00',
      ]) {
        expect(labelStatesTime(nome, oito), isTrue, reason: nome);
      }
      for (final nome in ['Culto das 10h30', '10:30 Culto']) {
        expect(labelStatesTime(nome, dezMeia), isTrue, reason: nome);
      }
    });

    test('nome sem a hora, ou com outra hora, mantém a hora', () {
      for (final nome in [
        'Manhã',
        'Culto 2',
        'Culto das 18h',
        'Culto das 10h',
      ]) {
        expect(labelStatesTime(nome, oito), isFalse, reason: nome);
      }
      expect(labelStatesTime('Culto das 10h', dezMeia), isFalse);
      expect(
        serviceNameAndTime('Manhã', DateTime.utc(2026, 9, 6, 11), _fuso),
        'Manhã 08:00',
      );
      expect(
        serviceNameAndTime('Culto das 8h', DateTime.utc(2026, 9, 6, 11), _fuso),
        'Culto das 8h',
      );
    });
  });

  test('a Home junta as escalas suas do mesmo dia na manchete', () {
    Map<String, dynamic> grupo(String position, String name) => {
          'positionId': position,
          'positionName': name,
          'positionCategory': 'VOCAL',
          'sortOrder': 0,
          'members': [
            {
              'id': 'a-$position',
              'membershipId': 'm1',
              'displayName': 'Ana',
              'note': null,
              'isRegisteredForPosition': true,
            },
          ],
        };
    final oito =
        _escala('Culto das 8h', '11:00', assignments: [grupo('p1', 'Vocal')]);
    final dezoito = _escala(
      'Culto das 18h',
      '21:00',
      assignments: [grupo('p2', 'Violão')],
    );
    final semanaQueVem = Event.fromJson({
      'id': 'proxima',
      'teamId': 't1',
      'startsAt': '2026-09-13T11:00:00.000Z',
      'status': 'PUBLISHED',
      'timezone': _fuso,
      'scheduleMode': 'SERVICE',
      'assignments': [grupo('p1', 'Vocal')],
      'songs': const [],
    });

    final resumo = HomeSummary.of(
      [oito, dezoito, semanaQueVem],
      membershipId: 'm1',
      canManage: false,
      now: _quarta,
    );

    expect(resumo.myNext?.id, oito.id);
    expect(resumo.mySameDay.map((e) => e.event.id), [dezoito.id]);
    expect(resumo.mySameDay.single.roles, ['Violão']);
    // "E depois" é o próximo dia, e não a das 18h do mesmo domingo.
    expect(resumo.myFollowing?.id, 'proxima');

    // Para quem lidera, "Esta semana na equipe" não repete a das 18h, que a
    // manchete já mostra.
    final lider = HomeSummary.of(
      [oito, dezoito, semanaQueVem],
      membershipId: 'm1',
      canManage: true,
      now: _quarta,
    );
    expect(lider.teamWeek.map((e) => e.id), isNot(contains(dezoito.id)));
  });
}
