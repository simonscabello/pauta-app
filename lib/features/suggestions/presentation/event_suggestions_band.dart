import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_button_styles.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../events/domain/event_models.dart';
import '../../songs/data/song_repository.dart';
import '../../songs/domain/song_models.dart';
import '../../songs/presentation/add_song_screen.dart';
import '../data/suggestion_repository.dart';
import '../domain/song_suggestion.dart';

/// A faixa de sugestões da equipe, no topo da montagem do repertório.
///
/// **É a razão de a funcionalidade existir.** As outras telas alimentam esta:
/// o líder monta o repertório vendo o que a equipe pediu para aquele domingo,
/// em vez de tentar lembrar do que passou no grupo do WhatsApp.
///
/// Recolhida quando a escala já tem música, aberta quando está vazia: na escala
/// em branco a sugestão é a melhor porta de entrada; na já montada ela não pode
/// empurrar o repertório para baixo da dobra. Some inteira quando não há
/// sugestão — estado vazio no topo da tela mais importante do fluxo é ruído.
class EventSuggestionsBand extends ConsumerStatefulWidget {
  const EventSuggestionsBand({
    super.key,
    required this.teamId,
    required this.eventId,
    required this.services,
    required this.servicesWithSong,
    required this.setlistIsEmpty,
    required this.onAddToService,
  });

  final String teamId;
  final String eventId;
  final List<EventService> services;

  /// Em quais cultos desta escala a música já está.
  ///
  /// Vem da tela, e não de uma consulta: o que vale é o que está montado agora,
  /// inclusive o que ainda não foi salvo.
  final Set<String> Function(String songId) servicesWithSong;

  final bool setlistIsEmpty;

  final Future<void> Function(String songId, EventService service)
      onAddToService;

  @override
  ConsumerState<EventSuggestionsBand> createState() =>
      _EventSuggestionsBandState();
}

class _EventSuggestionsBandState extends ConsumerState<EventSuggestionsBand> {
  /// Nulo = ainda não mexeram; vale o padrão que depende da escala estar vazia.
  bool? _expanded;
  String? _busyId;

  void _invalidate() {
    ref.invalidate(eventSuggestionsProvider(widget.eventId));
    ref.invalidate(suggestionsProvider);
    ref.invalidate(openSuggestionCountProvider);
  }

