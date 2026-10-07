import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/date/civil_date.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/responsive/adaptive_dialog.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_bottom_action_bar.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_choice_bar.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_notice.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/section_header.dart';
import '../../events/data/agenda_provider.dart';
import '../../events/data/event_repository.dart';
import '../data/copilot_repository.dart';
import '../domain/copilot_models.dart';

/// Copiloto de Escalas: o mês inteiro distribuído de uma vez.
///
/// Dois momentos na mesma tela. **Antes**: os dias do mês, a formação de
/// costume de cada dia da semana e o que só o cadastro permite (quem tem cada
/// função). **Depois**: a proposta, o equilíbrio do mês, o "por quê" de cada
/// escolha, trocas e travas -- e nada vira escala até "Salvar rascunhos".
///
/// A proposta mora no servidor, com versões: o F5 e outro aparelho voltam a
/// ela, e "Voltar à versão anterior" desfaz uma troca.
class ScheduleCopilotScreen extends ConsumerStatefulWidget {
  const ScheduleCopilotScreen({
    super.key,
    required this.teamId,
    required this.initialMonth,
  });

  final String teamId;

  /// Primeiro dia do mês aberto.
  final DateTime initialMonth;

  @override
  ConsumerState<ScheduleCopilotScreen> createState() =>
      _ScheduleCopilotScreenState();
}

enum _Tab { schedules, balance }

class _ScheduleCopilotScreenState extends ConsumerState<ScheduleCopilotScreen> {
  late DateTime _month =
      DateTime(widget.initialMonth.year, widget.initialMonth.month);
  MonthPreview? _preview;
  List<WeekdayLineup> _lineups = const [];
  bool _includeDrafts = false;
  ScheduleCopilotSession? _session;
  Object? _error;
  bool _loading = true;
  bool _busy = false;
  _Tab _tab = _Tab.schedules;

