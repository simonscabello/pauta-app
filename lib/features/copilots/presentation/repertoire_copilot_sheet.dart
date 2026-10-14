import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/responsive/adaptive_dialog.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_button_styles.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_choice_bar.dart';
import '../../../shared/widgets/app_notice.dart';
import '../../../shared/widgets/section_header.dart';
import '../../events/domain/event_models.dart';
import '../../events/domain/service_moments.dart';
import '../data/copilot_repository.dart';
import '../domain/copilot_models.dart';

/// Abre o Copiloto de Repertório para um culto e devolve as músicas que o
/// líder decidiu usar (nulo se fechou sem usar). **Nada é salvo aqui**: quem
/// chama põe as músicas no culto, e o "Salvar músicas" de sempre grava.
Future<List<SuggestedSong>?> showRepertoireCopilot(
  BuildContext context, {
  required String eventId,
  required EventService service,
}) {
  return showAdaptiveSheet<List<SuggestedSong>>(
    context: context,
    maxWidth: 560,
    builder: (_) => _RepertoireCopilotSheet(eventId: eventId, service: service),
  );
}

class _RepertoireCopilotSheet extends ConsumerStatefulWidget {
  const _RepertoireCopilotSheet({required this.eventId, required this.service});

  final String eventId;
  final EventService service;

  @override
  ConsumerState<_RepertoireCopilotSheet> createState() =>
      _RepertoireCopilotSheetState();
}

