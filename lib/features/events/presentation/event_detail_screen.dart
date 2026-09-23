import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../onboarding/domain/member_tour.dart';
import '../../onboarding/presentation/tour_target.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_bottom_action_bar.dart';
import '../../../shared/widgets/app_button_styles.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_detail_header.dart';
import '../../../shared/widgets/app_facts_strip.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_notice.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/cache_stamp_banner.dart';
import '../../../shared/widgets/position_icon.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/share_action.dart';
import '../../../shared/widgets/unavailable_badge.dart';
import '../../../shared/widgets/you_highlight.dart';
import '../../auth/application/auth_controller.dart';
import '../data/event_repository.dart';
import '../domain/event_datetime.dart';
import '../domain/event_models.dart';
import '../domain/schedule_share_text.dart';
import '../../suggestions/presentation/suggest_song_sheet.dart';
import '../../unavailability/domain/unavailability_models.dart';
import 'duplicate_event_dialog.dart';
import 'event_song_sheet.dart';

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(eventProvider(eventId));
    final teams = ref.watch(authControllerProvider).teams;

    return eventAsync.when(
      loading: () => const Scaffold(body: AppLoading()),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Escala')),
        body: AppErrorState(
          message: error is ApiException
              ? error.message
              : 'Não foi possível carregar a escala.',
          onRetry: () => ref.invalidate(eventProvider(eventId)),
        ),
      ),
      data: (cached) {
        final event = cached.data;
        // Permissao e identidade vem da equipe DO CULTO, nao da primeira da
        // lista: quem participa de mais de uma equipe veria o menu de lider
        // num culto onde e apenas membro.
        final myTeam = teams.where((t) => t.teamId == event.teamId).firstOrNull;
        final myMembershipId = myTeam?.membershipId;
        final canManage = myTeam?.canManage ?? false;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Escala'),
            actions: [
              if (!event.isDraft)
                IconButton(
                  tooltip: 'Compartilhar escala',
                  onPressed: () =>
                      shareText(context, buildScheduleShareText(event)),
                  icon: const Icon(Icons.share_outlined),
                ),
              if (canManage)
                PopupMenuButton<String>(
                  tooltip: 'Mais opções desta escala',
                  onSelected: (value) async {
                    switch (value) {
                      case 'edit':
                        context.push('/agenda/${event.id}/editar');
                      case 'duplicate':
                        await showDuplicateEventDialog(
                          context: context,
                          ref: ref,
                          source: event,
                        );
                      case 'unpublish':
                        await _confirmUnpublish(context, ref, event);
                      case 'delete':
                        await _confirmDelete(context, ref, event);
                    }
                  },
                  // Sem "Escalar equipe": a ação está no bloco da equipe, no
                  // lugar onde a falta é percebida, e repeti-la aqui era a
                  // mesma porta em dois cantos.
                  itemBuilder: (menuContext) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Editar dia e horários'),
                    ),
                    if (FeatureFlags.duplicateSchedule)
                      const PopupMenuItem(
                        value: 'duplicate',
                        child: Text('Duplicar escala'),
                      ),
                    if (!event.isDraft)
                      const PopupMenuItem(
                        value: 'unpublish',
                        child: Text('Voltar a rascunho'),
                      ),
                    // Em vermelho: é a única opção destrutiva do menu e estava
                    // com o mesmo peso visual das outras.
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Excluir escala',
                        style: TextStyle(
                          color: Theme.of(menuContext).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          // Sem `SafeArea` o fim da lista ficava embaixo dos botoes de
          // navegacao do Android. Esta tela nao tem barra inferior propria,
          // entao ninguem estava consumindo o recuo do sistema.
          body: SafeArea(
            top: false,
            child: AppContentWidth.reading(
              child: RefreshIndicator(
                onRefresh: () => ref.refresh(eventProvider(eventId).future),
                child: _EventDetailBody(
                  event: event,
                  myMembershipId: myMembershipId,
                  canManage: canManage,
                  fromCache: cached.fromCache,
                  cachedAt: cached.cachedAt,
                ),
              ),
            ),
          ),
          bottomNavigationBar:
              canManage && event.isDraft ? _PublishBar(event: event) : null,
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Event event,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Excluir escala?',
      message: 'A escala de ${event.describe()} será removida para toda a '
          'equipe. Não dá para desfazer.',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(eventRepositoryProvider).remove(event.id);
      ref.invalidate(eventsProvider((event.teamId, 'upcoming')));
      ref.invalidate(eventsProvider((event.teamId, 'past')));
      ref.invalidate(eventProvider(event.id));
      if (context.mounted) {
        context.pop();
        showAppSnackBar(context, 'Escala excluída.', tone: AppTone.success);
      }
    } on ApiException catch (error) {
      if (!context.mounted) return;
      showAppSnackBar(context, error.message, tone: AppTone.danger);
    }
  }

  Future<void> _confirmUnpublish(
    BuildContext context,
    WidgetRef ref,
    Event event,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Voltar a rascunho?',
      message: 'A equipe deixa de ver esta escala até você publicá-la de novo.',
      confirmLabel: 'Voltar a rascunho',
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(eventRepositoryProvider).unpublish(event.id);
      ref.invalidate(eventProvider(event.id));
      ref.invalidate(eventsProvider((event.teamId, 'upcoming')));
      ref.invalidate(eventsProvider((event.teamId, 'past')));
      if (context.mounted) {
        showAppSnackBar(
          context,
          'A escala voltou a ser rascunho.',
          tone: AppTone.warning,
        );
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        showAppSnackBar(context, error.message, tone: AppTone.danger);
      }
    }
  }
}

