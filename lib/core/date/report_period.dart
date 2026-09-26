import 'package:intl/intl.dart';

import 'civil_date.dart';

/// O período de um relatório: **a mesma escolha nos três.**
///
/// A participação contava em semanas (8, 12, 24) e o uso do repertório em
/// meses (3, 6, 12). A equipe pensa em meses, e comparar "12 semanas" de uma
/// tela com "3 meses" da outra era conta que ninguém devia ter de fazer. Agora
/// participação, "Quem não pode" e uso do repertório oferecem os mesmos atalhos
/// ([reportPeriodPresets]) e o mesmo "Escolher datas…".
///
/// Igualdade por valor: o período é parte da chave do provider, e dois
/// `ReportPeriodMonths(3)` diferentes precisam cair no mesmo cache.
sealed class ReportPeriod {
  const ReportPeriod();

  /// O que vai na consulta. A API aceita `months` **ou** `from`/`to`.
  Map<String, Object> toQuery();

  /// O rótulo do seletor: "Últimos 3 meses", "1 de mar. – 30 de jun.".
  String get label;

  /// O pedaço de frase que diz o período: "nos últimos 3 meses", "entre 1 de
  /// mar. e 30 de jun.". Vai no fim de frases como "12 músicas cantadas …".
  String get phrase;
}

/// Os atalhos. Um mês para "como foi o último mês", doze para o ano.
const reportPeriodPresets = [1, 3, 6, 12];

/// O filtro por dia da semana dos relatórios: "Só domingos", "Só quintas".
///
/// Numeração da grade de cultos (0 = domingo), e **não** o `DateTime.weekday`
/// do Dart. Por extenso e sem "-feira", como a equipe fala do culto de quinta.
const _weekdayPlurals = [
  'domingos',
  'segundas',
  'terças',
  'quartas',
  'quintas',
  'sextas',
  'sábados',
];

/// Um dia da semana com escala no período, e quantas: as opções do filtro.
/// Vêm da resposta, e não da grade de cultos: a grade diz o que se repete
/// hoje, e o histórico importado ou a vigília de sábado também contam.
class ReportWeekday {
  const ReportWeekday({required this.weekday, required this.count});

  factory ReportWeekday.fromJson(Map<String, dynamic> json) {
    return ReportWeekday(
      weekday: json['weekday'] as int,
      count: json['count'] as int? ?? 0,
    );
  }

  /// 0 = domingo ... 6 = sábado.
  final int weekday;

  /// Escalas publicadas naquele dia da semana, no período.
  final int count;
}

List<ReportWeekday> reportWeekdaysFromJson(Object? json) {
  return (json as List<dynamic>? ?? const [])
      .map((item) => ReportWeekday.fromJson(item as Map<String, dynamic>))
      .toList();
}

/// "Domingos", para a opção do menu.
String weekdayPluralLabel(int weekday) {
  final plural = _weekdayPlurals[weekday];
  return '${plural[0].toUpperCase()}${plural.substring(1)}';
}

/// "Só domingos" ou "Todos os dias", para o botão do filtro.
String weekdayFilterLabel(int? weekday) =>
    weekday == null ? 'Todos os dias' : 'Só ${_weekdayPlurals[weekday]}';

/// "aos domingos", "às quintas" — o fim de uma frase de resumo. Nulo quando
/// não há filtro, e aí a frase não ganha nada.
String? weekdayPhrase(int? weekday) {
  if (weekday == null) return null;
  // Domingo e sábado são masculinos; os outros, femininos.
  final article = weekday == 0 || weekday == 6 ? 'aos' : 'às';
  return '$article ${_weekdayPlurals[weekday]}';
}

class ReportPeriodMonths extends ReportPeriod {
  const ReportPeriodMonths(this.months);

  final int months;

  @override
  Map<String, Object> toQuery() => {'months': months};

  @override
  String get label => months == 1 ? 'Último mês' : 'Últimos $months meses';

  @override
  String get phrase =>
      months == 1 ? 'no último mês' : 'nos últimos $months meses';

  @override
  bool operator ==(Object other) =>
      other is ReportPeriodMonths && other.months == months;

  @override
  int get hashCode => Object.hash('months', months);
}

/// Um intervalo de dias civis, as duas pontas inclusivas.
///
/// O fim pode ser hoje, e nunca depois: relatório conta o que aconteceu, e o
/// seletor de datas não deixa escolher o que ainda não chegou.
class ReportPeriodRange extends ReportPeriod {
  ReportPeriodRange(DateTime from, DateTime to)
      : from = DateTime(from.year, from.month, from.day),
        to = DateTime(to.year, to.month, to.day);

  final DateTime from;
  final DateTime to;

  @override
  Map<String, Object> toQuery() => {'from': dateKey(from), 'to': dateKey(to)};

  /// O rótulo do menu, com o mês abreviado: "6 – 20 de set.", "6 de ago. –
  /// 20 de set.".
  @override
  String get label => _range(abbreviated: true, joiner: ' – ');

  /// A frase, com o mês por extenso: "entre 6 e 20 de setembro". O abreviado
  /// do pt_BR termina em ponto, e no fim de uma frase virava "set..".
  @override
  String get phrase => from == to
      ? 'em ${_range(abbreviated: false, joiner: '')}'
      : 'entre ${_range(abbreviated: false, joiner: ' e ')}';

  /// O que as duas pontas têm em comum só se escreve uma vez: o mês ("6 – 20
  /// de set."), e o ano, que só aparece quando não é este.
  String _range({required bool abbreviated, required String joiner}) {
    final month = abbreviated ? 'MMM' : 'MMMM';
    final year = from.year != to.year || to.year != today().year;
    String format(DateTime date, String pattern) =>
        DateFormat(pattern, 'pt_BR').format(date);
    final end = format(to, "d 'de' $month${year ? " 'de' y" : ''}");

    if (from == to) return end;
    if (from.year == to.year && from.month == to.month) {
      return '${from.day}$joiner$end';
    }
    if (from.year == to.year) {
      return '${format(from, "d 'de' $month")}$joiner$end';
    }
    return '${format(from, "d 'de' $month 'de' y")}$joiner$end';
  }

  @override
  bool operator ==(Object other) =>
      other is ReportPeriodRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash('range', from, to);
}
