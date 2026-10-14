import 'event_datetime.dart';
import 'event_models.dart';

/// Quanto dura um culto no calendário. A escala não guarda hora de término, e
/// um evento sem duração aparece como um traço que ninguém vê.
const _serviceDuration = Duration(hours: 2);
const _rehearsalDuration = Duration(hours: 2);

/// O nome do compromisso na agenda do celular: o título da escala, quando ela
/// tem um, e o culto. "Culto · Manhã", "Páscoa · Noite".
String _summary(Event event, EventService service, bool severalServices) {
  final base = event.hasTitle ? event.title! : 'Culto';
  return severalServices ? '$base · ${service.label}' : base;
}

/// A escala como arquivo de calendário (.ics): um compromisso por culto e um
/// para o ensaio. É o que a agenda do iPhone, do Outlook e da maioria dos
/// celulares Android sabe importar.
///
/// Os horários vão em UTC (`...Z`): o calendário de quem abre converte para o
/// fuso do aparelho, e o arquivo não precisa descrever o fuso da igreja.
String buildScheduleIcs(Event event, {DateTime? now}) {
  final stamp = _icsTime(now ?? DateTime.now().toUtc());
  final services = event.displayServices;
  final varios = services.length > 1;
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Pauta//Escala//PT-BR',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    for (final service in services) ...[
      'BEGIN:VEVENT',
      'UID:${event.id}-${service.id}@pauta',
      'DTSTAMP:$stamp',
      'DTSTART:${_icsTime(service.startsAt)}',
      'DTEND:${_icsTime(service.startsAt.add(_serviceDuration))}',
      'SUMMARY:${_escape(_summary(event, service, varios))}',
      if (event.location != null && event.location!.trim().isNotEmpty)
        'LOCATION:${_escape(event.location!.trim())}',
      'END:VEVENT',
    ],
    if (event.rehearsalAt != null) ...[
      'BEGIN:VEVENT',
      'UID:${event.id}-ensaio@pauta',
      'DTSTAMP:$stamp',
      'DTSTART:${_icsTime(event.rehearsalAt!)}',
      'DTEND:${_icsTime(event.rehearsalAt!.add(_rehearsalDuration))}',
      'SUMMARY:${_escape(event.hasTitle ? 'Ensaio · ${event.title}' : 'Ensaio')}',
      'END:VEVENT',
    ],
    'END:VCALENDAR',
  ];
  // CRLF é o que a especificação pede, e o que o Outlook exige.
  return '${lines.join('\r\n')}\r\n';
}

/// O endereço que abre o Google Agenda com o primeiro culto preenchido. O
/// Google não aceita vários compromissos de uma vez: os outros horários e o
/// ensaio vão escritos na descrição.
String googleCalendarUrl(Event event) {
  final services = event.displayServices;
  final first = services.first;
  final detalhes = <String>[
    if (services.length > 1)
      for (final service in services.skip(1))
        'Também: ${service.label}, ${_humanUtc(service.startsAt, event)}',
    if (event.rehearsalAt != null)
      'Ensaio: ${_humanUtc(event.rehearsalAt!, event)}',
  ];
  final params = <String, String>{
    'action': 'TEMPLATE',
    'text': _summary(event, first, services.length > 1),
    'dates':
        '${_icsTime(first.startsAt)}/${_icsTime(first.startsAt.add(_serviceDuration))}',
    if (event.location != null && event.location!.trim().isNotEmpty)
      'location': event.location!.trim(),
    if (detalhes.isNotEmpty) 'details': detalhes.join('\n'),
  };
  return Uri.https('calendar.google.com', '/calendar/render', params).toString();
}

/// O nome do arquivo: `escala-2026-10-18.ics`.
String scheduleIcsFileName(Event event) {
  final d = event.startsAt.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'escala-${d.year}-${two(d.month)}-${two(d.day)}.ics';
}

/// "domingo, 18 de outubro, 19:00", no fuso da equipe.
String _humanUtc(DateTime instant, Event event) {
  final zone = event.timezone.isEmpty ? 'America/Sao_Paulo' : event.timezone;
  return '${formatEventWeekdayDate(instant, zone)}, ${formatEventTime(instant, zone)}';
}

String _icsTime(DateTime instant) {
  final u = instant.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}T'
      '${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

/// Vírgula, ponto e vírgula, barra invertida e quebra de linha têm sentido no
/// formato e precisam de escape.
String _escape(String text) => text
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll('\n', r'\n');
