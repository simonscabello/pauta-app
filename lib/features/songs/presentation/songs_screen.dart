import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_choice_bar.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_pressable.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/app_primary_action.dart';
import '../../auth/application/auth_controller.dart';
import '../../suggestions/presentation/suggest_song_sheet.dart';
import '../data/song_repository.dart';
import '../domain/song_models.dart';
import 'song_resources.dart';
import 'song_theme_picker.dart';

/// Repertório da equipe.
///
/// O filtro "Novas" é o modo de trabalho desta tela: mostra o que a equipe está
/// aprendendo, e é por ele que a marca se gerencia — a lista fica curta e dá
/// para tirar de uma vez as que a igreja já canta junto, em vez de lembrar de
/// música por música.
///
/// Havia também um filtro "faltando dados", por tom da equipe, hino/cântico e
/// andamento. Saiu a pedido: essas três decisões continuam existindo na edição,
/// mas cobrá-las numa aba não era o jeito desta equipe trabalhar.
class SongsScreen extends ConsumerStatefulWidget {
  const SongsScreen({
    super.key,
    required this.teamId,
    this.archived = false,
    this.initialFilter,
  });

  final String teamId;

  /// O arquivo reaproveita esta tela inteira — busca, linhas, estados vazios.
  /// O que muda é o acervo consultado e o que não faz sentido lá: escolher
  /// entre cânticos e hinos, e adicionar música.
  final bool archived;

  /// A aba em que a tela abre. Nulo é "Cânticos", como sempre foi; o cartão
  /// "Estamos aprendendo" da Home pede "Novas".
  final SongFilter? initialFilter;

  @override
  ConsumerState<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends ConsumerState<SongsScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  String _search = '';
  late SongFilter _filter = widget.archived
      ? SongFilter.arquivadas
      : (widget.initialFilter ?? SongFilter.canticos);
  Set<String> _themes = {};

