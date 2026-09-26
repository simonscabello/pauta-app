import '../../../core/date/report_period.dart';

/// Quantas vezes uma música foi cantada, quando foi a última e em que tons.
class SongUsage {
  const SongUsage({
    required this.songId,
    required this.title,
    required this.playCount,
    required this.keys,
    this.artist,
    this.hymnRef,
    this.isArchived = false,
    this.lastPlayedAt,
  });

  factory SongUsage.fromJson(Map<String, dynamic> json) {
    return SongUsage(
      songId: json['songId'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String?,
      hymnRef: json['hymnRef'] as String?,
      isArchived: json['isArchived'] as bool? ?? false,
      playCount: json['playCount'] as int? ?? 0,
      lastPlayedAt: json['lastPlayedAt'] == null
          ? null
          : DateTime.parse(json['lastPlayedAt'] as String).toUtc(),
      keys: (json['keys'] as List<dynamic>? ?? const [])
          .map((item) => item as String)
          .toList(),
    );
  }

  final String songId;
  final String title;
  final String? artist;

  /// "314 CC", já montado pelo servidor. Nulo quando a música não está em
  /// hinário nenhum — e aí a tela não mostra nada no lugar.
  final String? hymnRef;

  /// A música pode ter sido arquivada depois de tocada. Ela continua no
  /// histórico — ele conta o que aconteceu, e o que aconteceu não muda.
  final bool isArchived;

  /// Escalas em que ela entrou. Manhã e noite do mesmo domingo contam uma.
  final int playCount;
  final DateTime? lastPlayedAt;

  /// Tons em que a equipe já a cantou, do próprio repertório da escala.
  final List<String> keys;

  bool get isHymn => hymnRef != null;
}

class SongUsageReport {
  const SongUsageReport({
    required this.neverPlayedCount,
    required this.songs,
    this.months,
    this.weekdays = const [],
  });

  factory SongUsageReport.fromJson(Map<String, dynamic> json) {
    return SongUsageReport(
      months: json['months'] as int?,
      weekdays: reportWeekdaysFromJson(json['weekdays']),
      neverPlayedCount: json['neverPlayedCount'] as int? ?? 0,
      songs: (json['songs'] as List<dynamic>? ?? const [])
          .map((item) => SongUsage.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Nulo quando o período veio por datas.
  final int? months;

  /// Os dias da semana com escala publicada no período — as opções do filtro.
  final List<ReportWeekday> weekdays;

  /// Quantas músicas do repertório ativo não entraram em nenhuma escala do
  /// período. Um número, e não uma lista: com os 581 hinos do Cantor Cristão
  /// importados de uma vez, a lista seria de centenas de linhas mudas.
  final int neverPlayedCount;
  final List<SongUsage> songs;
}
