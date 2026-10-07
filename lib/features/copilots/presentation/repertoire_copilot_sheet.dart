import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/responsive/adaptive_dialog.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_card.dart';
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
  final _context = TextEditingController();
  final _refine = TextEditingController();

  /// Nulo = o que este culto costuma ter (o servidor decide pelo histórico).
  int? _count;
  RepertoireSuggestion? _result;
  final Set<String> _locked = {};
  bool _busy = false;
  String? _error;

  CopilotRepository get _repo => ref.read(copilotRepositoryProvider);

  @override
  void dispose() {
    _theme.dispose();
    _context.dispose();
    _refine.dispose();
    super.dispose();
  }

  Future<void> _suggest() async {
    if (_theme.text.trim().length < 2) {
      setState(() => _error = 'Escreva o tema da mensagem.');
      return;
    }
    await _call(
      () => _repo.suggestRepertoire(
        widget.eventId,
        serviceId: widget.service.id,
        theme: _theme.text.trim(),
        context: _context.text,
        count: _count,
      ),
    );
    _locked.clear();
  }

  Future<void> _ask() async {
    final instruction = _refine.text.trim();
    if (instruction.length < 2 || _result == null) return;
    await _call(
      () => _repo.refineRepertoire(
        widget.eventId,
        _result!.id,
        baseVersion: _result!.version,
        instruction: instruction,
        lockedSongIds: _locked.toList(),
      ),
    );
    if (_error == null) _refine.clear();
  }

  Future<void> _call(Future<RepertoireSuggestion> Function() request) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await request();
      if (mounted) setState(() => _result = result);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _use() {
    final result = _result!;
    // Só registro: a métrica de quanto o copiloto ajuda. Falhar aqui não
    // muda nada para quem está montando o culto.
    _repo.markApplied(
      widget.eventId,
      result.id,
      [for (final s in result.songs) s.song.id],
    ).ignore();
    Navigator.pop(context, result.songs);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = _result;

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
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Tema da mensagem',
                  hintText: 'Fidelidade de Deus',
                ),
                onSubmitted: (_) => _suggest(),
              ),
              TextField(
                controller: _context,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Contexto (opcional)',
                  hintText:
                      'A mensagem será em Romanos 8. Começar alegre e terminar contemplativo.',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Quantas músicas', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  ChoiceChip(
                    label: const Text('O de costume'),
                    selected: _count == null,
                    onSelected:
                        _busy ? null : (_) => setState(() => _count = null),
                  ),
                  for (final n in const [3, 4, 5, 6])
                    ChoiceChip(
                      label: Text('$n'),
                      selected: _count == n,
                      onSelected:
                          _busy ? null : (_) => setState(() => _count = n),
                    ),
                ],
              ),
            ] else ...[
              Text('Tema: ${result.theme}', style: theme.textTheme.titleSmall),
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
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (index, item) in result.songs.indexed) ...[
                      if (index > 0)
                        Divider(height: 1, color: scheme.outlineVariant),
                      _SuggestedTile(
                        position: index + 1,
                        item: item,
                        locked: _locked.contains(item.song.id),
                        onToggleLock: _busy
                            ? null
                            : () => setState(() {
                                  _locked.contains(item.song.id)
                                      ? _locked.remove(item.song.id)
                                      : _locked.add(item.song.id);
                                }),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _refine,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: 'Pedir um ajuste',
                  hintText:
                      'Troque a segunda · algo mais congregacional · só quatro músicas',
                  helperText:
                      _locked.isEmpty ? null : 'As músicas com cadeado ficam.',
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
            if (_busy)
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
                    onPressed: () => setState(() {
                      _result = null;
                      _locked.clear();
                    }),
                    child: const Text('Outro tema'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: result.songs.isEmpty ? null : _use,
                    child: Text(
                      result.songs.length == 1
                          ? 'Usar esta'
                          : 'Usar estas ${result.songs.length}',
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

class _SuggestedTile extends StatelessWidget {
  const _SuggestedTile({
    required this.position,
    required this.item,
    required this.locked,
    required this.onToggleLock,
  });

  final int position;
  final SuggestedSong item;
  final bool locked;
  final VoidCallback? onToggleLock;

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
        AppSpacing.xs,
        AppSpacing.md,
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
              ],
            ),
          ),
          IconButton(
            tooltip: locked ? 'Destravar' : 'Manter esta no ajuste',
            onPressed: onToggleLock,
            icon: Icon(
              locked ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: locked ? scheme.primary : scheme.onSurfaceVariant,
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
