import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/date/civil_date.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/app_choice_bar.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_month_grid.dart';
import '../../../shared/widgets/app_states.dart';
import '../../auth/application/auth_controller.dart';
import '../../events/data/event_repository.dart';
import '../../events/domain/event_datetime.dart';
import '../../team/data/team_repository.dart';
import '../data/unavailability_repository.dart';
import '../domain/unavailability_models.dart';
import 'unavailability_summary_view.dart';

/// O mês da equipe: quem avisou que não pode, e em que dia.
///
/// A indisponibilidade já existia dos dois lados — o integrante marcava os dias
/// e a escala mostrava o aviso —, mas só **dentro** de uma escala já criada. O
/// líder que planeja o mês descobria a ausência tarde: depois de escalar. Aqui
/// ele vê o mês antes de montar qualquer coisa.
///
/// Para quem lidera há uma segunda aba, **"Por pessoa"**
/// ([UnavailabilitySummaryView]): quem mais avisou que não podia num período,
/// e quem ficou livre sem ser chamado.
class TeamUnavailabilityScreen extends ConsumerStatefulWidget {
  const TeamUnavailabilityScreen({super.key, required this.teamId});

  final String teamId;

  @override
  ConsumerState<TeamUnavailabilityScreen> createState() =>
      _TeamUnavailabilityScreenState();
}

/// As duas leituras: o mês (quem não pode em cada dia) e a pessoa (quem mais
/// avisou, quem ficou livre sem ser chamado).
enum _View { calendar, people }

