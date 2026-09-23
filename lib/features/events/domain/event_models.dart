import '../../songs/domain/hymnal_models.dart';
import '../../unavailability/domain/unavailability_models.dart';
import 'event_datetime.dart';
import 'service_moments.dart';

class AssignmentMember {
  const AssignmentMember({
    required this.id,
    required this.membershipId,
    required this.displayName,
    required this.note,
    required this.isRegisteredForPosition,
    this.avatarUrl,
  });

  factory AssignmentMember.fromJson(Map<String, dynamic> json) {
    return AssignmentMember(
      id: json['id'] as String,
      membershipId: json['membershipId'] as String,
      displayName: json['displayName'] as String,
      note: json['note'] as String?,
      isRegisteredForPosition: json['isRegisteredForPosition'] as bool? ?? true,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }

  final String id;
  final String membershipId;
  final String displayName;
  final String? note;
  final bool isRegisteredForPosition;

  /// Foto da conta, quando ela existe. Caminho relativo ao host da API, como
  /// em toda resposta do servidor -- quem monta o endereço é o [AppAvatar].
  ///
  /// Nula em três casos, e todos caem na inicial do nome: integrante sem
  /// conta, convidado, e cache gravado antes desta versão. **A listagem da
  /// agenda continua sem foto**: ela devolve dezenas de escalas por resposta,
  /// e nenhum card mostra rosto.
  final String? avatarUrl;
}

/// Quem conduz a ministração do louvor nesta escala.
///
/// Um por escala, não por função: é quem lê os versículos, fala antes das
/// Uma música dentro da escala.
///
/// O `key` já vem resolvido pelo servidor: é o tom desta escala quando alguém
/// o definiu, senão o tom da equipe. A tela não precisa refazer essa escolha,
/// e o texto compartilhado também não.
class EventSong {
  const EventSong({
    required this.songId,
    required this.serviceId,
    required this.title,
    this.artist,
    this.key,
    this.keyOverride,
    this.defaultKey,
    this.note,
    this.isNew = false,
    this.moment,
    this.momentLabel,
    this.hymnals = const [],
    this.chordsUrl,
    this.lyricsUrl,
    this.youtubeUrl,
    this.spotifyUrl,
  });

  final String songId;

  /// Em qual culto da escala esta música entra.
  ///
  /// A mesma música pode aparecer de manhã e à noite: são duas linhas, e à
  /// noite pode estar em outro tom, em outra ordem e com outro recado.
  final String serviceId;

  final String title;
  final String? artist;

  /// O tom que vale nesta escala.
  final String? key;

  /// Só quando esta escala mudou o tom -- a tela sinaliza a diferença.
  final String? keyOverride;
  final String? defaultKey;

  /// Recado da música ("entra só o teclado", "repetir o refrão").
  final String? note;

  /// A equipe ainda não tocou esta música: "chegue sabendo".
  ///
  /// **Vem calculado do servidor, e não há como marcá-lo daqui.** Ou a música
  /// já apareceu numa escala publicada anterior desta equipe, ou não apareceu;
  /// é um fato entre a equipe e a canção, não uma escolha de quem monta a
  /// escala. Depois do domingo em que ela estreia, o selo some sozinho.
  ///
  /// O que a equipe controla é a exceção, na tela da música: "já cantamos esta
  /// há anos", para o acervo que entrou no app sem histórico.
  final bool isNew;

  /// Em que momento do culto esta música entra, nos valores do enum do
  /// servidor (`'ABERTURA'`, `'DIZIMOS_E_OFERTAS'`...). Nulo quando ninguém
  /// escolheu — e nulo **continua nulo**: nada aqui deduz "Momento de Louvor".
  ///
  /// **É desta escala, e não do cadastro da música**, pelo mesmo motivo que o
  /// tom desta escala: "Estou Seguro" é oferta num domingo e abertura no
  /// outro.
  final String? moment;

  /// O nome escrito à mão quando o momento é `OUTRO` ("Santa Ceia").
  final String? momentLabel;

  /// Em que hinários a MÚSICA está, com a principal na frente. Fato do
  /// cadastro, como o título — vem junto para a linha da escala poder
  /// escrever "314 CC" sem uma segunda ida ao servidor.
  final List<HymnalRef> hymnals;

