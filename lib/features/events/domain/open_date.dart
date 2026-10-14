import 'package:timezone/timezone.dart' as tz;

import '../../team/domain/service_template.dart';
import 'event_models.dart';
import 'next_service_date.dart';

/// A janela de planejamento da agenda: quatro semanas.
///
/// É o mês que a liderança consegue enxergar de uma vez sem que a lista de
/// datas em aberto fique mais longa que a das escalas que já existem — e é o
/// mesmo padrão do gerador em Cultos da igreja, então as duas telas propõem a
/// mesma coisa.
const openDatesWeeks = 4;

/// Um horário de culto dentro de uma data que ainda não tem escala.
class OpenDateService {
  const OpenDateService({required this.label, required this.startsAt});

  final String label;

  /// O instante do culto, já resolvido no fuso da equipe.
  final DateTime startsAt;
}

/// Uma data que a grade de cultos prevê e que **ainda não virou escala**.
///
/// Não existe no banco: é a diferença entre a grade e a agenda, calculada na
/// hora de desenhar a tela. Serve para a liderança ver o mês inteiro —
/// inclusive os buracos — sem precisar criar nada antes; a linha só nasce
/// quando alguém toca na data ou usa "criar rascunhos".
///
/// Por isso ela não tem id, status nem escalação: não é uma escala vazia, é a
/// ausência de uma.
class OpenDate {
  const OpenDate({
    required this.startsAt,
    required this.services,
    required this.timezone,
    this.templateId,
  });

  /// O culto da grade, quando a linha é **um culto** (equipe que escala por
  /// culto) e não o dia inteiro. Vai para o formulário como `?culto=`.
  final String? templateId;

  /// O culto mais cedo do dia — o mesmo critério que a escala usa para se
  /// ordenar na agenda, para que as datas em aberto e as escalas reais possam
  /// ser lidas na mesma régua.
  final DateTime startsAt;

  final List<OpenDateService> services;

  final String timezone;

  /// A data no formato que `/agenda/novo?data=` espera.
  String get dateParam =>
      _dateKey(tz.TZDateTime.from(startsAt, tz.getLocation(timezone)));

  /// O endereço do formulário de nova escala para esta linha.
  String get newScheduleRoute => templateId == null
      ? '/agenda/novo?data=$dateParam'
      : '/agenda/novo?data=$dateParam&culto=$templateId';
}

/// As datas da grade que ainda não têm escala, da mais próxima à mais distante.
///
/// **Espelha `EventsService.generate` do backend de propósito**: mesma regra
/// (dias da grade ativa, a partir de hoje, pulando as datas que já têm escala)
/// e mesma janela. É o que permite ao botão de criar em lote prometer
/// exatamente as datas que estão na tela — divergir aqui faria a prévia mentir
/// sobre o que o servidor vai criar.
///
/// [events] é a lista que a agenda já carregou (as vinte próximas), e não uma
/// consulta nova: numa igreja de dois ou três cultos por semana isso cobre as
/// quatro semanas com folga. Passando de vinte cultos dentro da janela, as
/// últimas datas poderiam ser propostas mesmo já tendo escala — o que erra a
/// **sugestão**, não o resultado: quem decide o que já existe é o servidor, e é
/// ele que pula as datas ocupadas ao criar os rascunhos.
List<OpenDate> openDates({
  required List<ServiceTemplate> templates,
  required List<Event> events,
  required String timezone,
  required DateTime now,
  int weeks = openDatesWeeks,
  bool perService = false,
}) {
  final active = templates.where((template) => template.isActive).toList();
  if (active.isEmpty) return const [];

  final location = tz.getLocation(timezone);
  final today = tz.TZDateTime.from(now, location);

  // Na equipe que escala por culto, a linha em aberto é o **culto**: o
  // domingo com a das 8h montada ainda mostra a das 10h30. Mesma regra do
  // servidor ao gerar (`EventsService.generate`).
  if (perService) {
    final scheduled = scheduledServiceInstants(events);
    final abertos = <OpenDate>[];
    for (var offset = 0; offset < weeks * 7; offset += 1) {
      final date = DateTime.utc(today.year, today.month, today.day + offset);
      for (final template in openTemplatesOn(
        date: date,
        templates: active,
        scheduled: scheduled,
        timezone: timezone,
      )) {
        final startsAt = templateInstant(template, date, location);
        abertos.add(
          OpenDate(
            startsAt: startsAt,
            services: [OpenDateService(label: template.label, startsAt: startsAt)],
            timezone: timezone,
            templateId: template.id,
          ),
        );
      }
    }
    return abertos;
  }

  // As datas que já têm escala, no calendário da equipe. Um domingo com culto
  // de manhã e de noite ocupa o dia inteiro com **uma** escala, então a chave
  // é o dia civil e não o horário.
  final ocupadas = <String>{
    for (final event in events)
      _dateKey(tz.TZDateTime.from(event.startsAt, location)),
  };

  final abertas = <OpenDate>[];
  for (var offset = 0; offset < weeks * 7; offset += 1) {
    // A contagem dos dias anda em UTC de propósito: somar 24 horas a um
    // horário local atravessaria uma virada de horário de verão pulando ou
    // repetindo uma data. Aqui só interessa a sequência do calendário; o fuso
    // volta a valer abaixo, na hora de dar horário ao culto.
    final date = DateTime.utc(today.year, today.month, today.day + offset);
    if (ocupadas.contains(_dateKey(date))) continue;

    final doDia = active.where((template) => template.matchesDate(date)).toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    if (doDia.isEmpty) continue;

    final services = [
      for (final template in doDia)
        OpenDateService(
          label: template.label,
          startsAt: tz.TZDateTime(
            location,
            date.year,
            date.month,
            date.day,
            template.hour,
            template.minute,
          ).toUtc(),
        ),
    ];

    abertas.add(
      OpenDate(
        startsAt: services.first.startsAt,
        services: services,
        timezone: timezone,
      ),
    );
  }

  return abertas;
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
