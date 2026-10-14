import '../../events/domain/service_moments.dart';

/// Em que momento do culto a música costuma entrar, e quantas vezes.
///
/// **Inferido do histórico das escalas, nunca cadastrado.** Ninguém precisa
/// dizer que "Tudo Entregarei" serve para as ofertas: se a equipe já a cantou
/// ali quatro vezes, o app sabe.
class MomentUsage {
  const MomentUsage({
    required this.moment,
    required this.count,
    this.label,
    this.momentId,
  });

  factory MomentUsage.fromJson(Map<String, dynamic> json) {
    return MomentUsage(
      moment: json['moment'] as String,
      label: json['label'] as String?,
      momentId: json['momentId'] as String?,
      count: json['count'] as int? ?? 0,
    );
  }

  /// O valor do enum (`'LOUVOR'`, `'DIZIMOS_E_OFERTAS'`...).
  final String moment;

  /// O nome do momento na equipe — renomeado, ou cadastrado por ela —, ou o
  /// escrito à mão em `OUTRO` ("Santa Ceia"). Nulo no de fábrica sem a lista
  /// da equipe (as escalas de antes dela).
  final String? label;

  /// O momento da lista da equipe, quando o histórico sabe qual é.
  final String? momentId;

  /// Escalas, e não cultos: a oferta da manhã e a da noite do mesmo domingo
  /// são uma ida à oferta.
  final int count;

  String get displayLabel {
    final nome = label?.trim() ?? '';
    if (nome.isNotEmpty) return nome;
    return serviceMomentLabel(moment) ?? moment;
  }
}

/// O que o histórico diz de uma música: quando foi a última vez, quantas vezes
/// e em que momentos do culto.
///
/// Só existe para música **já cantada** — escala publicada e já passada, a
/// mesma regra do relatório de uso. A nunca cantada não tem histórico, e a
/// tela não inventa um "nunca" em cada linha.
class SongHistory {
  const SongHistory({
    required this.songId,
    this.lastPlayedAt,
    this.playCount = 0,
    this.last3Months = 0,
    this.last6Months = 0,
    this.last12Months = 0,
    this.moments = const [],
  });

  factory SongHistory.fromJson(Map<String, dynamic> json) {
    return SongHistory(
      songId: json['songId'] as String,
      lastPlayedAt: json['lastPlayedAt'] == null
          ? null
          : DateTime.parse(json['lastPlayedAt'] as String).toUtc(),
      playCount: json['playCount'] as int? ?? 0,
      last3Months: json['last3Months'] as int? ?? 0,
      last6Months: json['last6Months'] as int? ?? 0,
      last12Months: json['last12Months'] as int? ?? 0,
      moments: (json['moments'] as List<dynamic>? ?? const [])
          .map((item) => MomentUsage.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final String songId;
  final DateTime? lastPlayedAt;
  final int playCount;
  final int last3Months;
  final int last6Months;
  final int last12Months;

  /// Da mais usada para a menos.
  final List<MomentUsage> moments;
}

// ---------------------------------------------------------------------------
// Como o histórico se diz em português
//
// **Frase, e não métrica.** "Cantada há 12 dias" e "Há 9 meses sem cantar" são
// lidas de relance por quem não pensa em números; "12d" e "last: 2026-06-02"
// obrigariam a traduzir. As funções são puras para o teste travar a redação.
// ---------------------------------------------------------------------------

/// Dias de calendário entre a escala e hoje, no fuso do aparelho.
///
/// Por datas, e não por horas: a escala de domingo às 19h ainda é "ontem" na
/// segunda às 8h, embora não tenham passado 24 horas.
int civilDaysSince(DateTime instant, DateTime now) {
  final antes = instant.toLocal();
  final agora = now.toLocal();
  return DateTime.utc(agora.year, agora.month, agora.day)
      .difference(DateTime.utc(antes.year, antes.month, antes.day))
      .inDays;
}

/// Meses de calendário completos entre a escala e hoje.
int monthsSince(DateTime instant, DateTime now) {
  final antes = instant.toLocal();
  final agora = now.toLocal();
  final meses = (agora.year - antes.year) * 12 + agora.month - antes.month;
  return agora.day < antes.day ? meses - 1 : meses;
}

/// "meses", "um ano", "mais de um ano", "mais de 2 anos".
String _longSpan(int months) {
  if (months < 12) return '$months meses';
  if (months == 12) return 'um ano';
  if (months < 24) return 'mais de um ano';
  return 'mais de ${months ~/ 12} anos';
}

/// A última vez, dita do jeito que se fala.
///
/// - até cinco meses, o foco é **quando**: "Cantada há 12 dias", "Cantada há
///   3 meses";
/// - a partir de seis, o foco vira **a ausência**: "Há 8 meses sem cantar" —
///   é o ponto em que a informação deixa de ser "cuidado com a repetição" e
///   passa a ser "essa sumiu".
///
/// Nulo quando a música nunca foi cantada.
String? lastPlayedPhrase(DateTime? lastPlayedAt, DateTime now) {
  if (lastPlayedAt == null) return null;

  final days = civilDaysSince(lastPlayedAt, now);
  if (days <= 0) return 'Cantada hoje';
  if (days == 1) return 'Cantada ontem';
  if (days < 30) return 'Cantada há $days dias';
  if (days < 60) return 'Cantada há ${days ~/ 7} semanas';

  final months = monthsSince(lastPlayedAt, now);
  if (months < 6) return 'Cantada há ${months < 2 ? 2 : months} meses';
  return 'Há ${_longSpan(months)} sem cantar';
}

/// O descanso da música como **motivo** de sugestão: "4 meses sem cantar".
///
/// Em minúscula e sem o "Há", porque entra no meio da linha de motivos
/// ("Gratidão · já utilizada neste momento · 4 meses sem cantar").
String? restPhrase(DateTime? lastPlayedAt, DateTime now) {
  if (lastPlayedAt == null) return null;

  final days = civilDaysSince(lastPlayedAt, now);
  if (days < 14) return null;
  if (days < 60) return '${days ~/ 7} semanas sem cantar';

  final months = monthsSince(lastPlayedAt, now);
  return '${_longSpan(months < 2 ? 2 : months)} sem cantar';
}

/// Cantada nas últimas três semanas: é o ponto em que pô-la de novo vira
/// repetição que a igreja percebe. A tela usa isso só para tingir a frase —
/// avisa, e não impede.
bool isRecentlyPlayed(DateTime? lastPlayedAt, DateTime now) =>
    lastPlayedAt != null && civilDaysSince(lastPlayedAt, now) <= 21;

/// "3 vezes em 6 meses". Nulo com uma vez ou nenhuma: a frase da última vez
/// já disse isso, e "1 vez em 6 meses" ao lado de "Cantada há 2 meses" é a
/// mesma informação duas vezes.
String? recentCountPhrase(int last6Months) =>
    last6Months >= 2 ? '$last6Months vezes em 6 meses' : null;

String timesLabel(int count) => count == 1 ? '1 vez' : '$count vezes';

/// "Momento de Louvor (7 vezes) · Abertura (2 vezes)" — os mais usados.
String? usualMomentsPhrase(List<MomentUsage> moments, {int max = 2}) {
  if (moments.isEmpty) return null;
  return moments
      .take(max)
      .map((m) => '${m.displayLabel} (${timesLabel(m.count)})')
      .join(' · ');
}
