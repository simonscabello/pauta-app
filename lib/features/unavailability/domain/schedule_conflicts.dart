import '../../events/domain/event_datetime.dart';
import '../../events/domain/event_models.dart';

/// Uma escala em que a pessoa já está, vista pelo dia civil.
typedef ScheduledDay = ({Event event, List<String> roles});

/// Os dias em que esta pessoa já está escalada, pelo dia civil **no fuso da
/// equipe** — é esse dia que o calendário de indisponibilidade marca.
///
/// Existe para o aviso antes de marcar "não posso": quem avisa num domingo em
/// que já está na escala precisa saber que o recado vai chegar a quem lidera,
/// em vez de achar que marcar o dia resolveu a troca. Com dois cultos no mesmo
/// dia, vale a primeira escala.
Map<DateTime, ScheduledDay> scheduledDaysFor(
  Iterable<Event> events,
  String? membershipId,
) {
  final days = <DateTime, ScheduledDay>{};
  if (membershipId == null || membershipId.isEmpty) return days;

  for (final event in events) {
    final roles = event.personalRolesFor(membershipId);
    if (roles.isEmpty) continue;
    final timezone =
        event.timezone.isEmpty ? 'America/Sao_Paulo' : event.timezone;
    final local = eventLocalTime(event.startsAt, timezone);
    final day = DateTime(local.year, local.month, local.day);
    days.putIfAbsent(day, () => (event: event, roles: roles));
  }
  return days;
}

/// "dom 4/10 (Ministra, Vocal e Violão)" — o dia e o que a pessoa faz nele.
String scheduledDayPhrase(DateTime day, ScheduledDay scheduled) {
  const weekdays = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
  final roles = scheduled.roles;
  final joined = roles.length == 1
      ? roles.single
      : '${roles.sublist(0, roles.length - 1).join(', ')} e ${roles.last}';
  return '${weekdays[day.weekday - 1]} ${day.day}/${day.month} ($joined)';
}
