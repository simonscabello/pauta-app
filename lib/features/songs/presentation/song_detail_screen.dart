import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_detail_header.dart';
import '../../../shared/widgets/app_facts_strip.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/section_header.dart';
import '../../auth/application/auth_controller.dart';
import '../../suggestions/data/suggestion_repository.dart';
import '../data/song_repository.dart';
import '../domain/song_history.dart';
import '../domain/song_models.dart';
import '../../../shared/widgets/open_link.dart';
import 'song_resources.dart';
import 'song_theme_picker.dart';
import 'lyrics_reader.dart';

class SongDetailScreen extends ConsumerWidget {
  const SongDetailScreen({
    super.key,
    required this.teamId,
    required this.songId,
  });

  final String teamId;
  final String songId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (teamId: teamId, songId: songId);
    final song = ref.watch(songProvider(args));
    // A equipe DESTA música, e não a primeira da lista: quem participa de duas
    // veria o lápis de editar num repertório onde é apenas membro.
    final canManage = ref
            .watch(authControllerProvider)
            .teams
            .where((t) => t.teamId == teamId)
            .firstOrNull
            ?.canManage ??
        false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Música'),
        actions: [
          if (canManage)
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push(
                '/equipe/musicas/$songId/editar',
                extra: song.valueOrNull,
              ),
            ),
          // Só depois que a música carregou: o rótulo do menu depende de ela
          // estar arquivada ou não, e um menu que muda de texto sozinho depois
          // de aberto seria pior que menu nenhum.
          if (canManage && song.valueOrNull != null)
            PopupMenuButton<String>(
              tooltip: 'Mais opções',
              onSelected: (value) => switch (value) {
                'delete' => _delete(context, ref, song.value!),
                _ => _toggleArchived(context, ref, song.value!),
              },
              itemBuilder: (menuContext) => [
                PopupMenuItem(
                  value: 'archive',
                  child: Text(
                    song.value!.isArchived ? 'Restaurar' : 'Arquivar',
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Excluir música',
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
          child: song.when(
            loading: () => const AppLoading(),
            error: (error, _) => AppErrorState(
              message: error is ApiException
                  ? error.message
                  : 'Não foi possível carregar a música.',
              onRetry: () => ref.invalidate(songProvider(args)),
            ),
            data: (value) => _Body(
              song: value,
              teamId: teamId,
              showHistory: canManage,
            ),
          ),
        ),
      ),
    );
  }