class _TeamUnavailabilityScreenState
    extends ConsumerState<TeamUnavailabilityScreen> {
  late DateTime _month = _monthOf(DateTime.now());
  _View _view = _View.calendar;

  /// Nulo = a equipe inteira. Com alguém escolhido, o calendário responde
  /// "quando o João não pode?", que é a pergunta de quem já sabe de quem
  /// precisa e procura o domingo em que ele está livre.
  String? _memberFilter;

  static DateTime _monthOf(DateTime date) => DateTime(date.year, date.month);

  void _shiftMonth(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
  }

  @override
  Widget build(BuildContext context) {
    final key = (
      teamId: widget.teamId,
      year: _month.year,
      month: _month.month,
    );
    final unavailability = ref.watch(teamUnavailabilityProvider(key));
    final members = ref.watch(membersProvider(widget.teamId)).valueOrNull;
    // "Por pessoa" cruza as ausências com as escalas, e isso é relatório:
    // só quem lidera lê (a API responde 403 para o resto). O calendário
    // continua de todos.
    final canManage = ref
            .watch(authControllerProvider)
            .teams
            .where((team) => team.teamId == widget.teamId)
            .firstOrNull
            ?.canManage ??
        false;
    final view = canManage ? _view : _View.calendar;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quem não pode'),
        actions: [
          if (view == _View.calendar && members != null && members.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Filtrar por pessoa',
              icon: Icon(
                _memberFilter == null
                    ? Icons.filter_alt_outlined
                    : Icons.filter_alt_rounded,
              ),
              onSelected: (value) => setState(
                () => _memberFilter = value.isEmpty ? null : value,
              ),
              itemBuilder: (_) => [
                const PopupMenuItem(value: '', child: Text('Todo mundo')),
                for (final member in members)
                  PopupMenuItem(
                    value: member.id,
                    child: Text(member.displayName),
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
              if (canManage)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.md,
                    AppSpacing.screenPadding,
                    0,
                  ),
                  child: AppChoiceBar<_View>(
                    expanded: true,
                    value: view,
                    onChanged: (value) => setState(() => _view = value),
                    options: const [
                      AppChoice(
                        value: _View.calendar,
                        label: 'Calendário',
                        icon: Icons.calendar_month_rounded,
                      ),
                      AppChoice(
                        value: _View.people,
                        label: 'Por pessoa',
                        icon: Icons.people_alt_rounded,
                      ),
                    ],
                  ),
                ),
              if (view == _View.people)
                Expanded(
                  child: UnavailabilitySummaryView(teamId: widget.teamId),
                )
              else ...[
                _MonthHeader(
                  month: _month,
                  onPrevious: () => _shiftMonth(-1),
                  onNext: () => _shiftMonth(1),
                ),
                Expanded(
                  child: unavailability.when(
                    loading: () => const AppLoading(),
                    error: (error, _) => AppErrorState(
                      message: error is ApiException
                          ? error.message
                          : 'Não foi possível carregar o calendário.',
                      onRetry: () =>
                          ref.invalidate(teamUnavailabilityProvider(key)),
                    ),
                    data: (all) {
                      final visible = _memberFilter == null
                          ? all
                          : all
                              .where(
                                (item) => item.membershipId == _memberFilter,
                              )
                              .toList();
                      return _MonthBody(
                        teamId: widget.teamId,
                        month: _month,
                        items: visible,
                        filteredName: _memberFilter == null
                            ? null
                            : members
                                ?.where((m) => m.id == _memberFilter)
                                .firstOrNull
                                ?.displayName,
                        onRefresh: () async =>
                            ref.refresh(teamUnavailabilityProvider(key).future),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = monthYearLabel(month);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        0,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Mês anterior',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'Próximo mês',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _MonthBody extends StatelessWidget {
  const _MonthBody({
    required this.teamId,
    required this.month,
    required this.items,
    required this.filteredName,
    required this.onRefresh,
  });

  final String teamId;
  final DateTime month;
  final List<Unavailability> items;

  /// Nome de quem está filtrado, para o vazio dizer de quem ele fala.
  final String? filteredName;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final byDay = <int, List<Unavailability>>{};
    for (final item in items) {
      if (item.date.year != month.year || item.date.month != month.month) {
        continue;
      }
      byDay.putIfAbsent(item.date.day, () => []).add(item);
    }

    final today = DateTime.now();

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          // A mesma grade da agenda: dia com alguém que não pode é o dia
          // pintado, em âmbar, com um traço por pessoa. Era um círculo com o
          // número embaixo — um terceiro desenho de calendário no app.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: AppMonthGrid(
              month: month,
              today: DateTime(today.year, today.month, today.day),
              keyPrefix: 'quem-nao-pode-',
              describe: (day) {
                final count = (byDay[day.day] ?? const []).length;
                return AppMonthDay(
                  marks: day.month == month.month ? count : 0,
                  markTone: AppTone.warning,
                  detail: count == 0
                      ? 'ninguém avisou que não pode'
                      : count == 1
                          ? '1 pessoa não pode'
                          : '$count pessoas não podem',
                );
              },
              onTap: (day) {
                final people = byDay[day.day] ?? const <Unavailability>[];
                if (people.isNotEmpty) _openDay(context, day, people);
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (byDay.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
              ),
              child: Text(
                filteredName == null
                    ? 'Ninguém avisou indisponibilidade neste mês.'
                    : '$filteredName não marcou nenhum dia neste mês.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            // A lista abaixo do calendário não é repetição: a grade responde
            // "quais domingos estão comprometidos?" de relance, e a lista
            // responde "quem, e por quê?" sem exigir um toque por dia.
            for (final day in byDay.keys.toList()..sort())
              _DaySummary(
                day: DateTime(month.year, month.month, day),
                people: byDay[day]!,
                onTap: () => _openDay(
                  context,
                  DateTime(month.year, month.month, day),
                  byDay[day]!,
                ),
              ),
        ],
      ),
    );
  }

  void _openDay(
    BuildContext context,
    DateTime day,
    List<Unavailability> people,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _DaySheet(teamId: teamId, day: day, people: people),
    );
  }
}

class _DaySummary extends StatelessWidget {
  const _DaySummary({
    required this.day,
    required this.people,
    required this.onTap,
  });

  final DateTime day;
  final List<Unavailability> people;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xs,
      ),
      title: Text(
        capitalizeWeekday(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(day)),
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Text(
        people.map((person) => person.displayName ?? 'Alguém').join(', '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

class _DaySheet extends ConsumerWidget {
  const _DaySheet({
    required this.teamId,
    required this.day,
    required this.people,
  });

  final String teamId;
  final DateTime day;
  final List<Unavailability> people;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // A escala que já existe neste dia, se existe: o botão leva a ela em vez
    // de propor criar outra.
    final escalas = [
      for (final scope in ['upcoming', 'past'])
        ...?ref.watch(eventsProvider((teamId, scope))).valueOrNull?.data,
    ];
    final existente = escalas.where((event) {
      final local = eventLocalTime(
        event.startsAt,
        event.timezone.isEmpty ? 'America/Sao_Paulo' : event.timezone,
      );
      return local.year == day.year &&
          local.month == day.month &&
          local.day == day.day;
    }).firstOrNull;
    final scheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              capitalizeWeekday(
                DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(day),
              ),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              people.length == 1
                  ? '1 pessoa avisou que não pode'
                  : '${people.length} pessoas avisaram que não podem',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final person in people)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: AppAvatar(
                  name: person.displayName ?? '?',
                  radius: 18,
                ),
                title: Text(person.displayName ?? 'Alguém'),
                subtitle: person.reason == null ? null : Text(person.reason!),
              ),
            // A folha responde "quem não pode neste dia" e para aí. Propor
            // criar escala a partir de uma ausência era estranho: quem abre o
            // dia veio consultar, não montar. Se já existe escala, o atalho
            // para ela fica — é a pergunta seguinte natural (quem está nela).
            if (existente != null) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/agenda/${existente.id}');
                },
                icon: const Icon(Icons.event_note_rounded, size: 18),
                label: const Text('Ver escala'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
