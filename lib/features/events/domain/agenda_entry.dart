import '../../../core/date/civil_date.dart';
import '../../team_events/domain/team_event.dart';
import 'event_datetime.dart';
import 'event_models.dart';

/// Uma coisa marcada num dia da agenda.
///
/// **Duas naturezas, uma lista.** A agenda mostra escalas (`Event`, com cultos
/// e escalação) e eventos da equipe (`TeamEvent`: reunião, churrasco,
/// treinamento). São entidades diferentes de propósito — ver o vocabulário no
/// AGENTS.md —, mas para o calendário são a mesma pergunta: "o que tem neste
/// dia?". `sealed` porque quem desenha precisa tratar as duas, e o compilador
/// é quem deve cobrar isso quando a terceira aparecer.
sealed class AgendaEntry {
  const AgendaEntry();

  /// Identidade **do horário**. É o que o calendário conta: um domingo com
  /// manhã e noite tem duas entradas, e a vigília que atravessa a meia-noite
  /// pinta os dois dias.
  String get id;

  /// Identidade **da linha da lista**.
  ///
  /// Uma escala com dois cultos é uma escala só: a linha já escreve "Manhã
  /// 08:30 · Noite 19:00", e mostrá-la duas vezes faria a equipe achar que
  /// toca em dobro. Um evento é sempre uma linha.
  String get rowId;

  DateTime get startsAt;
  String get timezone;

  /// O dia civil no fuso da equipe — que é onde a coisa acontece, e não onde
  /// está o relógio de quem consulta.
  DateTime get day {
    final local = eventLocalTime(startsAt, timezone);
    return DateTime(local.year, local.month, local.day);
  }
}

/// Um horário de culto de uma escala.
final class ScheduleEntry extends AgendaEntry {
  const ScheduleEntry({required this.event, required this.service});

  final Event event;
  final EventService service;

  @override
  String get id => 'escala/${event.id}/${service.id}';

  @override
  String get rowId => 'escala/${event.id}';

  @override
  DateTime get startsAt => service.startsAt;

  @override
  String get timezone =>
      event.timezone.isEmpty ? 'America/Sao_Paulo' : event.timezone;

  String get title => event.hasTitle ? event.title! : service.label;
}

/// Um evento da equipe: reunião, ensaio geral, churrasco, treinamento.
final class TeamEventEntry extends AgendaEntry {
  const TeamEventEntry(this.event);

  final TeamEvent event;

  @override
  String get id => 'evento/${event.id}';

  @override
  String get rowId => id;

  @override
  DateTime get startsAt => event.startsAt;

  @override
  String get timezone =>
      event.timezone.isEmpty ? 'America/Sao_Paulo' : event.timezone;
}

/// Tudo o que está marcado, na ordem do relógio.
///
/// Escalas e eventos entram na mesma lista e são ordenados juntos: quem abre a
/// agenda quer o dia inteiro, e não a agenda de escalas seguida da agenda de
/// eventos.
List<AgendaEntry> agendaEntries(
  Iterable<Event> schedules, {
  Iterable<TeamEvent> teamEvents = const [],
}) {
  final escalas = {for (final event in schedules) event.id: event};
  final eventos = {for (final event in teamEvents) event.id: event};

  return [
    for (final event in escalas.values)
      for (final service in event.displayServices)
        ScheduleEntry(event: event, service: service),
    for (final event in eventos.values) TeamEventEntry(event),
  ]..sort((a, b) {
      final time = a.startsAt.compareTo(b.startsAt);
      return time == 0 ? a.id.compareTo(b.id) : time;
    });
}

/// As **entradas** de cada dia — uma por horário. É o que o calendário marca.
Map<String, List<AgendaEntry>> groupAgendaEntries(List<AgendaEntry> entries) {
  final groups = <String, List<AgendaEntry>>{};
  for (final entry in entries) {
    (groups[dateKey(entry.day)] ??= []).add(entry);
  }
  return groups;
}

/// As **linhas** de cada dia — uma por escala, uma por evento.
///
/// A ordem é a das entradas, que já vêm ordenadas pelo horário: o primeiro
/// horário do dia é o que decide onde a linha entra.
Map<String, List<AgendaEntry>> groupAgendaRows(List<AgendaEntry> entries) {
  final groups = <String, List<AgendaEntry>>{};
  for (final entry in entries) {
    final linhas = groups[dateKey(entry.day)] ??= [];
    if (!linhas.any((linha) => linha.rowId == entry.rowId)) {
      linhas.add(entry);
    }
  }
  return groups;
}

/// O recorte da agenda: tudo, ou só onde eu entro.
enum AgendaFilter {
  /// A agenda da equipe inteira.
  all,

  /// Só as escalas em que a pessoa tem alguma responsabilidade — mais os
  /// eventos, que são de todo mundo.
  mine,

  /// (liderança) Só os rascunhos: o que a equipe ainda não vê. É para onde o
  /// aviso "5 escalas em rascunho" da Home leva — antes ele abria a agenda
  /// inteira, e os rascunhos tinham de ser caçados no mês.
  drafts;

  bool get isMine => this == AgendaFilter.mine;
  bool get isDrafts => this == AgendaFilter.drafts;
}

/// As entradas em que a pessoa tem **alguma responsabilidade**.
///
/// Responsabilidade é estar escalado em alguma função. O ministrante entra
/// junto sem uma segunda conferência: o servidor recusa ministrante que não
/// esteja entre os escalados (`assertMinisterIsAssigned`), então quem ministra
/// já aparece em `assignments`. Se um dia isso deixar de valer, é aqui que a
/// segunda fonte entra — e não em cada tela que pergunta "é minha?".
///
/// **O evento da equipe nunca sai do recorte.** Ele não tem escalados: um
/// churrasco é de todo mundo, e escondê-lo em "Minhas escalas" faria a pessoa
/// perder um compromisso que também é dela. O filtro tira o domingo em que
/// você não toca, não o que a equipe inteira vai fazer junto.
List<AgendaEntry> filterAgendaEntries(
  List<AgendaEntry> entries, {
  required AgendaFilter filter,
  required String membershipId,
}) {
  if (filter == AgendaFilter.all) return entries;
  if (filter == AgendaFilter.drafts) {
    // Evento da equipe não tem rascunho: ele existe assim que é criado.
    return [
      for (final entry in entries)
        if (entry case ScheduleEntry(:final event) when event.isDraft) entry,
    ];
  }
  return [
    for (final entry in entries)
      if (switch (entry) {
        TeamEventEntry() => true,
        ScheduleEntry(:final event) =>
          event.positionsForMembership(membershipId).isNotEmpty,
      })
        entry,
  ];
}