  /// Arquivar tira a música do repertório do dia a dia sem apagá-la: é o que
  /// sobra quando excluir não é possível (a música já entrou em escala) e o
  /// que se quer quando ela só saiu de uso. O caminho de volta fica em
  /// Repertório → arquivadas.
  ///
  /// [confirm] falso quando a pergunta já foi feita — pelo diálogo que oferece
  /// arquivar no lugar da exclusão recusada.
  Future<void> _toggleArchived(
    BuildContext context,
    WidgetRef ref,
    Song song, {
    bool confirm = true,
  }) async {
    final restoring = song.isArchived;

    if (!restoring && confirm) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Arquivar ${song.title}?',
        message: 'Ela sai do repertório, mas continua nas escalas em que já '
            'foi tocada. Dá para restaurar depois.',
        confirmLabel: 'Arquivar',
      );
      if (!confirmed || !context.mounted) return;
    }

    try {
      await ref.read(songRepositoryProvider).setArchived(
            teamId,
            songId,
            isArchived: !restoring,
          );
      ref.invalidate(songProvider((teamId: teamId, songId: songId)));
      ref.invalidate(songCatalogProvider);
      ref.invalidate(learningSongsProvider(teamId));
      if (context.mounted) {
        showAppSnackBar(
          context,
          restoring
              ? '${song.title} voltou para o repertório.'
              : '${song.title} foi arquivada.',
          tone: AppTone.success,
        );
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, e.message, tone: AppTone.danger);
      }
    }
  }

  /// Excluir de vez: a música cadastrada por engano, repetida, ou que nunca
  /// chegou a ser cantada.
  ///
  /// A regra 21 continua no servidor: música que já entrou em escala não se
  /// exclui, para as escalas passadas não ficarem com buraco. A tela não tenta
  /// adivinhar isso antes — o histórico que ela tem só conta escala publicada
  /// e passada, e um rascunho também segura a música. Quando o servidor recusa
  /// (`SONG_IN_USE`), a resposta vira a oferta de arquivar, que é o que a
  /// pessoa provavelmente queria: tirar a música da frente.
  Future<void> _delete(BuildContext context, WidgetRef ref, Song song) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Excluir "${song.title}"?',
      message: 'Ela sai do repertório de vez, com letra, links e hinários, e '
          'não dá para desfazer. Para só tirar do dia a dia, arquive.',
      confirmLabel: 'Excluir música',
      cancelLabel: 'Manter',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(songRepositoryProvider).remove(teamId, songId);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      if (e.code == 'SONG_IN_USE') {
        await _offerArchive(context, ref, song);
      } else {
        showAppSnackBar(context, e.message, tone: AppTone.danger);
      }
      return;
    }

    ref.invalidate(songCatalogProvider);
    ref.invalidate(learningSongsProvider(teamId));
    // A análise conta as ativas e as que nunca entraram em escala — esta era
    // uma delas.
    ref.invalidate(repertoireHealthProvider(teamId));
    // Uma sugestão que apontava para esta música perdeu o vínculo (o servidor
    // anula o `songId` e guarda o título): quem voltar para ela precisa ver
    // isso, e não um atalho para uma música que não existe mais.
    ref.invalidate(suggestionsProvider);
    ref.invalidate(suggestionProvider);
    ref.invalidate(openSuggestionCountProvider);
    ref.invalidate(eventSuggestionsProvider);
    if (!context.mounted) return;

    // O `Navigator` desta tela, e não o do go_router: ela também é aberta por
    // cima de telas empilhadas à mão (o detalhe de uma sugestão). Aberta por
    // link direto, sem tela embaixo, volta ao repertório.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      context.go('/equipe/musicas');
    }
    showAppSnackBar(
      context,
      '${song.title} foi excluída.',
      tone: AppTone.success,
    );
  }

  /// A exclusão recusada porque a música já está em escala.
  Future<void> _offerArchive(
    BuildContext context,
    WidgetRef ref,
    Song song,
  ) async {
    // Já arquivada, não há o que oferecer: só dizer por que ela fica.
    if (song.isArchived) {
      showAppSnackBar(
        context,
        '${song.title} já entrou em escala e não pode ser excluída. '
        'Ela continua arquivada.',
        tone: AppTone.warning,
      );
      return;
    }

    final archive = await showConfirmDialog(
      context,
      title: 'Esta música já entrou em escala',
      message: 'Excluir "${song.title}" abriria um buraco nas escalas em que '
          'ela aparece. Arquivar tira a música do repertório e mantém essas '
          'escalas como estão.',
      confirmLabel: 'Arquivar',
      cancelLabel: 'Manter como está',
    );
    if (!archive || !context.mounted) return;

    await _toggleArchived(context, ref, song, confirm: false);
  }
}

/// A tela da música, na ordem em que o músico a usa: **o que é** (nome, tom,
/// tipo, andamento, temas), **como ensaiar** (cifra, letra, YouTube, Spotify),
/// a letra, e por último **quando foi cantada** — que é consulta de quem monta
/// o culto, e não do músico que abriu a música para tirar o tom.
class _Body extends StatelessWidget {
  const _Body({
    required this.song,
    required this.teamId,
    required this.showHistory,
  });

  final Song song;
  final String teamId;

  /// Só para quem lidera: o histórico é relatório, e o servidor o recusa ao
  /// integrante. Pedir e esconder o erro seria uma requisição à toa.
  final bool showHistory;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.lg,
        AppSpacing.screenPadding,
        AppSpacing.xxl,
      ),
      children: [
        _Header(song: song),
        const SizedBox(height: AppSpacing.lg),
        _Facts(song: song),
        // Logo abaixo dos fatos, e não no rodapé: é a resposta de "esta música
        // serve para o culto que estou montando?", que vem antes de abrir a
        // cifra. Sem tema nenhum, some calada — cobrar classificação de 1.210
        // músicas numa tela de leitura seria alarme permanente.
        if (song.themes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          SongThemeChips(themes: song.themes),
        ],
        const SizedBox(height: AppSpacing.xl),
        _Preparation(song: song),
        if (song.hasLyrics) ...[
          // Menos que entre os outros blocos: o cabeçalho da letra tem a altura
          // do botão "Ver completa", e a folga dele já faz parte do respiro.
          const SizedBox(height: AppSpacing.md),
          _LyricsPreview(song: song),
        ],
        if (showHistory) _SongHistorySection(teamId: teamId, songId: song.id),
      ],
    );
  }
}

/// "142 · Pão da Vida": o número antes do nome, como o hinário e o púlpito
/// dizem — "cento e quarenta e dois, Pão da Vida".
String _displayTitle(Song song) =>
    song.hymnal != null ? '${song.hymnal!.number} · ${song.title}' : song.title;

void _openLyrics(BuildContext context, Song song) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => SongLyricsScreen(song: song)),
  );
}

bool _filled(String? value) => value != null && value.trim().isNotEmpty;