class _PublishBar extends ConsumerStatefulWidget {
  const _PublishBar({required this.event});

  final Event event;

  @override
  ConsumerState<_PublishBar> createState() => _PublishBarState();
}

class _PublishBarState extends ConsumerState<_PublishBar> {
  bool _publishing = false;

  /// Ver [kArrivalTapShield]: o fim da criação desemboca aqui, e o "Salvar e
  /// ver a escala" da tela anterior ficava exatamente sobre o "Publicar".
  final DateTime _montadaEm = DateTime.now();

  Future<void> _publish() async {
    if (DateTime.now().difference(_montadaEm) < kArrivalTapShield) return;
    // A barra some ao publicar (a escala deixa de ser rascunho), e o toque em
    // "Compartilhar" chega depois disso: a ação usa o contexto de quem mostra
    // o aviso, que continua de pé.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _publishing = true);
    try {
      await ref.read(eventRepositoryProvider).publish(widget.event.id);
      ref.invalidate(eventProvider(widget.event.id));
      ref.invalidate(eventsProvider((widget.event.teamId, 'upcoming')));
      ref.invalidate(eventsProvider((widget.event.teamId, 'past')));
      if (mounted) {
        showAppSnackBar(
          context,
          // Publicar sem repertório é caminho normal, e não descuido: a
          // confirmação diz o que a equipe recebeu e o que ainda vem. No modo
          // "na hora" `hasNoSongs` é falso de propósito -- não vem nada
          // depois, e prometer músicas seria desdizer o que a própria pessoa
          // acabou de escolher.
          widget.event.hasNoSongs
              ? 'Escala publicada. A equipe já sabe quem está escalado; '
                  'as músicas você escolhe depois.'
              : 'Escala publicada para a equipe.',
          tone: AppTone.success,
          // O passo seguinte natural: agora sim o ícone de compartilhar
          // existe, e o texto pode ir para o grupo.
          action: SnackBarAction(
            label: 'Compartilhar',
            onPressed: () => shareText(
              messenger.context,
              buildScheduleShareText(widget.event),
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        showAppSnackBar(context, error.message, tone: AppTone.danger);
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  /// O que a barra diz acima do botão.
  ///
  /// Repertório em aberto não é mais pendência de publicação, e a frase
  /// precisa dizer as duas coisas de uma vez: **dá** para publicar, e as
  /// músicas ainda não estão lá. Dizer só "pronta" esconderia da liderança
  /// o que ela mesma vai precisar terminar.
  String _resumo(List<String> blockers) {
    if (blockers.isNotEmpty) return 'Falta ${blockers.join(' e ')}';

    // `servicesWithoutSongs` já vem vazio no modo "na hora": a barra diz
    // "pronta" porque a escala **está** pronta -- não falta nada que alguém
    // ainda vá fazer.
    final semRepertorio = widget.event.servicesWithoutSongs;
    if (semRepertorio.isEmpty) return 'Pronta para a equipe';
    if (widget.event.hasNoSongs) {
      return 'Dá para publicar; as músicas podem vir depois';
    }
    return 'Dá para publicar; falta o repertório '
        'de ${semRepertorio.join(' e ')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final blockers = widget.event.publicationBlockers;

    return AppBottomActionBar(
      sideBySideFrom: 0,
      leading: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppBadge(label: 'Rascunho', tone: AppTone.warning),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _resumo(blockers),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      action: FilledButton(
        onPressed: _publishing ? null : _publish,
        child: _publishing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Publicar'),
      ),
    );
  }
}

class _EventDetailBody extends StatelessWidget {
  const _EventDetailBody({
    required this.event,
    required this.myMembershipId,
    required this.canManage,
    required this.fromCache,
    required this.cachedAt,
  });

  final Event event;
  final String? myMembershipId;
  final bool canManage;
  final bool fromCache;
  final DateTime? cachedAt;

  @override
  Widget build(BuildContext context) {
    final timezone =
        event.timezone.isEmpty ? 'America/Sao_Paulo' : event.timezone;
    final youPositions = event.personalRolesFor(myMembershipId);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        if (fromCache && cachedAt != null)
          CacheStampBanner(cachedAt: cachedAt!),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.lg,
            AppSpacing.screenPadding,
            AppSpacing.xxxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A identidade da escala — data, título, horários, "você" — no
              // mesmo cartão de manchete da agenda. As duas telas mostram a
              // mesma coisa e precisam mostrá-la igual: abrir a escala não deve
              // reapresentar o que a agenda já disse, num formato diferente.
              _EventHeader(
                event: event,
                timezone: timezone,
                youPositions: youPositions,
              ),
              const SizedBox(height: AppSpacing.xl),
              // **Conflito antes de tudo.** A faixa ficava abaixo das músicas,
              // no meio da página, e mandava procurar "Editar" na equipe; agora
              // é a primeira coisa depois do cabeçalho, com a ação na própria
              // faixa.
              if (event.warnings.unavailableAssigned.isNotEmpty) ...[
                _UnavailableWarningBand(
                  event: event,
                  people: event.warnings.unavailableAssigned,
                  canManage: canManage,
                  myMembershipId: myMembershipId,
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
              _EventNotes(event: event),
              // **O repertório vem antes da equipe.** É o que traz o músico a
              // esta tela — a cifra, o tom, a ordem —, e atrás da manchete e
              // da lista de nomes ele começava fora da tela. "Onde eu entro"
              // já está respondido na faixa de fatos do topo.
              TourTarget(
                id: TourTargetIds.eventSongs,
                child: _SongsSection(event: event, canManage: canManage),
              ),
              const SizedBox(height: AppSpacing.xl),
              _TeamSection(
                event: event,
                canManage: canManage,
                myMembershipId: myMembershipId,
              ),
              const SizedBox(height: AppSpacing.xl),
              // Para a equipe inteira, e não dentro do menu de quem lidera:
              // "quem me tirou da escala?" é pergunta de quem foi tirado.
              _HistoryLink(eventId: event.id),
            ],
          ),
        ),
      ],
    );
  }
}

/// Porta do histórico, discreta e no fim da tela: ela não compete com a
/// escala em si, que é o que se abre para ver.
class _HistoryLink extends StatelessWidget {
  const _HistoryLink({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => context.push('/agenda/$eventId/historico'),
        icon: const Icon(Icons.history_rounded, size: 18),
        label: const Text('Histórico de alterações'),
        style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// O cabeçalho da escala: a data, e a faixa com o que se pergunta primeiro.
///
/// **No modelo da tela da música, e não da manchete da Home.** A escala abria
/// com o mesmo cartão violeta da Home — quem tocava na manchete de lá chegava
/// numa tela que repetia a manchete. A justificativa era a continuidade com a
/// manchete da agenda, que deixou de existir quando a agenda virou calendário.
///
/// A data é o título; o nome especial ("Páscoa") e o local ficam embaixo; e a
/// faixa de fatos responde, na ordem, **quando é o culto, quando é o ensaio e
/// onde você entra** — a frase "Domingo 09h, você, guitarra, ensaio sábado 19h"
/// que é a razão de o app existir. Sem você na escala, a coluna não existe.
class _EventHeader extends StatelessWidget {
  const _EventHeader({
    required this.event,
    required this.timezone,
    required this.youPositions,
  });

  final Event event;
  final String timezone;
  final List<String> youPositions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final hasLocation = event.location?.isNotEmpty ?? false;
    final services = event.displayServices;
    final rehearsalAt = event.rehearsalAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDetailHeader(
          title: formatEventWeekdayDate(event.startsAt, timezone),
          lines: [
            if (event.hasTitle)
              Text(
                event.title!,
                style: theme.textTheme.titleMedium?.copyWith(color: muted),
              ),
            // Fora de etiqueta: um endereço longo tem a largura toda e corta
            // com "…" em vez de estourar.
            if (hasLocation)
              DetailMetaLine(
                icon: Icons.location_on_outlined,
                text: event.location!,
                maxLines: 1,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppFactsStrip(
          facts: [
            if (services.length <= 1)
              AppFact(
                icon: Icons.church_rounded,
                label: services.isEmpty ? 'Culto' : services.first.label,
                value: formatEventTime(
                  services.isEmpty ? event.startsAt : services.first.startsAt,
                  timezone,
                ),
              )
            else
              AppFact(
                icon: Icons.church_rounded,
                label: 'Cultos',
                // Uma linha por culto, com a hora alinhada: é a pergunta de
                // quem abre a escala, e comparar 08:30 com 19:00 é de relance.
                // Cada linha encolhe em vez de quebrar: nenhum culto some.
                value: [
                  for (final service in services)
                    '${service.label} '
                        '${formatEventTime(service.startsAt, timezone)}',
                ].join('\n'),
              ),
            AppFact(
              icon: Icons.schedule_rounded,
              label: 'Ensaio',
              value: rehearsalAt == null
                  ? 'Sem ensaio'
                  : formatRehearsalTime(rehearsalAt, event.startsAt, timezone),
              wrapValue: true,
            ),
            if (youPositions.isNotEmpty)
              AppFact(
                icon: Icons.star_rounded,
                label: 'Sua função',
                value: youPositions.join(' · '),
                highlight: true,
                wrapValue: true,
                // "Ministra · Vocal · Violão" numa coluna de celular precisa
                // de três linhas; com duas, a última função saía cortada.
                maxLines: 3,
              ),
          ],
        ),
      ],
    );
  }
}

/// Paleta de roupas e observações do líder.
///
/// Saíram do cartão de identidade e viraram um bloco próprio: são recados sobre
/// a escala, não o que a escala **é**. Só aparecem quando existem.
///
/// A paleta vem rotulada ("Roupas: preto e dourado"). Só o ícone de paleta ao
/// lado do texto deixava a linha ambígua -- podia ser tema visual da escala,
/// e o que ela diz é como a equipe combinou de se vestir.
class _EventNotes extends StatelessWidget {
  const _EventNotes({required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final hasPalette = event.colorPalette?.isNotEmpty ?? false;
    final hasNotes = event.notes?.isNotEmpty ?? false;
    if (!hasPalette && !hasNotes) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: AppCard(
        surface: CardSurface.sunken,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasPalette)
              _MetaLine(
                icon: Icons.palette_outlined,
                text: 'Roupas: ${event.colorPalette}',
                maxLines: 2,
              ),
            if (hasPalette && hasNotes) const SizedBox(height: AppSpacing.sm),
            if (hasNotes)
              _MetaLine(
                icon: Icons.sticky_note_2_outlined,
                text: event.notes!,
                maxLines: 4,
              ),
          ],
        ),
      ),
    );
  }
}

/// Linha de apoio (paleta, observações): ícone à esquerda, texto que ocupa o
/// resto da largura.
class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.icon,
    required this.text,
    required this.maxLines,
  });

