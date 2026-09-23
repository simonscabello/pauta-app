import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/date/civil_date.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/responsive/adaptive_dialog.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_notice.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_detail_header.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/app_options_sheet.dart';
import '../../auth/application/auth_controller.dart';
import '../../events/data/event_repository.dart';
import '../../events/domain/event_datetime.dart';
import '../../events/domain/event_models.dart';
import '../../songs/data/song_repository.dart';
import '../../songs/domain/song_models.dart';
import '../../songs/presentation/add_song_screen.dart';
import '../../songs/presentation/song_resources.dart';
import '../../songs/presentation/song_theme_picker.dart';
import '../data/suggestion_repository.dart';
import '../domain/song_suggestion.dart';
import 'suggestions_screen.dart' show suggestionMaterialIcon;

/// Abre o detalhe de uma sugestão.
///
/// `Navigator.push` e não `context.push` do go_router, pelo mesmo motivo do
/// cadastro de música aberto de dentro da escala: a tela de trás — que pode
/// ser a montagem do repertório, com trabalho não salvo — continua viva
/// embaixo e volta intacta.
///
/// `suggestion` é o que a lista já tinha em mãos: a tela desenha na hora com
/// ele e troca pelo que o servidor responder. Sem isso, tocar num cartão daria
/// uma tela em branco a cada vez.
Future<void> openSuggestionDetail(
  BuildContext context, {
  required String teamId,
  required SongSuggestion suggestion,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => SuggestionDetailScreen(
        teamId: teamId,
        suggestionId: suggestion.id,
        initial: suggestion,
      ),
    ),
  );
}

/// Abre, no repertório, a música para a qual a sugestão aponta.
///
/// **Pelo `songId`, nunca pelo título** — o mesmo motivo do "Ver no
/// repertório" da escala (`event_song_sheet.dart`): o repertório pode ter duas
/// versões da mesma canção. E a equipe **da sugestão** vai na consulta: quem
/// serve em duas equipes procuraria a música na equipe ativa (armadilha 10).
///
/// A rota do go_router entra por cima do detalhe da sugestão, que foi empilhado
/// à mão e continua embaixo: voltar da música devolve a sugestão.
void openSuggestedSong(
  GoRouter router, {
  required String teamId,
  required String songId,
}) {
  router.push('/equipe/musicas/$songId?equipe=$teamId');
}

/// A sugestão inteira, e as decisões sobre ela.
///
/// Mesmo formato da tela de uma música do repertório — título grande, artista
/// embaixo, os materiais como chips, e o corpo do texto num cartão — porque é
/// a mesma pergunta que se faz nas duas: "o que é essa música, e vale a pena?"
/// O que muda é o que a página tem a mais: o motivo assinado de quem pediu, e
/// as duas decisões no rodapé.
class SuggestionDetailScreen extends ConsumerStatefulWidget {
  const SuggestionDetailScreen({
    super.key,
    required this.teamId,
    required this.suggestionId,
    this.initial,
  });

  final String teamId;
  final String suggestionId;

  /// O que a lista já sabia, para a tela nascer desenhada.
  final SongSuggestion? initial;

  @override
  ConsumerState<SuggestionDetailScreen> createState() =>
      _SuggestionDetailScreenState();
}

