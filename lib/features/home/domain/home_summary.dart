import '../../events/domain/event_datetime.dart';
import '../../events/domain/event_models.dart';
import '../../unavailability/domain/unavailability_models.dart';

/// Quantas músicas a escala tem, ou `null` quando o app **não sabe**.
///
/// A listagem da agenda devolve `songs` vazio de propósito (carregar o
/// repertório de cada escala multiplicaria a resposta), e o que ela traz é o
/// `songCount` de cada culto. Cache gravado antes desse campo existir o traz
/// nulo — e ali "não sei" e "não tem" teriam a mesma cara.
///
/// **Sem saber, cala**: é a mesma regra de `Event.servicesWithoutSongs`. Zero é
/// uma resposta ("nenhuma música ainda"); nulo não é.
int? scheduleSongCount(Event event) {
  if (event.songs.isNotEmpty) return event.songs.length;

  var total = 0;
  for (final service in event.displayServices) {
    final count = service.songCount;
    if (count == null) return null;
    total += count;
  }
  return total;
}

/// Quantos dias faltam para a escala, contados em **dias civis** no fuso da
/// equipe.
///
/// Zero é hoje, um é amanhã. Pelo relógio a conta erraria o caso que mais
/// importa: um culto às 09:00 de amanhã está a menos de 24 horas de uma consulta
/// feita hoje às 20:00, e "faltam 0 dias" viraria "é hoje".
int daysUntilEvent(Event event, DateTime now) {
  final timezone =
      event.timezone.isEmpty ? 'America/Sao_Paulo' : event.timezone;
  final scheduleDay = eventLocalTime(event.startsAt, timezone);
  final today = eventLocalTime(now.toUtc(), timezone);
  return DateTime(scheduleDay.year, scheduleDay.month, scheduleDay.day)
      .difference(DateTime(today.year, today.month, today.day))
      .inDays;
}

/// O que um aviso da Home está dizendo.
///
/// O enum carrega o **fato**, não a frase: quem escreve o texto é a tela, que é
/// onde já vivem os formatadores de horário. Aqui fica só a decisão de qual
/// aviso nasce, que é o que vale a pena travar em teste.
enum HomeNoticeKind {
  /// (liderança) alguém escalado avisou que não pode naquele dia.
  ///
  /// **O primeiro da lista**: é o problema mais caro do domingo, e antes ele
  /// só aparecia dentro da escala — na Web, que não recebe push, o líder
  /// descobria no próprio domingo.
  unavailableAssigned,

  /// (liderança) escalas em rascunho, que a equipe ainda não vê.
  pendingDrafts,

  /// (liderança) a próxima escala da equipe ainda não tem ninguém escalado.
  unstaffedSchedule,
}

/// Um aviso curto da Home, logo abaixo da manchete.
///
/// **Nada aqui é dado novo.** Todo aviso sai da mesma lista de escalas que a
/// tela já mostrou acima — é a leitura dela, não uma segunda requisição.
class HomeNotice {
  const HomeNotice({
    required this.kind,
    this.event,
    this.count = 0,
    this.person,
  });

  final HomeNoticeKind kind;

  /// Quem avisou que não pode, no aviso de [HomeNoticeKind.unavailableAssigned].
  final UnavailableMember? person;

  /// A escala de que o aviso fala, quando ele fala de uma.
  final Event? event;

  /// Quantas escalas o aviso conta, quando ele conta.
  final int count;

  /// A rota é uma **aba** da casca, e não uma tela empilhada.
  ///
  /// Muda o gesto de navegação: aba se troca com `go`, e empilhar a agenda
  /// sobre a Home deixaria a barra inferior acesa num lugar com a tela
  /// mostrando outro.
  bool get opensTab => kind == HomeNoticeKind.pendingDrafts;

  /// Para onde o toque leva. Sempre uma rota que já existe.
  String get route => switch (kind) {
        // Direto na escalação, com a pessoa destacada e "Tirar de todas as
        // funções" à mão — o caminho de oito passos virou um.
        HomeNoticeKind.unavailableAssigned =>
          '/agenda/${event!.id}/escalar?substituir=${person!.membershipId}',
        // Já filtrada: o aviso fala dos rascunhos, e a agenda inteira os
        // escondia entre as publicadas.
        HomeNoticeKind.pendingDrafts => '/agenda?filtro=rascunhos',
        HomeNoticeKind.unstaffedSchedule => '/agenda/${event!.id}/escalar',
      };
}

/// A Home, lida a partir da agenda.
///
/// **Uma lista de escalas, quatro respostas.** A Home não busca nada que a
/// agenda já não busque: ela observa o mesmo `eventsProvider((teamId,
/// 'upcoming'))` — mesma chave, mesma resposta, nenhuma requisição a mais — e
/// derreteria em duplicação se cada bloco da tela fizesse a sua própria conta
/// em cima da lista. Aqui a conta é uma só, e é testável sem widget nenhum.
///
/// A diferença que dá razão à tela está em [myNext]: a agenda destaca a próxima
/// escala **da equipe**, e a Home destaca a próxima escala **em que você
/// entra**. Quase sempre são a mesma; quando não são, é justamente aí que a
/// pergunta "quando eu toco?" precisava de resposta.
class HomeSummary {
  const HomeSummary({
    required this.myNext,
    required this.myNextDaysAway,
    required this.myPositions,
    required this.myFollowing,
    required this.notices,
    required this.hasSchedules,
    this.teamWeek = const [],
  });