  final IconData icon;
  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            icon,
            size: 15,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

/// Destaque "onde eu apareço" — visível sem rolar.
///
/// Continua existindo como widget nomeado porque é o contrato do teste da
/// Etapa 5; a aparência agora vem do [YouHighlight] compartilhado, para o
/// destaque ser idêntico aqui e na agenda.
class YouAssignmentBanner extends StatelessWidget {
  const YouAssignmentBanner({super.key, required this.positionNames});

  final List<String> positionNames;

  @override
  Widget build(BuildContext context) =>
      YouHighlight(positionNames: positionNames);
}

/// Faixa de alerta quando alguém escalado já tinha avisado que não pode.
///
/// Fica logo acima de "Equipe escalada", e não no topo da tela: assim não
/// disputa atenção com o destaque pessoal ("VOCÊ") e aparece colada na lista
/// de nomes a que se refere.
class _UnavailableWarningBand extends StatelessWidget {
  const _UnavailableWarningBand({
    required this.event,
    required this.people,
    required this.canManage,
    required this.myMembershipId,
  });

  final Event event;
  final List<UnavailableMember> people;
  final bool canManage;
  final String? myMembershipId;

  @override
  Widget build(BuildContext context) {
    final meu = people
        .where((p) => p.membershipId == myMembershipId)
        .firstOrNull;

    // **Quem avisou lê em segunda pessoa, e em âmbar.** A Maria lia, em
    // vermelho, "Maria avisou que não pode neste dia" — sobre ela mesma, com
    // o tom de erro. O que ela precisa saber é que o recado chegou.
    if (meu != null && !canManage) {
      return AppNotice(
        tone: AppTone.warning,
        icon: Icons.event_busy_rounded,
        title: 'Você avisou que não pode neste dia',
        message: [
          if (meu.reason?.isNotEmpty ?? false) 'Motivo: ${meu.reason}.',
          'Quem lidera já foi avisado e vai achar alguém no seu lugar.',
        ].join(' '),
      );
    }

    final names = joinNames(people.map((p) => p.displayName));
    final single = people.length == 1;

    // O que cada um faz, e o motivo quando existe: é o que o líder precisa
    // para trocar sem esquecer o ministrante. Ninguém é obrigado a justificar.
    final linhas = [
      for (final p in people)
        [
          if (event.rolesPhraseFor(p.membershipId) case final funcoes?)
            '${p.displayName} $funcoes',
          if (p.reason?.isNotEmpty ?? false) '(${p.reason})',
        ].join(' '),
    ].where((linha) => linha.isNotEmpty);

    return AppNotice(
      tone: canManage ? AppTone.danger : AppTone.warning,
      icon: Icons.event_busy_rounded,
      title: single
          ? '$names avisou que não pode neste dia'
          : '$names avisaram que não podem neste dia',
      message: [
        ...linhas,
        if (!canManage) 'Quem lidera já sabe.',
      ].join('\n'),
      action: canManage
          ? Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final p in people)
                  FilledButton.tonalIcon(
                    style: AppButtonStyles.compact,
                    onPressed: () => context.push(
                      '/agenda/${event.id}/escalar?substituir=${p.membershipId}',
                    ),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: Text('Substituir ${_firstName(p.displayName)}'),
                  ),
              ],
            )
          : null,
    );
  }
}

