import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_detail_header.dart';
import '../../../shared/widgets/app_fact_list.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_states.dart';
import '../../auth/application/auth_controller.dart';
import '../../events/domain/event_datetime.dart';
import '../../team/data/team_repository.dart';
import '../data/team_event_repository.dart';
import '../domain/team_event.dart';
import 'team_event_tile.dart';

/// O evento aberto: o que é, quando, onde e o recado.
///
/// **Tela de leitura, e curta.** Não há escalação para montar nem repertório
/// para conferir — o que a pessoa veio ver é se precisa levar alguma coisa e a
/// que horas chegar.
///
/// **No modelo das outras telas de detalhe**: o nome como manchete, a faixa
/// Data · Horário logo abaixo (como Tom · Tipo · Andamento na música),
/// editar na barra e cancelar no ⋮. Antes eram dois botões no fim do corpo,
/// e o de cancelar ficava a um polegar do de editar.
class TeamEventDetailScreen extends ConsumerWidget {
  const TeamEventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evento = ref.watch(teamEventProvider(eventId));
    final teamId = ref.watch(activeTeamIdProvider);
    final auth = ref.watch(authControllerProvider);
    final canManage =
        auth.teams.where((t) => t.teamId == teamId).firstOrNull?.canManage ??
            false;
    final loaded = evento.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Evento'),
        actions: [
          if (canManage && loaded != null) ...[
            IconButton(
              tooltip: 'Editar evento',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/eventos/${loaded.id}/editar'),
            ),
            PopupMenuButton<String>(
              tooltip: 'Mais opções deste evento',
              onSelected: (_) => _cancelar(context, ref, loaded, teamId),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'cancelar',
                  child: Text('Cancelar evento'),
                ),
              ],
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: AppContentWidth.reading(
          child: evento.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => AppErrorState(
              message: error is ApiException
                  ? error.message
                  : 'Não foi possível carregar o evento.',
              onRetry: () => ref.invalidate(teamEventProvider(eventId)),
            ),
            data: (data) => _Corpo(event: data),
          ),
        ),
      ),
    );
  }

  Future<void> _cancelar(
    BuildContext context,
    WidgetRef ref,
    TeamEvent event,
    String? teamId,
  ) async {
    final confirmado = await showConfirmDialog(
      context,
      title: 'Cancelar este evento?',
      // A frase diz o que o sistema NÃO faz. Prometer que "a equipe será
      // avisada" seria mentira: só a criação notifica, e quem já leu o aviso
      // vai continuar contando com o churrasco.
      message: 'O evento sai da agenda de todo mundo, mas a equipe não '
          'recebe aviso. Avise quem precisar saber.',
      confirmLabel: 'Cancelar evento',
      cancelLabel: 'Voltar',
      destructive: true,
    );
    if (!confirmado || !context.mounted) return;

    try {
      await ref.read(teamEventRepositoryProvider).remove(event.id);
      if (teamId != null) {
        for (final scope in ['upcoming', 'past']) {
          ref.invalidate(teamEventsProvider((teamId, scope)));
        }
      }
      if (!context.mounted) return;
      showAppSnackBar(context, 'Evento cancelado.');
      context.go('/agenda');
    } on ApiException catch (error) {
      if (context.mounted) {
        showAppSnackBar(context, error.message, tone: AppTone.danger);
      }
    }
  }
}

class _Corpo extends StatelessWidget {
  const _Corpo({required this.event});

  final TeamEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.lg,
        AppSpacing.screenPadding,
        AppSpacing.xxl,
      ),
      children: [
        // O local numa linha do cabeçalho, como na escala, e não na faixa: um
        // endereço tem comprimento livre, e numa coluna de um terço da largura
        // saía cortado ("Salão principal da igreja, 2º a…").
        AppDetailHeader(
          title: event.title,
          lines: [
            if (event.hasLocation)
              DetailMetaLine(
                icon: Icons.location_on_outlined,
                text: event.location!,
                maxLines: 2,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppFactList(
          facts: [
            AppFact(
              icon: Icons.event_rounded,
              label: 'Data',
              value: formatEventDayMonth(event.startsAt, event.timezone),
              hint: capitalizeWeekday(
                formatEventWeekdayName(event.startsAt, event.timezone),
              ),
            ),
            AppFact(
              icon: Icons.schedule_rounded,
              label: 'Horário',
              value: teamEventHours(event),
            ),
          ],
        ),
        if (event.hasNotes) ...[
          const SizedBox(height: AppSpacing.xl),
          AppGroup(
            title: 'Recado',
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  event.notes!,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
