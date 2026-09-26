import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date/report_period.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/on_leave_badge.dart';
import '../../../shared/widgets/report_filters.dart';
import '../../team/data/team_repository.dart';
import '../../team/domain/workload_report.dart';

/// "Quem não pode", por pessoa: em cada escala do período, cada um **serviu**,
/// **não pôde** (tinha avisado) ou ficou **livre** sem ser chamado.
///
/// O calendário responde "quem não pode no dia 14?"; esta aba responde a
/// pergunta de quem acompanha a equipe ao longo dos meses — quem está tendo
/// imprevistos demais, e quem está disponível e ninguém escala. A segunda só
/// aparece cruzando a indisponibilidade com a escala, e por isso os números
/// vêm da participação (`GET .../reports/workload`), e não da lista de dias:
/// a mesma resposta, a mesma chave de cache da tela de participação.
///
/// Nada aqui julga. "Não pôde em 6" pode ser plantão, faculdade ou luto; o
/// motivo continua no calendário, para quem lidera, e a conversa é de quem
/// lidera.
class UnavailabilitySummaryView extends ConsumerStatefulWidget {
  const UnavailabilitySummaryView({super.key, required this.teamId});

  final String teamId;

  @override
  ConsumerState<UnavailabilitySummaryView> createState() =>
      _UnavailabilitySummaryViewState();
}

