import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_pressable.dart';
import '../data/event_repository.dart';
import '../domain/open_date.dart';
import 'agenda_event_tile.dart';

class AgendaOpenDates extends ConsumerStatefulWidget {
  const AgendaOpenDates({
    super.key,
    required this.teamId,
    required this.dates,
    required this.wide,
  });

  final String teamId;
  final List<OpenDate> dates;
  final bool wide;

  @override
  ConsumerState<AgendaOpenDates> createState() => _AgendaOpenDatesState();
}

class _AgendaOpenDatesState extends ConsumerState<AgendaOpenDates> {
  bool _saving = false;

  Future<void> _createAll() async {
    final count = widget.dates.length;
    final confirmed = await showConfirmDialog(
      context,
      title: count == 1 ? 'Criar 1 rascunho?' : 'Criar $count rascunhos?',
      // Por culto, cada linha é um culto, e não um dia.
      message: widget.dates.any((date) => date.templateId != null)
          ? 'Cada culto vira uma escala em rascunho, com a sua equipe. A '
              'equipe só vê depois que você publicar.'
          : 'Cada data vira uma escala em rascunho, com os cultos da grade '
              'já marcados. A equipe só vê depois que você publicar.',
      confirmLabel: 'Criar',
    );
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    try {
      final result = await ref
          .read(eventRepositoryProvider)
          .generate(widget.teamId, weeks: openDatesWeeks);
      if (!mounted) return;

      // A lista de datas em aberto sai da lista de escalas: invalidar uma
      // recalcula a outra, e as linhas somem sozinhas.
      ref.invalidate(eventsProvider((widget.teamId, 'upcoming')));
      showAppSnackBar(
        context,
        result.createdCount == 0
            ? 'Estas datas já tinham escala.'
            : '${result.createdCount} '
                '${result.createdCount == 1 ? 'rascunho criado' : 'rascunhos criados'}.',
        tone: AppTone.success,
      );
    } on ApiException catch (error) {
      if (mounted) {
        showAppSnackBar(context, error.message, tone: AppTone.danger);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppGroup(
      title: 'Datas sem escala',
      subtitle: 'Da grade de cultos da igreja, nas próximas '
          '$openDatesWeeks semanas.',
      dividerIndent: AppGroup.textIndent,
      children: [
        for (final date in widget.dates)
          OpenDateTile(date: date, wide: widget.wide),
        _CreateDraftsRow(
          count: widget.dates.length,
          saving: _saving,
          onTap: _createAll,
        ),
      ],
    );
  }
}

/// A última linha do grupo: cria de uma vez as datas listadas acima.
///
/// Fica **depois** da lista, e não no cabeçalho, porque ela é o resumo do que
/// está ali — o líder lê as datas, decide que é isso mesmo e confirma no fim. É
/// também a posição em que o polegar chega sem cobrir a lista que ele acabou de
/// conferir.
class _CreateDraftsRow extends StatelessWidget {
  const _CreateDraftsRow({
    required this.count,
    required this.saving,
    required this.onTap,
  });

  final int count;
  final bool saving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppPressable(
      onTap: saving ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: saving
                  ? CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    )
                  : Icon(
                      Icons.event_repeat_rounded,
                      size: 20,
                      color: scheme.primary,
                    ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                count == 1
                    ? 'Criar o rascunho desta data'
                    : 'Criar os rascunhos destas $count datas',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