class _RepertoireCopilotSheetState
    extends ConsumerState<_RepertoireCopilotSheet> {
  final _theme = TextEditingController();
  final _refine = TextEditingController();

  /// Nulo até o servidor responder; enquanto isso vale o `fallback`.
  RepertoireDefaults? _defaults;
  bool _countTouched = false;
  int _count = RepertoireDefaults.fallback.count;

  /// Nulo = tanto faz; 0 = nenhum hino.
  int? _hymns;

  RepertoireSuggestion? _result;

  /// As fixadas: o ajuste e o "Trocar" não mexem nelas.
  final Set<String> _pinned = {};

  /// Todas as que o líder tirou nesta sugestão. Vão ao servidor em cada
  /// ajuste, para não voltarem; as da lista atual ainda podem ser trazidas
  /// de volta.
  final Set<String> _excluded = {};

  bool _busy = false;
  String? _swapping;
  String? _error;

  CopilotRepository get _repo => ref.read(copilotRepositoryProvider);
  RepertoireDefaults get _limits => _defaults ?? RepertoireDefaults.fallback;
  bool get _offerHymns => _limits.hymnsAvailable > 0;

  List<SuggestedSong> get _visible => [
        for (final s in _result?.songs ?? const <SuggestedSong>[])
          if (!_excluded.contains(s.song.id)) s,
      ];

  List<SuggestedSong> get _removedHere => [
        for (final s in _result?.songs ?? const <SuggestedSong>[])
          if (_excluded.contains(s.song.id)) s,
      ];

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    RepertoireDefaults defaults;
    try {
      defaults = await _repo.repertoireDefaults(
        widget.eventId,
        serviceId: widget.service.id,
      );
    } on ApiException {
      defaults = RepertoireDefaults.fallback;
    }
    if (!mounted) return;
    setState(() {
      _defaults = defaults;
      if (!_countTouched) _count = defaults.count;
    });
  }

  @override
  void dispose() {
    _theme.dispose();
    _refine.dispose();
    super.dispose();
  }

  void _step(int delta) => setState(() {
        _countTouched = true;
        _count = (_count + delta).clamp(1, _limits.maxCount);
        if (_hymns != null && _hymns! > _count) _hymns = _count;
      });

  Future<void> _suggest() async {
    if (_theme.text.trim().length < 2) {
      setState(() => _error = 'Escreva o tema e a ideia central.');
      return;
    }
    final ok = await _call(
      () => _repo.suggestRepertoire(
        widget.eventId,
        serviceId: widget.service.id,
        theme: _theme.text.trim(),
        count: _count,
        hymns: _offerHymns ? _hymns : null,
      ),
    );
    if (ok) {
      _pinned.clear();
      _excluded.clear();
    }
  }

  /// Quantos hinos o ajuste pede: os que estão na lista, se a pessoa pediu
  /// hinos -- tirar um hino é decidir ter um a menos.
  int? _hymnsFor(List<SuggestedSong> keep, int count) {
    final asked = _result?.hymns;
    if (asked == null) return null;
    if (keep.isEmpty) return asked > count ? count : asked;
    return keep.where((s) => s.song.isHymn).length;
  }

  Future<void> _ask() async {
    final instruction = _refine.text.trim();
    final result = _result;
    if (instruction.length < 2 || result == null) return;
    final visible = _visible;
    final count = visible.isEmpty ? result.songs.length : visible.length;
    final ok = await _call(
      () => _repo.refineRepertoire(
        widget.eventId,
        result.id,
        baseVersion: result.version,
        instruction: instruction,
        lockedSongIds: [
          for (final s in visible)
            if (_pinned.contains(s.song.id)) s.song.id,
        ],
        excludedSongIds: _excluded.toList(),
        count: count,
        hymns: _hymnsFor(visible, count),
      ),
    );
    if (ok) _refine.clear();
  }

  /// "Trocar": um ajuste que mexe só nesta. As outras ficam como estão, e a
  /// trocada não volta.
  Future<void> _swap(SuggestedSong item) async {
    final result = _result!;
    final visible = _visible;
    setState(() => _swapping = item.song.id);
    final ok = await _call(
      () => _repo.refineRepertoire(
        widget.eventId,
        result.id,
        baseVersion: result.version,
        instruction: 'Troque "${item.song.title}" por outra música.',
        lockedSongIds: [
          for (final s in visible)
            if (s.song.id != item.song.id) s.song.id,
        ],
        excludedSongIds: [..._excluded, item.song.id],
        count: visible.length,
        hymns: _hymnsFor(visible, visible.length),
      ),
    );
    if (!mounted) return;
    setState(() {
      _swapping = null;
      if (ok) _excluded.add(item.song.id);
    });
  }

  void _remove(SuggestedSong item) => setState(() {
        _excluded.add(item.song.id);
        _pinned.remove(item.song.id);
      });

  void _restore() => setState(() {
        _excluded.removeAll(_removedHere.map((s) => s.song.id));
      });

  Future<bool> _call(Future<RepertoireSuggestion> Function() request) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await request();
      if (mounted) setState(() => _result = result);
      return true;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _use() {
    final result = _result!;
    final songs = _visible;
    // Só registro: a métrica de quanto o copiloto ajuda. Falhar aqui não
    // muda nada para quem está montando o culto.
    _repo.markApplied(
      widget.eventId,
      result.id,
      [for (final s in songs) s.song.id],
    ).ignore();
    Navigator.pop(context, songs);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = _result;
    final visible = _visible;
    final removed = _removedHere;
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xs,
          AppSpacing.xl,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Sugerir repertório',
              subtitle:
                  'Músicas do repertório da equipe para ${widget.service.label}, a partir do tema da mensagem.',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (result == null) ...[
              TextField(
                controller: _theme,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 600,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Tema e ideia central',
                  hintText:
                      'Fidelidade de Deus, a partir de Romanos 8. Começar alegre e terminar contemplativo.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _CountStepper(
                value: _count,
                max: _limits.maxCount,
                enabled: !_busy,
                onStep: _step,
              ),
              Text(
                _defaults == null
                    ? 'Peça a mais, se quiser: depois você tira as que não servirem.'
                    : '${widget.service.label} costuma ter ${_defaults!.count}. '
                        'Peça a mais, se quiser: depois você tira as que não servirem.',
                style: muted,
              ),
              if (_offerHymns) ...[
                const SizedBox(height: AppSpacing.lg),
                Text('Hinos entre elas', style: theme.textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                AppChoiceBar<int?>(
                  value: _hymns,
                  onChanged: (v) {
                    if (!_busy) setState(() => _hymns = v);
                  },
                  options: [
                    const AppChoice(value: null, label: 'Tanto faz'),
                    const AppChoice(value: 0, label: 'Nenhum'),
                    for (var n = 1;
                        n <= 3 && n <= _count && n <= _limits.hymnsAvailable;
                        n++)
                      AppChoice(value: n, label: '$n'),
                  ],
                ),
              ],
            ] else ...[
              Text(
                result.theme,
                style: theme.textTheme.titleSmall,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (result.summary != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  result.summary!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (result.unmet != null) ...[
                const SizedBox(height: AppSpacing.sm),
                AppNotice(
                  tone: AppTone.info,
                  icon: Icons.info_outline_rounded,
                  message: result.unmet!,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Text(
                'Fixe as que você quer manter: o ajuste e o "Trocar" mexem só '
                'nas outras. Tire as que não vai usar.',
                style: muted,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (visible.isNotEmpty)
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (index, item) in visible.indexed) ...[
                        if (index > 0)
                          Divider(height: 1, color: scheme.outlineVariant),
                        _SuggestedTile(
                          position: index + 1,
                          item: item,
                          pinned: _pinned.contains(item.song.id),
                          swapping: _swapping == item.song.id,
                          onTogglePin: _busy
                              ? null
                              : () => setState(() {
                                    _pinned.contains(item.song.id)
                                        ? _pinned.remove(item.song.id)
                                        : _pinned.add(item.song.id);
                                  }),
                          onSwap: _busy ? null : () => _swap(item),
                          onRemove: _busy ? null : () => _remove(item),
                        ),
                      ],
                    ],
                  ),
                )
              else
                const AppNotice(
                  tone: AppTone.info,
                  icon: Icons.info_outline_rounded,
                  message:
                      'Você tirou todas. Traga de volta, peça um ajuste ou tente outro tema.',
                ),
              if (removed.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        removed.length == 1
                            ? '1 música tirada'
                            : '${removed.length} músicas tiradas',
                        style: muted,
                      ),
                    ),
                    TextButton(
                      style: AppButtonStyles.compactText,
                      onPressed: _busy ? null : _restore,
                      child: const Text('Trazer de volta'),
                    ),
                  ],
                ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _refine,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: 'Pedir um ajuste',
                  hintText: 'Algo mais congregacional · terminar com um hino',
                  helperText: switch (_pinned.length) {
                    0 => null,
                    1 => 'A fixada fica.',
                    final n => 'As $n fixadas ficam.',
                  },
                  suffixIcon: IconButton(
                    tooltip: 'Pedir ajuste',
                    onPressed: _busy ? null : _ask,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ),
                onSubmitted: (_) => _ask(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppNotice(
                tone: AppTone.danger,
                icon: Icons.error_outline_rounded,
                message: _error!,
                liveRegion: true,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (_busy && _swapping == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (result == null)
              FilledButton.icon(
                onPressed: _suggest,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Sugerir repertório'),
              )
            else
              Row(
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _result = null;
                              _pinned.clear();
                              _excluded.clear();
                            }),
                    child: const Text('Outro tema'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: visible.isEmpty || _busy ? null : _use,
                    child: Text(
                      visible.length == 1
                          ? 'Usar esta'
                          : 'Usar estas ${visible.length}',
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// "Quantas músicas": de 1 ao teto do servidor, um toque por vez.
class _CountStepper extends StatelessWidget {
  const _CountStepper({
    required this.value,
    required this.max,
    required this.enabled,
    required this.onStep,
  });

  final int value;
  final int max;
  final bool enabled;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text('Quantas músicas', style: theme.textTheme.labelLarge),
        ),
        IconButton.outlined(
          tooltip: 'Uma a menos',
          onPressed: enabled && value > 1 ? () => onStep(-1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 40,
          child: Semantics(
            liveRegion: true,
            label: '$value músicas',
            excludeSemantics: true,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
        IconButton.outlined(
          tooltip: 'Uma a mais',
          onPressed: enabled && value < max ? () => onStep(1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

class _SuggestedTile extends StatelessWidget {
  const _SuggestedTile({
    required this.position,
    required this.item,
    required this.pinned,
    required this.swapping,
    required this.onTogglePin,
    required this.onSwap,
    required this.onRemove,
  });

  final int position;
  final SuggestedSong item;
  final bool pinned;
  final bool swapping;
  final VoidCallback? onTogglePin;
  final VoidCallback? onSwap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final song = item.song;
    final moment = serviceMomentLabel(item.moment);
    final hymn = song.hymnal;
    final subtitle = [
      if (hymn != null)
        '${hymn.number} ${hymn.abbreviation}'
      else if (song.artist != null)
        song.artist!,
      if (moment != null) moment,
      _lastPlayed(item.lastPlayedAt),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$position',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(song.title, style: theme.textTheme.titleSmall),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Text(item.reason, style: theme.textTheme.bodyMedium),
                for (final concern in item.concerns)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Row(
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 14,
                          color: AppStatusColors.of(context).warning.foreground,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            concern,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Escritas, e não só ícones: o cadeado de antes só se
                // explicava passando o mouse, e no celular não há mouse.
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    TextButton.icon(
                      style: AppButtonStyles.compactText.copyWith(
                        foregroundColor: pinned
                            ? null
                            : WidgetStatePropertyAll(scheme.onSurfaceVariant),
                      ),
                      onPressed: onTogglePin,
                      icon: Icon(
                        pinned
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                        size: 18,
                      ),
                      label: Text(pinned ? 'Fixada' : 'Fixar'),
                    ),
                    TextButton.icon(
                      style: AppButtonStyles.compactText,
                      onPressed: pinned ? null : onSwap,
                      icon: swapping
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: Text(swapping ? 'Trocando…' : 'Trocar'),
                    ),
                    TextButton.icon(
                      style: AppButtonStyles.compactText,
                      onPressed: onRemove,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Tirar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _lastPlayed(DateTime? at) {
    if (at == null) return 'Nunca cantada';
    final days = DateTime.now().difference(at).inDays;
    if (days < 1) return 'Cantada hoje';
    if (days < 14) return 'Cantada há $days dias';
    if (days < 60) return 'Cantada há ${days ~/ 7} semanas';
    return 'Cantada há ${days ~/ 30} meses';
  }
}