  /// (liderança) As escalas da equipe nos próximos sete dias, rascunhos
  /// incluídos, na ordem da data — menos a da manchete ([myNext]).
  ///
  /// A Home do líder abria por "Você está livre por enquanto" enquanto havia
  /// cinco rascunhos e uma quinta sem equipe. Para quem lidera, o estado do
  /// ministério na semana é a pergunta de quem abre o app — e cada linha já
  /// diz o que falta (a mesma linha da agenda).
  final List<Event> teamWeek;

  /// A próxima escala em que a pessoa está escalada, dentro do horizonte que a
  /// agenda carregou. Nula quando ela não aparece em nenhuma.
  final Event? myNext;

  /// Quantos dias civis faltam para [myNext]: 0 é hoje, 1 é amanhã. Nulo sem
  /// [myNext].
  ///
  /// **"É hoje" mora na manchete, e não num aviso.** O aviso "Sua escala é
  /// hoje" falava exatamente da escala que a manchete já mostrava — e, com o
  /// limite de dois avisos, tomava a vaga de "Ninguém escalado ainda" de quem
  /// lidera e toca no mesmo domingo.
  final int? myNextDaysAway;

  /// O que ela faz em [myNext] — "Ministra" primeiro, depois as funções (ver
  /// `Event.personalRolesFor`). Vazio quando não há [myNext].
  final List<String> myPositions;

  /// A escala seguinte a [myNext] -- **também sua**.
  ///
  /// Responde "e depois?" no fio que a manchete abriu. A pergunta é "quando eu
  /// toco de novo?", e não "o que a equipe faz depois": a segunda é a agenda
  /// que responde, e responder as duas aqui era ter a agenda em miniatura
  /// dentro da Home -- três linhas repetindo a aba do lado.
  final Event? myFollowing;

  final List<HomeNotice> notices;

  /// A equipe tem alguma escala à frente. Separa "você está livre" de "não há
  /// nada marcado" — duas situações que pedem frases diferentes.
  final bool hasSchedules;

  /// No máximo dois avisos.
  ///
  /// A Home fecha com um bloco discreto, não com uma caixa de entrada: o
  /// terceiro aviso não é lido, e o que ele faz é tirar peso dos dois primeiros.
  static const int maxNotices = 2;

  static HomeSummary of(
    List<Event> events, {
    required String membershipId,
    required bool canManage,
    required DateTime now,
  }) {
    // A lista já vem ordenada do servidor (a mais próxima primeiro) e é essa
    // ordem que faz "a primeira em que eu entro" ser "a próxima em que eu
    // entro". Reordenar aqui só criaria uma segunda verdade.
    final minhas = [
      for (final event in events)
        if (event.positionsForMembership(membershipId).isNotEmpty) event,
    ];
    final myNext = minhas.firstOrNull;

    return HomeSummary(
      myNext: myNext,
      myNextDaysAway: myNext == null ? null : daysUntilEvent(myNext, now),
      myPositions: myNext?.personalRolesFor(membershipId) ?? const [],
      // A segunda em que eu entro, e não a segunda da equipe: a manchete abriu
      // o fio de "quando eu toco", e "e depois?" continua o mesmo fio.
      myFollowing: minhas.length > 1 ? minhas[1] : null,
      hasSchedules: events.isNotEmpty,
      notices: _notices(events, canManage: canManage),
      // Sem a escala da manchete: o mesmo compromisso em dois blocos vizinhos
      // é a regra que a agenda também segue ("duas listas, nunca o mesmo
      // compromisso nas duas").
      teamWeek: canManage
          ? [
              for (final event in events)
                if (event.id != myNext?.id &&
                    daysUntilEvent(event, now) < 7 &&
                    daysUntilEvent(event, now) >= 0)
                  event,
            ]
          : const [],
    );
  }

  static List<HomeNotice> _notices(
    List<Event> events, {
    required bool canManage,
  }) {
    final notices = <HomeNotice>[];

    if (canManage) {
      // O conflito vem antes de tudo. A listagem só traz esse aviso para quem
      // lidera (`warnings.unavailableAssigned`), e a primeira escala com ele é
      // a mais urgente — a lista já vem em ordem de data.
      final conflito = events
          .where((e) => e.warnings.unavailableAssigned.isNotEmpty)
          .firstOrNull;
      if (conflito != null) {
        notices.add(
          HomeNotice(
            kind: HomeNoticeKind.unavailableAssigned,
            event: conflito,
            person: conflito.warnings.unavailableAssigned.first,
            count: conflito.warnings.unavailableAssigned.length,
          ),
        );
      }

      // Rascunho não é visível para a equipe: só quem gerencia recebe a lista
      // com eles, e só para essa pessoa a contagem significa alguma coisa.
      final drafts = events.where((e) => e.isDraft).length;
      if (drafts > 0) {
        notices.add(
          HomeNotice(kind: HomeNoticeKind.pendingDrafts, count: drafts),
        );
      }

      final unstaffed = events.where((e) => e.assignments.isEmpty).firstOrNull;
      if (unstaffed != null) {
        notices.add(
          HomeNotice(
            kind: HomeNoticeKind.unstaffedSchedule,
            event: unstaffed,
          ),
        );
      }
    }

    return notices.take(maxNotices).toList();
  }
}
