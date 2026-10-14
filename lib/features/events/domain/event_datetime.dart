import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/date/civil_date.dart';

DateTime eventLocalTime(DateTime utc, String timezone) {
  return tz.TZDateTime.from(utc, tz.getLocation(timezone));
}

String formatEventWeekdayDate(DateTime utc, String timezone) {
  final location = tz.getLocation(timezone);
  final localTime = tz.TZDateTime.from(utc, location);
  final now = tz.TZDateTime.now(location);

  // O ano so aparece quando difere do atual: "Domingo, 9 de agosto" no uso do
  // dia a dia, "Domingo, 9 de agosto de 2025" ao revisitar cultos passados.
  final pattern = localTime.year == now.year
      ? "EEEE, d 'de' MMMM"
      : "EEEE, d 'de' MMMM 'de' y";

  // O pt_BR devolve o dia da semana em minuscula ("domingo"); como este texto
  // abre cards e mensagens, a maiuscula inicial faz diferenca na leitura.
  return _capitalize(DateFormat(pattern, 'pt_BR').format(localTime));
}

/// "21 de setembro" — a data **sem** o dia da semana.
///
/// Para as linhas que já abrem com o bloco de data ("DOM 21"): ali o dia da
/// semana e o número já estão escritos, e repeti-los por extenso ao lado
/// ("Domingo, 21 de setembro") era dizer a mesma coisa duas vezes na mesma
/// linha. O ano só aparece quando difere do atual, como em
/// [formatEventWeekdayDate].
String formatEventDayMonth(DateTime utc, String timezone) {
  final location = tz.getLocation(timezone);
  final localTime = tz.TZDateTime.from(utc, location);
  final now = tz.TZDateTime.now(location);
  final pattern =
      localTime.year == now.year ? "d 'de' MMMM" : "d 'de' MMMM 'de' y";
  return DateFormat(pattern, 'pt_BR').format(localTime);
}