  @override
  void didUpdateWidget(covariant SongsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Um link com outra aba (`?aba=novas`) pode chegar a esta tela já montada:
    // no navegador, trocar o endereço reaproveita a página de `/equipe/musicas`
    // que estava embaixo de "saude" ou de uma música. Sem isto, o link abria
    // na aba em que a tela nasceu.
    final pedida = widget.initialFilter;
    if (!widget.archived &&
        pedida != null &&
        pedida != oldWidget.initialFilter) {
      _filter = pedida;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Sem espera, cada letra digitada viraria uma consulta.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _search = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = SongQuery(
      teamId: widget.teamId,
      search: _search,
      filter: _filter,
      themes: _themes,
    );
    final songs = ref.watch(songsProvider(query));
    // Com busca, cada aba diz quantas músicas tem ("Hinos (3)"): o hino
    // procurado em Cânticos parecia não existir.
    final counts = _search.trim().isEmpty
        ? null
        : ref.watch(songTabCountsProvider(query));
    final canManage = ref
            .watch(authControllerProvider)
            .teams
            .where((t) => t.teamId == widget.teamId)
            .firstOrNull
            ?.canManage ??
        false;

    // Um botão por papel (ver o comentário do `floatingActionButton`), no
    // lugar do formato: flutuante no celular, cabeçalho com a barra lateral.
    final principal = widget.archived
        ? null
        : canManage
            ? AppPrimaryAction(
                label: 'Adicionar',
                icon: Icons.add_rounded,
                onPressed: () => context.push('/equipe/musicas/nova'),
              )
            : AppPrimaryAction(
                label: 'Sugerir',
                icon: Icons.lightbulb_outline_rounded,
                onPressed: () =>
                    showSuggestSongSheet(context, teamId: widget.teamId),
              );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.archived ? 'Arquivadas' : 'Repertório'),
        actions: [
          if (principal?.headerAction(context) case final acao?) acao,
          // Sugerir é da equipe inteira, e esta é a tela onde se pensa em
          // música. Para quem lidera fica no cabeçalho, porque o botão
          // flutuante já é "Adicionar" -- a ação principal dele.
          if (canManage && !widget.archived)
            // Com rótulo: a lâmpada sozinha não dizia "sugerir" a ninguém
            // (WCAG 2.5.3), e é uma ação rara, que ninguém decora.
            TextButton.icon(
              onPressed: () =>
                  showSuggestSongSheet(context, teamId: widget.teamId),
              icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
              label: const Text('Sugerir'),
            ),
          // O arquivo e os relatórios são do repertório, e de quem lidera.
          // Eram um ícone mudo (a caixa do arquivo) e duas telas que só se
          // achavam em Gerenciar equipe; agora ficam juntos, com nome.
          if (canManage && !widget.archived)
            PopupMenuButton<String>(
              tooltip: 'Mais opções do repertório',
              onSelected: (route) => context.push(route),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: '/equipe/musicas/arquivadas',
                  child: Text('Músicas arquivadas'),
                ),
                PopupMenuItem(
                  value: '/equipe/musicas/uso',
                  child: Text('Uso do repertório'),
                ),
                PopupMenuItem(
                  value: '/equipe/musicas/saude',
                  child: Text('Análise do repertório'),
                ),
              ],
            ),
        ],
      ),
      // Um botão por papel, e não dois na mesma tela: para quem lidera a ação
      // principal do repertório é cadastrar; para quem canta é sugerir -- e o
      // integrante não tinha ação nenhuma aqui.
      floatingActionButton: principal?.fab(context),
      body: SafeArea(
        top: false,
        child: AppContentWidth.wide(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.md,
                  AppSpacing.screenPadding,
                  AppSpacing.md,
                ),
                // `ListenableBuilder` no controlador: o botão de limpar era
                // desenhado a partir de `_searchController.text`, que só era
                // relido quando o `setState` do debounce disparava. Resultado:
                // o X aparecia 350ms depois da primeira letra, e por um
                // instante depois de limpar o campo ele continuava lá.
                child: ListenableBuilder(
                  listenable: _searchController,
                  builder: (context, _) => TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Buscar por título, artista ou compositor',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpar busca',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            ),
                    ),
                  ),
                ),
              ),
              // **Abas e temas numa linha só.** Eram três faixas de controle —
              // busca, abas e a faixa de temas — antes da primeira música. O
              // filtro de temas virou um botão com a contagem ao lado das abas,
              // e a faixa só aparece quando há tema escolhido, para dizer qual
              // e deixar tirar.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  0,
                  AppSpacing.screenPadding - AppSpacing.sm,
                  0,
                ),
                child: Row(
                  children: [
                    if (!widget.archived)
                      Flexible(
                        child: AppChoiceBar<SongFilter>(
                          value: _filter,
                          onChanged: (value) =>
                              setState(() => _filter = value),
                          options: [
                            AppChoice(
                              value: SongFilter.canticos,
                              label: songTabLabel(
                                'Cânticos',
                                counts?[SongFilter.canticos],
                              ),
                            ),
                            AppChoice(
                              value: SongFilter.hinos,
                              label: songTabLabel(
                                'Hinos',
                                counts?[SongFilter.hinos],
                              ),
                            ),
                            AppChoice(
                              value: SongFilter.novas,
                              label: songTabLabel(
                                'Novas',
                                counts?[SongFilter.novas],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const Spacer(),
                    const SizedBox(width: AppSpacing.sm),
                    SongThemeFilterButton(
                      selected: _themes,
                      onChanged: (themes) => setState(() => _themes = themes),
                    ),
                  ],
                ),
              ),
              if (_themes.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                SongThemeFilterBar(
                  selected: _themes,
                  showTrigger: false,
                  onChanged: (themes) => setState(() => _themes = themes),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: songs.when(
                  loading: () => const AppListSkeleton(
                    itemCount: 6,
                    leadingBlock: true,
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.screenPadding,
                      0,
                      AppSpacing.screenPadding,
                      AppSpacing.fabClearance,
                    ),
                  ),
                  error: (error, _) => AppErrorState(
                    message: error is ApiException
                        ? error.message
                        : 'Não foi possível carregar o repertório.',
                    onRetry: () => ref.invalidate(songCatalogProvider),
                  ),
                  data: (list) => _SongList(
                    songs: list,
                    teamId: widget.teamId,
                    query: query,
                    filter: _filter,
                    hasSearch: _search.trim().isNotEmpty,
                    themes: _themes,
                    onClearThemes: () => setState(() => _themes = {}),
                    canManage: canManage,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SongList extends ConsumerWidget {
  const _SongList({
    required this.songs,
    required this.teamId,
    required this.query,
    required this.filter,
    required this.hasSearch,
    required this.themes,
    required this.onClearThemes,
    required this.canManage,
  });

  final List<Song> songs;
  final String teamId;
  final SongQuery query;
  final SongFilter filter;
  final bool hasSearch;
  final Set<String> themes;
  final VoidCallback onClearThemes;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (songs.isEmpty) {
      // Com tema marcado, é ELE que explica a lista vazia e é ele que se
      // desfaz — dizer "nenhum cântico" a quem filtrou por "Ceia" descreveria
      // o acervo inteiro e esconderia o que de fato tirou as linhas da tela.
      if (themes.isNotEmpty) {
        return RefreshableMessage(
          onRefresh: () => refreshSongs(ref, query),
          child: AppEmptyState(
            icon: Icons.sell_outlined,
            title: 'Nada com esses temas',
            message: hasSearch
                ? 'Nenhuma música com esses temas e esse nome. Tire um dos '
                    'dois para alargar a busca.'
                : switch (filter) {
                    SongFilter.canticos =>
                      'Nenhum cântico classificado assim. Se for hino, toque '
                          'em Hinos.',
                    SongFilter.hinos =>
                      'Nenhum hino classificado assim. Se for cântico, toque '
                          'em Cânticos.',
                    SongFilter.novas =>
                      'Nenhuma música em aprendizado com esses temas.',
                    SongFilter.arquivadas =>
                      'Nenhuma música arquivada com esses temas.',
                  },
            actionLabel: 'Limpar temas',
            onAction: onClearThemes,
          ),
        );
      }

      // A ação só existe quando ela é possível: antes o callback era passado
      // sempre, e só o rótulo era condicional -- um integrante sem permissão
      // via a tela sem saída, e a ação ficava presa a um botão invisível.
      final canAdd = !hasSearch && filter == SongFilter.canticos && canManage;


      return RefreshableMessage(
        onRefresh: () => refreshSongs(ref, query),
        child: AppEmptyState(
          icon: hasSearch
              ? Icons.search_off_rounded
              : Icons.library_music_outlined,
          tone: filter == SongFilter.novas && !hasSearch
              ? AppTone.success
              : AppTone.primary,
          title: hasSearch
              ? 'Nada encontrado'
              : switch (filter) {
                  // Lista vazia aqui é boa notícia, e não um buraco: quer
                  // dizer que a equipe já domina tudo o que canta.
                  SongFilter.novas => 'Nada em aprendizado',
                  SongFilter.hinos => 'Nenhum hino',
                  SongFilter.canticos => 'Nenhum cântico',
                  SongFilter.arquivadas => 'O arquivo está vazio',
                },
          // Com a busca preenchida, a mensagem diz em qual acervo se procurou.
          // Sem isso, quem digita "142" em Cânticos vê "Nada encontrado" e
          // conclui que o hino não existe -- quando ele está na aba do lado.
          message: hasSearch
              ? switch (filter) {
                  SongFilter.canticos =>
                    'Procuramos só nos cânticos. Se for hino, toque em Hinos.',
                  SongFilter.hinos =>
                    'Procuramos só nos hinos. Se for cântico, toque em Cânticos.',
                  SongFilter.novas =>
                    'Nenhuma música em aprendizado com esse nome.',
                  SongFilter.arquivadas =>
                    'Nenhuma música arquivada com esse nome.',
                }
              : switch (filter) {
                  SongFilter.novas =>
                    'Marque uma música como nova ao adicioná-la, ou na edição.',
                  SongFilter.hinos =>
                    'O Cantor Cristão ainda não foi importado nesta equipe.',
                  SongFilter.canticos => canManage
                      ? 'Adicione as músicas que a equipe canta.'
                      : 'Quando o líder cadastrar as músicas, elas aparecem '
                          'aqui com letra, cifra e tom.',
                  SongFilter.arquivadas =>
                    'Nada foi tirado do repertório até agora. Arquivar é o '
                        'caminho para uma música que a equipe não canta mais, '
                        'sem apagar as escalas em que ela foi tocada.',
                },
          actionLabel: canAdd ? 'Adicionar música' : null,
          onAction:
              canAdd ? () => context.push('/equipe/musicas/nova') : null,
        ),
      );
    }

    // Linhas com fio na página, e **não** um grupo de superfície única como no
    // Perfil ou em Gerenciar equipe. A regra que separa os dois casos:
    //
    //   grupo fechado  → conjunto finito e curto, que se lê inteiro
    //   linhas na página → lista longa, que se percorre e se filtra
    //
    // O repertório desta igreja tem 286 músicas. Envolvê-las numa moldura só
    // seria uma moldura de dois metros de altura — e, pior, exigiria construir
    // as 286 linhas de uma vez, porque uma `Column` dentro de moldura não é
    // preguiçosa. Aqui o `ListView.separated` continua construindo só o que
    // aparece.
    return RefreshIndicator(
      onRefresh: () => refreshSongs(ref, query),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.fabClearance),
        itemCount: songs.length,
        separatorBuilder: (context, __) => Divider(
          height: 1,
          thickness: 1,
          indent: AppSpacing.screenPadding,
          endIndent: AppSpacing.screenPadding,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        itemBuilder: (_, index) => _SongRow(
          song: songs[index],
          teamId: teamId,
          filter: filter,
          canManage: canManage,
        ),
      ),
    );
  }
}

/// Uma música na lista do repertório.
///
/// **O tom é uma etiqueta à direita**, como em toda lista de música do app —
/// a escala, a montagem do repertório, o seletor. Era um bloco de 46px à
/// esquerda, que no hino virava o número: dois desenhos para a mesma coluna, e
/// um terceiro desenho de tom só nesta tela.
///
/// No hino o número abre o título ("314 · Estou Seguro"), como na tela da
/// música e como o púlpito anuncia; a sigla do hinário vai para a linha de
/// apoio. O tipo da música só aparece quando não é o da aba: "Cântico" na aba
/// Cânticos repetia o filtro em cada linha.
class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.song,
    required this.teamId,
    required this.filter,
    this.canManage = false,
  });

  final Song song;
  final String teamId;
  final SongFilter filter;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hymnal = song.isHymn ? song.hymnal : null;
    final kindIsTab = (filter == SongFilter.canticos && song.kind == 'SONG') ||
        (filter == SongFilter.hinos && song.kind == 'HYMN');

    final author = [song.artist, song.composer]
        .where((part) => part != null && part.trim().isNotEmpty)
        .firstOrNull;
    final details = [
      if (hymnal != null) hymnal.abbreviation,
      if (author != null) author,
      if (hymnal == null && song.kind != null && !kindIsTab)
        kindLabel(song.kind),
      if (song.pace != null) paceLabel(song.pace),
    ].where((part) => part.trim().isNotEmpty).join(' · ');

    return AppPressable(
      onTap: () => context.push('/equipe/musicas/${song.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          hymnal != null
                              ? '${hymnal.number} · ${song.title}'
                              : song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      // Também fora do filtro "Novas": percorrendo o repertório
                      // inteiro é assim que se lembra do que ainda está sendo
                      // aprendido.
                      if (song.isNew) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const AppBadge(label: 'Nova', tone: AppTone.info),
                      ],
                    ],
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _LinkDots(song: song),
            _KeyBadge(song: song, canManage: canManage),
          ],
        ),
      ),
    );
  }
}