String _firstName(String name) => name.trim().split(RegExp(r'\s+')).first;

/// Quem toca o quê nesta escala.
///
/// O vazio deixou de ser uma frase mandando procurar: dizia "O líder pode
/// montar a escala pelo menu", num app em que "o menu" são três pontinhos no
/// canto superior. **A ação principal de uma escala recém-criada é escalar a
/// equipe** — ela agora é um botão, no lugar onde a falta é percebida, com a
/// mesma forma do botão de montar o repertório logo abaixo.
class _TeamSection extends StatelessWidget {
  const _TeamSection({
    required this.event,
    required this.canManage,
    this.myMembershipId,
  });

  final Event event;
  final bool canManage;
  final String? myMembershipId;

  @override
  Widget build(BuildContext context) {
    final empty = event.assignments.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Equipe escalada',
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          trailing: canManage && !empty
              ? TextButton.icon(
                  onPressed: () => context.push('/agenda/${event.id}/escalar'),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar'),
                )
              : null,
        ),
        if (empty)
          _EmptySection(
            message: canManage
                ? 'Ninguém escalado ainda.'
                : 'A equipe desta escala ainda não foi definida.',
            action: canManage
                ? FilledButton.tonalIcon(
                    style: AppButtonStyles.compact,
                    onPressed: () =>
                        context.push('/agenda/${event.id}/escalar'),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('Escalar equipe'),
                  )
                : null,
          )
        else
          _AssignedTeamCard(
            groups: event.assignments,
            minister: event.minister,
            showRegistryBadge: canManage,
            myMembershipId: myMembershipId,
            unavailable: {
              for (final person in event.unavailable)
                person.membershipId: person.reason,
            },
          ),
      ],
    );
  }
}

