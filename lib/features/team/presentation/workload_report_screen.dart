import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_choice_bar.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../data/team_repository.dart';
import '../domain/workload_report.dart';

class WorkloadReportScreen extends ConsumerStatefulWidget {
  const WorkloadReportScreen({super.key, required this.teamId});

  final String teamId;

  @override
  ConsumerState<WorkloadReportScreen> createState() =>
      _WorkloadReportScreenState();
}

class _WorkloadReportScreenState extends ConsumerState<WorkloadReportScreen> {
  int _weeks = 8;

  @override
  Widget build(BuildContext context) {
    final query = (teamId: widget.teamId, weeks: _weeks);
    final report = ref.watch(workloadProvider(query));

    return Scaffold(
      appBar: AppBar(title: const Text('Participação da equipe')),
      body: SafeArea(
        top: false,
        child: AppContentWidth.wide(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                child: AppChoiceBar<int>(
                  value: _weeks,
                  onChanged: (value) => setState(() => _weeks = value),
                  options: const [
                    AppChoice(value: 8, label: '8 semanas'),
                    AppChoice(value: 12, label: '12 semanas'),
                    AppChoice(value: 24, label: '24 semanas'),
                  ],
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
  const _ReportBody({required this.report, required this.onRefresh});

  final WorkloadReport report;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxCount = report.members.fold<int>(
      0,
      (maximum, member) =>
          member.scheduleCount > maximum ? member.scheduleCount : maximum,
    );

    if (report.members.isEmpty) {
      return const AppEmptyState(
        icon: Icons.people_outline_rounded,
        title: 'Nenhum integrante ativo',
        message: 'A participação aparece depois que a equipe é cadastrada.',
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xxxl,
        ),
        children: [
          Text(
            'Escalas publicadas no período. Quem acumula duas funções no '
            'mesmo dia conta uma vez.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppGroup(
            dividerIndent: AppGroup.textIndent,
            children: [
              for (final member in report.members)
                _WorkloadRow(member: member, maximum: maxCount),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkloadRow extends StatelessWidget {
  const _WorkloadRow({required this.member, required this.maximum});

  final WorkloadMember member;
  final int maximum;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final warning = AppStatusColors.of(context).warning;
    final count = member.scheduleCount;
    final positions = member.positions
        .map((position) => '${position.name} ${position.count}×')
        .join(' · ');
    final last = member.lastScheduledAt == null
        ? 'não apareceu no período'
        : 'última em ${DateFormat("d 'de' MMM", 'pt_BR').format(
            member.lastScheduledAt!.toLocal(),
          )}';

    return Semantics(
      label: '${member.displayName}, $count '
          '${count == 1 ? 'escala' : 'escalas'}, $last',
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
                  child: Text(
                    member.displayName,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
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
              positions.isEmpty ? last : '$positions · $last',
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