  String get _monthKey =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
  CopilotRepository get _repo => ref.read(copilotRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _loading = true;
      _error = null;
      _session = null;
    });
    try {
      final preview = await _repo.monthPreview(widget.teamId, _monthKey);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _lineups = preview.lineups;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  void _changeMonth(int delta) {
    _month = DateTime(_month.year, _month.month + delta);
    _loadPreview();
  }

  Future<void> _run(Future<ScheduleCopilotSession> Function() action) async {
    setState(() => _busy = true);
    try {
      final session = await action();
      if (mounted) setState(() => _session = session);
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.message, tone: AppTone.danger);
      // Outra pessoa da liderança mexeu na proposta: mostra como está agora.
      if (e.code == 'COPILOT_VERSION_CHANGED' && _session != null) {
        final fresh = await _repo.session(widget.teamId, _session!.id);
        if (mounted) setState(() => _session = fresh);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() => _run(
        () => _repo.generate(
          widget.teamId,
          month: _monthKey,
          includeDrafts: _includeDrafts,
          lineups: _lineups,
        ),
      );

  Future<void> _resume(String sessionId) =>
      _run(() => _repo.session(widget.teamId, sessionId));

  Future<void> _edit(
    String action, {
    String? dateKey,
    String? positionId,
    int? slotIndex,
    String? membershipId,
    int? toVersion,
  }) {
    final session = _session!;
    return _run(
      () => _repo.edit(
        widget.teamId,
        session.id,
        baseVersion: session.version,
        action: action,
        dateKey: dateKey,
        positionId: positionId,
        slotIndex: slotIndex,
        membershipId: membershipId,
        toVersion: toVersion,
      ),
    );
  }

  Future<void> _discard() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Descartar a proposta?',
      message:
          'Nenhuma escala foi criada. Você pode gerar outra quando quiser.',
      confirmLabel: 'Descartar',
      cancelLabel: 'Manter',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repo.discard(widget.teamId, _session!.id);
      if (mounted) await _loadPreview();
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message, tone: AppTone.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final session = _session!;
    final chosen = await showAdaptiveSheet<List<String>>(
      context: context,
      maxWidth: 480,
      builder: (_) => _SaveSheet(days: session.generatedDays),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final results = await _repo.commit(
        widget.teamId,
        session.id,
        version: session.version,
        dateKeys: chosen,
      );
      if (!mounted) return;
      ref.invalidate(eventsProvider);
      ref.invalidate(agendaEventsProvider);
      final saved = results.where((r) => r.saved).length;
      final skipped = results.where((r) => !r.saved).toList();
      if (skipped.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              saved == 1 ? '1 rascunho salvo' : '$saved rascunhos salvos',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Estes dias ficaram de fora:'),
                  const SizedBox(height: AppSpacing.sm),
                  for (final r in skipped)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text('${_dayTitle(r.dateKey)}: ${r.detail ?? ''}'),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Entendi'),
              ),
            ],
          ),
        );
      }
      if (!mounted) return;
      if (saved > 0) {
        context.go('/agenda?filtro=rascunhos');
        showAppSnackBar(
          context,
          saved == 1
              ? 'Rascunho salvo. A equipe só vê depois que você publicar.'
              : '$saved rascunhos salvos. A equipe só vê cada escala depois que você publicar.',
          tone: AppTone.success,
        );
      }
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message, tone: AppTone.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Montar o mês'),
        actions: [
          if (session != null && session.isOpen)
            PopupMenuButton<String>(
              tooltip: 'Mais opções',
              enabled: !_busy,
              onSelected: (value) => switch (value) {
                'regenerate' => _edit('REGENERATE'),
                'undo' => _edit('REVERT', toVersion: session.version - 1),
                'discard' => _discard(),
                _ => null,
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'regenerate',
                  child: Text('Refazer o que não está travado'),
                ),
                if (session.version > 1)
                  const PopupMenuItem(
                    value: 'undo',
                    child: Text('Desfazer a última mudança'),
                  ),
                const PopupMenuItem(
                  value: 'discard',
                  child: Text('Descartar a proposta'),
                ),
              ],
            ),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
      body: SafeArea(
        top: false,
        child: AppContentWidth.reading(child: _body()),
      ),
    );
  }

  Widget? _bottomBar() {
    if (_loading || _error != null) return null;
    final session = _session;
    if (session == null) {
      final generatable = _preview?.days
              .where(
                (d) =>
                    !d.past &&
                    (d.state == CopilotDayState.empty ||
                        (_includeDrafts && d.state == CopilotDayState.draft)),
              )
              .length ??
          0;
      return AppBottomActionBar(
        action: AppSubmitButton(
          label: 'Gerar proposta',
          loadingLabel: 'Gerando',
          loading: _busy,
          onPressed: generatable == 0 ? null : _generate,
        ),
      );
    }
    if (!session.isOpen) return null;
    final count = session.generatedDays.length;
    return AppBottomActionBar(
      action: AppSubmitButton(
        label: count == 1 ? 'Salvar rascunho' : 'Salvar rascunhos',
        loading: _busy,
        onPressed: _save,
      ),
    );
  }

  Widget _body() {
    if (_loading) return const AppListSkeleton(itemCount: 5);
    if (_error != null) {
      return AppErrorState(
        message: _error is ApiException
            ? (_error! as ApiException).message
            : 'Não foi possível abrir o mês.',
        onRetry: _loadPreview,
      );
    }
    final session = _session;
    if (session == null) return _monthSetup(_preview!);
    return _proposal(session);
  }

  // ---------------------------------------------------------------------------
  // Antes: o mês, a formação e os avisos
  // ---------------------------------------------------------------------------

  Widget _monthSetup(MonthPreview preview) {
    final theme = Theme.of(context);
    final days = preview.days.where((d) => !d.past).toList();
    final hasDrafts = days.any((d) => d.state == CopilotDayState.draft);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.md,
        AppSpacing.screenPadding,
        AppSpacing.xxl,
      ),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Mês anterior',
              onPressed: _busy ? null : () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                monthYearLabel(_month),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Próximo mês',
              onPressed: _busy ? null : () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'O copiloto distribui a equipe pelo mês inteiro de uma vez, pelo cadastro de funções, '
          'pela disponibilidade e pelo rodízio. Nada é salvo até você revisar, e as escalas '
          'nascem como rascunho.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (preview.openSessionId case final open?) ...[
          const SizedBox(height: AppSpacing.lg),
          AppNotice(
            tone: AppTone.info,
            icon: Icons.history_rounded,
            title: 'Há uma proposta aberta deste mês',
            message: 'Continue de onde parou, ou gere outra.',
            action: TextButton(
              onPressed: _busy ? null : () => _resume(open),
              child: const Text('Continuar'),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (days.isEmpty)
          const AppEmptyState(
            icon: Icons.event_busy_rounded,
            title: 'Nenhum culto pela frente neste mês',
            message: 'Os dias vêm da grade de cultos da equipe.',
          )
        else
          AppGroup(
            title: 'Dias do mês',
            dividerIndent: AppGroup.textIndent,
            children: [
              for (final day in days)
                AppGroupRow(
                  title: _dayTitle(day.dateKey),
                  subtitle: [day.title, day.services.join(' · ')]
                      .whereType<String>()
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  showChevron: false,
                  trailing: AppBadge(
                    label: day.state.label,
                    tone: switch (day.state) {
                      CopilotDayState.empty => AppTone.neutral,
                      CopilotDayState.draft => AppTone.warning,
                      CopilotDayState.published => AppTone.success,
                    },
                  ),
                ),
            ],
          ),
        if (hasDrafts) ...[
          const SizedBox(height: AppSpacing.lg),
          AppChoiceBar<bool>(
            expanded: true,
            value: _includeDrafts,
            onChanged: (v) => setState(() => _includeDrafts = v),
            options: const [
              AppChoice(value: false, label: 'Só os dias sem escala'),
              AppChoice(value: true, label: 'Refazer rascunhos'),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Escala publicada nunca muda. Fora da proposta, ela entra só na conta do equilíbrio.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        for (final lineup in _lineups) ...[
          const SizedBox(height: AppSpacing.xl),
          _LineupEditor(
            lineup: lineup,
            enabled: !_busy,
            onChanged: (updated) => setState(() {
              _lineups = [
                for (final l in _lineups)
                  l.weekday == updated.weekday ? updated : l,
              ];
            }),
          ),
        ],
        if (preview.hints.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Bom saber antes'),
          for (final hint in preview.hints)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppNotice(
                tone: hint.kind == 'SCARCE' ? AppTone.warning : AppTone.info,
                icon: hint.kind == 'TALENT'
                    ? Icons.auto_awesome_rounded
                    : Icons.info_outline_rounded,
                message: hint.text,
                action: hint.kind == 'TALENT' && hint.membershipId != null
                    ? TextButton(
                        onPressed: () => context.go('/equipe'),
                        child: const Text('Abrir a equipe'),
                      )
                    : null,
              ),
            ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Depois: a proposta e o equilíbrio
  // ---------------------------------------------------------------------------

  Widget _proposal(ScheduleCopilotSession session) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.md,
            AppSpacing.screenPadding,
            AppSpacing.xxl,
          ),
          children: [
            Text(monthYearLabel(_month), style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              session.isOpen
                  ? 'Toque numa pessoa para ver o porquê, trocar ou travar. O que estiver travado '
                      'fica igual quando você pedir para refazer.'
                  : 'Esta proposta já foi salva.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppChoiceBar<_Tab>(
              expanded: true,
              value: _tab,
              onChanged: (t) => setState(() => _tab = t),
              options: const [
                AppChoice(
                  value: _Tab.schedules,
                  label: 'Escalas',
                  icon: Icons.event_note_rounded,
                ),
                AppChoice(
                  value: _Tab.balance,
                  label: 'Equilíbrio',
                  icon: Icons.balance_rounded,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final warning in session.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AppNotice(
                  tone: AppTone.warning,
                  icon: Icons.warning_amber_rounded,
                  message: warning,
                ),
              ),
            if (_tab == _Tab.schedules)
              for (final day in session.days)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: _DayCard(
                    day: day,
                    editable: session.isOpen && !_busy,
                    onToggleLock: () => _edit(
                      day.locked ? 'UNLOCK_DAY' : 'LOCK_DAY',
                      dateKey: day.dateKey,
                    ),
                    onSlot: (position, slot) =>
                        _openSlot(session, day, position, slot),
                  ),
                )
            else
              _BalanceView(session: session),
          ],
        ),
        if (_busy)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  Future<void> _openSlot(
    ScheduleCopilotSession session,
    CopilotDay day,
    CopilotPosition position,
    CopilotSlot slot,
  ) async {
    if (!session.isOpen || _busy) return;
    final action = await showAdaptiveSheet<_SlotAction>(
      context: context,
      maxWidth: 480,
      builder: (_) => _SlotSheet(day: day, position: position, slot: slot),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _SlotAction.pick:
        final picked = await showAdaptiveSheet<String>(
          context: context,
          maxWidth: 480,
          builder: (_) => _PersonPicker(
            session: session,
            day: day,
            position: position,
            slot: slot,
          ),
        );
        if (picked != null && mounted) {
          await _edit(
            'SET',
            dateKey: day.dateKey,
            positionId: position.positionId,
            slotIndex: slot.index,
            membershipId: picked,
          );
        }
      case _SlotAction.replace:
        await _edit(
          'REPLACE',
          dateKey: day.dateKey,
          positionId: position.positionId,
          slotIndex: slot.index,
        );
      case _SlotAction.lock:
        await _edit(
          'SET',
          dateKey: day.dateKey,
          positionId: position.positionId,
          slotIndex: slot.index,
          membershipId: slot.membershipId,
        );
      case _SlotAction.unlock:
        await _edit(
          'UNLOCK_SLOT',
          dateKey: day.dateKey,
          positionId: position.positionId,
          slotIndex: slot.index,
        );
      case _SlotAction.clear:
        await _edit(
          'CLEAR',
          dateKey: day.dateKey,
          positionId: position.positionId,
          slotIndex: slot.index,
        );
    }
  }
}

/// "Domingo, 8 de novembro".
String _dayTitle(String key) {
  final date = parseDateKey(key);
  if (date == null) return key;
  final text = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(date);
  return text[0].toUpperCase() + text.substring(1);
}

// -----------------------------------------------------------------------------
// Formação de costume
// -----------------------------------------------------------------------------

class _LineupEditor extends StatelessWidget {
  const _LineupEditor({
    required this.lineup,
    required this.enabled,
    required this.onChanged,
  });

  final WeekdayLineup lineup;
  final bool enabled;
  final ValueChanged<WeekdayLineup> onChanged;

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (lineup.source) {
      'SAVED' => 'A de costume. O que mudar aqui vale para as próximas vezes.',
      'HISTORY' => 'Sugerida pelas escalas anteriores. Confira antes de gerar.',
      _ => 'Diga quantas pessoas cada função leva neste dia.',
    };
    return AppGroup(
      title: 'Formação de ${lineup.weekdayName}',
      subtitle: subtitle,
      dividerIndent: AppGroup.textIndent,
      children: [
        for (final position in lineup.positions)
          _CountRow(
            label: position.name,
            value: position.count,
            enabled: enabled,
            onChanged: (count) => onChanged(
              WeekdayLineup(
                weekday: lineup.weekday,
                weekdayName: lineup.weekdayName,
                source: lineup.source,
                positions: [
                  for (final p in lineup.positions)
                    p.positionId == position.positionId
                        ? p.copyWith(count: count)
                        : p,
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: value == 0 ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Menos $label',
            onPressed: enabled && value > 0 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'Mais $label',
            onPressed:
                enabled && value < 10 ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Um dia da proposta
// -----------------------------------------------------------------------------

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.editable,
    required this.onToggleLock,
    required this.onSlot,
  });

  final CopilotDay day;
  final bool editable;
  final VoidCallback onToggleLock;
  final void Function(CopilotPosition, CopilotSlot) onSlot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final context0 = !day.generated;

    return AppCard(
      surface: context0 ? CardSurface.sunken : CardSurface.plain,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _dayTitle(day.dateKey),
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      [day.title, day.services.join(' · ')]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (context0)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: AppBadge(
                    label: switch (day.state) {
                      CopilotDayState.published => 'Publicada, fica como está',
                      CopilotDayState.draft => 'Rascunho mantido',
                      // Sem escala e fora da proposta: o dia da semana não
                      // tem formação definida (o aviso no topo diz).
                      CopilotDayState.empty => 'Fora da proposta',
                    },
                    tone: AppTone.neutral,
                  ),
                )
              else
                IconButton(
                  tooltip: day.locked ? 'Destravar o dia' : 'Travar o dia',
                  onPressed: editable ? onToggleLock : null,
                  icon: Icon(
                    day.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                    color:
                        day.locked ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (day.changed)
            const Padding(
              padding:
                  EdgeInsets.only(top: AppSpacing.sm, right: AppSpacing.sm),
              child: AppNotice(
                tone: AppTone.warning,
                icon: Icons.sync_problem_rounded,
                message:
                    'A escala deste dia mudou depois da proposta. Ao salvar, este dia fica de fora.',
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          if (day.positions.isEmpty)
            Text(
              'Ninguém escalado.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          for (final position in day.positions)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 112,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        position.name,
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final slot in position.slots)
                          _SlotChip(
                            slot: slot,
                            onTap: day.generated && editable
                                ? () => onSlot(position, slot)
                                : null,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({required this.slot, required this.onTap});

  final CopilotSlot slot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = slot.membershipId == null;
    final warn = slot.warnings.isNotEmpty;
    return ActionChip(
      onPressed: onTap,
      avatar: slot.locked
          ? Icon(Icons.lock_rounded, size: 16, color: scheme.primary)
          : warn
              ? Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: AppStatusColors.of(context).warning.foreground,
                )
              : null,
      label: Text(empty ? 'Vaga vazia' : slot.name ?? ''),
      labelStyle: TextStyle(
        color: empty ? scheme.onSurfaceVariant : null,
        fontStyle: empty ? FontStyle.italic : null,
      ),
      tooltip: slot.reason,
    );
  }
}

enum _SlotAction { pick, replace, lock, unlock, clear }

class _SlotSheet extends StatelessWidget {
  const _SlotSheet({
    required this.day,
    required this.position,
    required this.slot,
  });

  final CopilotDay day;
  final CopilotPosition position;
  final CopilotSlot slot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final empty = slot.membershipId == null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xs,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: empty ? 'Vaga vazia' : slot.name!,
              subtitle: '${position.name} · ${_dayTitle(day.dateKey)}',
              padding: EdgeInsets.zero,
            ),
            if (slot.reason != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Por quê',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(slot.reason!, style: theme.textTheme.bodyMedium),
            ],
            for (final warning in slot.warnings) ...[
              const SizedBox(height: AppSpacing.sm),
              AppNotice(
                tone: AppTone.warning,
                icon: Icons.warning_amber_rounded,
                message: warning,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.pop(context, _SlotAction.pick),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: Text(empty ? 'Escolher quem' : 'Trocar por outra pessoa'),
            ),
            if (!empty) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, _SlotAction.replace),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('O copiloto escolhe outra pessoa'),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (slot.locked)
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context, _SlotAction.unlock),
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Destravar'),
                  )
                else if (!empty)
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context, _SlotAction.lock),
                    icon: const Icon(Icons.lock_rounded),
                    label: const Text('Travar'),
                  ),
                const Spacer(),
                if (!empty)
                  TextButton(
                    onPressed: () => Navigator.pop(context, _SlotAction.clear),
                    child: const Text('Deixar vazia'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Quem pode entrar nesta vaga. Primeiro quem as regras permitem, com as
/// escalas que já tem no mês; depois o resto da equipe, cada um com o motivo
/// de não ter sido proposto -- a escolha manual é do líder, como no app.
class _PersonPicker extends StatelessWidget {
  const _PersonPicker({
    required this.session,
    required this.day,
    required this.position,
    required this.slot,
  });

  final ScheduleCopilotSession session;
  final CopilotDay day;
  final CopilotPosition position;
  final CopilotSlot slot;

  @override
  Widget build(BuildContext context) {
    final candidates = slot.candidates.toSet();
    final inDay = {
      for (final p in day.positions)
        for (final s in p.slots)
          if (s.membershipId != null && p.positionId == position.positionId)
            s.membershipId!,
    };
    final people =
        session.members.where((m) => !inDay.contains(m.membershipId)).toList();
    final able = people
        .where((m) => candidates.contains(m.membershipId))
        .toList()
      ..sort((a, b) => a.monthCount.compareTo(b.monthCount));
    final others =
        people.where((m) => !candidates.contains(m.membershipId)).toList();

    String why(CopilotMember m) {
      if (day.unavailable.contains(m.membershipId)) {
        return 'Avisou que não pode neste dia';
      }
      if (m.onLeave) return 'Em afastamento';
      if (m.isGuest) return 'De fora da equipe';
      if (!m.positionIds.contains(position.positionId)) {
        return 'Sem ${position.name} no cadastro';
      }
      return 'Pode';
    }

    String count(CopilotMember m) => m.monthCount == 1
        ? '1 escala no mês'
        : '${m.monthCount} escalas no mês';

    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          SectionHeader(title: position.name, subtitle: _dayTitle(day.dateKey)),
          if (able.isNotEmpty)
            AppGroup(
              title: 'Podem pelas regras',
              dividerIndent: AppGroup.textIndent,
              children: [
                for (final m in able)
                  AppGroupRow(
                    title: m.name,
                    subtitle: count(m),
                    showChevron: false,
                    onTap: () => Navigator.pop(context, m.membershipId),
                  ),
              ],
            ),
          if (others.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            AppGroup(
              title: 'Outras pessoas',
              subtitle: 'Você pode escolher; o copiloto não propõe.',
              dividerIndent: AppGroup.textIndent,
              children: [
                for (final m in others)
                  AppGroupRow(
                    title: m.name,
                    subtitle: '${why(m)} · ${count(m)}',
                    showChevron: false,
                    onTap: () => Navigator.pop(context, m.membershipId),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Equilíbrio do mês
// -----------------------------------------------------------------------------

class _BalanceView extends StatelessWidget {
  const _BalanceView({required this.session});

  final ScheduleCopilotSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final highlight in session.highlights)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppNotice(
              tone: AppTone.info,
              icon: Icons.insights_rounded,
              message: highlight,
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        AppGroup(
          title: 'Escalas de cada pessoa no mês',
          subtitle:
              'Com as publicadas. O número entre parênteses é o que a disponibilidade sugere.',
          dividerIndent: AppGroup.textIndent,
          children: [
            for (final m in session.balance)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.name, style: theme.textTheme.bodyLarge),
                          if (m.positions.isNotEmpty || m.note != null)
                            Text(
                              [
                                if (m.positions.isNotEmpty)
                                  m.positions.join(', '),
                                if (m.note != null) m.note!,
                              ].join(' · '),
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${m.count} (${_target(m.target)})',
                          style: theme.textTheme.titleMedium,
                        ),
                        if (_badge(m) case final badge?) badge,
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  static String _target(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1).replaceAll('.', ',');

  static Widget? _badge(BalanceMember m) => switch (m.status) {
        BalanceStatus.high =>
          const AppBadge(label: 'Mais que o esperado', tone: AppTone.warning),
        BalanceStatus.low =>
          const AppBadge(label: 'Menos que o esperado', tone: AppTone.info),
        BalanceStatus.leftOut =>
          const AppBadge(label: 'Ficou de fora', tone: AppTone.info),
        BalanceStatus.unavailable =>
          const AppBadge(label: 'Sem dia possível', tone: AppTone.neutral),
        BalanceStatus.onLeave =>
          const AppBadge(label: 'Afastamento', tone: AppTone.neutral),
        BalanceStatus.ok => null,
      };
}

// -----------------------------------------------------------------------------
// Salvar
// -----------------------------------------------------------------------------

class _SaveSheet extends StatefulWidget {
  const _SaveSheet({required this.days});

  final List<CopilotDay> days;

  @override
  State<_SaveSheet> createState() => _SaveSheetState();
}

class _SaveSheetState extends State<_SaveSheet> {
  late final Set<String> _chosen = {
    for (final d in widget.days)
      if (!d.changed) d.dateKey,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              title: 'Salvar como rascunho',
              subtitle:
                  'Só a liderança vê. Cada escala é publicada depois, como sempre.',
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            ),
            for (final day in widget.days)
              CheckboxListTile(
                value: _chosen.contains(day.dateKey),
                onChanged: day.changed
                    ? null
                    : (v) => setState(
                          () => v == true
                              ? _chosen.add(day.dateKey)
                              : _chosen.remove(day.dateKey),
                        ),
                title: Text(_dayTitle(day.dateKey)),
                subtitle: Text(
                  day.changed
                      ? 'Mudou depois da proposta'
                      : [
                          '${day.filled} ${day.filled == 1 ? 'pessoa' : 'pessoas'}',
                          if (day.empty > 0)
                            '${day.empty} ${day.empty == 1 ? 'vaga vazia' : 'vagas vazias'}',
                          if (day.state == CopilotDayState.draft)
                            'substitui o rascunho',
                        ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _chosen.isEmpty
                  ? null
                  : () => Navigator.pop(context, _chosen.toList()..sort()),
              child: Text(
                _chosen.length == 1
                    ? 'Salvar 1 rascunho'
                    : 'Salvar ${_chosen.length} rascunhos',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