/// Um bloco vazio que diz o que falta **e** oferece o caminho.
///
/// Os vazios da escala diziam "Toque em ‘Escalar’ para escolher quem toca o
/// quê" — mandando procurar um botão de texto pequeno no cabeçalho, num canto
/// que o olho não visita. A ação agora mora dentro do próprio vazio.
class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      surface: CardSurface.sunken,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}

/// A escala inteira em um cartão, com uma seção por função.
///
/// Um cartão por função gastava a tela toda para mostrar cinco nomes: cada
/// pessoa vinha embrulhada em sombra, borda e margem própria. Aqui a função
/// aparece **uma vez** como cabeçalho e as pessoas dela vêm listadas logo
/// abaixo — inclusive quando são várias, que era o caso em que "Vocalista"
/// acabava escrito duas vezes.
///
/// **Com muita gente, a lista se recolhe.** Uma escala de banda completa com
/// multimídia passa de doze pessoas, e doze linhas empurravam o repertório
/// para fora da tela — sendo que **o repertório é o que traz o músico a esta
/// tela**. Aparecem [_collapsedLimit] nomes e uma linha dizendo quantos
/// faltam; quem quer a lista inteira toca nela. O corte segue a ordem das
/// funções, então o que fica visível é o topo da escala (ministrante,
/// vocais), e não cinco nomes quaisquer.
///
/// **O recolhimento não vale para as músicas**: elas continuam inteiras, e por
/// isso o comportamento mora aqui e não numa seção genérica.
class _AssignedTeamCard extends StatefulWidget {
  const _AssignedTeamCard({
    required this.groups,
    this.minister,
    this.unavailable = const {},
    this.showRegistryBadge = false,
    this.myMembershipId,
  });

  final List<AssignmentGroup> groups;

  /// Para destacar as linhas de quem está olhando: na lista de doze nomes, o
  /// músico procura o próprio.
  final String? myMembershipId;

  /// "Fora do cadastro" é recado de gestão: diz a quem monta a escala que a
  /// pessoa não tem aquela função na ficha. Para o integrante era um alerta
  /// âmbar ao lado do próprio nome — "fui escalada errado?" — sobre algo que
  /// ele não resolve.
  final bool showRegistryBadge;

  /// Quem conduz a ministração do louvor.
  final EventMinister? minister;

  /// membershipId -> motivo (ou nulo) de quem avisou que não pode neste dia.
  final Map<String, String?> unavailable;

  @override
  State<_AssignedTeamCard> createState() => _AssignedTeamCardState();
}

class _AssignedTeamCardState extends State<_AssignedTeamCard> {
  /// Quantos nomes ficam à vista antes de "Ver mais".
  ///
  /// Cinco é o tamanho da banda mínima (ministrante, violão, baixo, bateria,
  /// vocal) — abaixo disso a escala já cabe inteira, e recolher seria esconder
  /// o que não atrapalha.
  static const int _collapsedLimit = 5;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = widget.groups;
    final total = groups.fold<int>(0, (sum, g) => sum + g.members.length);

    // Com **um** a mais que o limite, esconder essa pessoa gastaria a mesma
    // linha que mostrá-la. O corte só compensa a partir de dois — a mesma
    // conta que a pilha de avatares faz antes de escrever "+N".
    final recolhivel = total > _collapsedLimit + 1;
    final mostrando = recolhivel && !_expanded ? _collapsedLimit : total;

