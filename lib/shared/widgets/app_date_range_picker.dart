import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/date/civil_date.dart';
import '../../core/date/report_period.dart';
import '../../core/responsive/adaptive_dialog.dart';
import '../../core/theme/app_spacing.dart';
import 'app_bottom_action_bar.dart';
import 'app_month_grid.dart';

/// Escolher um **período** — dois toques na grade mensal do app.
///
/// O `showDateRangePicker` do Material abre em tela cheia com um calendário
/// que não é o do resto do app; este é a mesma [AppMonthGrid] da agenda e do
/// "Quem não pode", olhando para trás: o mês de [lastDate] fica embaixo, à
/// mão, e os anteriores sobem. Dias depois de [lastDate] ficam apagados —
/// relatório conta o que já aconteceu.
///
/// Primeiro toque é o começo; o segundo, o fim. Tocar antes do começo inverte
/// as pontas em vez de recomeçar: quem escolhe "até 30 de junho" e depois
/// rola para março escolheu o começo. Um dia só também é período ("como foi a
/// Páscoa?").
Future<DateTimeRange?> showAppDateRangePicker({
  required BuildContext context,
  DateTimeRange? initialRange,
  DateTime? lastDate,
  int monthsBack = 60,
  String title = 'Escolha o período',
}) {
  final last = _day(lastDate ?? DateTime.now());
  return showAdaptiveSheet<DateTimeRange>(
    context: context,
    builder: (_) => _AppDateRangeSheet(
      initialRange: initialRange,
      lastDate: last,
      firstDate: DateTime(last.year, last.month - monthsBack, 1),
      monthsBack: monthsBack,
      title: title,
    ),
  );
}

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

class _AppDateRangeSheet extends StatefulWidget {
  const _AppDateRangeSheet({
    required this.initialRange,
    required this.lastDate,
    required this.firstDate,
    required this.monthsBack,
    required this.title,
  });

  final DateTimeRange? initialRange;
  final DateTime lastDate;
  final DateTime firstDate;
  final int monthsBack;
  final String title;

  @override
  State<_AppDateRangeSheet> createState() => _AppDateRangeSheetState();
}

class _AppDateRangeSheetState extends State<_AppDateRangeSheet> {
  late DateTime? _start =
      widget.initialRange == null ? null : _day(widget.initialRange!.start);
  late DateTime? _end =
      widget.initialRange == null ? null : _day(widget.initialRange!.end);

  void _tap(DateTime day) {
    setState(() {
      if (_start == null || _end != null) {
        _start = day;
        _end = null;
      } else if (day.isBefore(_start!)) {
        _end = _start;
        _start = day;
      } else {
        _end = day;
      }
    });
  }

  String get _status {
    if (_start == null) return 'Toque no primeiro dia do período.';
    if (_end == null) {
      return '${ReportPeriodRange(_start!, _start!).label} — agora toque no '
          'último dia.';
    }
    return ReportPeriodRange(_start!, _end!).label;
  }

  AppMonthDay _describe(DateTime day) {
    final enabled =
        !day.isAfter(widget.lastDate) && !day.isBefore(widget.firstDate);
    final isStart = day == _start;
    final isEnd = day == _end;
    final inside = _start != null &&
        _end != null &&
        day.isAfter(_start!) &&
        day.isBefore(_end!);
    return AppMonthDay(
      selected: isStart || isEnd,
      inRange: inside,
      enabled: enabled,
      detail: isStart && isEnd
          ? 'começo e fim do período'
          : isStart
              ? 'começo do período'
              : isEnd
                  ? 'fim do período'
                  : inside
                      ? 'dentro do período'
                      : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final height = math.min(MediaQuery.sizeOf(context).height * 0.8, 720.0);
    final today = _day(DateTime.now());

    return SizedBox(
      height: height,
      child: Column(
        // `stretch`: com o padrão (centro), o bloco do título encolhia até o
        // texto e ficava no meio do diálogo, andando a cada toque.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _status,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            // Invertida: o mês atual embaixo, onde a lista abre, e os
            // anteriores para cima — quem escolhe período de relatório olha
            // para trás.
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              itemCount: widget.monthsBack + 1,
              itemBuilder: (context, index) {
                final month = DateTime(
                  widget.lastDate.year,
                  widget.lastDate.month - index,
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.sm,
                          AppSpacing.lg,
                          AppSpacing.sm,
                          AppSpacing.sm,
                        ),
                        child: Text(
                          monthYearLabel(month),
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      AppMonthGrid(
                        month: month,
                        today: today,
                        keyPrefix: 'periodo-',
                        onTap: _tap,
                        describe: _describe,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          AppBottomActionBar(
            sideBySideFrom: 0,
            action: FilledButton(
              onPressed: _start == null
                  ? null
                  : () => Navigator.of(context).pop(
                        DateTimeRange(start: _start!, end: _end ?? _start!),
                      ),
              child: const Text('Ver este período'),
            ),
          ),
        ],
      ),
    );
  }
}