  final String? chordsUrl;
  final String? lyricsUrl;
  final String? youtubeUrl;
  final String? spotifyUrl;

  bool get hasCustomKey => keyOverride != null && keyOverride!.isNotEmpty;

  /// A referência que sai na escala, ou nulo quando a música não está em
  /// hinário nenhum.
  HymnalRef? get hymnal => primaryHymnalRef(hymnals);

  /// "Dízimos e Ofertas" — ou o que a pessoa escreveu, em `OUTRO`. Nulo sem
  /// momento: a linha não mostra marcador de campo vazio.
  String? get momentText => serviceMomentLabel(moment, momentLabel);

  factory EventSong.fromJson(Map<String, dynamic> json) {
    return EventSong(
      songId: json['songId'] as String,
      // Cache gravado antes do repertório por culto não tem `serviceId`. Vazio
      // em vez de exceção: a escala continua abrindo, e as músicas caem no
      // primeiro culto ao serem agrupadas -- que é onde elas estavam.
      serviceId: json['serviceId'] as String? ?? '',
      title: json['title'] as String,
      artist: json['artist'] as String?,
      key: json['key'] as String?,
      keyOverride: json['keyOverride'] as String?,
      defaultKey: json['defaultKey'] as String?,
      note: json['note'] as String?,
      // Falso quando ausente: é o que o cache gravado antes desta versão
      // significa, e é o que a maioria das músicas será para sempre.
      isNew: json['isNew'] as bool? ?? false,
      moment: json['moment'] as String?,
      momentLabel: json['momentLabel'] as String?,
      // Ausente vale lista vazia: é o que o cache gravado antes desta versão
      // guarda, e é o que a maioria das músicas é.
      hymnals: (json['hymnals'] as List<dynamic>? ?? const [])
          .map((e) => HymnalRef.fromJson(e as Map<String, dynamic>))
          .toList(),
      chordsUrl: json['chordsUrl'] as String?,
      lyricsUrl: json['lyricsUrl'] as String?,
      youtubeUrl: json['youtubeUrl'] as String?,
      spotifyUrl: json['spotifyUrl'] as String?,
    );
  }
}

/// músicas e delega. Está escalado em alguma função, mas o papel não pertence
/// à função.
class EventMinister {
  const EventMinister({required this.membershipId, required this.displayName});

  factory EventMinister.fromJson(Map<String, dynamic> json) {
    return EventMinister(
      membershipId: json['membershipId'] as String,
      displayName: json['displayName'] as String,
    );
  }

  final String membershipId;
  final String displayName;
}

class AssignmentGroup {
  const AssignmentGroup({
    required this.positionId,
    required this.positionName,
    this.positionCategory,
    required this.sortOrder,
    required this.members,
  });