    // O corte atravessa os grupos: uma função pode entrar pela metade, e a
    // contagem no cabeçalho dela continua sendo a de verdade — é ela que diz
    // que ainda há gente ali embaixo.
    final sections = <Widget>[];
    var restante = mostrando;
    for (final group in groups) {
      if (restante <= 0) break;
      final visiveis = group.members.length <= restante
          ? group.members
          : group.members.take(restante).toList();
      restante -= visiveis.length;
      if (sections.isNotEmpty) {
        sections.addAll([
          const SizedBox(height: AppSpacing.md),
          Divider(color: scheme.outlineVariant, height: 1),
          const SizedBox(height: AppSpacing.md),
        ]);
      }
      sections.add(
        _AssignmentGroupSection(
          group: group,
          visibleMembers: visiveis,
          unavailable: widget.unavailable,
          showRegistryBadge: widget.showRegistryBadge,
          myMembershipId: widget.myMembershipId,
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // O ministrante fica fora da conta e sempre à vista: é uma linha só,
          // e é a primeira pergunta de quem abre a escala.
          if (widget.minister != null) ...[
            _MinisterBanner(
              name: widget.minister!.displayName,
              // Quem ministra e avisou que não pode é a ausência mais cara do
              // domingo, e a linha dele era a única sem o selo.
              isUnavailable:
                  widget.unavailable.containsKey(widget.minister!.membershipId),
              unavailableReason:
                  widget.unavailable[widget.minister!.membershipId],
            ),
            const SizedBox(height: AppSpacing.md),
            Divider(color: scheme.outlineVariant, height: 1),
            const SizedBox(height: AppSpacing.md),
          ],
          ...sections,
          if (recolhivel) ...[
            const SizedBox(height: AppSpacing.sm),
            Divider(color: scheme.outlineVariant, height: 1),
            _MoreMembersButton(
              hidden: total - mostrando,
              expanded: _expanded,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Ver mais 4 integrantes" / "Ver menos".
///
/// O número vai escrito, e não "Ver todos": quem lê precisa saber se o que
/// falta são dois nomes ou dez antes de decidir abrir — é a diferença entre um
/// toque e perder o repertório de vista.
class _MoreMembersButton extends StatelessWidget {
  const _MoreMembersButton({
    required this.hidden,
    required this.expanded,
    required this.onTap,
  });

  final int hidden;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = expanded
        ? 'Ver menos'
        : hidden == 1
            ? 'Ver mais 1 integrante'
            : 'Ver mais $hidden integrantes';

    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(
        expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
        size: 20,
      ),
      label: Text(label),
      style: TextButton.styleFrom(
        // Largura inteira: a linha inteira é o alvo, como nas listas do app.
        minimumSize: const Size.fromHeight(AppSpacing.touchTarget),
      ),
    );
  }
}

/// Quem conduz a ministracao, no topo da equipe escalada.
///
/// Linha discreta acima das funcoes: e a primeira pergunta de quem abre a
/// escala pensando "quem vai conduzir?". Sem faixa colorida — o peso vem do
/// rotulo e do icone.
class _MinisterBanner extends StatelessWidget {
  const _MinisterBanner({
    required this.name,
    this.isUnavailable = false,
    this.unavailableReason,
  });

  final String name;
  final bool isUnavailable;
  final String? unavailableReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        Icon(
          Icons.record_voice_over_rounded,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Ministrante · ',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: name,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isUnavailable) UnavailableBadge(reason: unavailableReason),
      ],
    );
  }
}

class _AssignmentGroupSection extends StatelessWidget {
  const _AssignmentGroupSection({
    required this.group,
    required this.visibleMembers,
    required this.unavailable,
    this.showRegistryBadge = false,
    this.myMembershipId,
  });

  final AssignmentGroup group;
  final String? myMembershipId;

  /// Quem desta função aparece agora. Pode ser um pedaço de [group.members]
  /// quando o cartão está recolhido — a contagem do cabeçalho continua sendo a
  /// do grupo inteiro, e é ela que avisa que há mais gente.
  final List<AssignmentMember> visibleMembers;

  final Map<String, String?> unavailable;
  final bool showRegistryBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Sem `category`: o backend so devolve o nome da funcao no grupo
            // da escala. O mapa de icones resolve pelo nome.
            // Cinza, e não violeta: é cabeçalho de grupo, e o violeta do app
            // diz "é aqui que você entra". Cinco funções em violeta faziam a
            // escala inteira gritar.
            PositionIcon(
              group.positionName,
              size: 15,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                group.positionName,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            // Com mais de uma pessoa na função, dizer quantas evita ter de
            // contar os avatares.
            if (group.members.length > 1)
              Text(
                '${group.members.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < visibleMembers.length; i++)
          _AssignedMemberRow(
            member: visibleMembers[i],
            unavailableReason: unavailable[visibleMembers[i].membershipId],
            isUnavailable:
                unavailable.containsKey(visibleMembers[i].membershipId),
            showRegistryBadge: showRegistryBadge,
            isMe: visibleMembers[i].membershipId == myMembershipId,
            isLast: i == visibleMembers.length - 1,
          ),
      ],
    );
  }
}

class _AssignedMemberRow extends StatelessWidget {
  const _AssignedMemberRow({
    required this.member,
    required this.unavailableReason,
    required this.isUnavailable,
    required this.isLast,
    this.showRegistryBadge = false,
    this.isMe = false,
  });