/// O pt_BR devolve o dia da semana em minúscula; exposto para outros pontos
/// que formatam data por conta própria usarem a mesma regra.
String capitalizeWeekday(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

String _capitalize(String value) => capitalizeWeekday(value);

/// Duas datas caem no mesmo dia civil no fuso da equipe?
/// Usado para não repetir a data do culto no horário do ensaio.
bool isSameLocalDay(DateTime a, DateTime b, String timezone) {
  final localA = eventLocalTime(a, timezone);
  final localB = eventLocalTime(b, timezone);
  return localA.year == localB.year &&
      localA.month == localB.month &&
      localA.day == localB.day;
}

String formatEventTime(DateTime utc, String timezone) {
  final localTime = eventLocalTime(utc, timezone);
  return DateFormat('HH:mm', 'pt_BR').format(localTime);
}

/// Dia da semana abreviado e em minúscula: "sáb", "qui".
///
/// Minúscula porque nunca aparece sozinho -- entra dentro de um rótulo
/// ("Ensaio sáb 19:00"), e ali a maiúscula parece começo de frase. O ponto que
/// o pt_BR acrescenta ("sáb.") sai: encosta no horário e vira sujeira.
String formatEventShortWeekday(DateTime utc, String timezone) {
  final localTime = eventLocalTime(utc, timezone);
  return DateFormat('EEE', 'pt_BR').format(localTime).replaceAll('.', '');
}

/// "sáb 09/08" — a escala identificada no menor espaço que ainda a identifica.
///
/// Existe para colunas estreitas (o painel lateral da agenda no monitor), onde
/// "Sábado, 9 de agosto" não cabe e só o número do dia não diz nada.
String formatEventShortDate(DateTime utc, String timezone) {
  final localTime = eventLocalTime(utc, timezone);
  return '${formatEventShortWeekday(utc, timezone)} '
      '${DateFormat('dd/MM', 'pt_BR').format(localTime)}';
}

/// O dia da semana por extenso e em minúscula, **sem o "-feira"**: "sábado",
/// "quinta".
///
/// É como se fala. "Ensaio na quinta-feira" está correto e ninguém diz — o
/// sufixo só aparece em texto formal, e aqui a frase é a de um recado.
String formatEventWeekdayName(DateTime utc, String timezone) {
  final localTime = eventLocalTime(utc, timezone);
  final name = DateFormat('EEEE', 'pt_BR').format(localTime);
  return name.replaceAll('-feira', '');
}

/// "no sábado", "na quinta" — o dia do ensaio dentro de uma frase.
///
/// Devolve vazio quando o ensaio é no mesmo dia da escala: ali dizer o dia
/// seria repetir a data que está logo acima.
///
/// O artigo muda com o gênero do dia: sábado e domingo são masculinos ("no"),
/// e de segunda a sexta o substantivo é "feira", feminino ("na"). Sai errado em
/// metade da semana se for fixo.
String formatRehearsalDayPhrase(
  DateTime rehearsalAt,
  DateTime startsAt,
  String timezone,
) {
  if (isSameLocalDay(rehearsalAt, startsAt, timezone)) return '';

  final localTime = eventLocalTime(rehearsalAt, timezone);
  final masculine = localTime.weekday == DateTime.saturday ||
      localTime.weekday == DateTime.sunday;
  final article = masculine ? 'no' : 'na';
  return '$article ${formatEventWeekdayName(rehearsalAt, timezone)}';
}

/// O horário do ensaio, curto o suficiente para caber numa linha.
///
/// No mesmo dia da escala: só a hora. Em outro dia: o dia da semana abreviado
/// antes dela. A data por extenso ("Segunda-feira, 10 de agosto 00:30")
/// estourava o cartão e não acrescentava nada de útil -- o ensaio acontece na
/// semana da escala, e ninguém marca um três semanas antes.
String formatRehearsalTime(
  DateTime rehearsalAt,
  DateTime startsAt,
  String timezone,
) {
  final hora = formatEventTime(rehearsalAt, timezone);
  if (isSameLocalDay(rehearsalAt, startsAt, timezone)) return hora;
  return '${formatEventShortWeekday(rehearsalAt, timezone)} $hora';
}

/// "DOM", "QUI" — o dia da semana dentro do bloco de data.
///
/// Caixa alta porque ali ele não é uma palavra numa frase: é o rótulo de cima
/// de um bloco de dois andares, e em minúscula sumia debaixo do número.
String formatEventBadgeWeekday(DateTime utc, String timezone) {
  return formatEventShortWeekday(utc, timezone).toUpperCase();
}

/// "13" — o número do dia, o andar de baixo do bloco de data.
///
/// Sem zero à esquerda: "03" ocupa a mesma largura de "13" e lê como código.
/// O alinhamento entre linhas vem dos algarismos tabulares, não do zero.
String formatEventDayNumber(DateTime utc, String timezone) {
  return DateFormat('d', 'pt_BR').format(eventLocalTime(utc, timezone));
}

/// "Setembro 2026" — o cabeçalho de um mês na lista da agenda.
///
/// Com o ano sempre, e não só quando difere do atual: aqui o título é a única
/// coisa separando dezembro de janeiro, e a agenda atravessa a virada do ano
/// com dois blocos vizinhos que se chamariam "Dezembro" e "Janeiro" sem dizer
/// de quando. É o inverso da regra de [formatEventWeekdayDate], onde a data
/// aparece dentro de uma frase e o ano repetido vira ruído.
String formatEventMonthYear(DateTime utc, String timezone) {
  // O rótulo vem de `monthYearLabel`, que é o mesmo do calendário de
  // indisponibilidade. O que esta função acrescenta é o fuso: um culto de
  // 1º de setembro às 00:30 em São Paulo é 03:30 UTC, e agrupá-lo pelo
  // instante o jogaria para o mês errado na virada.
  return monthYearLabel(eventLocalTime(utc, timezone));
}

/// A chave de agrupamento por mês: "2026-09".
///
/// Separada do rótulo porque dois meses de anos diferentes podem gerar o mesmo
/// nome, e agrupar pelo texto juntaria setembro de 2026 com setembro de 2027.
String eventMonthKey(DateTime utc, String timezone) {
  final localTime = eventLocalTime(utc, timezone);
  return '${localTime.year}-${localTime.month.toString().padLeft(2, '0')}';
}

/// "Manhã 08:00" — o culto pelo nome e pela hora, **sem repetir a hora** quando
/// o nome já a diz ("Culto das 8h", "Culto 10h30", "Vigília 22:00"). Na
/// equipe que escala por culto é comum o nome ser a própria hora, e "Culto das
/// 8h 08:00" dizia a mesma coisa duas vezes.
String serviceNameAndTime(String label, DateTime utc, String timezone) {
  final time = formatEventTime(utc, timezone);
  return labelStatesTime(label, eventLocalTime(utc, timezone))
      ? label
      : '$label $time';
}

/// O nome do culto já traz esta hora? "8h", "08h", "8:00", "08:00", "10h30",
/// "10:30" — e, com minuto zero, também "8h00". Um número qualquer ("Culto 2")
/// não conta: só a hora certa do culto.
bool labelStatesTime(String label, DateTime local) {
  final h = local.hour;
  final m = local.minute.toString().padLeft(2, '0');
  final hora = '0?$h';
  final pattern = local.minute == 0
      ? RegExp('(^|[^0-9])$hora(h(00)?|:00)(?![0-9])', caseSensitive: false)
      : RegExp('(^|[^0-9])$hora(h|:)$m(?![0-9])', caseSensitive: false);
  return pattern.hasMatch(label);
}