  factory AssignmentGroup.fromJson(Map<String, dynamic> json) {
    return AssignmentGroup(
      positionId: json['positionId'] as String,
      positionName: json['positionName'] as String,
      positionCategory: json['positionCategory'] as String?,
      sortOrder: json['sortOrder'] as int? ?? 0,
      members: (json['members'] as List<dynamic>? ?? const [])
          .map((e) => AssignmentMember.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String positionId;
  final String positionName;

  /// `VOCAL`, `INSTRUMENT`, `TECH` ou `OTHER`. Nulo em cache gravado antes de o
  /// servidor mandar o campo -- e aí quem usa trata a função como outra
  /// qualquer, em vez de adivinhar pelo nome.
  final String? positionCategory;

  bool get isInstrument => positionCategory == 'INSTRUMENT';

  final int sortOrder;
  final List<AssignmentMember> members;
}

/// Um horário de culto dentro da escala do dia.
///
/// No domingo típico da equipe são dois — manhã e noite — com a mesma
/// escalação, o mesmo ensaio e o mesmo local. Por isso o culto é filho da
/// escala, e não uma escala própria.
class EventService {
  const EventService({
    required this.id,
    required this.label,
    required this.startsAt,
    this.songCount,
  });

  factory EventService.fromJson(Map<String, dynamic> json) {
    return EventService(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? 'Culto',
      startsAt: DateTime.parse(json['startsAt'] as String).toUtc(),
      songCount: json['songCount'] as int?,
    );
  }

  final String id;

  /// "Manhã", "Noite". Vem da grade da igreja, ou é digitado em culto avulso.
  final String label;

  final DateTime startsAt;
  final int? songCount;
}

class SameDayConflict {
  const SameDayConflict({
    required this.membershipId,
    required this.displayName,
    required this.otherEventId,
    this.otherEventTitle,
  });

  factory SameDayConflict.fromJson(Map<String, dynamic> json) {
    return SameDayConflict(
      membershipId: json['membershipId'] as String,
      displayName: json['displayName'] as String,
      otherEventId: json['otherEventId'] as String,
      otherEventTitle: json['otherEventTitle'] as String?,
    );
  }

  final String membershipId;
  final String displayName;
  final String otherEventId;

  /// Título da outra escala do mesmo dia. **Nulo é o caso comum**, e não
  /// ausência de dado: só culto especial recebe nome, o domingo comum é
  /// identificado pela data. O backend sempre declarou `string | null` aqui;
  /// era o cast não-nulável deste lado que derrubava a escala inteira por
  /// causa de um aviso secundário -- e como o estouro acontece dentro do
  /// `fromJson`, a tela mostrava "Não foi possível carregar a escala", que
  /// é a mensagem de rede fora do ar.
  final String? otherEventTitle;
}

class EventWarnings {
  const EventWarnings({
    this.sameDayConflicts = const [],
    this.unavailableAssigned = const [],
  });

  factory EventWarnings.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const EventWarnings();
    }

    return EventWarnings(
      sameDayConflicts: (json['sameDayConflicts'] as List<dynamic>? ?? const [])
          .map((e) => SameDayConflict.fromJson(e as Map<String, dynamic>))
          .toList(),
      unavailableAssigned:
          (json['unavailableAssigned'] as List<dynamic>? ?? const [])
              .map((e) => UnavailableMember.fromJson(e as Map<String, dynamic>))
              .toList(),
    );
  }

  final List<SameDayConflict> sameDayConflicts;

  /// Gente escalada que já tinha avisado que não pode neste dia.
  final List<UnavailableMember> unavailableAssigned;
}

/// Como o repertório desta escala é decidido.
///
/// **É da escala inteira, e não de cada culto.** No domingo de manhã e noite
/// quem ministra é a mesma pessoa e o jeito de trabalhar é um só; guardar isso
/// por culto criaria um estado que ninguém pediu e quatro combinações para as
/// telas tratarem.
///
/// Um booleano não serviria: `semRepertorio: true` não distingue "a lista
/// ainda não saiu" de "não vai existir lista", e é exatamente essa a pergunta
/// que a agenda, o detalhe, a publicação e o texto compartilhado fazem.
enum RepertoireMode {
  /// Escolhido antes. Culto sem música é pendência, e o app diz o que falta.
  planned('PLANNED'),

  /// Definido na hora, no culto. Repertório vazio é o estado final: nada aqui
  /// é chamado de pendência, e a criação da escala não passa pela montagem.
  onTheFly('ON_THE_FLY');

  const RepertoireMode(this.wire);

  /// O valor que vai e vem no JSON.
  final String wire;

