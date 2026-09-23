import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/responsive/adaptive_dialog.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_choice_bar.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_notice.dart';
import '../../../shared/widgets/app_picker_field.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/quarter_hour_picker.dart';
import '../../../shared/widgets/app_primary_action.dart';
import '../../events/data/event_repository.dart';
import '../data/team_repository.dart';
import '../domain/service_template.dart';

/// A grade de cultos da igreja.
///
/// Existe para o líder não digitar rótulo e horário a cada escala. Ele cadastra
/// aqui uma vez ("Domingo 08:30 Manhã", "Domingo 19:00 Noite", "Quinta 19:30")
/// e, na tela de nova escala, escolhe só a data -- os cultos daquele dia da
/// semana já vêm marcados.
class ServiceTemplatesScreen extends ConsumerWidget {
  const ServiceTemplatesScreen({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(serviceTemplatesProvider(teamId));
    final adicionar = AppPrimaryAction(
      label: 'Adicionar',
      icon: Icons.add_rounded,
      onPressed: () => _openEditor(context, ref),
    );

    return Scaffold(
      // "Planejar próximas escalas" era um ícone sem rótulo nesta barra. Virou
      // uma linha com nome no fim da lista, onde a grade já foi lida.
      appBar: AppBar(
        title: const Text('Cultos da igreja'),
        actions: [
          if (adicionar.headerAction(context) case final acao?) acao,
        ],
      ),
      floatingActionButton: adicionar.fab(context),
      body: SafeArea(
        top: false,
        child: AppContentWidth.reading(
          child: templates.when(
            loading: () => const AppListSkeleton(itemCount: 4),
            error: (error, _) => AppErrorState(
              message: error is ApiException
                  ? error.message
                  : 'Não foi possível carregar os cultos.',
              onRetry: () => ref.invalidate(serviceTemplatesProvider(teamId)),
            ),
            data: (list) => list.isEmpty
                ? RefreshableMessage(
                    onRefresh: () async =>
                        ref.refresh(serviceTemplatesProvider(teamId).future),
                    child: AppEmptyState(
                      icon: Icons.church_outlined,
                      title: 'Nenhum culto cadastrado',
                      message: 'Cadastre os horários que se repetem toda '
                          'semana. Eles aparecem prontos ao criar uma escala.',
                      actionLabel: 'Adicionar culto',
                      onAction: () => _openEditor(context, ref),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () async =>
                        ref.refresh(serviceTemplatesProvider(teamId).future),
                    child: _TemplateList(
                      teamId: teamId,
                      templates: list,
                      onEdit: (t) => _openEditor(context, ref, template: t),
                      onPlan: () => _openGenerator(context, ref),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    ServiceTemplate? template,
  }) async {
    final saved = await showAdaptiveSheet<bool>(
      context: context,
      maxWidth: 480,
      builder: (_) => _TemplateEditorSheet(teamId: teamId, template: template),
    );
    if (saved == true) ref.invalidate(serviceTemplatesProvider(teamId));
  }

  Future<void> _openGenerator(BuildContext context, WidgetRef ref) async {
    final result = await showAdaptiveSheet<GeneratedSchedules>(
      context: context,
      maxWidth: 480,
      builder: (_) => _GenerateSchedulesSheet(teamId: teamId),
    );
    if (result == null || !context.mounted) return;

    ref.invalidate(eventsProvider((teamId, 'upcoming')));
    final message = result.createdCount == 0
        ? 'As próximas datas já tinham escala.'
        : '${result.createdCount} '
            '${result.createdCount == 1 ? 'rascunho criado' : 'rascunhos criados'}.';
    showAppSnackBar(context, message, tone: AppTone.success);
  }
}

/// Folha, e não diálogo: é um formulário curto (período + confirmar), como as
/// outras do app. O período é uma barra de três opções, e não uma lista
/// suspensa com três linhas.
class _GenerateSchedulesSheet extends ConsumerStatefulWidget {
  const _GenerateSchedulesSheet({required this.teamId});

  final String teamId;

  @override
  ConsumerState<_GenerateSchedulesSheet> createState() =>
      _GenerateSchedulesSheetState();
}

class _GenerateSchedulesSheetState
    extends ConsumerState<_GenerateSchedulesSheet> {
  int _weeks = 4;
  bool _saving = false;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(eventRepositoryProvider)
          .generate(widget.teamId, weeks: _weeks);
      if (mounted) Navigator.of(context).pop(result);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
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
            Text('Planejar próximas escalas', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Cria rascunhos usando os dias e horários desta grade. Datas que '
              'já têm escala são mantidas como estão.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppChoiceBar<int>(
              expanded: true,
              value: _weeks,
              onChanged: (value) {
                if (!_saving) setState(() => _weeks = value);
              },
              options: const [
                AppChoice(value: 4, label: '4 semanas'),
                AppChoice(value: 8, label: '8 semanas'),
                AppChoice(value: 12, label: '12 semanas'),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppNotice(
                tone: AppTone.danger,
                message: _error!,
                liveRegion: true,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppSubmitButton(
              label: 'Criar rascunhos',
              loading: _saving,
              onPressed: _generate,
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateList extends ConsumerWidget {
  const _TemplateList({
    required this.teamId,
    required this.templates,
    required this.onEdit,
    required this.onPlan,
  });

  final String teamId;
  final List<ServiceTemplate> templates;
  final ValueChanged<ServiceTemplate> onEdit;
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Agrupado por dia da semana: é assim que se pensa a semana da igreja, e
    // uma lista corrida de sete horários não deixa ver que domingo tem dois.
    final byWeekday = <int, List<ServiceTemplate>>{};
    for (final template in templates) {
      byWeekday.putIfAbsent(template.weekday, () => []).add(template);
    }
    final weekdays = byWeekday.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.lg,
        AppSpacing.screenPadding,
        AppSpacing.fabClearance,
      ),
      children: [
        Text(
          'Os horários que se repetem toda semana. Ao criar uma escala, você '
          'escolhe a data e os cultos do dia já vêm marcados.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final weekday in weekdays) ...[
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            // Cinza, como os cabeçalhos de grupo do resto do app: o violeta
            // fica para o que se toca.
            child: Text(
              weekdayName(weekday),
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              children: [
                for (var i = 0; i < byWeekday[weekday]!.length; i++) ...[
                  if (i > 0) Divider(color: scheme.outlineVariant, height: 1),
                  _TemplateRow(
                    template: byWeekday[weekday]![i],
                    onEdit: () => onEdit(byWeekday[weekday]![i]),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        const SizedBox(height: AppSpacing.sm),
        AppGroup(
          children: [
            AppGroupRow(
              icon: Icons.event_repeat_rounded,
              title: 'Planejar próximas escalas',
              subtitle: 'Cria rascunhos das próximas semanas com esta grade',
              onTap: onPlan,
            ),
          ],
        ),
      ],
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({required this.template, required this.onEdit});

  final ServiceTemplate template;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onEdit,
      // A hora como texto, e não dentro de um bloco azul. Era o mesmo ladrilho
      // tingido que saiu das outras telas — e aqui ele era pior: pintava de
      // azul-marca uma informação puramente factual, repetida em toda linha da
      // grade. Em algarismos tabulares as horas caem na mesma vertical, que é o
      // que se quer numa grade semanal.
      leading: SizedBox(
        width: 58,
        child: Text(
          template.timeLabel,
          style: AppTypography.time(context),
        ),
      ),
      title: Text(template.label, style: theme.textTheme.titleSmall),
      // Sem lixeira em toda linha: remover é raro e mora na folha de edição.
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
      ),
    );
  }
}

/// Folha de cadastro/edição de um culto da grade.
class _TemplateEditorSheet extends ConsumerStatefulWidget {
  const _TemplateEditorSheet({required this.teamId, this.template});

  final String teamId;
  final ServiceTemplate? template;

  @override
  ConsumerState<_TemplateEditorSheet> createState() =>
      _TemplateEditorSheetState();
}

/// Os nomes que quase toda igreja usa ([serviceNamePresets], os mesmos do
/// culto avulso da escala). Um toque, sem teclado; "Outro" abre o campo para o
/// que fugir disso ("Quinta", "Jovens", "Santa Ceia").
const _presetLabels = serviceNamePresets;

class _TemplateEditorSheetState extends ConsumerState<_TemplateEditorSheet> {
  late final TextEditingController _label = TextEditingController(
    text: _presetLabels.contains(widget.template?.label)
        ? ''
        : widget.template?.label ?? '',
  );
  late String? _preset = _presetLabels.contains(widget.template?.label)
      ? widget.template!.label
      : null;
  late bool _other =
      widget.template != null && !_presetLabels.contains(widget.template!.label);

  /// O campo só ganha foco quando a pessoa toca em "Outro". Abrindo a edição
  /// de um culto que já tem nome livre, o teclado subia sem ninguém pedir e
  /// cobria o resto da folha.
  bool _focusOther = false;
  late int _weekday = widget.template?.weekday ?? 0;
  late TimeOfDay _time =
      widget.template?.timeOfDay ?? const TimeOfDay(hour: 19, minute: 0);

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.template != null;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  int get _startMinutes => _time.hour * 60 + _time.minute;

  Future<void> _save() async {
    final label = _other ? _label.text.trim() : (_preset ?? '');
    if (label.isEmpty) {
      setState(
        () => _error = _other
            ? 'Informe o nome do culto.'
            : 'Escolha o nome do culto.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repository = ref.read(teamRepositoryProvider);

      if (!_isEditing) {
        await repository.addServiceTemplate(
          widget.teamId,
          label: label,
          weekday: _weekday,
          startMinutes: _startMinutes,
        );
        if (mounted) Navigator.of(context).pop(true);
        return;
      }

      final template = widget.template!;
      final changedTime = template.startMinutes != _startMinutes;
      final changedLabel = template.label != label;

      // Só pergunta sobre escalas futuras quando alguma delas realmente
      // mudaria. Trocar o dia da semana não mexe em escala já montada -- isso
      // vale para as próximas.
      var applyToFuture = false;
      if (changedTime || changedLabel) {
        final affected = await repository.serviceTemplateFutureEvents(
          widget.teamId,
          template.id,
        );
        if (affected.isNotEmpty) {
          if (!mounted) return;
          final answer = await _askApplyToFuture(affected.length);
          if (answer == null) {
            setState(() => _saving = false);
            return;
          }
          applyToFuture = answer;
        }
      }

      await repository.updateServiceTemplate(
        widget.teamId,
        template.id,
        label: label,
        weekday: _weekday,
        startMinutes: _startMinutes,
        applyToFutureEvents: applyToFuture,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// `null` = desistiu de salvar.
  Future<bool?> _askApplyToFuture(int count) {
    final plural = count == 1 ? 'escala futura usa' : 'escalas futuras usam';
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Atualizar escalas futuras?'),
        content: Text(
          '$count $plural este culto. Quer que elas passem a usar o horário e '
          'o nome novos?\n\n'
          'A data de cada escala não muda.',
        ),
        // "Só as próximas" dizia o contrário do que fazia: mantinha as escalas
        // já criadas. Os dois botões agora dizem o que acontece com elas.
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Manter como estão'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              count == 1 ? 'Atualizar 1 escala' : 'Atualizar $count escalas',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _remove() async {
    final template = widget.template!;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remover ${template.label}?',
      message: 'Sai da grade de '
          '${weekdayName(template.weekday).toLowerCase()}. As escalas já '
          'montadas continuam com o horário que têm hoje.',
      confirmLabel: 'Remover',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(teamRepositoryProvider)
          .removeServiceTemplate(widget.teamId, template.id);
      if (!mounted) return;
      showAppSnackBar(
        context,
        '${template.label} saiu da grade.',
        tone: AppTone.success,
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
            Text(
              _isEditing ? 'Editar culto' : 'Novo culto',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Nome', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final preset in _presetLabels)
                  ChoiceChip(
                    label: Text(preset),
                    selected: !_other && _preset == preset,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() {
                              _preset = preset;
                              _other = false;
                              _error = null;
                            }),
                  ),
                ChoiceChip(
                  label: const Text('Outro'),
                  selected: _other,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() {
                            _other = true;
                            _focusOther = true;
                            _error = null;
                          }),
                ),
              ],
            ),
            if (_other) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _label,
                autofocus: _focusOther,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome do culto',
                  hintText: 'Quinta, Jovens, Santa Ceia...',
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text('Dia da semana', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (var day = 0; day < 7; day++)
                  ChoiceChip(
                    label: Text(weekdayName(day).substring(0, 3)),
                    selected: _weekday == day,
                    onSelected:
                        _saving ? null : (_) => setState(() => _weekday = day),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            // O campo inteiro abre o seletor, como os outros campos de escolha
            // do app. Era um botão contornado com a hora dentro.
            AppPickerField(
              label: 'Horário',
              icon: Icons.schedule_outlined,
              value: '${_time.hour.toString().padLeft(2, '0')}:'
                  '${_time.minute.toString().padLeft(2, '0')}',
              enabled: !_saving,
              onTap: () async {
                final picked = await showQuarterHourPicker(
                  context: context,
                  initialTime: _time,
                  title: 'Horário do culto',
                );
                if (picked != null) setState(() => _time = picked);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppNotice(
                tone: AppTone.danger,
                message: _error!,
                liveRegion: true,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppSubmitButton(
              label: 'Salvar',
              loading: _saving,
              onPressed: _save,
            ),
            if (_isEditing) ...[
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: _saving ? null : _remove,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                child: const Text('Remover da grade'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