class _SuggestionDetailScreenState
    extends ConsumerState<SuggestionDetailScreen> {
  bool _busy = false;

  /// O que dizer embaixo do indicador, quando a espera é longa o bastante
  /// para merecer explicação.
  String? _busyMessage;

  SuggestionRef get _args => (teamId: widget.teamId, id: widget.suggestionId);

  void _refresh() {
    ref.invalidate(suggestionProvider(_args));
    ref.invalidate(suggestionsProvider);
    ref.invalidate(openSuggestionCountProvider);
    ref.invalidate(eventSuggestionsProvider);
  }

  /// Roda a ação, avisa e volta para a lista.
  ///
  /// Fechar a tela faz parte da decisão: respondida, a sugestão mudou de aba,
  /// e deixar a pessoa olhando para uma tela que já não corresponde à lista de
  /// trás seria pedir que ela mesma descobrisse isso.
  ///
  /// [songToShow], num aceite, devolve a música aceita — lida só depois da
  /// ação, porque no aceite que cadastra ela ainda não existe antes. O aviso
  /// ganha "Ver música": a tela fecha, e o líder que acabou de acolher a
  /// sugestão costuma querer conferir o tom e a cifra em seguida.
  Future<void> _run(
    Future<void> Function() action,
    String ok, {
    bool close = true,
    String? Function()? songToShow,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      _refresh();
      if (!mounted) return;
      // Antes do `pop`: o contexto desta tela não serve para navegar depois
      // que ela sai da pilha.
      final router = GoRouter.maybeOf(context);
      final songId = songToShow?.call();
      if (close) Navigator.of(context).pop();
      showAppSnackBar(
        context,
        ok,
        tone: AppTone.success,
        action: songId == null || router == null
            ? null
            : SnackBarAction(
                label: 'Ver música',
                onPressed: () => openSuggestedSong(
                  router,
                  teamId: widget.teamId,
                  songId: songId,
                ),
              ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        showAppSnackBar(context, error.message, tone: AppTone.danger);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = null;
        });
      }
    }
  }

  /// Aceitar.
  ///
  /// Com a música no repertório, é um toque só. Sem ela, cadastrar **é** a
  /// resposta afirmativa — e o cadastro abre com o que a sugestão já trouxe:
  /// título, artista e os links. Redigitar o que quem sugeriu digitou é o tipo
  /// de trabalho que faz o líder deixar a sugestão para depois.
  ///
  /// Quando quem sugeriu escolheu a música no Spotify, nem a busca abre: a
  /// faixa já foi escolhida uma vez, e o líder só confirma numa folha curta.
  ///
  /// O `isNew` continua sendo decidido à mão — na folha ou na busca, onde já
  /// nasce marcado: ligá-lo aqui seria deduzir "a equipe está aprendendo" de
  /// "alguém sugeriu".
  Future<void> _accept(SongSuggestion s) async {
    final songId = s.songId ?? _songIdCriado;

    if (songId == null && _veioDoSpotify(s)) {
      final escolha = await showAdaptiveSheet<_SpotifyChoice>(
        context: context,
        maxWidth: 480,
        builder: (_) => _AddFromSpotifySheet(suggestion: s),
      );
      if (escolha == null || !mounted) return;
      if (escolha is _SpotifyConfirmed) {
        return _acceptFromSpotify(s, escolha);
      }
      // "Escolher outra versão": o link da sugestão não era o certo, e o
      // caminho é a busca de sempre — sem a pergunta de antes, que já foi
      // respondida nesta folha.
      return _acceptViaSearch(s, outraVersao: true);
    }

    if (songId == null) return _acceptViaSearch(s);

    await _run(
      () => ref
          .read(suggestionRepositoryProvider)
          .accept(widget.teamId, s.id, songId: songId)
          .then((_) {}),
      'Sugestão aceita.',
      songToShow: () => songId,
    );
  }

  /// A sugestão trouxe a faixa do Spotify, com título e artista.
  ///
  /// É o que o cadastro pelo Spotify precisa — o servidor vai ao CifraClub com
  /// título e artista, e guarda o link. Procurar a mesma música de novo só
  /// para tocar no mesmo resultado era trabalho repetido. O artista é
  /// obrigatório lá; sem ele, o caminho é a busca.
  static bool _veioDoSpotify(SongSuggestion s) =>
      (s.spotifyUrl ?? '').trim().isNotEmpty &&
      (s.artist ?? '').trim().length >= 2;

  /// A escala do dia pedido, quando existe e a sugestão já aponta para uma
  /// música do repertório. É o que torna "Adicionar ao culto" possível.
  Event? _escalaDaData(SongSuggestion s) {
    final data = s.targetDate;
    final songId = s.songId ?? _songIdCriado;
    if (data == null || songId == null) return null;
    final escalas =
        ref.watch(eventsProvider((widget.teamId, 'upcoming'))).valueOrNull?.data;
    return escalas?.where((e) {
      final local = eventLocalTime(
        e.startsAt,
        e.timezone.isEmpty ? 'America/Sao_Paulo' : e.timezone,
      );
      return local.year == data.year &&
          local.month == data.month &&
          local.day == data.day;
    }).firstOrNull;
  }

  /// **Aceitar e pôr no culto, de uma vez.**
  ///
  /// "Aceitar sugestão" só registrava o aceite: a música não entrava em escala
  /// nenhuma, e quem sugeriu para o domingo 4/10 lia "aceita" como "vai ser
  /// cantada". Quando o dia pedido já tem escala, a ação principal faz as duas
  /// coisas que o líder quer — e diz isso no botão. Aceitar sem pôr no culto
  /// continua ali, como segunda opção.
  Future<void> _acceptIntoSchedule(SongSuggestion s, Event escala) async {
    final songId = s.songId ?? _songIdCriado;
    if (songId == null) return;

    // A escala inteira, com o repertório: a da lista não traz as músicas, e o
    // PUT substitui a lista — mandar só a nova apagaria as outras.
    final atual = (await ref.read(eventRepositoryProvider).find(escala.id)).data;
    if (!mounted) return;

    final fuso = atual.timezone.isEmpty ? 'America/Sao_Paulo' : atual.timezone;
    final cultos = atual.displayServices;
    var culto = cultos.first;
    if (cultos.length > 1) {
      final escolha = await showAppOptionsSheet<String>(
        context: context,
        title: 'Em qual culto?',
        selected: cultos.first.id,
        options: [
          for (final c in cultos)
            AppOption(
              value: c.id,
              label: '${c.label} ${formatEventTime(c.startsAt, fuso)}',
            ),
        ],
      );
      if (escolha == null || !mounted) return;
      culto = cultos.firstWhere((c) => c.id == escolha.value);
    }

    final jaEsta =
        atual.songs.any((m) => m.songId == songId && m.serviceId == culto.id);

    await _run(
      () async {
        await ref
            .read(suggestionRepositoryProvider)
            .accept(widget.teamId, s.id, songId: songId);
        if (jaEsta) return;
        final musica = await ref
            .read(songRepositoryProvider)
            .find(widget.teamId, songId);
        await ref.read(eventRepositoryProvider).replaceSongs(atual.id, [
          ...atual.songs,
          EventSong(
            songId: musica.id,
            serviceId: culto.id,
            title: musica.title,
            artist: musica.artist,
            key: musica.defaultKey,
            defaultKey: musica.defaultKey,
            hymnals: musica.hymnals,
            chordsUrl: musica.chordsUrl,
            lyricsUrl: musica.lyricsUrl,
            youtubeUrl: musica.youtubeUrl,
            spotifyUrl: musica.spotifyUrl,
          ),
        ]);
        ref.invalidate(eventProvider(atual.id));
        ref.invalidate(eventsProvider((widget.teamId, 'upcoming')));
      },
      jaEsta
          ? 'Sugestão aceita. A música já estava no culto.'
          : 'Sugestão aceita e a música entrou no culto de '
              '${formatEventShortDate(atual.startsAt, fuso)}.',
    );
  }

  /// A música criada por um aceite que falhou no meio.
  ///
  /// Cadastrar e aceitar são duas chamadas. Se a segunda falha, a música já
  /// existe — e tentar de novo não pode cadastrá-la outra vez (o servidor
  /// recusaria como repetida e o líder ficaria preso).
  String? _songIdCriado;

  Future<void> _acceptFromSpotify(
    SongSuggestion s,
    _SpotifyConfirmed escolha,
  ) async {
    final songs = ref.read(songRepositoryProvider);
    final sugestoes = ref.read(suggestionRepositoryProvider);

    // O servidor vai ao CifraClub atrás de cifra, letra e tom: segundos, e
    // não um instante.
    _busyMessage = 'Procurando a cifra, a letra e o tom.';
    await _run(
      () async {
        if (_songIdCriado == null) {
          var song = await songs.createFromExternal(
            widget.teamId,
            ExternalCandidate(
              title: s.title.trim(),
              artist: s.artist!.trim(),
              spotifyUrl: s.spotifyUrl!.trim(),
            ),
            isNew: escolha.isNew,
            themes: escolha.themes,
          );
          song = await applySuggestedLinks(
            songs,
            widget.teamId,
            song,
            lyricsUrl: s.lyricsUrl,
            youtubeUrl: s.youtubeUrl,
          );
          _songIdCriado = song.id;
          ref.invalidate(songCatalogProvider);
          ref.invalidate(learningSongsProvider(widget.teamId));
        }
        await sugestoes.accept(widget.teamId, s.id, songId: _songIdCriado!);
      },
      'Sugestão aceita. "${s.title}" entrou no repertório.',
      songToShow: () => _songIdCriado,
    );
  }

  /// Cadastrar pela busca, que já abre com o que a sugestão trouxe. É o
  /// caminho quando a sugestão não tem o Spotify, ou quando o líder recusou o
  /// link que veio nela.
  ///
  /// [outraVersao]: o líder já disse, na folha do Spotify, que quer cadastrar
  /// e que aquele link não é o certo. Nem a pergunta volta, nem o link
  /// descartado entra na música pela porta dos fundos.
  Future<void> _acceptViaSearch(
    SongSuggestion s, {
    bool outraVersao = false,
  }) async {
    if (!outraVersao) {
      final cadastrar = await showConfirmDialog(
        context,
        title: 'Adicionar ao repertório?',
        message: '"${s.title}" ainda não está no repertório da equipe. '
            'O cadastro já vem com o que a sugestão trouxe.',
        confirmLabel: 'Adicionar ao repertório',
      );
      if (!cadastrar || !mounted) return;
    }

    final criada = await Navigator.of(context).push<Song>(
      MaterialPageRoute(
        builder: (rota) => AddSongScreen(
          teamId: widget.teamId,
          initialSearch: s.title,
          initialArtist: s.artist,
          initialLyricsUrl: s.lyricsUrl,
          initialYoutubeUrl: s.youtubeUrl,
          initialSpotifyUrl: outraVersao ? null : s.spotifyUrl,
          onCreated: (song) => Navigator.of(rota).pop(song),
        ),
      ),
    );
    if (criada == null || !mounted) return;
    ref.invalidate(songCatalogProvider);

    await _run(
      () => ref
          .read(suggestionRepositoryProvider)
          .accept(widget.teamId, s.id, songId: criada.id)
          .then((_) {}),
      'Sugestão aceita.',
      songToShow: () => criada.id,
    );
  }

  /// Recusar. O motivo é opcional e a tela **não** empurra ninguém a escrever:
  /// às vezes o motivo certo (teologia, por exemplo) é uma conversa pessoal, e
  /// o app não é o canal. O rótulo avisa que quem sugeriu vai ler — sem isso,
  /// um líder escreve achando que é nota interna e o app entrega na cara da
  /// pessoa.
  Future<void> _decline(SongSuggestion s) async {
    // Folha, e não diálogo: é um formulário curto, e os formulários curtos do
    // app sobem do rodapé.
    final motivo = await showAdaptiveSheet<String>(
      context: context,
      maxWidth: 480,
      builder: (_) => _DeclineSheet(title: s.title),
    );
    if (motivo == null) return;

    await _run(
      () => ref
          .read(suggestionRepositoryProvider)
          .decline(widget.teamId, s.id, reason: motivo)
          .then((_) {}),
      'Sugestão recusada.',
    );
  }

  Future<void> _reopen(SongSuggestion s) => _run(
        () => ref
            .read(suggestionRepositoryProvider)
            .reopen(widget.teamId, s.id)
            .then((_) {}),
        'Sugestão reaberta.',
        close: false,
      );

  Future<void> _remove(SongSuggestion s) async {
    final confirmou = await showConfirmDialog(
      context,
      title: 'Excluir sugestão?',
      message: '"${s.title}" some da lista para todo mundo.',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!confirmou) return;

    await _run(
      () => ref.read(suggestionRepositoryProvider).remove(widget.teamId, s.id),
      'Sugestão excluída.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final pedida = ref.watch(suggestionProvider(_args));
    // O que o servidor respondeu manda; enquanto ele não responde, vale o que
    // a lista trouxe. Sem o segundo, tocar num cartão daria uma tela vazia.
    final s = pedida.valueOrNull ?? widget.initial;

    final team = ref
        .watch(authControllerProvider)
        .teams
        .where((t) => t.teamId == widget.teamId)
        .firstOrNull;
    final canManage = team?.canManage ?? false;
    final isMine = s?.createdBy.membershipId == team?.membershipId;

    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sugestão')),
        body: pedida.hasError
            ? AppErrorState(
                message: pedida.error is ApiException
                    ? (pedida.error as ApiException).message
                    : 'Não foi possível carregar a sugestão.',
                onRetry: () => ref.invalidate(suggestionProvider(_args)),
              )
            : const AppLoading(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sugestão'),
        actions: [
          // No menu, e não uma lixeira ao lado do título: é uma ação rara e
          // sem volta, e o ícone solto no topo pesava como a ação da tela.
          if (isMine || canManage)
            PopupMenuButton<String>(
              tooltip: 'Mais opções',
              enabled: !_busy,
              onSelected: (_) => _remove(s),
              itemBuilder: (menuContext) => [
                PopupMenuItem(
                  value: 'remove',
                  child: Text(
                    'Excluir sugestão',
                    style: TextStyle(
                      color: Theme.of(menuContext).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: AppContentWidth.reading(
          child: _Body(
            suggestion: s,
            isMine: isMine,
            canManage: canManage,
            busy: _busy,
            busyMessage: _busyMessage,
            onAccept: () => _accept(s),
            scheduleForDate: canManage ? _escalaDaData(s) : null,
            onAcceptIntoSchedule: (escala) => _acceptIntoSchedule(s, escala),
            onDecline: () => _decline(s),
            onReopen: () => _reopen(s),
            onOpenSong: s.songId == null
                ? null
                : () => openSuggestedSong(
                      GoRouter.of(context),
                      teamId: widget.teamId,
                      songId: s.songId!,
                    ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.suggestion,
    required this.isMine,
    required this.canManage,
    required this.busy,
    this.busyMessage,
    required this.onAccept,
    required this.onDecline,
    required this.onReopen,
    this.onOpenSong,
    this.scheduleForDate,
    this.onAcceptIntoSchedule,
  });

  /// A escala do dia pedido, quando dá para pôr a música nela.
  final Event? scheduleForDate;
  final ValueChanged<Event>? onAcceptIntoSchedule;

  final SongSuggestion suggestion;
  final bool isMine;
  final bool canManage;
  final bool busy;
  final String? busyMessage;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onReopen;

  /// Nulo quando a sugestão ainda não aponta para uma música do repertório.
  final VoidCallback? onOpenSong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = suggestion;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        // `Wrap` e não `Row`, como na tela da música: título longo ocupa duas
        // linhas e a etiqueta desce inteira em vez de espremer o nome.
        // O cabeçalho da tela da música: é a mesma pergunta — que música é
        // esta, e onde encontrá-la.
        AppDetailHeader(
          title: s.title,
          badges: [
            if (s.status == SuggestionStatus.accepted)
              const AppBadge(
                label: 'Aceita',
                tone: AppTone.success,
                icon: Icons.check_circle_outline_rounded,
              ),
            if (s.status == SuggestionStatus.declined)
              const AppBadge(label: 'Recusada', tone: AppTone.neutral),
          ],
          overline: s.artist,
          lines: [
            DetailMetaLine(
              icon: s.isForRepertoire
                  ? Icons.library_music_outlined
                  : Icons.event_rounded,
              text: s.isForRepertoire
                  ? 'Para o repertório'
                  : 'Para ${_dataLonga(s.targetDate!)}',
            ),
          ],
        ),
        // A música do repertório a um toque, e não só a frase "já está no
        // repertório": depois de aceita, a pergunta de quem abre a sugestão
        // passa a ser "em que tom ficou, tem cifra?" — e a resposta mora lá.
        // Para todos os papéis, porque o integrante também lê o repertório, e
        // fora das decisões do rodapé, porque não é uma delas.
        if (onOpenSong != null) ...[
          const SizedBox(height: AppSpacing.lg),
          AppGroup(
            children: [
              AppGroupRow(
                icon: Icons.library_music_outlined,
                title: 'Ver no repertório',
                subtitle: s.inRepertoire
                    ? 'Tom, cifra e letra da equipe'
                    : 'Arquivada no repertório',
                onTap: onOpenSong,
              ),
            ],
          ),
        ],
        if (s.materials.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          // Os mesmos ladrilhos de recurso da música, só com o que a sugestão
          // trouxe: link que ninguém mandou não vira ladrilho apagado aqui,
          // porque não há ninguém a quem cobrar.
          SongResourceRow(
            resources: [
              for (final material in s.materials)
                SongResource(
                  icon: suggestionMaterialIcon(material.kind),
                  label: material.label,
                  status: 'Abrir link',
                  onTap: () => openResourceLink(context, material.url),
                ),
            ],
          ),
        ],

        const SizedBox(height: AppSpacing.xl),
        const SectionHeader(
          title: 'Por que essa música',
          padding: EdgeInsets.only(bottom: AppSpacing.sm),
        ),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Inteiro, e sem cortar: é o conteúdo da sugestão, e é o que
              // torna a recusa uma resposta a um argumento em vez de resposta
              // ao gosto de alguém.
              Text(
                s.reason,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  AppAvatar(
                    name: s.createdBy.displayName,
                    imageUrl: s.createdBy.avatarUrl,
                    radius: 12,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _assinatura(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // O motivo da recusa, quando existe. Em branco não vira rótulo
        // pendurado no vazio — campo vazio é uso legítimo, não esquecimento.
        if ((s.declineReason ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(
            title: 'Resposta',
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
          ),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            surface: CardSurface.sunken,
            child: Text(s.declineReason!, style: theme.textTheme.bodyMedium),
          ),
        ],

        const SizedBox(height: AppSpacing.xxl),
        ..._acoes(context),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  /// As decisões, no fim da página e não no topo: elas vêm depois de ler o
  /// motivo, que é a ordem em que a decisão acontece de verdade.
  List<Widget> _acoes(BuildContext context) {
    if (!canManage) return const [];

    if (busy) {
      return [
        const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        if (busyMessage != null)
          Text(
            busyMessage!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
      ];
    }

    if (suggestion.status.isResolved) {
      // Botão de texto: reabrir é a saída para o toque errado, e não a ação
      // principal de uma sugestão já resolvida.
      return [
        Align(
          child: TextButton.icon(
            onPressed: onReopen,
            icon: const Icon(Icons.undo_rounded),
            label: const Text('Reabrir'),
          ),
        ),
      ];
    }

    // Venceu sem resposta: aceitar poria a música num domingo que já foi.
    if (suggestion.isExpiredOn(today())) {
      return const [
        AppNotice(
          icon: Icons.event_busy_rounded,
          message: 'O dia desta sugestão já passou, e ela ficou sem resposta.',
        ),
      ];
    }

    final theme = Theme.of(context);
    final escala = scheduleForDate;
    final ajuda = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    // O que cada botão faz vai escrito embaixo dele: "Aceitar" era lido como
    // "já entrou no culto", e não entrava.
    if (escala != null && onAcceptIntoSchedule != null) {
      final dia = formatEventShortDate(
        escala.startsAt,
        escala.timezone.isEmpty ? 'America/Sao_Paulo' : escala.timezone,
      );
      return [
        FilledButton.icon(
          onPressed: () => onAcceptIntoSchedule!(escala),
          icon: const Icon(Icons.playlist_add_check_rounded),
          label: Text('Adicionar ao culto de $dia'),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'A música entra no repertório desta escala, e quem sugeriu fica '
          'sabendo que foi aceita.',
          textAlign: TextAlign.center,
          style: ajuda,
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton(
          onPressed: onAccept,
          child: const Text('Aceitar sem pôr no culto'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(onPressed: onDecline, child: const Text('Recusar')),
      ];
    }

    return [
      // Empilhados, e não lado a lado: "Aceitar sugestão" não cabe ao lado de
      // "Recusar" num celular estreito, e meio botão cortado num par de
      // decisões opostas é como se toca na errada.
      FilledButton.icon(
        onPressed: onAccept,
        icon: const Icon(Icons.check_rounded),
        label: const Text('Aceitar sugestão'),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        suggestion.songId == null
            ? 'Aceitar começa pelo cadastro da música no repertório. Ela não '
                'entra em nenhuma escala sozinha.'
            : 'Quem sugeriu fica sabendo. A música não entra em nenhuma '
                'escala sozinha.',
        textAlign: TextAlign.center,
        style: ajuda,
      ),
      const SizedBox(height: AppSpacing.sm),
      TextButton(onPressed: onDecline, child: const Text('Recusar')),
    ];
  }

  String _assinatura() {
    final quem = isMine ? 'Você' : suggestion.createdBy.displayName;
    final outros = suggestion.alsoSuggestedBy;
    if (outros.isEmpty) return 'Sugerida por $quem';

    // Repetida é sinal, não erro: dizer quem mais quer a mesma música é metade
    // do que o líder precisa para priorizar. Aqui cabem os nomes.
    final lista = outros.length == 1
        ? outros.first
        : '${outros.take(outros.length - 1).join(', ')} e ${outros.last}';
    final verbo = outros.length == 1 ? 'também sugeriu' : 'também sugeriram';
    return 'Sugerida por $quem · $lista $verbo';
  }
}

/// O que a folha do Spotify respondeu.
sealed class _SpotifyChoice {
  const _SpotifyChoice();
}

/// Cadastrar a faixa que veio na sugestão, com o que o líder marcou.
class _SpotifyConfirmed extends _SpotifyChoice {
  const _SpotifyConfirmed({required this.isNew, required this.themes});

  final bool isNew;
  final Set<String> themes;
}

/// O link não era o certo: procurar outra versão na busca de sempre.
class _SpotifyOtherVersion extends _SpotifyChoice {
  const _SpotifyOtherVersion();
}

/// Aceitar uma sugestão que já veio do Spotify.
///
/// O lugar da confirmação que antes abria a busca: a música aparece como a
/// busca a mostraria, e o que só o líder sabe fica aqui — se a equipe vai
/// aprendê-la e sob que temas. É o mesmo par de controles da tela de
/// adicionar, com o mesmo padrão: "Música nova" nasce ligada.
///
/// "Escolher outra versão" é a saída para o link errado — ao vivo no lugar
/// do estúdio, ou a gravação de outro ministério com o mesmo nome.
class _AddFromSpotifySheet extends StatefulWidget {
  const _AddFromSpotifySheet({required this.suggestion});

  final SongSuggestion suggestion;

  @override
  State<_AddFromSpotifySheet> createState() => _AddFromSpotifySheetState();
}

class _AddFromSpotifySheetState extends State<_AddFromSpotifySheet> {
  bool _isNew = true;
  Set<String> _themes = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = widget.suggestion;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Adicionar ao repertório', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Ao adicionar, buscamos a cifra, a letra e o vídeo.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Icons.headphones_rounded, color: scheme.primary),
                title: Text(s.title),
                subtitle: Text(s.artist!),
                trailing: IconButton(
                  tooltip: 'Ouvir no Spotify',
                  icon: const Icon(Icons.open_in_new_rounded),
                  onPressed: () => openResourceLink(context, s.spotifyUrl!),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              value: _isNew,
              onChanged: (v) => setState(() => _isNew = v),
              contentPadding: EdgeInsets.zero,
              title: const Text('Música nova'),
            ),
            SongThemeStrip(
              themes: _themes,
              onChanged: (themes) => setState(() => _themes = themes),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(
                _SpotifyConfirmed(isNew: _isNew, themes: _themes),
              ),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Adicionar e aceitar'),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(const _SpotifyOtherVersion()),
              child: const Text('Escolher outra versão'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Os materiais, como chips que abrem fora do app.
///
/// **Só o que existe.** Botão apagado para um link que ninguém mandou seria
/// uma promessa falsa, e a seção inteira some quando não há nada — o que só
/// acontece em sugestão antiga, já que hoje o servidor exige a letra ou a
/// cifra de toda música que ainda não está no repertório.
/// Recusar, com o motivo opcional.
///
/// O campo avisa que **quem sugeriu vai ler**: sem isso um líder escreve
/// "letra com teologia duvidosa" achando que é nota interna. E pode ficar em
/// branco — às vezes o motivo certo é uma conversa pessoal.
class _DeclineSheet extends StatefulWidget {
  const _DeclineSheet({required this.title});

  final String title;

  @override
  State<_DeclineSheet> createState() => _DeclineSheetState();
}

class _DeclineSheetState extends State<_DeclineSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Recusar sugestão', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '"${widget.title}" vai para as encerradas.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _controller,
              maxLines: 3,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                helperText: 'Quem sugeriu vai ler. Pode deixar em branco e '
                    'conversar pessoalmente.',
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_controller.text.trim()),
              child: const Text('Recusar'),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Voltar'),
            ),
          ],
        ),
      ),
    );
  }
}

const _meses = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

const _diasDaSemana = [
  'segunda',
  'terça',
  'quarta',
  'quinta',
  'sexta',
  'sábado',
  'domingo',
];

String _dataLonga(DateTime date) {
  final dia = _diasDaSemana[date.weekday - 1];
  return '$dia, ${date.day} de ${_meses[date.month - 1]}';
}
