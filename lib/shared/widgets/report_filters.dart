import 'package:flutter/material.dart';

import '../../core/date/report_period.dart';
import '../../core/theme/app_spacing.dart';
import 'app_date_range_picker.dart';

/// A linha de filtros de um relatório: os menus à esquerda e a ordem à
/// direita.
///
/// Os menus são texto, e não barras de escolha: logo abaixo das abas de uma
/// tela, duas barras iguais empilhadas pesam o mesmo, e o período parecia uma
/// aba a mais. Quando não cabem lado a lado (320px, fonte aumentada), eles
/// quebram a linha em vez de cortar o texto.
class ReportFilterBar extends StatelessWidget {
  const ReportFilterBar({super.key, required this.filters, this.trailing});

  final List<Widget> filters;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding - AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.screenPadding - AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(spacing: AppSpacing.xs, children: filters),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// "Últimos 3 meses ▾": os atalhos e "Escolher datas…".
class ReportPeriodMenu extends StatelessWidget {
  const ReportPeriodMenu({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ReportPeriod value;
  final ValueChanged<ReportPeriod> onChanged;

  static const _custom = -1;

  Future<void> _pickRange(BuildContext context) async {
    final current = value;
    final range = await showAppDateRangePicker(
      context: context,
      initialRange: current is ReportPeriodRange
          ? DateTimeRange(start: current.from, end: current.to)
          : null,
    );
    if (range != null) onChanged(ReportPeriodRange(range.start, range.end));
  }

  @override
  Widget build(BuildContext context) {
    final current = value;
    return PopupMenuButton<int>(
      tooltip: 'Período',
      onSelected: (months) {
        if (months == _custom) {
          _pickRange(context);
        } else {
          onChanged(ReportPeriodMonths(months));
        }
      },
      itemBuilder: (_) => [
        for (final months in reportPeriodPresets)
          CheckedPopupMenuItem(
            value: months,
            checked: current is ReportPeriodMonths && current.months == months,
            child: Text(ReportPeriodMonths(months).label),
          ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: _custom,
          checked: current is ReportPeriodRange,
          child: Text(
            current is ReportPeriodRange ? current.label : 'Escolher datas…',
          ),
        ),
      ],
      child: _MenuLabel(icon: Icons.date_range_rounded, label: value.label),
    );
  }
}

/// "Todos os dias ▾" / "Só quintas ▾".
///
/// As opções vêm dos dias da semana em que o período teve escala. Com um dia
/// só, e nenhum escolhido, o menu some: "Todos os dias" e "Só domingos"
/// seriam a mesma resposta.
class ReportWeekdayMenu extends StatelessWidget {
  const ReportWeekdayMenu({
    super.key,
    required this.value,
    required this.weekdays,
    required this.onChanged,
  });

  final int? value;
  final List<ReportWeekday> weekdays;
  final ValueChanged<int?> onChanged;

  static const _all = -1;

  @override
  Widget build(BuildContext context) {
    final options = [...weekdays];
    // O dia escolhido continua na lista mesmo se o novo período não tem
    // escala nele — senão não haveria como ver que ele está escolhido.
    if (value != null && !options.any((o) => o.weekday == value)) {
      options.add(ReportWeekday(weekday: value!, count: 0));
      options.sort((a, b) => a.weekday.compareTo(b.weekday));
    }
    if (value == null && options.length <= 1) return const SizedBox.shrink();

    return PopupMenuButton<int>(
      tooltip: 'Dia da semana',
      onSelected: (weekday) => onChanged(weekday == _all ? null : weekday),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: _all,
          checked: value == null,
          child: const Text('Todos os dias'),
        ),
        for (final option in options)
          CheckedPopupMenuItem(
            value: option.weekday,
            checked: value == option.weekday,
            child: Text(
              '${weekdayPluralLabel(option.weekday)} · '
              '${option.count} ${option.count == 1 ? 'escala' : 'escalas'}',
            ),
          ),
      ],
      child: _MenuLabel(
        icon: Icons.event_repeat_rounded,
        label: weekdayFilterLabel(value),
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSpacing.touchTarget),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
            Flexible(child: Text(label, style: theme.textTheme.titleSmall)),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.expand_more_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}