/// Tom da equipe, à direita, em violeta. Sem ele, o tom da gravação em cinza.
///
/// **Já foi âmbar com lápis em toda música sem tom**, e o acervo inteiro
/// ficou âmbar: "Sem tom definido" em 1.207 de 1.208 músicas. A cor de
/// atenção deixou de significar alguma coisa, e o lápis sugeria ao integrante
/// uma edição que ele não pode fazer. A cobrança do que falta preencher mora
/// em Relatórios › Análise ("Sem tom definido"); aqui fica só a informação.
///
/// Quem lidera ainda vê um lápis pequeno no tom da gravação — "este não é o
/// de vocês, dá para decidir" —, em cinza, sem o peso de um alerta. **A cor não
/// é o único sinal** (WCAG 1.4.1): violeta × cinza vem com o `Semantics`
/// dizendo a frase inteira.
///
/// No hino sem tom não aparece nada: o número é o que o identifica.
class _KeyBadge extends StatelessWidget {
  const _KeyBadge({required this.song, this.canManage = false});

  final Song song;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final own = song.defaultKey;
    final recording = song.originalKey;

    if (own != null) {
      return Padding(
        padding: const EdgeInsets.only(left: AppSpacing.sm),
        child: AppBadge(
          label: own,
          tone: AppTone.primary,
          semanticsLabel: 'Tom da equipe: $own',
        ),
      );
    }
    if (song.isHymn) return const SizedBox.shrink();
    // Sem o de vocês e sem o da gravação, não há o que mostrar ao integrante;
    // a quem lidera, a lacuna aparece na Análise.
    if (recording == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: AppBadge(
        label: recording,
        icon: canManage ? Icons.edit_outlined : null,
        tone: AppTone.neutral,
        semanticsLabel: 'Tom da gravação: $recording. Sem tom da equipe.',
      ),
    );
  }
}

/// Quais links a música tem, sem ocupar uma linha de texto.
class _LinkDots extends StatelessWidget {
  const _LinkDots({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final links = <(IconData, String)>[
      if (song.chordsUrl != null) (SongResourceIcons.chords, 'cifra'),
      if (song.lyricsUrl != null) (SongResourceIcons.lyrics, 'letra'),
      if (song.youtubeUrl != null) (SongResourceIcons.youtube, 'vídeo'),
      if (song.spotifyUrl != null) (SongResourceIcons.spotify, 'áudio'),
    ];

    if (links.isEmpty) return const SizedBox.shrink();

    return Semantics(
      label: 'Tem ${links.map((l) => l.$2).join(', ')}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final link in links)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Icon(link.$1, size: 16, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
