import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/date/report_period.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_choice_bar.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/on_leave_badge.dart';
import '../../../shared/widgets/report_filters.dart';
import '../data/team_repository.dart';
import '../domain/workload_report.dart';

/// Participação da equipe: quantas escalas cada um serviu no período.
///
/// Responde três perguntas, uma por filtro:
///
/// - **quem está segurando a equipe?** — a ordem padrão, de quem mais serviu
///   para quem menos (o ⇅ inverte: quem está sumindo);
/// - **quem tocou violão?** — o filtro de função, que traz também quem sabe
///   tocar e não tocou nenhuma vez;
/// - **e nas quintas?** — o filtro de dia da semana.
///
/// O período é o mesmo dos outros relatórios: meses, e não as semanas de antes
/// (8, 12, 24), que ninguém na equipe usava para pensar.
class WorkloadReportScreen extends ConsumerStatefulWidget {
  const WorkloadReportScreen({super.key, required this.teamId});

  final String teamId;

  @override
  ConsumerState<WorkloadReportScreen> createState() =>
      _WorkloadReportScreenState();
}

class _WorkloadReportScreenState extends ConsumerState<WorkloadReportScreen> {
  ReportPeriod _period = const ReportPeriodMonths(3);
  int? _weekday;
  WorkloadPositionOption? _position;
  WorkloadOrder _order = WorkloadOrder.most;

  /// A última resposta que chegou. Os filtros (dias da semana, funções) saem
  /// dela, e sem guardá-la eles piscariam a cada troca de período, enquanto a
  /// consulta nova carrega.
  WorkloadReport? _shown;