class _UnavailabilitySummaryViewState
    extends ConsumerState<UnavailabilitySummaryView> {
  ReportPeriod _period = const ReportPeriodMonths(3);
  int? _weekday;
  AbsenceOrder _order = AbsenceOrder.mostAbsent;
  List<ReportWeekday> _weekdays = const [];

  @override
  Widget build(BuildContext context) {
    final query = (teamId: widget.teamId, period: _period, weekday: _weekday);
    final report = ref.watch(workloadProvider(query));
    _weekdays = report.valueOrNull?.weekdays ?? _weekdays;

    return Column(
      children: [
        ReportFilterBar(
          filters: [
            ReportPeriodMenu(
              value: _period,
              onChanged: (value) => setState(() => _period = value),
            ),
            ReportWeekdayMenu(
              value: _weekday,
              weekdays: _weekdays,
              onChanged: (value) => setState(() => _weekday = value),
            ),
          ],
          trailing: PopupMenuButton<AbsenceOrder>(
            tooltip: 'Ordenar',
            icon: const Icon(Icons.swap_vert_rounded),
            onSelected: (value) => setState(() => _order = value),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: AbsenceOrder.mostAbsent,
                checked: _order == AbsenceOrder.mostAbsent,
                child: const Text('Mais ausências primeiro'),
              ),
              CheckedPopupMenuItem(
                value: AbsenceOrder.leastAbsent,
                checked: _order == AbsenceOrder.leastAbsent,
                child: const Text('Menos ausências primeiro'),
              ),
              CheckedPopupMenuItem(
                value: AbsenceOrder.mostFree,
                checked: _order == AbsenceOrder.mostFree,
                child: const Text('Mais vezes livre primeiro'),
              ),
            ],
          ),
        ),
        Expanded(
          child: report.when(
            loading: () => const AppListSkeleton(itemCount: 6),
            error: (error, _) => AppErrorState(
              message: error is ApiException
                  ? error.message
                  : 'Não foi possível carregar as ausências.',
              onRetry: () => ref.invalidate(workloadProvider(query)),
            ),
            data: (value) => _SummaryBody(
              report: value,
              when: [
                _period.phrase,
                if (weekdayPhrase(_weekday) case final dia?) dia,
              ].join(', '),
              order: _order,
              onRefresh: () => ref.refresh(workloadProvider(query).future),
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({
    required this.report,
    required this.when,
    required this.order,
    required this.onRefresh,
  });

  final WorkloadReport report;
  final String when;
  final AbsenceOrder order;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = report.scheduleTotal;

    if (report.members.isEmpty) {
      return const AppEmptyState(
        icon: Icons.people_outline_rounded,
        title: 'Nenhum integrante ativo',
        message: 'O resumo aparece depois que a equipe é cadastrada.',
      );
    }
    if (total == 0) {
      return RefreshableMessage(
        onRefresh: onRefresh,
        child: AppEmptyState(
          icon: Icons.event_busy_rounded,
          title: 'Nenhuma escala no período',
          message: 'Não há escala publicada $when. O resumo cruza os dias '
              'marcados com as escalas que já passaram.',
        ),
      );
    }

    final members = absenceRanking(report, order: order);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          0,
          AppSpacing.screenPadding,
          AppSpacing.xxxl,
        ),
        children: [
          Text(
            '$total ${total == 1 ? 'escala publicada' : 'escalas publicadas'} '
            '$when. Em cada uma, a pessoa serviu, não pôde (tinha avisado) '
            'ou ficou livre sem ser chamada.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const _Legend(),
          const SizedBox(height: AppSpacing.lg),
          AppGroup(
            dividerIndent: AppGroup.textIndent,
            children: [
              for (final member in members)
                _PersonRow(member: member, total: total, order: order),
            ],
          ),
        ],
      ),
    );
  }
}

/// As três cores da barra, com o nome de cada uma. Cor sozinha não é sinal
/// (WCAG 1.4.1): a frase embaixo de cada barra repete os números.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final colors = _SegmentColors.of(context);
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.xs,
      children: [
        _LegendItem(color: colors.served, label: 'Serviu'),
        _LegendItem(color: colors.unavailable, label: 'Não pôde'),
        _LegendItem(color: colors.free, label: 'Livre'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _SegmentColors {
  const _SegmentColors({
    required this.served,
    required this.unavailable,
    required this.free,
  });

  factory _SegmentColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _SegmentColors(
      served: scheme.primary,
      unavailable: AppStatusColors.of(context).warning.foreground,
      // O cinza do contorno, e não o do trilho: "livre" é uma situação, e não
      // a falta de uma — precisa aparecer como parte da barra.
      free: scheme.outline,
    );
  }

  final Color served;
  final Color unavailable;
  final Color free;
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.member,
    required this.total,
    required this.order,
  });

  final WorkloadMember member;
  final int total;
  final AbsenceOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = _SegmentColors.of(context);
    final absent = member.unavailableCount;

    // O número da direita é o da ordem escolhida: quem ordena por "livre"
    // procura esse número, e não o das ausências.
    final String headline;
    final Color headlineColor;
    if (order == AbsenceOrder.mostFree) {
      headline = 'Livre em ${member.freeCount}';
      headlineColor = scheme.onSurfaceVariant;
    } else {
      headline = switch (absent) {
        0 => 'Nenhuma ausência',
        1 => '1 ausência',
        _ => '$absent ausências',
      };
      headlineColor =
          absent == 0 ? scheme.onSurfaceVariant : colors.unavailable;
    }

    final detail = [
      'Serviu em ${member.scheduleCount}',
      'não pôde em $absent',
      'livre em ${member.freeCount}',
      if (member.markedDays > 0)
        member.markedDays == 1
            ? '1 dia marcado'
            : '${member.markedDays} dias marcados',
    ].join(' · ');

    return Semantics(
      label: '${member.displayName}, $detail, de $total '
          '${total == 1 ? 'escala' : 'escalas'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.displayName,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (member.onLeave) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const OnLeaveBadge(),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  headline,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: headlineColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // A barra inteira é o período: as três partes somam o total de
            // escalas, para todo mundo, e por isso as barras se comparam de
            // relance de uma linha para a outra.
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              child: SizedBox(
                height: 8,
                // `stretch`: sem ele cada ColoredBox (sem filho) recebe altura
                // frouxa e encolhe a zero — a barra existia e não aparecia.
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (count, color) in [
                      (member.scheduleCount, colors.served),
                      (member.unavailableCount, colors.unavailable),
                      (member.freeCount, colors.free),
                    ])
                      if (count > 0)
                        Expanded(flex: count, child: ColoredBox(color: color)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
