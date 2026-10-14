import 'package:timezone/timezone.dart' as tz;

import '../../team/domain/service_template.dart';
import 'event_models.dart';

/// Até onde vale procurar uma data com culto na grade.
///
/// Oito semanas cobrem com folga qualquer grade real -- uma igreja que só tem
/// culto no primeiro domingo do mês ainda cai dentro. Passando disso, propor
/// uma data seria adivinhação, e é melhor abrir no dia de hoje e deixar a
/// pessoa escolher.
const nextServiceDateWeeks = 8;

/// A próxima data que a grade da equipe prevê, a partir de agora.
///
/// **Existe porque "Nova escala" abria sempre em hoje**, e hoje quase nunca é
/// dia de culto: quem cria a escala de domingo chegava numa quarta-feira sem
/// grade, via "Não há grade para este dia da semana" e tinha de abrir o
/// calendário para consertar o que o app tinha errado sozinho.
///
/// **Nada de domingo e quinta no código.** Quais dias têm culto é o que a
/// própria equipe cadastrou em [ServiceTemplate]; uma igreja de sábado à noite
/// recebe a mesma ajuda.
///
/// Hoje conta enquanto ainda houver culto por vir: às 08h de domingo a resposta
/// é o próprio domingo; às 22h, o próximo dia da grade. Devolve nulo quando a
/// grade está vazia ou nada aparece na janela -- aí quem chama mantém o que
/// tinha, e nenhuma data é inventada.
DateTime? nextScheduledDate({
  required List<ServiceTemplate> templates,
  required String timezone,
  required DateTime now,
  int weeks = nextServiceDateWeeks,
}) {
  final active = templates.where((template) => template.isActive).toList();
  if (active.isEmpty) return null;

  final today = tz.TZDateTime.from(now, tz.getLocation(timezone));
  final nowMinutes = today.hour * 60 + today.minute;

  for (var offset = 0; offset < weeks * 7; offset += 1) {
    // A contagem dos dias anda em UTC, como em `openDates`: somar 24 horas a
    // um horário local atravessaria uma virada de horário de verão pulando ou
    // repetindo uma data. Aqui só interessa a sequência do calendário.
    final date = DateTime.utc(today.year, today.month, today.day + offset);
    final doDia = active.where((template) => template.matchesDate(date));
    if (doDia.isEmpty) continue;

    // Hoje só serve se algum culto ainda estiver por vir. Abrir o formulário
    // no domingo à noite propondo o domingo que já acabou seria pior do que
    // não propor nada.
    if (offset == 0 &&
        !doDia.any((template) => template.startMinutes >= nowMinutes)) {
      continue;
    }

    // Data civil "solta", sem fuso: é o que o formulário guarda e o que o
    // seletor de data mostra. O fuso volta a valer na gravação, quando cada
    // culto ganha horário.
    return DateTime(date.year, date.month, date.day);
  }

  return null;
}

/// Os instantes dos cultos que já têm escala — o que a equipe que escala por
/// culto conta como "já montado". O servidor faz a mesma conta ao gerar pela
/// grade (pelo culto da grade ou pelo horário); aqui, sem o id da grade na
/// escala, vale o horário, que cobre os dois casos.
Set<int> scheduledServiceInstants(List<Event> events) => {
      for (final event in events)
        for (final service in event.displayServices)
          service.startsAt.toUtc().millisecondsSinceEpoch,
    };

/// O instante de um culto da grade numa data, no fuso da equipe.
DateTime templateInstant(
  ServiceTemplate template,
  DateTime date,
  tz.Location location,
) =>
    tz.TZDateTime(
      location,
      date.year,
      date.month,
      date.day,
      template.hour,
      template.minute,
    ).toUtc();

/// Os cultos da grade numa data que ainda não têm escala, por horário.
List<ServiceTemplate> openTemplatesOn({
  required DateTime date,
  required List<ServiceTemplate> templates,
  required Set<int> scheduled,
  required String timezone,
}) {
  final location = tz.getLocation(timezone);
  return templates
      .where((t) => t.isActive && t.matchesDate(date))
      .where(
        (t) => !scheduled.contains(
          templateInstant(t, date, location).millisecondsSinceEpoch,
        ),
      )
      .toList()
    ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
}

/// O próximo **culto** da grade que ainda não tem escala — o que o formulário
/// propõe na equipe que escala por culto. Com a das 8h montada, a próxima
/// sugestão é a das 10h30 do mesmo domingo, e não o domingo seguinte.
///
/// O culto de hoje que já começou não conta. Nulo quando a grade está vazia
/// ou tudo na janela já tem escala.
({DateTime date, ServiceTemplate template})? nextOpenService({
  required List<ServiceTemplate> templates,
  required List<Event> events,
  required String timezone,
  required DateTime now,
  int weeks = nextServiceDateWeeks,
}) {
  final location = tz.getLocation(timezone);
  final today = tz.TZDateTime.from(now, location);
  final scheduled = scheduledServiceInstants(events);

  for (var offset = 0; offset < weeks * 7; offset += 1) {
    final date = DateTime.utc(today.year, today.month, today.day + offset);
    for (final template in openTemplatesOn(
      date: date,
      templates: templates,
      scheduled: scheduled,
      timezone: timezone,
    )) {
      if (!templateInstant(template, date, location).isAfter(now)) continue;
      return (date: DateTime(date.year, date.month, date.day), template: template);
    }
  }
  return null;
}
