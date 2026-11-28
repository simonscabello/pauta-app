import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/network/api_exception.dart';
import '../../../core/responsive/adaptive_dialog.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_picker_field.dart';
import '../../../shared/widgets/quarter_hour_picker.dart';
import '../data/agenda_provider.dart';
import '../domain/event_datetime.dart';
import '../data/event_repository.dart';
import '../domain/event_models.dart';

/// Pede a data/hora do novo culto e chama a API de duplicação.
///
/// **Folha, e não diálogo**: é um formulário curto, como os outros do app
/// (diálogo fica para confirmação). A hora usa o seletor de 15 minutos de todo
/// lugar — aqui era o mostrador do Material, o único do app, com os 60 minutos.
Future<void> showDuplicateEventDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Event source,
}) async {
  final timezone =
      source.timezone.isEmpty ? 'America/Sao_Paulo' : source.timezone;
  final location = tz.getLocation(timezone);
  final localStart = tz.TZDateTime.from(source.startsAt, location);

  final pickedLocal = await showAdaptiveSheet<tz.TZDateTime>(
    context: context,
    maxWidth: 480,
    builder: (_) => _DuplicateSheet(
      source: source,
      location: location,
      // Sugere +7 dias, mesmo horário local.
      initial: localStart.add(const Duration(days: 7)),
    ),
  );

  if (pickedLocal == null || !context.mounted) return;

  try {
    final created = await ref.read(eventRepositoryProvider).duplicate(
          source.id,
          startsAt: pickedLocal.toUtc().toIso8601String(),
        );
    invalidateAgendaSchedules(ref, source.teamId);
    if (!context.mounted) return;
    context.push('/agenda/${created.id}');
    showAppSnackBar(
      context,
      'Escala duplicada. Confira os horários e o repertório.',
      tone: AppTone.success,
    );
  } on ApiException catch (error) {
    if (!context.mounted) return;
    showAppSnackBar(context, error.message, tone: AppTone.danger);
  }
}

class _DuplicateSheet extends StatefulWidget {
  const _DuplicateSheet({
    required this.source,
    required this.location,
    required this.initial,
  });

  final Event source;
  final tz.Location location;
  final tz.TZDateTime initial;

  @override
  State<_DuplicateSheet> createState() => _DuplicateSheetState();
}

class _DuplicateSheetState extends State<_DuplicateSheet> {
  late tz.TZDateTime _picked = widget.initial;

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      // O resto do app abre o calendário em português; sem isto, só este
      // vinha em inglês.
      locale: const Locale('pt', 'BR'),
      initialDate: DateTime(_picked.year, _picked.month, _picked.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    setState(() {
      _picked = tz.TZDateTime(
        widget.location,
        date.year,
        date.month,
        date.day,
        _picked.hour,
        _picked.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final time = await showQuarterHourPicker(
      context: context,
      initialTime: TimeOfDay(hour: _picked.hour, minute: _picked.minute),
      title: 'Horário da nova escala',
    );
    if (time == null || !mounted) return;
    setState(() {
      _picked = tz.TZDateTime(
        widget.location,
        _picked.year,
        _picked.month,
        _picked.day,
        time.hour,
        time.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
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
            Text('Duplicar escala', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Copia a escalação e os detalhes de ${widget.source.describe()} '
              'para a nova data. O ensaio mantém a mesma diferença.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            // Mesma formatação do resto do app (dia da semana com maiúscula).
            AppPickerField(
              label: 'Dia',
              icon: Icons.event_rounded,
              value: capitalizeWeekday(
                DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(_picked),
              ),
              onTap: _pickDate,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPickerField(
              label: 'Horário',
              icon: Icons.schedule_rounded,
              value: DateFormat('HH:mm', 'pt_BR').format(_picked),
              onTap: _pickTime,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_picked),
              child: const Text('Duplicar'),
            ),
          ],
        ),
      ),
    );
  }
}
