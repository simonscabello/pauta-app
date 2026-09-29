/// Em que pé está a sugestão.
///
/// `fromJson` tolerante de propósito: o backend pode ganhar um valor novo (um
/// "conversar sobre", por exemplo) antes de o APK atualizado chegar no celular
/// de todo mundo. Cair em `pending` mostra a sugestão em vez de derrubar a
/// tela — e pendente é o que ela mais provavelmente é.
enum SuggestionStatus {
  pending,
  accepted,
  declined;

  static SuggestionStatus fromJson(Object? value) => switch (value) {
        'ACCEPTED' => SuggestionStatus.accepted,
        'DECLINED' => SuggestionStatus.declined,
        _ => SuggestionStatus.pending,
      };

  bool get isPending => this == SuggestionStatus.pending;
  bool get isResolved => !isPending;
}

/// Quem sugeriu. Sempre presente: sugestão anônima não existe.
class SuggestionAuthor {
  const SuggestionAuthor({
    required this.membershipId,
    required this.displayName,
    this.avatarUrl,
  });

  final String membershipId;
  final String displayName;
  final String? avatarUrl;

  factory SuggestionAuthor.fromJson(Map<String, dynamic> json) {
    return SuggestionAuthor(
      membershipId: json['membershipId'] as String,
      displayName: json['displayName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

/// Que tipo de material é o link.
///
/// Enum e não três campos soltos na tela: é o que faz a lista e o detalhe
/// mostrarem o mesmo ícone e o mesmo rótulo sem ninguém precisar lembrar de
/// mudar nos dois lugares.
enum SuggestionMaterialKind { lyrics, spotify, youtube }

class SuggestionMaterial {
  const SuggestionMaterial(this.kind, this.url);

  final SuggestionMaterialKind kind;
  final String url;

  String get label => switch (kind) {
        SuggestionMaterialKind.lyrics => 'Letra ou cifra',
        SuggestionMaterialKind.spotify => 'Spotify',
        SuggestionMaterialKind.youtube => 'YouTube',
      };
}

/// Alguém da equipe pedindo que a equipe cante uma música.
///
/// Uma coisa só, com data opcional: `targetDate` nulo quer dizer "para o
/// repertório, sem data", e não "faltou preencher".
class SongSuggestion {
  const SongSuggestion({
    required this.id,
    required this.title,
    required this.reason,
    required this.status,
    required this.createdBy,
    this.songId,
    this.artist,
    this.lyricsUrl,
    this.spotifyUrl,
    this.youtubeUrl,
    this.targetDate,
    this.declineReason,
    this.inRepertoire = false,
    this.alsoSuggestedBy = const [],
  });

  final String id;

  /// A música do repertório, quando a sugestão já corresponde a uma. Nula
  /// enquanto ninguém cadastrou — é o que decide entre "pôr no culto" e
  /// "cadastrar antes".
  final String? songId;

  /// Já resolvido pelo servidor: com `songId`, é o título da música.
  final String title;
  final String? artist;

  /// Onde a equipe encontra a música. Os mesmos três materiais que a tela de
  /// uma música do repertório oferece.
  ///
  /// **Letra e cifra num campo só**, ao contrário de [Song]: quem sugere manda
  /// o link que tem na mão. Obrigatório no servidor quando a sugestão não
  /// aponta para o repertório — sem ele o líder teria de sair procurando.
  ///
  /// Com `songId`, o servidor cai nos links da própria música quando a
  /// sugestão não trouxe os dela: a mesma regra do título.
  final String? lyricsUrl;
  final String? spotifyUrl;
  final String? youtubeUrl;

  /// Dia civil pedido, ou nulo para "sem data".
  final DateTime? targetDate;

  /// Por que valeria a pena. Vazio quando quem sugeriu não disse: o motivo
  /// é opcional desde 09/2026 (o servidor manda `null`).
  final String reason;

  bool get hasReason => reason.trim().isNotEmpty;

  final SuggestionStatus status;

  /// O que o líder escreveu ao adiar. Nulo é uso legítimo: às vezes o motivo
  /// certo é uma conversa pessoal, e o app não é o canal.
  final String? declineReason;

  final SuggestionAuthor createdBy;

  /// A música já está no repertório ativo da equipe.
  final bool inRepertoire;

  /// Quem **mais** pediu a mesma música, sem contar o autor desta.
  ///
  /// Repetida não é erro: é o sinal de que a equipe quer aquilo.
  final List<String> alsoSuggestedBy;

  bool get isForRepertoire => targetDate == null;

  /// Ficou sem resposta e o dia dela já passou.
  ///
  /// O servidor já a manda para as encerradas; a tela precisa saber também,
  /// senão a lista a mostra sem selo nenhum e o detalhe ainda oferece
  /// "Aceitar" para um domingo que acabou.
  bool isExpiredOn(DateTime today) =>
      status.isPending && targetDate != null && targetDate!.isBefore(today);

  /// Dá para pôr direto no culto? Sem cadastro, não há o que selecionar.
  bool get canGoToSetlist => songId != null;

  /// Os materiais que existem, na ordem em que a tela os mostra.
  ///
  /// Só o que veio preenchido: link que não existe não vira botão apagado nem
  /// linha "—". A lista usa isto para os indicadores miúdos do cartão, e a
  /// tela de detalhes para os botões — uma verdade só, nos dois lugares.
  List<SuggestionMaterial> get materials => [
        if ((lyricsUrl ?? '').isNotEmpty)
          SuggestionMaterial(SuggestionMaterialKind.lyrics, lyricsUrl!),
        if ((spotifyUrl ?? '').isNotEmpty)
          SuggestionMaterial(SuggestionMaterialKind.spotify, spotifyUrl!),
        if ((youtubeUrl ?? '').isNotEmpty)
          SuggestionMaterial(SuggestionMaterialKind.youtube, youtubeUrl!),
      ];

  factory SongSuggestion.fromJson(Map<String, dynamic> json) {
    final raw = json['targetDate'] as String?;
    final parts = raw?.split('-').map(int.parse).toList();

    return SongSuggestion(
      id: json['id'] as String,
      songId: json['songId'] as String?,
      title: json['title'] as String,
      artist: json['artist'] as String?,
      lyricsUrl: json['lyricsUrl'] as String?,
      spotifyUrl: json['spotifyUrl'] as String?,
      youtubeUrl: json['youtubeUrl'] as String?,
      // Sem UTC nem fuso: é data de calendário, não instante. Mesma leitura de
      // `Unavailability.date`.
      targetDate: parts == null ? null : DateTime(parts[0], parts[1], parts[2]),
      reason: json['reason'] as String? ?? '',
      status: SuggestionStatus.fromJson(json['status']),
      declineReason: json['declineReason'] as String?,
      inRepertoire: json['inRepertoire'] as bool? ?? false,
      createdBy: SuggestionAuthor.fromJson(
        json['createdBy'] as Map<String, dynamic>,
      ),
      alsoSuggestedBy: (json['alsoSuggestedBy'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
    );
  }
}

/// O que a montagem do repertório recebe: as pendentes do dia daquela escala,
/// e as sem data.
///
/// Duas listas numa resposta só — a faixa da tela usa `forDate`, a aba do
/// seletor usa as duas.
class EventSuggestions {
  const EventSuggestions({
    required this.date,
    this.forDate = const [],
    this.undated = const [],
  });

  /// O dia civil da escala, já resolvido no fuso da equipe pelo servidor.
  final String date;
  final List<SongSuggestion> forDate;
  final List<SongSuggestion> undated;

  bool get isEmpty => forDate.isEmpty && undated.isEmpty;

  /// As que dá para escolher no seletor: as sem cadastro não têm o que
  /// selecionar e ficam só na faixa, com o botão de cadastrar.
  List<SongSuggestion> get selectable =>
      [...forDate, ...undated].where((s) => s.canGoToSetlist).toList();

  factory EventSuggestions.fromJson(Map<String, dynamic> json) {
    List<SongSuggestion> parse(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .map((e) => SongSuggestion.fromJson(e as Map<String, dynamic>))
            .toList();

    return EventSuggestions(
      date: json['date'] as String? ?? '',
      forDate: parse('forDate'),
      undated: parse('undated'),
    );
  }
}
