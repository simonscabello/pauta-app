import 'package:flutter/material.dart';

import '../../core/date/civil_date.dart';
import '../../core/theme/app_spacing.dart';
import 'app_month_grid.dart';

/// Escolher **um** dia, na grade mensal do app.
///
/// O `showDatePicker` do Material não sabe do que importa aqui: não marca os
/// dias de culto da grade, não mostra que outro dia já tem escala e, com o
/// primeiro ano em 2020, aceitava criar escala num domingo que já passou. Este
/// seletor é a mesma [AppMonthGrid] da agenda e da indisponibilidade — quem
/// usa uma, lê as outras.
///
/// [isMarked] pinta o dia (a grade de cultos) e [markedLabel] diz na legenda o
/// que o traço quer dizer. Dias antes de [firstDate] ficam apagados.
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  String title = 'Escolha o dia',
  bool Function(DateTime day)? isMarked,
  String markedLabel = 'Dia de culto',
  int monthsAhead = 12,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AppDatePickerSheet(
      initialDate: _day(initialDate),
      firstDate: _day(firstDate),
      title: title,
      isMarked: isMarked,
      markedLabel: markedLabel,
      monthsAhead: monthsAhead,
    ),
  );
}

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

class _AppDatePickerSheet extends StatelessWidget {
  const _AppDatePickerSheet({
    required this.initialDate,
    required this.firstDate,
    required this.title,
    required this.isMarked,
    required this.markedLabel,
    required this.monthsAhead,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final String title;
  final bool Function(DateTime day)? isMarked;
  final String markedLabel;
  final int monthsAhead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final media = MediaQuery.of(context);
    final today = _day(DateTime.now());
    final start = DateTime(firstDate.year, firstDate.month);

    return SafeArea(
      child: SizedBox(
        height: media.size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleLarge),
                  ),
                  if (isMarked != null) ...[
                    const AppDayLegendChip(),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      markedLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                itemCount: monthsAhead + 1,
                itemBuilder: (context, index) {
                  final month = DateTime(start.year, start.month + index);
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
                          keyPrefix: 'escolher-dia-',
                          onTap: (day) => Navigator.of(context).pop(day),
                          describe: (day) {
                            final marcado = isMarked?.call(day) ?? false;
                            return AppMonthDay(
                              selected: day == initialDate,
                              marks: marcado ? 1 : 0,
                              enabled: !day.isBefore(firstDate),
                              detail: marcado ? markedLabel.toLowerCase() : null,
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
