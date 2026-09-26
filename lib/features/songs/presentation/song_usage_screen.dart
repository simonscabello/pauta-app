import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/date/report_period.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_pressable.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/report_filters.dart';
import '../data/song_repository.dart';
import '../domain/song_usage.dart';

/// Como a lista é ordenada — e as duas perguntas que ela responde.
enum _UsageOrder {
  /// "O que a gente mais canta?" — o retrato do repertório de verdade, que
  /// costuma ser bem menor do que o acervo cadastrado.
  mostPlayed,

  /// "O que a gente não canta há tempo?" — a pergunta de quem monta o culto e
  /// não quer repetir as mesmas cinco músicas do mês passado.
  longestAgo,
}

/// Histórico de uso do repertório.
///
/// A informação já existia — cada escala guarda o que foi tocado —, mas só
/// dentro de cada escala, uma por uma. Quem monta o culto perguntava à memória
/// "já cantamos essa?" e "faz quanto tempo?", e a memória responde repetindo o
/// que se cantou no domingo passado.
class SongUsageView extends ConsumerStatefulWidget {
  const SongUsageView({super.key, required this.teamId});

  final String teamId;

  @override
  ConsumerState<SongUsageView> createState() => _SongUsageViewState();
}

class _SongUsageViewState extends ConsumerState<SongUsageView> {
  ReportPeriod _period = const ReportPeriodMonths(6);
  int? _weekday;
  _UsageOrder _order = _UsageOrder.mostPlayed;

  /// A última resposta que chegou: os dias da semana do filtro saem dela, e
  /// sem guardá-la o menu sumiria a cada troca de período.
  List<ReportWeekday> _weekdays = const [];

  @override
  Widget build(BuildContext context) {
    final query = (teamId: widget.teamId, period: _period, weekday: _weekday);
    final report = ref.watch(songUsageProvider(query));
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
          trailing: PopupMenuButton<_UsageOrder>(
            tooltip: 'Ordenar',
            icon: const Icon(Icons.swap_vert_rounded),
            onSelected: (value) => setState(() => _order = value),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: _UsageOrder.mostPlayed,
                checked: _order == _UsageOrder.mostPlayed,
                child: const Text('Mais cantadas'),
              ),
              CheckedPopupMenuItem(
                value: _UsageOrder.longestAgo,
                checked: _order == _UsageOrder.longestAgo,
                child: const Text('Há mais tempo'),
              ),
            ],
          ),
        ),
        Expanded(
          child: report.when(
            loading: () => const AppListSkeleton(itemCount: 8),
            error: (error, _) => AppErrorState(
              message: error is ApiException
                  ? error.message
                  : 'Não foi possível carregar o histórico.',
              onRetry: () => ref.invalidate(songUsageProvider(query)),
            ),
            data: (value) => _UsageBody(
              teamId: widget.teamId,
              report: value,
              when: [
                _period.phrase,
                if (weekdayPhrase(_weekday) case final dia?) dia,
              ].join(', '),
              order: _order,
              onRefresh: () => ref.refresh(songUsageProvider(query).future),
            ),
          ),
        ),
      ],
    );
  }
}

class _UsageBody extends StatelessWidget {
  const _UsageBody({
    required this.teamId,
    required this.report,
    required this.when,
    required this.order,
    required this.onRefresh,
  });

  final String teamId;
  final SongUsageReport report;

  /// "nos últimos 6 meses, às quintas" — o período escrito para a frase de
  /// resumo.
  final String when;
  final _UsageOrder order;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (report.songs.isEmpty) {
      return RefreshableMessage(
        onRefresh: onRefresh,
        child: const AppEmptyState(
          icon: Icons.history_rounded,
          title: 'Nenhuma música no período',
          message: 'O histórico conta as escalas publicadas que já passaram. '
              'Escolha um período maior, ou volte depois do próximo culto.',
        ),
      );
    }

    // Ordenar aqui, e não no servidor: a lista inteira já veio, e ir de novo à
    // rede só para trocar a ordem gastaria uma volta à toa.
    final songs = [...report.songs];
    if (order == _UsageOrder.longestAgo) {
      songs.sort((a, b) {
        final first = a.lastPlayedAt;
        final second = b.lastPlayedAt;
        if (first == null || second == null) return 0;
        return first.compareTo(second);
      });
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        itemCount: songs.length + 1,
        separatorBuilder: (context, index) => index == 0
            ? const SizedBox.shrink()
            : Divider(
                height: 1,
                thickness: 1,
                indent: AppSpacing.screenPadding,
                endIndent: AppSpacing.screenPadding,
                color: scheme.outlineVariant,
              ),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                0,
                AppSpacing.screenPadding,
                AppSpacing.lg,
              ),
              child: Text(
                [
                  '${songs.length} '
                      '${songs.length == 1 ? 'música cantada' : 'músicas cantadas'} '
                      '$when',
                  if (report.neverPlayedCount > 0)
                    '${report.neverPlayedCount} do repertório não entraram em '
                        'nenhuma escala do período',
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            );
          }

          return _UsageRow(teamId: teamId, usage: songs[index - 1]);
        },
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.teamId, required this.usage});

  final String teamId;
  final SongUsage usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = usage.playCount;
    final last = usage.lastPlayedAt == null
        ? null
        : DateFormat("d 'de' MMM", 'pt_BR').format(usage.lastPlayedAt!.toLocal());

    return AppPressable(
      // A tela responde "quando cantamos?"; a decisão seguinte é abrir a
      // música — ver a letra, o tom, a cifra. Sem esta ponte o líder teria de
      // procurá-la de novo no repertório, pelo nome.
      onTap: () => context.push('/equipe/musicas/${usage.songId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          usage.isHymn
                              ? '${usage.hymnRef} · ${usage.title}'
                              : usage.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (usage.isArchived) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const AppBadge(
                          label: 'Arquivada',
                          tone: AppTone.warning,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    [
                      if (last != null) 'última em $last',
                      if (usage.keys.isNotEmpty)
                        usage.keys.length == 1
                            ? 'tom ${usage.keys.first}'
                            : 'tons ${usage.keys.join(', ')}',
                      if (usage.artist != null && usage.artist!.isNotEmpty)
                        usage.artist!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              '$count×',
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
              semanticsLabel: count == 1 ? '1 escala' : '$count escalas',
            ),
          ],
        ),
      ),
    );
  }
}