  @override
  Widget build(BuildContext context) {
    final query = (
      teamId: widget.teamId,
      period: _period,
      weekday: _weekday,
    );
    final report = ref.watch(workloadProvider(query));
    _shown = report.valueOrNull ?? _shown;

    final positions = [...?_shown?.positions];
    if (_position != null &&
        !positions.any((p) => p.positionId == _position!.positionId)) {
      positions.add(_position!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Participação da equipe'),
        actions: [
          PopupMenuButton<WorkloadOrder>(
            tooltip: 'Ordenar',
            icon: const Icon(Icons.swap_vert_rounded),
            onSelected: (value) => setState(() => _order = value),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: WorkloadOrder.most,
                checked: _order == WorkloadOrder.most,
                child: const Text('Quem mais serviu primeiro'),
              ),
              CheckedPopupMenuItem(
                value: WorkloadOrder.least,
                checked: _order == WorkloadOrder.least,
                child: const Text('Quem menos serviu primeiro'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: AppContentWidth.wide(
          child: Column(
            children: [
              ReportFilterBar(
                filters: [
                  ReportPeriodMenu(
                    value: _period,
                    onChanged: (value) => setState(() => _period = value),
                  ),
                  ReportWeekdayMenu(
                    value: _weekday,
                    weekdays: _shown?.weekdays ?? const [],
                    onChanged: (value) => setState(() => _weekday = value),
                  ),
                ],
              ),
              if (positions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    0,
                    AppSpacing.screenPadding,
                    AppSpacing.md,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AppChoiceBar<String>(
                      value: _position?.positionId ?? '',
                      onChanged: (id) => setState(
                        () => _position = id.isEmpty
                            ? null
                            : positions.firstWhere((p) => p.positionId == id),
                      ),
                      options: [
                        const AppChoice(value: '', label: 'Todas as funções'),
                        for (final position in positions)
                          AppChoice(
                            value: position.positionId,
                            label: position.name,
                          ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: report.when(
                  loading: () => const AppListSkeleton(itemCount: 6),
                  error: (error, _) => AppErrorState(
                    message: error is ApiException
                        ? error.message
                        : 'Não foi possível carregar a participação.',
                    onRetry: () => ref.invalidate(workloadProvider(query)),
                  ),
                  data: (value) => _ReportBody(
                    report: value,
                    period: _period,
                    position: _position,
                    order: _order,
                    onRefresh: () =>
                        ref.refresh(workloadProvider(query).future),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.report,
    required this.period,
    required this.position,
    required this.order,
    required this.onRefresh,
  });

  final WorkloadReport report;
  final ReportPeriod period;
  final WorkloadPositionOption? position;
  final WorkloadOrder order;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (report.members.isEmpty) {
      return const AppEmptyState(
        icon: Icons.people_outline_rounded,
        title: 'Nenhum integrante ativo',
        message: 'A participação aparece depois que a equipe é cadastrada.',
      );
    }

    final when = [
      period.phrase,
      if (weekdayPhrase(report.weekday) case final dia?) dia,
    ].join(', ');
    if (report.scheduleTotal == 0) {
      return RefreshableMessage(
        onRefresh: onRefresh,
        child: AppEmptyState(
          icon: Icons.event_busy_rounded,
          title: 'Nenhuma escala no período',
          message: 'Não há escala publicada $when. A participação conta as '
              'escalas publicadas que já passaram.',
        ),
      );
    }

    final rows = workloadRows(
      report,
      positionId: position?.positionId,
      order: order,
    );
    final maxCount = rows.fold<int>(
      0,
      (maximum, row) => row.count > maximum ? row.count : maximum,
    );
    final total = report.scheduleTotal;
    final summary = position == null
        ? '$total ${total == 1 ? 'escala publicada' : 'escalas publicadas'} '
            '$when. Quem acumula duas funções no mesmo dia conta uma vez.'
        : 'Quantas vezes cada um serviu em ${position!.name}, entre as $total '
            '${total == 1 ? 'escala' : 'escalas'} $when. Entra também quem '
            'tem a função no cadastro e não apareceu nela.';

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
            summary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (rows.isEmpty)
            Text(
              'Ninguém tem ${position?.name ?? 'esta função'} no cadastro nem '
              'serviu nela no período.',
              style: theme.textTheme.bodyMedium,
            )
          else
            AppGroup(
              dividerIndent: AppGroup.textIndent,
              children: [
                for (final row in rows)
                  _WorkloadRow(
                    row: row,
                    maximum: maxCount,
                    position: position,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _WorkloadRow extends StatelessWidget {
  const _WorkloadRow({
    required this.row,
    required this.maximum,
    required this.position,
  });

  final WorkloadRow row;
  final int maximum;
  final WorkloadPositionOption? position;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final warning = AppStatusColors.of(context).warning;
    final member = row.member;
    final count = row.count;
    final last = row.lastScheduledAt == null
        ? position == null
            ? 'não apareceu no período'
            : 'não apareceu em ${position!.name} no período'
        : 'última em ${DateFormat("d 'de' MMM", 'pt_BR').format(
            row.lastScheduledAt!.toLocal(),
          )}';
    // Sem filtro, as funções da pessoa; com filtro, a função já está no
    // título da tela, e repetir "Violão 3×" em toda linha seria eco.
    final positions = position != null
        ? ''
        : member.positions
            .map((position) => '${position.name} ${position.count}×')
            .join(' · ');
    // O motivo de um número baixo: não pôde, ou pôde e ninguém chamou? A
    // resposta inteira mora na aba "Por pessoa" do "Quem não pode"; aqui
    // fica o que explica a linha.
    final detail = [
      if (positions.isNotEmpty) positions,
      last,
      if (member.unavailableCount > 0) 'não pôde em ${member.unavailableCount}',
    ].join(' · ');

    return Semantics(
      label: '${member.displayName}, $count '
          '${count == 1 ? 'escala' : 'escalas'}, $detail',
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
                // O nome e o selo ocupam o que sobra, e o número fica na
                // ponta: com um `Spacer` ao lado de um `Flexible`, os dois
                // dividiam a folga e o número parava no meio da linha.
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
                  '$count ${count == 1 ? 'escala' : 'escalas'}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: count == 0 ? warning.foreground : scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              child: Container(
                height: 6,
                color: scheme.surfaceContainerHigh,
                alignment: Alignment.centerLeft,
                child: maximum == 0
                    ? null
                    : FractionallySizedBox(
                        widthFactor: count / maximum,
                        // Sem isto a barra tinha largura e altura zero: dentro
                        // de um Container com `alignment`, o filho ganha
                        // restrição frouxa, e o ColoredBox encolhe até nada.
                        heightFactor: 1,
                        child: ColoredBox(
                          color:
                              count == 0 ? warning.foreground : scheme.primary,
                        ),
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
