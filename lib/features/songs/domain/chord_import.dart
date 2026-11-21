/// Um site de onde o importador sabe ler cifra, e se está liberado.
class ChordSourceInfo {
  const ChordSourceInfo({
    required this.id,
    required this.name,
    required this.mode,
  });

  final String id;
  final String name;

  /// `IMPORT` traz a cifra; `LINK_ONLY` só aceita guardar o link.
  final String mode;

  bool get canImport => mode == 'IMPORT';

  factory ChordSourceInfo.fromJson(Map<String, dynamic> json) =>
      ChordSourceInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        mode: json['mode'] as String,
      );
}

/// A cifra lida de um link, antes de virar a cifra da música.
class ChordPreview {
  const ChordPreview({
    required this.sourceName,
    required this.sourceUrl,
    required this.sheet,
    this.title,
    this.artist,
    this.key,
    this.capo,
    this.warnings = const [],
  });

  final String sourceName;
  final String sourceUrl;

  /// Acordes na linha de cima da sílaba, como a página escreve.
  final String sheet;
  final String? title;
  final String? artist;

  /// O tom em que os acordes da página estão escritos.
  final String? key;
  final int? capo;

  /// `OTHER_SONG`, `CAPO`, `TABLATURE_REMOVED`.
  final List<String> warnings;

  factory ChordPreview.fromJson(Map<String, dynamic> json) => ChordPreview(
        sourceName:
            (json['source'] as Map<String, dynamic>)['name'] as String,
        sourceUrl: json['sourceUrl'] as String,
        sheet: json['sheet'] as String,
        title: json['title'] as String?,
        artist: json['artist'] as String?,
        key: json['key'] as String?,
        capo: json['capo'] as int?,
        warnings: [
          for (final w in json['warnings'] as List<dynamic>? ?? const [])
            w as String,
        ],
      );
}

/// O que a folha de importar devolve ao formulário: a cifra lida, ou só o
/// link, quando o site não entrega a cifra.
typedef ChordImportResult = ({ChordPreview? preview, String? keepLink});