  /// **Ausente vale [planned]**, e é o que sustenta duas compatibilidades ao
  /// mesmo tempo: o cache gravado antes deste campo existir e o backend que
  /// ainda não o devolve. Valor desconhecido cai no mesmo lugar -- uma versão
  /// futura inventando um terceiro modo não pode derrubar a tela da escala.
  static RepertoireMode fromJson(Object? value) {
    return RepertoireMode.values.firstWhere(
      (mode) => mode.wire == value,
      orElse: () => RepertoireMode.planned,
    );
  }
}

class Event {
  const Event({
    required this.id,
    required this.teamId,
    required this.title,
    required this.startsAt,
    required this.rehearsalAt,
    required this.location,
    required this.notes,
    required this.colorPalette,
    required this.status,
    this.repertoireMode = RepertoireMode.planned,
    required this.timezone,
    required this.assignments,
    required this.songs,
    this.services = const [],
    this.minister,
    this.unavailable = const [],
    this.warnings = const EventWarnings(),
    this.updatedAt,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'] as String,
      teamId: json['teamId'] as String,
      title: (json['title'] as String?)?.trim(),
      startsAt: DateTime.parse(json['startsAt'] as String).toUtc(),
      rehearsalAt: _parseUtcDateTime(json['rehearsalAt']),
      location: json['location'] as String?,
      notes: json['notes'] as String?,
      colorPalette: json['colorPalette'] as String?,
      status: json['status'] as String,
      repertoireMode: RepertoireMode.fromJson(json['repertoireMode']),
      timezone: json['timezone'] as String? ?? 'America/Sao_Paulo',
      assignments: (json['assignments'] as List<dynamic>? ?? const [])
          .map((e) {
            if (e is! Map<String, dynamic>) {
              return null;
            }
            // Lista da agenda ainda devolve array vazio; detalhe traz grupos.
            if (!e.containsKey('positionId')) {
              return null;
            }
            return AssignmentGroup.fromJson(e);
          })
          .whereType<AssignmentGroup>()
          .toList(),
      services: (json['services'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(EventService.fromJson)
          .toList(),
      minister: json['minister'] is Map<String, dynamic>
          ? EventMinister.fromJson(json['minister'] as Map<String, dynamic>)
          : null,
      songs: (json['songs'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(EventSong.fromJson)
          .toList(),
      unavailable: (json['unavailable'] as List<dynamic>? ?? const [])
          .map((e) => UnavailableMember.fromJson(e as Map<String, dynamic>))
          .toList(),
      warnings: EventWarnings.fromJson(
        json['warnings'] as Map<String, dynamic>?,
      ),
      updatedAt: _parseUtcDateTime(json['updatedAt']),
    );
  }

  final String id;
  final String teamId;

  /// Nome do culto especial: "Páscoa", "Ceia", "Batismo".
  ///
  /// Nulo na maioria das escalas, e isso é o normal: o domingo comum já é
  /// identificado pela data e pelos horários. Use [hasTitle] antes de exibir.
  final String? title;
  final DateTime startsAt;
  final DateTime? rehearsalAt;
  final String? location;
  final String? notes;
  /// A combinação de roupa combinada para o dia ("Preto e dourado"). O app a
  /// chama de **paleta de roupas**: "paleta de cores" fazia parecer tema visual
  /// da escala, e o que a equipe precisa saber é como se vestir.
  final String? colorPalette;
  final String status;

  /// Ver [RepertoireMode].
  final RepertoireMode repertoireMode;

  /// O repertório desta escala sai no culto, e não antes.
  bool get isRepertoireOnTheFly => repertoireMode == RepertoireMode.onTheFly;
  final String timezone;
  final List<AssignmentGroup> assignments;

  /// Repertório desta escala, na ordem em que será tocado. Vem preenchido no
  /// detalhe; a listagem da agenda devolve vazio, porque nenhum card mostra
  /// músicas e carregá-las multiplicaria a resposta por evento.
  final List<EventSong> songs;

  /// Horários de culto desta escala, do mais cedo para o mais tarde.
  final List<EventService> services;

  /// Quem conduz a ministração do louvor. Nulo enquanto ninguém foi escolhido.
  final EventMinister? minister;

  /// Versão da escala para a trava de edição simultânea: vai junto na hora de
  /// gravar, e o servidor recusa se a escala mudou desde que esta tela a
  /// abriu. Nulo em resposta antiga guardada em cache — aí a gravação segue
  /// sem trava, como era antes.
  final DateTime? updatedAt;

  bool get hasTitle => title != null && title!.isNotEmpty;

  /// Como se referir a esta escala num texto corrido (diálogos, avisos).
  ///
  /// Sem título, a data por extenso: "a escala de domingo, 9 de agosto" lê
  /// melhor do que um identificador vazio.
  String describe() {
    if (hasTitle) return title!;
    return formatEventWeekdayDate(
      startsAt,
      timezone.isEmpty ? 'America/Sao_Paulo' : timezone,
    );
  }

  /// "Domingo, 4 de outubro · Páscoa" — **sempre com a data**.
  ///
  /// É o topo das telas de montar a escala (escalação e repertório). Com
  /// [describe], a escala com título mostrava só o título, e quem escalava não
  /// via de que domingo se tratava; o repertório não mostrava nem um nem outro.
  String get dateAndTitle {
    final date = formatEventWeekdayDate(
      startsAt,
      timezone.isEmpty ? 'America/Sao_Paulo' : timezone,
    );
    return hasTitle ? '$date · $title' : date;
  }

  /// Os cultos para exibir.
  ///
  /// Cache antigo, gravado antes desta versão, não tem `services`. Em vez de
  /// mostrar a escala sem horário nenhum, cai no `startsAt` — que é justamente
  /// o horário do primeiro culto.
  List<EventService> get displayServices {
    if (services.isNotEmpty) return services;
    return [EventService(id: id, label: 'Culto', startsAt: startsAt)];
  }

  /// O repertório separado por culto, na ordem dos cultos.
  ///
  /// Todo culto entra na lista, inclusive o que ainda não tem música: um
  /// domingo com a manhã montada e a noite vazia precisa **mostrar** a noite
  /// vazia, senão o líder não enxerga o que falta.
  ///
  /// Música cujo culto não existe mais — ou que veio de cache gravado antes
  /// desta versão, sem `serviceId` — cai no primeiro culto, que é onde ela
  /// estava antes de os cultos passarem a ter repertório próprio.
  List<({EventService service, List<EventSong> songs})> get songsByService {
    final cultos = displayServices;
    if (cultos.isEmpty) return const [];

    final porCulto = {for (final culto in cultos) culto.id: <EventSong>[]};
    for (final song in songs) {
      (porCulto[song.serviceId] ?? porCulto[cultos.first.id]!).add(song);
    }

    return [
      for (final culto in cultos) (service: culto, songs: porCulto[culto.id]!),
    ];
  }

  /// Quem avisou que não pode no dia desta escala.
  final List<UnavailableMember> unavailable;
  final EventWarnings warnings;

  bool get isDraft => status == 'DRAFT';

  /// O que ainda impede a publicação.
  ///
  /// Só a equipe: escala sem ninguém escalado não é escala, não há o que
  /// publicar. Repertório em aberto **não** entra aqui -- ele é dito por
  /// [servicesWithoutSongs], que informa sem travar.
  List<String> get publicationBlockers {
    return assignments.isEmpty ? const ['equipe'] : const [];
  }

  /// Os cultos desta escala que ainda não têm repertório.
  ///
  /// Vale em rascunho **e** em escala publicada, e essa é a razão de existir:
  /// a escala vai para a equipe com as músicas em aberto (o culto de quinta
  /// costuma ser assim), e quem está escalado precisa ver que o repertório
  /// ainda não saiu -- em vez de achar que a lista vazia é a lista final.
  ///
  /// Na agenda, `songCount` vem junto de cada culto; no detalhe, a própria
  /// lista de músicas serve de fonte alternativa.
  ///
  /// **Sem saber, cala.** `songCount` nulo é cache gravado antes de o campo
  /// existir, e na agenda `songs` vem sempre vazio de propósito -- ali "não
  /// sei" e "não tem" teriam a mesma cara. Dizer "músicas a definir" em cima
  /// do palpite marcaria como pendente toda escala montada que o app ainda não
  /// recarregou.
  List<String> get servicesWithoutSongs {
    // Repertório definido na hora não tem culto "sem repertório": a lista
    // vazia é o combinado. Esta única linha é o que apaga a cobrança das seis
    // telas que derivam daqui -- agenda, manchete da Home, detalhe, barra de
    // publicação, texto compartilhado e a linha de estado da escala.
    if (isRepertoireOnTheFly) return const [];

    final semRepertorio = <String>[];
    for (final service in displayServices) {
      if (service.songCount == null && songs.isEmpty) continue;

      final count = service.songCount ??
          songs.where((song) {
            final serviceId = song.serviceId.isEmpty
                ? displayServices.first.id
                : song.serviceId;
            return serviceId == service.id;
          }).length;
      if (count == 0) semRepertorio.add(service.label);
    }
    return semRepertorio;
  }

  /// Nenhum culto desta escala tem música **e isso é uma pendência**.
  ///
  /// Separado de [servicesWithoutSongs] porque a frase muda: com um culto
  /// montado e outro não, o que falta tem nome; sem nenhum, nomear os cultos
  /// só repete a escala inteira.
  ///
  /// Falso no repertório definido na hora, por herança de
  /// [servicesWithoutSongs]: ali a lista vazia não falta, e quem pergunta isto
  /// está sempre prestes a dizer que falta.
  bool get hasNoSongs =>
      servicesWithoutSongs.length == displayServices.length;

  /// Nomes das funções em que o membership aparece nesta escala.
  /// Quantas pessoas distintas estao escaladas. Quem acumula duas funcoes
  /// conta uma vez -- o numero responde "a escala esta montada?", nao
  /// "quantas linhas tem a escala".
  int get scheduledMemberCount {
    return <String>{
      for (final group in assignments)
        for (final member in group.members) member.membershipId,
    }.length;
  }

  /// Quem esta escalado, uma vez cada, na ordem das funcoes.
  ///
  /// Serve a pilha de rostos da manchete. **Sem foto**: a listagem da agenda
  /// devolve o nome de quem esta escalado e nada mais, e o campo existe aqui
  /// para o dia em que ela devolver a URL -- ate la a inicial do `AppAvatar`
  /// e o que aparece, que e o caminho que ele ja prevê para foto ausente.
  ///
  /// Quem acumula duas funcoes conta uma vez, pela mesma razao de
  /// [scheduledMemberCount]: a pergunta e "quem esta nesta escala", nao
  /// "quantas linhas ela tem".
  List<({String name, String? imageUrl})> get scheduledPeople {
    final vistos = <String>{};
    final pessoas = <({String name, String? imageUrl})>[];
    for (final group in assignments) {
      for (final member in group.members) {
        if (vistos.add(member.membershipId)) {
          pessoas.add((name: member.displayName, imageUrl: null));
        }
      }
    }
    return pessoas;
  }

  List<String> positionsForMembership(String? membershipId) {
    if (membershipId == null || membershipId.isEmpty) {
      return const [];
    }

    return [
      for (final group in assignments)
        if (group.members.any((m) => m.membershipId == membershipId))
          group.positionName,
    ];
  }

  /// O que esta pessoa faz na escala, **para mostrar**: "Ministra" primeiro, e
  /// depois as funções.
  ///
  /// Quem ministra lia "Vocal · Violão" na Home, no detalhe e na pílula da
  /// agenda — a responsabilidade maior ficava de fora das três. O verbo, e não
  /// "Ministrante", porque a linha é sobre o que a pessoa faz e cabe ao lado
  /// dos instrumentos sem adivinhar gênero.
  ///
  /// Para decidir "é minha?" continua valendo [positionsForMembership]: o
  /// servidor recusa ministrante fora da escalação, então as duas respostas
  /// coincidem, e só uma delas precisa existir como regra.
  List<String> personalRolesFor(String? membershipId) {
    final positions = positionsForMembership(membershipId);
    final ministra = membershipId != null &&
        membershipId.isNotEmpty &&
        minister?.membershipId == membershipId;
    return [if (ministra) 'Ministra', ...positions];
  }

  /// "ministra e está em Vocal e Violão" — o que esta pessoa faz na escala,
  /// dito de outra pessoa. É o que o líder precisa ler para substituir alguém
  /// sem esquecer o ministrante. Nulo quando ela não está na escala.
  String? rolesPhraseFor(String membershipId) {
    final positions = positionsForMembership(membershipId);
    final ministra = minister?.membershipId == membershipId;
    if (positions.isEmpty && !ministra) return null;
    final funcoes = positions.length <= 1
        ? positions.join()
        : '${positions.sublist(0, positions.length - 1).join(', ')} e '
            '${positions.last}';
    if (!ministra) return 'está em $funcoes';
    return positions.isEmpty ? 'ministra' : 'ministra e está em $funcoes';
  }

  static DateTime? _parseUtcDateTime(Object? value) {
    if (value == null) {
      return null;
    }

    return DateTime.parse(value as String).toUtc();
  }
}

/// Texto do destaque "onde eu apareco" no topo da escala.
String? youAssignmentLabel(List<String> positionNames) {
  if (positionNames.isEmpty) {
    return null;
  }

  return 'VOCÊ: ${positionNames.join(', ')}';
}