class _Header extends StatelessWidget {
  const _Header({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppDetailHeader(
      title: _displayTitle(song),
      badges: [
        if (song.isNew)
          const AppBadge(
            label: 'Nova',
            tone: AppTone.info,
            semanticsLabel: 'A equipe está aprendendo esta música',
          ),
        // Aberta a partir de uma escala antiga, a música arquivada não
        // teria como se explicar: some do repertório e continua ali.
        if (song.isArchived)
          const AppBadge(
            label: 'Arquivada',
            tone: AppTone.warning,
            semanticsLabel: 'Esta música está fora do repertório',
          ),
      ],
      overline: song.subtitle,
      lines: [
        // Os hinários, todos: aqui é a tela da música, e a que está no Cantor
        // Cristão e no HCC precisa mostrar os dois números -- é justamente o
        // que a estrutura anterior não sabia dizer. A escala mostra só a
        // principal, porque lá cabe uma.
        if (song.hymnals.isNotEmpty)
          Text(
            song.hymnals.map((ref) => '${ref.number} ${ref.name}').join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
      ],
    );
  }
}

/// Tom, tipo e andamento, numa faixa só ([AppFactsStrip]) — **só os que
/// existem**.
///
/// O tom da equipe vem na cor da marca quando existe; sem ele, o da gravação
/// entra com o próprio nome ("Tom da gravação"), em cinza — são coisas
/// diferentes. A faixa já mostrou "Tom — · Tipo — · Andamento —": três
/// travessões no lugar mais nobre da tela, dizendo ao integrante o que a
/// equipe ainda não cadastrou. O que falta preencher é cobrado na Análise do
/// repertório, e não aqui.
///
/// Os ícones são medidos contra o vocabulário inteiro, e não contra os valores
/// desta música: senão "Calma" teria ícones e "Moderada" não.
class _Facts extends StatelessWidget {
  const _Facts({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final hasKey = _filled(song.defaultKey);
    final hasRecording = _filled(song.originalKey);
    final hasKind = song.kind == 'HYMN' || song.kind == 'SONG';
    final hasPace = paceLabel(song.pace) != '—';

    final facts = [
      if (hasKey || hasRecording)
        AppFact(
          icon: Icons.piano_rounded,
          label: hasKey ? 'Tom' : 'Tom da gravação',
          value: hasKey ? song.defaultKey!.trim() : song.originalKey!.trim(),
          // Anotação antiga ("G (capo 2)") quebra em duas linhas em vez de
          // encolher até ninguém ler. Tom da lista sempre cabe.
          wrapValue: true,
          highlight: hasKey,
          probeValues: const ['C#m'],
        ),
      if (hasKind)
        AppFact(
          icon: Icons.library_music_outlined,
          label: 'Tipo',
          value: kindLabel(song.kind),
          probeValues: ['HYMN', 'SONG'].map(kindLabel).toList(),
        ),
      if (hasPace || song.bpm != null)
        AppFact(
          icon: Icons.speed_rounded,
          label: 'Andamento',
          value: hasPace ? paceLabel(song.pace) : '${song.bpm} bpm',
          probeValues: ['CALM', 'MODERATE', 'UPBEAT'].map(paceLabel).toList(),
        ),
    ];

    if (facts.isEmpty) return const SizedBox.shrink();
    return AppFactsStrip(facts: facts);
  }
}

/// Cifra, letra, YouTube e Spotify: o que se abre para ensaiar.
///
/// A letra é a única que tem duas fontes: guardada no banco ela abre aqui
/// dentro (sem rede, sem site fora do ar); sem ela, vale o link. Quando há os
/// dois, o link continua a um toque, no topo da tela da letra.
class _Preparation extends StatelessWidget {
  const _Preparation({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // O recuo de 4 é o do `AppGroup` ("Uso nas escalas", mais abaixo):
        // os títulos da tela alinham entre si.
        const SectionHeader(
          title: 'Preparação',
          padding: EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm),
        ),
        SongResourceGrid(
          resources: songResources(
            context,
            chordsUrl: song.chordsUrl,
            lyricsUrl: song.lyricsUrl,
            youtubeUrl: song.youtubeUrl,
            spotifyUrl: song.spotifyUrl,
            onOpenLyrics:
                song.hasLyrics ? () => _openLyrics(context, song) : null,
          ),
        ),
      ],
    );
  }
}

/// A letra, em prévia quando é comprida.
///
/// Inteira, ela empurrava o resto da tela para baixo de três ou quatro telas
/// de rolagem — e a letra não é o que se lê primeiro aqui. O corte é medido
/// com a largura e a fonte de verdade: contar quebras de linha erraria nas
/// estrofes de linha longa que o celular dobra.
///
/// Curta, aparece inteira e selecionável, sem "Ver completa" para abrir o
/// mesmo texto.
class _LyricsPreview extends StatelessWidget {
  const _LyricsPreview({required this.song});

