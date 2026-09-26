import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/responsive/adaptive_dialog.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_date_badge.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_pressable.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/app_primary_action.dart';
import '../../auth/application/auth_controller.dart';
import '../../events/data/event_repository.dart';
import '../../events/domain/event_datetime.dart';
import '../../team/data/team_repository.dart';
import '../data/unavailability_repository.dart';
import '../domain/schedule_conflicts.dart';
import '../domain/unavailability_models.dart';
import 'multi_date_picker.dart';

/// "Não posso nesses dias".
///
/// O modelo é avisar antes, não confirmar depois: em vez de a escala sair e
/// cada pessoa aceitar ou recusar, quem sabe que vai faltar marca o dia com
/// antecedência e quem monta a escala já enxerga isso na hora de escalar.
class MyUnavailabilityScreen extends ConsumerStatefulWidget {
  const MyUnavailabilityScreen({super.key, required this.teamId});

  final String teamId;

  @override
  ConsumerState<MyUnavailabilityScreen> createState() =>
      _MyUnavailabilityScreenState();
}

class _MyUnavailabilityScreenState
    extends ConsumerState<MyUnavailabilityScreen> {
  bool _saving = false;

  /// Os dias em que eu já estou escalado nesta equipe, a partir das próximas
  /// escalas que a agenda e a Home já carregam (mesma chave de cache).
  Map<DateTime, ScheduledDay> _scheduledDays() {
    final events =
        ref.read(eventsProvider((widget.teamId, 'upcoming'))).valueOrNull?.data;
    if (events == null) return const {};
    final membershipId = ref
        .read(authControllerProvider)
        .teams
        .where((t) => t.teamId == widget.teamId)
        .firstOrNull
        ?.membershipId;
    return scheduledDaysFor(events, membershipId);
  }

  /// O calendário edita o conjunto inteiro: o que a pessoa desmarcar é
  /// removido, o que marcar é criado. Assim o calendário mostra a verdade e
  /// não vira só um formulário de inclusão.
  Future<void> _editDays(List<Unavailability> current) async {
    final existing = {
      for (final item in current)
        if (!item.date.isBefore(_today)) item.date: item.id,
    };

    // A grade da igreja, se ela já chegou: marca no calendário os dias em que
    // há culto. Sem ela o calendário funciona igual, só sem a marca.
    final templates =
        ref.read(serviceTemplatesProvider(widget.teamId)).valueOrNull;

    final scheduled = _scheduledDays();

    final result = await showMultiDatePicker(
      context: context,
      initialSelection: existing.keys.toSet(),
      isServiceDay: templates == null || templates.isEmpty
          ? null
          : (day) => templates.any((t) => t.matchesDate(day)),
      scheduledOn: (day) => switch (scheduled[day]) {
        final escala? => scheduledDayPhrase(day, escala),
        null => null,
      },
    );

    if (result == null || !mounted) return;

    final added = result.dates.difference(existing.keys.toSet()).toList()
      ..sort();
    final removedIds = [
      for (final entry in existing.entries)
        if (!result.dates.contains(entry.key)) entry.value,
    ];

    if (added.isEmpty && removedIds.isEmpty) return;

    setState(() => _saving = true);
    try {
      final repository = ref.read(unavailabilityRepositoryProvider);

      for (final id in removedIds) {
        await repository.remove(widget.teamId, id);
      }
      if (added.isNotEmpty) {
        await repository.add(
          widget.teamId,
          dates: added,
          reason: result.reason,
        );
      }

      ref.invalidate(myUnavailabilityProvider(widget.teamId));

      // Diz o efeito, e não só o que foi gravado: num dia em que a pessoa já
      // estava na escala, o recado chega a quem lidera.
      final comEscala = added.where(scheduled.containsKey).length;
      if (mounted) {
        showAppSnackBar(
          context,
          switch ((added.length, comEscala)) {
            (0, _) => 'Dias atualizados. A equipe já vê.',
            (_, > 0) => 'Aviso enviado. Quem lidera já sabe que você não '
                'pode ${comEscala == 1 ? 'no dia em que estava escalado' : 'nos dias em que estava escalado'}.',
            (1, _) => 'Aviso enviado para 1 dia.',
            (final n, _) => 'Aviso enviado para $n dias.',
          },
          tone: AppTone.success,
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        showAppSnackBar(context, error.message, tone: AppTone.danger);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Corrige o motivo de **um** dia. Folha, e não diálogo: é um formulário
  /// curto, e os formulários curtos do app sobem do rodapé.
  Future<void> _editReason(Unavailability item) async {
    final reason = await showAdaptiveSheet<String>(
      context: context,
      maxWidth: 440,
      builder: (_) => _ReasonSheet(initial: item.reason ?? ''),
    );
    if (reason == null || !mounted) return;
    if (reason == (item.reason ?? '')) return;

    try {
      await ref.read(unavailabilityRepositoryProvider).updateReason(
            widget.teamId,
            item.id,
            reason: reason,
          );
      ref.invalidate(myUnavailabilityProvider(widget.teamId));
      if (mounted) {
        showAppSnackBar(
          context,
          reason.isEmpty
              ? 'Motivo apagado. O dia continua marcado.'
              : 'Motivo atualizado. Quem lidera já vê.',
          tone: AppTone.success,
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        showAppSnackBar(context, error.message, tone: AppTone.danger);
      }
    }
  }

  /// Tirar um dia, com volta. O toque é pequeno e fica ao lado da linha que
  /// abre o motivo: errar o alvo apagava o aviso sem jeito de desfazer.
  Future<void> _remove(Unavailability item) async {
    final repository = ref.read(unavailabilityRepositoryProvider);
    try {
      await repository.remove(widget.teamId, item.id);
      ref.invalidate(myUnavailabilityProvider(widget.teamId));
      if (mounted) {
        showAppSnackBar(
          context,
          'Você voltou a ficar disponível nesse dia.',
          tone: AppTone.success,
          action: SnackBarAction(
            label: 'Desfazer',
            onPressed: () async {
              try {
                await repository.add(
                  widget.teamId,
                  dates: [item.date],
                  reason: item.reason,
                );
                ref.invalidate(myUnavailabilityProvider(widget.teamId));
              } on ApiException catch (error) {
                if (mounted) {
                  showAppSnackBar(
                    context,
                    error.message,
                    tone: AppTone.danger,
                  );
                }
              }
            },
          ),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        showAppSnackBar(context, error.message, tone: AppTone.danger);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = ref.watch(myUnavailabilityProvider(widget.teamId));
    // Observadas aqui para já terem chegado quando a pessoa abrir o
    // calendário: a grade marca os dias de culto; as escalas, os dias em que
    // ela já está escalada.
    ref.watch(serviceTemplatesProvider(widget.teamId));
    ref.watch(eventsProvider((widget.teamId, 'upcoming')));
    final scheduled = _scheduledDays();

    final upcoming = items.valueOrNull
            ?.where((i) => !i.date.isBefore(_today))
            .toList(growable: false) ??
        const <Unavailability>[];

    void openPicker() => _editDays(
          ref.read(myUnavailabilityProvider(widget.teamId)).value ?? const [],
        );

    // Sem dia marcado, a ação mora no próprio vazio: dois botões para a
    // mesma coisa na mesma tela seria um a mais.
    final escolher = items.hasValue && upcoming.isNotEmpty
        ? AppPrimaryAction(
            label: 'Escolher dias',
            icon: Icons.edit_calendar_rounded,
            onPressed: _saving ? null : openPicker,
            wrap: (botao) => botao,
          )
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minha disponibilidade'),
        actions: [
          if (escolher?.headerAction(context) case final acao?) acao,
        ],
      ),
      floatingActionButton: escolher?.fab(context),
      body: SafeArea(
        top: false,
        child: AppContentWidth.reading(
          child: items.when(
            loading: () =>
                const AppListSkeleton(itemCount: 3, leadingBlock: true),
            error: (error, _) => AppErrorState(
              message: error is ApiException
                  ? error.message
                  : 'Não foi possível carregar seus dias.',
              onRetry: () =>
                  ref.invalidate(myUnavailabilityProvider(widget.teamId)),
            ),
            data: (_) => RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(myUnavailabilityProvider(widget.teamId)),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.lg,
                  AppSpacing.screenPadding,
                  AppSpacing.fabClearance,
                ),
                children: [
                  Text(
                    'Marque os dias em que você não pode ser escalado. Quem '
                    'monta a escala vê esse aviso na hora de escalar.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (upcoming.isEmpty)
                    AppCard(
                      surface: CardSurface.sunken,
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        children: [
                          Icon(
                            Icons.event_available_outlined,
                            size: 32,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Disponível em todos os dias',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Você não marcou nenhum dia.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          FilledButton.icon(
                            onPressed: _saving ? null : openPicker,
                            icon: const Icon(
                              Icons.edit_calendar_rounded,
                              size: 18,
                            ),
                            label: const Text('Escolher dias'),
                          ),
                        ],
                      ),
                    )
                  else
                    // Uma superfície para os dias, com o bloco de data da
                    // agenda: era um cartão com borda por dia, uma pilha de
                    // caixinhas para uma lista só.
                    AppGroup(
                      dividerIndent: AppSpacing.lg + 54 + AppSpacing.md,
                      children: [
                        for (final item in upcoming)
                          _UnavailabilityRow(
                            item: item,
                            scheduled: scheduled[item.date],
                            onEditReason: () => _editReason(item),
                            onRemove: () => _remove(item),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}

class _UnavailabilityRow extends StatelessWidget {
  const _UnavailabilityRow({
    required this.item,
    required this.onEditReason,
    required this.onRemove,
    this.scheduled,
  });

  final Unavailability item;
  final VoidCallback onEditReason;
  final VoidCallback onRemove;

  /// A escala em que a pessoa já estava nesse dia. A linha diz que o recado
  /// chegou a quem lidera — é a pergunta que sobra depois de marcar.
  final ScheduledDay? scheduled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final pattern =
        item.date.year == now.year ? "d 'de' MMMM" : "d 'de' MMMM 'de' y";
    final label = DateFormat(pattern, 'pt_BR').format(item.date);
    final weekday = DateFormat('EEE', 'pt_BR')
        .format(item.date)
        .replaceAll('.', '')
        .toUpperCase();
    final reason = item.reason?.isNotEmpty ?? false ? item.reason! : null;

    return AppPressable(
      onTap: onEditReason,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
        ),
        child: Row(
          children: [
            AppDateBadge(
              weekday: weekday,
              day: '${item.date.day}',
              semanticsLabel: capitalizeWeekday(
                DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(item.date),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.titleSmall),
                  Text(
                    reason ?? 'Toque para dizer o motivo',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontStyle: reason == null ? FontStyle.italic : null,
                    ),
                  ),
                  if (scheduled != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.campaign_outlined,
                          size: 14,
                          color: AppStatusColors.of(context)
                              .resolve(AppTone.warning, scheme)
                              .foreground,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Você está na escala · quem lidera foi avisado',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppStatusColors.of(context)
                                  .resolve(AppTone.warning, scheme)
                                  .foreground,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remover',
              icon: const Icon(Icons.close_rounded),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

/// O motivo de um dia já marcado, com os mesmos chips do calendário.
class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet({required this.initial});

  final String initial;

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  late final _controller = TextEditingController(text: widget.initial);

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
            Text('Motivo desse dia', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            UnavailabilityReasonField(controller: _controller, autofocus: true),
            const SizedBox(height: AppSpacing.lg),
            AppSubmitButton(
              label: 'Salvar',
              onPressed: () =>
                  Navigator.of(context).pop(_controller.text.trim()),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