  final AssignmentMember member;
  final String? unavailableReason;
  final bool isUnavailable;
  final bool isLast;
  final bool showRegistryBadge;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasNote = member.note?.isNotEmpty ?? false;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // A foto da conta quando ela existe, a inicial quando não.
              // Quem monta o endereço, mostra a inicial enquanto a imagem
              // carrega e volta para ela se o carregamento falhar é o próprio
              // [AppAvatar] — a lista não pode ficar com buraco nem com ícone
              // quebrado quando a rede da igreja oscila.
              AppAvatar(
                name: member.displayName,
                imageUrl: member.avatarUrl,
                radius: 14,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  isMe ? '${member.displayName} (você)' : member.displayName,
                  style: isMe
                      ? theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        )
                      : theme.textTheme.bodyLarge,
                ),
              ),
              // A etiqueta ao lado do nome diz *quem*; a faixa acima diz que
              // há um problema. Uma sem a outra obriga a procurar.
              if (isUnavailable)
                UnavailableBadge(reason: unavailableReason)
              else if (showRegistryBadge && !member.isRegisteredForPosition)
                AppBadge(
                  label: 'Fora do cadastro',
                  tone: AppTone.warning,
                  semanticsLabel: '${member.displayName} não tem esta função '
                      'no cadastro da equipe',
                ),
            ],
          ),
          if (hasNote)
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 2),
              child: Text(
                member.note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Repertório da escala, com uma seção por culto.
///
/// O cabeçalho do culto aparece sempre, mesmo quando a escala tem um só: é o
/// que faz "3ª música" querer dizer a mesma coisa em toda escala, e é o que
/// impede o vocalista da noite de ensaiar o repertório da manhã.
///
/// O tom aparece ao lado de cada música porque é a informação que o músico
/// procura primeiro. Quando esta escala mudou o tom, ele vem destacado — a
/// mesma canção sobe ou desce conforme quem canta.
class _SongsSection extends StatelessWidget {
  const _SongsSection({required this.event, required this.canManage});

  final Event event;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final timezone =
        event.timezone.isEmpty ? 'America/Sao_Paulo' : event.timezone;
    final grupos = event.songsByService;
    final diaDoCulto = eventLocalTime(event.startsAt, timezone);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: event.songs.isEmpty
              ? 'Músicas'
              : 'Músicas (${event.songs.length})',
          // No modo "na hora" a linha de apoio é o recado principal da seção:
          // é ela que impede a lista vazia de ser lida como escala pela metade.
          subtitle: event.isRepertoireOnTheFly
              ? 'Repertório definido na hora, no culto.'
              : null,
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          // Com músicas, "Editar" no cabeçalho. Sem nenhuma, a ação mora no
          // vazio logo abaixo — menos no modo "na hora" para quem lidera, em
          // que anotar uma música continua possível mas não é convidado.
          trailing: canManage && (event.songs.isNotEmpty || event.isRepertoireOnTheFly)
              ? TextButton.icon(
                  onPressed: () => context.push(
                    '/agenda/${event.id}/repertorio',
                    extra: event,
                  ),
                  icon: Icon(
                    event.songs.isEmpty ? Icons.add_rounded : Icons.edit_outlined,
                    size: 18,
                  ),
                  label: Text(event.songs.isEmpty ? 'Anotar' : 'Editar'),
                )
              : null,
        ),
        // Escala inteira sem música: um aviso só. Repetir "sem músicas" em cada
        // culto diria a mesma coisa duas vezes e ocuparia o dobro da tela.
        if (event.songs.isEmpty)
          _EmptySection(
            message: switch ((event.isRepertoireOnTheFly, canManage)) {
              // Nada de "ainda": o "ainda" promete uma lista que não vem.
              (true, _) =>
                'As músicas desta escala são definidas na hora, no culto.',
              (false, true) => 'Nenhuma música escolhida ainda.',
              (false, false) => 'O repertório ainda não foi definido.',
            },
            action: switch ((event.isRepertoireOnTheFly, canManage)) {
              (false, true) => FilledButton.tonalIcon(
                  style: AppButtonStyles.compact,
                  onPressed: () => context.push(
                    '/agenda/${event.id}/repertorio',
                    extra: event,
                  ),
                  icon: const Icon(Icons.queue_music_rounded, size: 18),
                  label: const Text('Escolher músicas'),
                ),
              // A porta que este vazio abre para quem não lidera. A escala
              // chega à equipe com as músicas em aberto, e é aí que a sugestão
              // tem chance de ser acolhida. A data vem preenchida com a do
              // culto. Culto que já passou não oferece nada: o servidor recusa
              // sugestão com data no passado.
              (_, false) when !_jaPassou(diaDoCulto) => TextButton.icon(
                  style: AppButtonStyles.compactText,
                  onPressed: () => showSuggestSongSheet(
                    context,
                    teamId: event.teamId,
                    targetDate: diaDoCulto,
                  ),
                  icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
                  label: const Text('Sugerir uma música'),
                ),
              _ => null,
            },
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < grupos.length; i++) ...[
                  if (i > 0) ...[
                    const SizedBox(height: AppSpacing.md),
                    Divider(color: scheme.outlineVariant, height: 1),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  _ServiceSongsSection(
                    teamId: event.teamId,
                    service: grupos[i].service,
                    songs: grupos[i].songs,
                    timezone: timezone,
                    onTheFly: event.isRepertoireOnTheFly,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// O dia do culto já ficou para trás.
///
/// Comparado no relógio do aparelho de propósito, e não no fuso da igreja: é o
/// mesmo corte que o `showDatePicker` da folha de sugerir usa como `firstDate`,
/// e divergir dele deixaria o seletor abrir com uma data anterior ao próprio
/// limite.
bool _jaPassou(DateTime diaDoCulto) {
  final hoje = DateTime.now();
  return DateTime(diaDoCulto.year, diaDoCulto.month, diaDoCulto.day)
      .isBefore(DateTime(hoje.year, hoje.month, hoje.day));
}

/// Um culto e o repertório dele. Mesma forma da seção de função em "Equipe
/// escalada": o rótulo uma vez no topo, os itens listados abaixo.
class _ServiceSongsSection extends StatelessWidget {
  const _ServiceSongsSection({
    required this.teamId,
    required this.service,
    required this.songs,
    required this.timezone,
    required this.onTheFly,
  });

  final String teamId;
  final EventService service;
  final List<EventSong> songs;
  final String timezone;

  /// O repertório desta escala sai no culto. Muda o que o culto sem música
  /// diz: "falta montar" vira "é assim que vai ser".
  final bool onTheFly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.church_rounded,
              size: 15,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${service.label} '
                '${formatEventTime(service.startsAt, timezone)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (songs.length > 1)
              Text(
                '${songs.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        // Culto sem música numa escala que já tem repertório é informação, não
        // vazio: quer dizer que falta montar este aqui.
        if (songs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs, left: 23),
            child: Text(
              onTheFly
                  ? 'Definido na hora.'
                  : 'Repertório ainda não montado.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (var i = 0; i < songs.length; i++)
            _SongRow(
              teamId: teamId,
              song: songs[i],
              position: i + 1,
              serviceSongs: songs,
            ),
      ],
    );
  }
}

/// A linha de apoio da música na escala: "314 CC · Dízimos e Ofertas".
///
/// O artista continua aí, depois dos dois, e o recado por último -- a ordem é
/// a de quem procura: identificar a música, saber quando ela entra, e só então
/// o resto. Nulo quando nada disso existe, para o `ListTile` não abrir uma
/// segunda linha vazia.
String? _subtitleOf(EventSong song) {
  final partes = [
    if (song.hymnal != null) song.hymnal!.label,
    if (song.momentText != null) song.momentText!,
    if (song.artist != null && song.artist!.isNotEmpty) song.artist!,
    if (song.note != null && song.note!.isNotEmpty) song.note!,
  ];
  return partes.isEmpty ? null : partes.join(' · ');
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.teamId,
    required this.song,
    required this.position,
    this.serviceSongs = const [],
  });

  final String teamId;
  final EventSong song;
  final int position;

  /// As músicas do mesmo culto: a letra passa de uma para a outra.
  final List<EventSong> serviceSongs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasKey = song.key != null && song.key!.isNotEmpty;

    // `Material` transparente em volta: o [AppCard] é uma superfície pintada,
    // e sem isto a onda do toque ia parar no `Material` do `Scaffold`, atrás
    // do cartão — a linha da música não dava sinal nenhum de ter sido tocada,
    // justamente na linha que abre a cifra.
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        // O que faltava: o vocalista e o instrumentista viam título, tom e
        // recado, mas não alcançavam a cifra nem a letra -- que é justamente o
        // que se procura antes de tocar. Vale para MEMBER, não só para o líder.
        onTap: () => showEventSongSheet(
          context: context,
          teamId: teamId,
          song: song,
          serviceSongs: serviceSongs,
        ),
        leading: Text(
          '$position',
          style: theme.textTheme.titleSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        // A etiqueta fica ao lado do título, e não no `trailing`: ali já está o
        // tom, e dois selos disputando a mesma ponta espremiam os dois numa
        // linha que o nome da música já ocupa.
        title: Row(
          children: [
            Flexible(
              child: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            if (song.isNew) ...[
              const SizedBox(width: AppSpacing.sm),
              const AppBadge(
                label: 'Nova',
                tone: AppTone.info,
                semanticsLabel: 'Música nova: a equipe ainda não tocou esta',
              ),
            ],
          ],
        ),
        // "314 CC · Dízimos e Ofertas" -- discreto e compacto, na linha de
        // apoio. O hinário identifica a música (a igreja pede "314", não
        // "Estou Seguro"); o momento diz em que ponto do culto ela entra.
        //
        // **Sem placeholder.** A música que não tem hinário nem momento não
        // ganha um traço no lugar: a maioria das linhas é assim, e um marcador
        // de vazio em cada uma seria mais tinta que as próprias músicas.
        subtitle: _subtitleOf(song) == null
            ? null
            : Text(
                _subtitleOf(song)!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: !hasKey
            ? null
            : AppBadge(
                label: song.key!,
                tone: song.hasCustomKey ? AppTone.primary : AppTone.neutral,
                semanticsLabel: song.hasCustomKey
                    ? 'Tom desta escala: ${song.key}'
                    : 'Tom: ${song.key}',
              ),
      ),
    );
  }
}
