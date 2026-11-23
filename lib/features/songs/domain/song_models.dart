import 'hymnal_models.dart';

/// Uma música do repertório da equipe.
///
/// O mesmo modelo serve à lista e ao detalhe: a lista não traz `lyrics` (são
/// centenas de músicas e a letra só importa na tela de uma delas), então o
/// campo fica nulo lá. `hasLyrics` diferencia "não tem letra" de "a lista não
/// carregou a letra".
/// Uma versão nomeada da cifra ("correção", "arranjo do ensaio 22/11"). A
/// original continua em [Song.chords].
class ChordVersion {
  const ChordVersion({
    required this.id,
    required this.name,
    required this.chords,
    this.chordsKey,
    this.createdByName,
    this.createdAt,
  });

  final String id;
  final String name;
  final String chords;

  /// Nulo usa o tom da cifra original.
  final String? chordsKey;
  final String? createdByName;
  final DateTime? createdAt;

  factory ChordVersion.fromJson(Map<String, dynamic> json) => ChordVersion(
        id: json['id'] as String,
        name: json['name'] as String,
        chords: json['chords'] as String,
        chordsKey: json['chordsKey'] as String?,
        createdByName: json['createdByName'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}

class Song {
  const Song({
    required this.id,
    required this.title,
    this.artist,
    this.composer,
    this.kind,
    this.pace,
    this.defaultKey,
    this.originalKey,
    this.bpm,
    this.lyrics,
    this.chords,
    this.chordsKey,
    this.chordsSource,
    this.chordVersions = const [],
    this.lyricsUrl,
    this.chordsUrl,
    this.youtubeUrl,
    this.spotifyUrl,
    this.isArchived = false,
    this.isNew = false,
    this.hymnals = const [],
    this.themes = const [],
  });

  final String id;
  final String title;
  final String? artist;
  final String? composer;

  /// 'HYMN' ou 'SONG'.
  final String? kind;

  /// 'CALM', 'MODERATE' ou 'UPBEAT'.
  final String? pace;

  /// O tom em que a equipe canta. Só a equipe preenche.
  final String? defaultKey;

  /// O tom da gravação, lido do CifraClub. Sugestão, não decisão.
  final String? originalKey;
  final int? bpm;

  final String? lyrics;
  final String? chords;
  final String? chordsKey;

  /// De onde veio a cifra guardada. Só o detalhe traz; nulo sem cifra.
  final ChordsSource? chordsSource;

  /// As versões da cifra além da original. Só o detalhe traz.
  final List<ChordVersion> chordVersions;

  ChordVersion? chordVersion(String? id) =>
      chordVersions.where((v) => v.id == id).firstOrNull;
  final String? lyricsUrl;
  final String? chordsUrl;
  final String? youtubeUrl;
  final String? spotifyUrl;
  final bool isArchived;

  /// A equipe ainda está aprendendo esta música.
  ///
  /// Marcado no cadastro, desligado no repertório quando a equipe domina e a
  /// igreja já canta junto. Não é dedução de nada: música cantada há anos que
  /// só hoje entrou no app é nova para o **app**, não para a equipe — e tocar
  /// uma vez não encerra a novidade.
  final bool isNew;

  /// Em que hinários esta música está, e com que número. Vazia em cântico.
  ///
  /// É como a igreja chama o hino — ninguém pede "Pão da Vida", pede "142" —
  /// então o número aparece no lugar de maior destaque da linha e a busca do
  /// servidor também o compara.
  ///
  /// **Lista, e não um número solto.** O mesmo hino está em mais de um hinário
  /// com números diferentes, e isso é um fato sobre a música, não sobre a
  /// igreja que a canta. A primeira é a principal — é ela que a escala e o
  /// texto do WhatsApp mostram.
  final List<HymnalRef> hymnals;

  /// Sobre o que a música fala, nos valores do enum do servidor
  /// (`'ADORACAO'`, `'CEIA'`...). Vazia enquanto ninguém classificou.
  ///
  /// Vem também na listagem, ao contrário da letra: são poucas etiquetas por
  /// música, a lista filtra por elas e a linha as mostra.
  final List<String> themes;

  /// A referência que representa a música, ou nulo quando ela não está em
  /// hinário nenhum.
  HymnalRef? get hymnal => primaryHymnalRef(hymnals);

  /// Está em algum hinário. É o que separa os dois acervos do repertório.
  bool get isHymn => hymnals.isNotEmpty;

  /// O número do hinário principal, para ordenar a aba "Hinos".
  int? get hymnNumber => hymnal?.number;

  bool get hasLyrics => lyrics != null && lyrics!.trim().isNotEmpty;

  bool get hasChords => chords?.trim().isNotEmpty ?? false;

  String get displayTitle =>
      hymnal == null ? title : '${hymnal!.number} · $title';

  String get subtitle {
    final parts = [artist, composer].where((p) => p != null && p.isNotEmpty);
    return parts.isEmpty ? 'Sem artista' : parts.first!;
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String?,
      composer: json['composer'] as String?,
      kind: json['kind'] as String?,
      pace: json['pace'] as String?,
      defaultKey: json['defaultKey'] as String?,
      originalKey: json['originalKey'] as String?,
      bpm: json['bpm'] as int?,
      lyrics: json['lyrics'] as String?,
      chords: json['chords'] as String?,
      chordsKey: json['chordsKey'] as String?,
      chordsSource: json['chordsSource'] == null
          ? null
          : ChordsSource.fromJson(json['chordsSource'] as Map<String, dynamic>),
      chordVersions: [
        for (final v in json['chordVersions'] as List<dynamic>? ?? const [])
          ChordVersion.fromJson(v as Map<String, dynamic>),
      ],
      lyricsUrl: json['lyricsUrl'] as String?,
      chordsUrl: json['chordsUrl'] as String?,
      youtubeUrl: json['youtubeUrl'] as String?,
      spotifyUrl: json['spotifyUrl'] as String?,
      isArchived: json['isArchived'] as bool? ?? false,
      isNew: json['isNew'] as bool? ?? false,
      // Ausente vale lista vazia: é o que o cache gravado antes desta versão
      // guarda, e é o que a maioria das músicas é.
      hymnals: (json['hymnals'] as List<dynamic>? ?? const [])
          .map((e) => HymnalRef.fromJson(e as Map<String, dynamic>))
          .toList(),
      // Ausente vale lista vazia: é o que o cache gravado antes desta versão
      // guarda, e é o que uma música sem classificação significa.
      themes: (json['themes'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
    );
  }
}

String kindLabel(String? kind) => switch (kind) {
      'HYMN' => 'Hino',
      'SONG' => 'Cântico',
      _ => '—',
    };

String paceLabel(String? pace) => switch (pace) {
      'CALM' => 'Calma',
      'MODERATE' => 'Moderada',
      'UPBEAT' => 'Agitada',
      _ => '—',
    };

/// Música que outra equipe já cadastrou.
///
/// Vem o cadastro -- cifra, links, hinário, temas --, **e não a letra**: o
/// texto que outra igreja digitou não é dela para redistribuir. O servidor lê
/// a letra de novo da página da cifra ou do Letras, quando ela responde.
class CatalogCandidate {
  const CatalogCandidate({
    required this.sourceSongId,
    required this.title,
    this.artist,
    this.composer,
    this.originalKey,
    this.bpm,
    this.hasChords = false,
    this.hasYoutube = false,
    this.hasSpotify = false,
  });

  final String sourceSongId;
  final String title;
  final String? artist;
  final String? composer;
  final String? originalKey;
  final int? bpm;
  final bool hasChords;
  final bool hasYoutube;
  final bool hasSpotify;

  factory CatalogCandidate.fromJson(Map<String, dynamic> json) {
    return CatalogCandidate(
      sourceSongId: json['sourceSongId'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String?,
      composer: json['composer'] as String?,
      originalKey: json['originalKey'] as String?,
      bpm: json['bpm'] as int?,
      hasChords: json['hasChords'] as bool? ?? false,
      hasYoutube: json['hasYoutube'] as bool? ?? false,
      hasSpotify: json['hasSpotify'] as bool? ?? false,
    );
  }
}

/// Resultado da busca no Spotify.
class ExternalCandidate {
  const ExternalCandidate({
    required this.title,
    required this.artist,
    required this.spotifyUrl,
    this.album,
    this.year,
  });

  final String title;
  final String artist;
  final String spotifyUrl;
  final String? album;
  final String? year;

  factory ExternalCandidate.fromJson(Map<String, dynamic> json) {
    return ExternalCandidate(
      title: json['title'] as String,
      artist: json['artist'] as String? ?? '',
      spotifyUrl: json['spotifyUrl'] as String? ?? '',
      album: json['album'] as String?,
      year: json['year'] as String?,
    );
  }
}

/// Por que a equipe diz que pode guardar a cifra, nas palavras da tela.
const chordRightsBasisLabels = {
  'TEAM_ARRANGEMENT': 'Arranjo da equipe',
  'PUBLIC_DOMAIN': 'Domínio público',
  'PERMISSION': 'Permissão do autor ou da editora',
  'SOURCE_LICENSE': 'Licença da fonte',
};

/// De onde veio a cifra guardada e quem declarou que a equipe pode guardá-la.
class ChordsSource {
  const ChordsSource({
    required this.kind,
    required this.rightsBasis,
    required this.importedAt,
    required this.importedByName,
    this.sourceHost,
  });

  /// `URL`, `TEXT` ou `FILE`.
  final String kind;
  final String rightsBasis;
  final DateTime importedAt;
  final String importedByName;
  final String? sourceHost;

  factory ChordsSource.fromJson(Map<String, dynamic> json) => ChordsSource(
        kind: json['kind'] as String,
        rightsBasis: json['rightsBasis'] as String,
        importedAt: DateTime.parse(json['importedAt'] as String),
        importedByName: json['importedByName'] as String,
        sourceHost: json['sourceHost'] as String?,
      );
}