  final Song song;

  static const _previewLines = 6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lyrics = song.lyrics!.trim();
    // Na prévia as estrofes se juntam: a linha em branco entre elas gastaria
    // um terço das seis linhas mostrando nada. A letra inteira mantém.
    final preview = lyrics.replaceAll(RegExp(r'\n\s*\n'), '\n');
    final style = theme.textTheme.bodyMedium?.copyWith(height: 1.6);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: preview, style: style),
          maxLines: _previewLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth - 2 * AppSpacing.lg);
        final long = painter.didExceedMaxLines;
        painter.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Título e link na mesma linha, centrados um no outro. Não é o
            // `SectionHeader`: lá a ação ao lado tem largura fixa, e a 320px com
            // a fonte do sistema aumentada ela empurrava o título para fora. O
            // título é uma palavra curta; o link fica com o resto da linha.
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Semantics(
                    header: true,
                    child: Text('Letra', style: theme.textTheme.titleMedium),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: long
                        ? Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton.icon(
                              onPressed: () => _openLyrics(context, song),
                              iconAlignment: IconAlignment.end,
                              icon: const Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                              ),
                              label: const Text(
                                'Ver completa',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                        // A altura do botão mesmo sem ele: a prévia não pula
                        // de lugar entre uma música e outra.
                        : const SizedBox(height: AppSpacing.touchTarget),
                  ),
                ],
              ),
            ),
            AppCard(
              onTap: long ? () => _openLyrics(context, song) : null,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: long
                  ? Text(
                      preview,
                      maxLines: _previewLines,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    )
                  : SelectableText(lyrics, style: style),
            ),
          ],
        );
      },
    );
  }
}

/// A letra inteira, sem nada em volta.
///
/// É a tela de quem está ensaiando com o celular na estante: título para
/// saber que é a música certa, e o texto em corpo maior. O link do site da
/// letra, quando existe, fica no topo — a letra guardada é a preferida, mas o
/// link continua sendo um recurso da música.
class SongLyricsScreen extends StatelessWidget {
  const SongLyricsScreen({super.key, required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final url = song.lyricsUrl;

    return KeepScreenOn(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Letra'),
          actions: [
            // Modo leitura: tamanho da letra e tela sempre ligada.
            const LyricsFontButtons(),
            if (_filled(url))
              IconButton(
                tooltip: 'Abrir no site',
                icon: const Icon(Icons.open_in_new_rounded),
                onPressed: () => openExternalLink(context, url!),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: AppContentWidth.reading(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.lg,
                AppSpacing.screenPadding,
                AppSpacing.xxl,
              ),
              children: [
                Text(_displayTitle(song), style: theme.textTheme.headlineMedium),
                const SizedBox(height: AppSpacing.xs),
                SmallCapsLine(song.subtitle),
                const SizedBox(height: AppSpacing.lg),
                Divider(height: 1, color: scheme.outlineVariant),
                const SizedBox(height: AppSpacing.lg),
                LyricsText(lyrics: song.lyrics ?? ''),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quando a equipe cantou esta música e em que momentos do culto.
///
/// Os momentos são **lidos das escalas**, e não cadastrados: é o que responde
/// "essa serve para a oferta?" sem ninguém ter precisado dizer isso ao app.
///
/// Fica no fim da tela: é consulta de quem monta o culto. Carregando ou com
/// falha, a seção não aparece — a tela da música é a da cifra e da letra, e o
/// histórico é o complemento.
class _SongHistorySection extends ConsumerWidget {
  const _SongHistorySection({required this.teamId, required this.songId});

  final String teamId;
  final String songId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(songHistoryProvider(teamId)).valueOrNull;
    if (all == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final history = all[songId];
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: AppGroup(
        title: 'Uso nas escalas',
        trailing: Tooltip(
          message: 'Só escalas publicadas que já aconteceram.',
          triggerMode: TooltipTriggerMode.tap,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              Icons.info_outline_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        dividerIndent: AppGroup.textIndent,
        children: history == null
            ? const [
                AppGroupRow(title: 'Ainda não entrou em escala publicada'),
              ]
            : [
                AppGroupRow(
                  title: lastPlayedPhrase(history.lastPlayedAt, now) ??
                      'Ainda não cantada',
                  subtitle: '${timesLabel(history.last6Months)} nos últimos '
                      '6 meses · ${timesLabel(history.playCount)} no total',
                ),
                for (final moment in history.moments.take(4))
                  AppGroupRow(
                    title: moment.displayLabel,
                    trailing: Text(
                      timesLabel(moment.count),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
      ),
    );
  }
}