  /// Aceitar: o líder diz que a ideia foi aceita.
  ///
  /// Botão à parte de "Adicionar ao culto", de propósito — são duas decisões
  /// diferentes, e a escala ainda pode ser rascunho que ninguém viu.
  Future<void> _accept(SongSuggestion s, {String? songId}) async {
    setState(() => _busyId = s.id);
    try {
      await ref
          .read(suggestionRepositoryProvider)
          .accept(widget.teamId, s.id, songId: songId ?? s.songId);
      _invalidate();
      if (mounted) {
        showAppSnackBar(context, 'Sugestão aceita.', tone: AppTone.success);
      }
    } on ApiException catch (error) {
      if (mounted) {
        showAppSnackBar(context, error.message, tone: AppTone.danger);
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Cadastra a música sugerida e, aí sim, acolhe junto.
  ///
  /// Aqui acolher junto é correto: cadastrar uma música por causa da sugestão
  /// **é** a resposta afirmativa, e ela já custou uma tela inteira ao líder. O
  /// `isNew` continua sendo decidido lá, no cadastro, onde já nasce marcado.
  Future<void> _register(SongSuggestion s) async {
    final created = await Navigator.of(context).push<Song>(
      MaterialPageRoute(
        builder: (rota) => AddSongScreen(
          teamId: widget.teamId,
          initialSearch: s.title,
          // O mesmo reaproveitamento da tela de detalhes: quem sugeriu já
          // mandou artista e links, e redigitá-los é o trabalho repetido que
          // faz a sugestão ficar para depois.
          initialArtist: s.artist,
          initialLyricsUrl: s.lyricsUrl,
          initialYoutubeUrl: s.youtubeUrl,
          initialSpotifyUrl: s.spotifyUrl,
          onCreated: (song) => Navigator.of(rota).pop(song),
        ),
      ),
    );
    if (created == null || !mounted) return;

    ref.invalidate(songCatalogProvider);
    await _accept(s, songId: created.id);
    if (mounted) await _pickServiceAndAdd(created.id);
  }

  /// Com um culto só, entra direto. Com dois, pergunta em qual — e oferece só
  /// os cultos em que a música ainda não está: repetir no mesmo culto o
  /// servidor recusa com `DUPLICATE_SONG`.
  Future<void> _pickServiceAndAdd(String songId) async {
    final taken = widget.servicesWithSong(songId);
    final free = widget.services.where((c) => !taken.contains(c.id)).toList();

    if (free.isEmpty) return;
    if (free.length == 1) {
      await widget.onAddToService(songId, free.first);
      return;
    }

    final chosen = await showModalBottomSheet<EventService>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'Em qual culto?',
                style: Theme.of(sheet).textTheme.titleSmall,
              ),
            ),
            for (final service in free)
              ListTile(
                leading: const Icon(Icons.church_outlined),
                title: Text(service.label),
                onTap: () => Navigator.of(sheet).pop(service),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) await widget.onAddToService(songId, chosen);
  }

  /// O cabeçalho fala do que é urgente. Só com as sem data, ele muda de
  /// assunto em vez de anunciar "0 sugestões para este domingo".
  String _titulo(int doDia, int semData) {
    if (doDia == 0) {
      return semData == 1
          ? '1 sugestão da equipe para o repertório'
          : '$semData sugestões da equipe para o repertório';
    }
    return doDia == 1
        ? '1 sugestão da equipe para este domingo'
        : '$doDia sugestões da equipe para este domingo';
  }

  Widget _linha(SongSuggestion s) => _SuggestionRow(
        suggestion: s,
        busy: _busyId == s.id,
        // "Já está na escala" só quando não sobra culto onde pôr.
        alreadyInSetlist: s.songId != null &&
            widget.services.every(
              (c) => widget.servicesWithSong(s.songId!).contains(c.id),
            ),
        onAdd: () => _pickServiceAndAdd(s.songId!),
        onRegister: () => _register(s),
        onAccept: () => _accept(s),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestions = ref.watch(eventSuggestionsProvider(widget.eventId));

    // Falha ou carregamento não desenham nada: a montagem do repertório
    // funciona sem a faixa, e um erro aqui não pode virar banner vermelho no
    // topo da tela.
    final data = suggestions.valueOrNull;
    final list = data?.forDate ?? const <SongSuggestion>[];

    // As sem data entram na mesma faixa, num grupo próprio: "vamos aprender
    // essa algum dia" é decisão que também se toma montando um domingo, e é
    // aqui que o líder está. Só as que já têm cadastro -- as outras não teriam
    // o que pôr no culto e vivem na tela de Sugestões.
    final undated = (data?.undated ?? const <SongSuggestion>[])
        .where((s) => s.canGoToSetlist)
        .toList();

    if (list.isEmpty && undated.isEmpty) return const SizedBox.shrink();

    final expanded = _expanded ?? widget.setlistIsEmpty;

    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      // `AppCard` não tem padding padrão: sem isto o conteúdo encosta na borda
      // e o `Clip.antiAlias` do canto arredondado come a primeira letra.
      padding: const EdgeInsets.all(AppSpacing.lg),
      surface: CardSurface.sunken,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !expanded),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline_rounded, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _titulo(list.length, undated.length),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
          if (expanded) ...[
            for (final s in list) ...[
              const Divider(height: AppSpacing.lg),
              _linha(s),
            ],
            if (undated.isNotEmpty) ...[
              const Divider(height: AppSpacing.lg),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'Para o repertório',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final s in undated) _linha(s),
            ],
          ],
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.busy,
    required this.alreadyInSetlist,
    required this.onAdd,
    required this.onRegister,
    required this.onAccept,
  });

  final SongSuggestion suggestion;
  final bool busy;
  final bool alreadyInSetlist;
  final VoidCallback onAdd;
  final VoidCallback onRegister;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = suggestion;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.title, style: theme.textTheme.titleSmall),
        if ((s.artist ?? '').isNotEmpty)
          Text(
            s.artist!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        // A justificativa aparece aqui, e não só na tela de sugestões: é o que
        // o líder lê para decidir, e ele está decidindo agora. Em duas linhas:
        // inteira, cada sugestão ocupava meio celular no topo da montagem.
        Text(
          s.reason,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          s.alsoSuggestedBy.isEmpty
              ? s.createdBy.displayName
              : '${s.createdBy.displayName} · e mais ${s.alsoSuggestedBy.length}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Botões do tamanho de uma ação de linha: o tonal herdava os
              // 52px do botão que salva um formulário.
              // "Aceitar" ao lado de "Cadastrar" não dizia o que cada um faz:
              // um responde a quem sugeriu, o outro põe a música no acervo.
              TextButton(
                style: AppButtonStyles.compactText,
                onPressed: onAccept,
                child: const Text('Marcar como aceita'),
              ),
              if (!s.canGoToSetlist)
                FilledButton.tonalIcon(
                  style: AppButtonStyles.compact,
                  onPressed: onRegister,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Cadastrar no repertório'),
                )
              else if (alreadyInSetlist)
                Text(
                  'Já está na escala',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                FilledButton.tonalIcon(
                  style: AppButtonStyles.compact,
                  onPressed: onAdd,
                  icon: const Icon(Icons.playlist_add_rounded, size: 18),
                  label: const Text('Adicionar ao culto'),
                ),
            ],
          ),
      ],
    );
  }
}
