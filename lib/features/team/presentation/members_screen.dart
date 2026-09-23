import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../onboarding/domain/member_tour.dart';
import '../../onboarding/presentation/tour_target.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/responsive/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/domain/person_fields.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/contact_actions.dart';
import '../../../shared/widgets/greeting_header.dart';
import '../../../shared/widgets/on_leave_badge.dart';
import '../../../shared/widgets/position_icon.dart';
import '../../../shared/widgets/section_header.dart';
import '../../auth/application/auth_controller.dart';
import '../../invites/presentation/invite_actions.dart';
import '../../suggestions/data/suggestion_repository.dart';
import '../data/team_repository.dart';
import '../domain/team_models.dart';
import 'reset_password_action.dart';

/// A aba Equipe: as músicas da equipe e as pessoas da equipe.
///
/// O repertório abre a tela e é **visível para todo mundo**. Ele vivia dentro
/// de "Gerenciar equipe", atrás do ícone de engrenagem que só aparece para
/// líderes — de modo que o integrante que precisa achar a cifra antes do ensaio
/// não tinha caminho nenhum até ela. Quem lidera continua sendo o único que
/// escreve; isso é decidido lá dentro, e não escondendo a porta.
class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider(teamId));
    final myTeam = ref
            .watch(authControllerProvider)
            .teams
            .where((t) => t.teamId == teamId)
            .firstOrNull ??
        ref.watch(authControllerProvider).teams.firstOrNull;
    final canManage = myTeam?.canManage ?? false;
    // Um líder não redefine a senha do dono (o servidor devolve 403), então a
    // opção nem aparece para ele. Esconder é melhor que deixar tentar.
    final actorIsOwner = myTeam?.role == 'OWNER';
    final wide = AppBreakpoints.of(context).isWide;

    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      // Mesma razão da agenda: o botão flutuante é o canto que o polegar
      // alcança. Com mouse, a ação principal vai para o cabeçalho.
      floatingActionButton: canManage && !wide
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/equipe/membros/novo'),
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Adicionar'),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: AppContentWidth.wide(
          child: Column(
            children: [
              // O mesmo cabeçalho de Início e Agenda ([TabHeader]): as quatro
              // abas abrem com o título grande. Aqui era o título pequeno da
              // barra, e trocar de aba parecia trocar de app.
              TabHeader(
                title: 'Equipe',
                teamName: myTeam?.name,
                activeTeamId: teamId,
                showTeamSwitcher: !wide,
                teams: [
                  for (final item in auth.teams)
                    (id: item.teamId, name: item.name),
                ],
                onTeamChanged: (id) =>
                    ref.read(activeTeamIdProvider.notifier).select(id),
                trailing: [
                  // Uma entrada só. Antes eram dois ícones — corrente e igreja
                  // — e ninguém adivinha que "corrente" leva a convites.
                  //
                  // No monitor ele sai: a barra lateral já lista "Gerenciar
                  // equipe" com nome escrito.
                  if (canManage && !wide)
                    IconButton(
                      tooltip: 'Gerenciar equipe',
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => context.push('/equipe/gerenciar'),
                    ),
                  if (canManage && wide)
                    FilledButton.icon(
                      onPressed: () => context.push('/equipe/membros/novo'),
                      icon: const Icon(Icons.person_add_rounded, size: 18),
                      label: const Text('Adicionar integrante'),
                    ),
                ],
              ),
              Expanded(
                child: members.when(
                  loading: () =>
                      const AppListSkeleton(itemCount: 5, leadingBlock: true),
                  error: (error, _) => AppErrorState(
                    message: error is ApiException
                        ? error.message
                        : 'Não foi possível carregar a equipe.',
                    onRetry: () => ref.invalidate(membersProvider(teamId)),
                  ),
                  data: (list) => LayoutBuilder(
                    builder: (context, constraints) => RefreshIndicator(
                      onRefresh: () async =>
                          ref.refresh(membersProvider(teamId).future),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.screenPadding,
                          AppSpacing.xs,
                          AppSpacing.screenPadding,
                          wide ? AppSpacing.xxl : AppSpacing.fabClearance,
                        ),
                        children: [
                          AppGroup(
                            children: [
                              TourTarget(
                                id: TourTargetIds.teamRepertoire,
                                child: AppGroupRow(
                                  icon: Icons.library_music_outlined,
                                  title: 'Repertório',
                                  subtitle:
                                      'As músicas da equipe, com letra, cifra e tom',
                                  onTap: () => context.push('/equipe/musicas'),
                                ),
                              ),
                              // Ao lado do repertório e para todo mundo, pelo mesmo
                              // motivo dele: quem sugere é a equipe inteira, e quem
                              // sugeriu precisa ver o que aconteceu.
                              AppGroupRow(
                                icon: Icons.lightbulb_outline_rounded,
                                title: 'Sugestões',
                                subtitle:
                                    'Músicas que a equipe pediu, e por quê',
                                trailing: canManage
                                    ? _SuggestionCountBadge(teamId: teamId)
                                    : null,
                                onTap: () =>
                                    context.push('/equipe/sugestoes'),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          _Birthdays(members: list, canManage: canManage),
                          if (list.isEmpty) ...[
                            const SectionHeader(title: 'Integrantes'),
                            _NoMembers(canManage: canManage),
                          ] else if (constraints.maxWidth >= 860)
                            // A largura da **lista**, e não a da janela: com a barra
                            // lateral aberta um monitor de 1024px deixa ~700px aqui,
                            // e as quatro colunas da tabela precisam de 860 para não
                            // se espremerem. Abaixo disso a mesma equipe volta a ser
                            // a lista do celular, que continua correta.
                            _MembersTable(
                              members: list,
                              teamId: teamId,
                              canManage: canManage,
                              actorIsOwner: actorIsOwner,
                            )
                          else
                            // Uma superfície para a equipe inteira, e não um cartão
                            // por pessoa. Doze integrantes viravam doze retângulos
                            // com borda e margem própria: a tela parecia um mural de
                            // fichas soltas, quando o que existe ali é **uma** lista.
                            AppGroup(
                              title: 'Integrantes',
                              dividerIndent: AppSpacing.lg + 40 + AppSpacing.md,
                              trailing: AppBadge(
                                label: '${list.length}',
                                semanticsLabel: list.length == 1
                                    ? '1 integrante'
                                    : '${list.length} integrantes',
                              ),
                              children: [
                                for (final member in list)
                                  _MemberRow(
                                    member: member,
                                    teamId: teamId,
                                    canManage: canManage,
                                    actorIsOwner: actorIsOwner,
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
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

/// A equipe como tabela, onde há largura para isso.
///
/// **É a mesma lista, com as colunas alinhadas.** No celular cada pessoa é um
/// bloco que se lê inteiro antes de passar ao próximo; num monitor, com doze
/// integrantes, a pergunta muda: "quem toca guitarra?", "quem ainda não tem
/// conta?". Essas se respondem varrendo uma coluna, e para isso os campos
/// precisam começar sempre no mesmo x. Nenhum campo novo entrou — são os
/// mesmos do cartão, postos lado a lado.
class _MembersTable extends StatelessWidget {
  const _MembersTable({
    required this.members,
    required this.teamId,
    required this.canManage,
    required this.actorIsOwner,
  });

  final List<Member> members;
  final String teamId;
  final bool canManage;
  final bool actorIsOwner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Integrantes',
          trailing: AppBadge(
            label: '${members.length}',
            semanticsLabel: members.length == 1
                ? '1 integrante'
                : '${members.length} integrantes',
          ),
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.md,
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: scheme.surfaceContainerLow,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 260,
                      child:
                          Text('Pessoa', style: AppTypography.eyebrow(context)),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Text(
                        'Funções',
                        style: AppTypography.eyebrow(context),
                      ),
                    ),
                    // A coluna Conta é de quem convida: "Sem conta" diz a
                    // quem lidera quem ainda precisa do convite. Para o
                    // integrante era um selo âmbar sobre os colegas, que ele
                    // não tem como resolver.
                    if (canManage) ...[
                      const SizedBox(width: AppSpacing.lg),
                      SizedBox(
                        width: 150,
                        child: Text(
                          'Conta',
                          style: AppTypography.eyebrow(context),
                        ),
                      ),
                    ],
                    // Largura do menu, para o cabeçalho não desalinhar das
                    // linhas que o têm.
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              for (var i = 0; i < members.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: scheme.outlineVariant,
                  ),
                _MemberTableRow(
                  member: members[i],
                  teamId: teamId,
                  canManage: canManage,
                  actorIsOwner: actorIsOwner,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MemberTableRow extends ConsumerWidget {
  const _MemberTableRow({
    required this.member,
    required this.teamId,
    required this.canManage,
    required this.actorIsOwner,
  });

  final Member member;
  final String teamId;
  final bool canManage;
  final bool actorIsOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: () => _showMemberSheet(
        context,
        member: member,
        canManage: canManage,
      ),
      // Sem `hoverColor` o mouse não recebe resposta nenhuma numa linha que é
      // clicável — no toque o respingo basta, com cursor não.
      hoverColor: scheme.onSurface.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 260,
              child: Row(
                children: [
                  AppAvatar(
                    name: member.displayName,
                    imageUrl: member.avatarUrl,
                    radius: 18,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      member.displayName,
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (member.role != 'MEMBER') ...[
                    const SizedBox(width: AppSpacing.sm),
                    AppBadge(label: member.roleLabel),
                  ],
                  if (member.onLeave) ...[
                    const SizedBox(width: AppSpacing.sm),
                    const OnLeaveBadge(),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: member.positions.isEmpty
                  ? Text(
                      'Sem função definida',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final position in member.positions)
                          _PositionLabel(position: position),
                      ],
                    ),
            ),
            if (canManage) ...[
              const SizedBox(width: AppSpacing.lg),
              SizedBox(
                width: 150,
                child: member.hasAccount
                    ? Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Tem conta',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      )
                    // Alinhada à esquerda: solta na coluna, a pílula se
                    // esticava até a largura inteira dela.
                    : const Align(
                        alignment: Alignment.centerLeft,
                        child: AppBadge(
                          label: 'Sem conta',
                          tone: AppTone.warning,
                        ),
                      ),
              ),
            ],
            SizedBox(
              width: 48,
              child: _MemberMenu(
                member: member,
                teamId: teamId,
                canManage: canManage,
                actorIsOwner: actorIsOwner,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PositionLabel extends StatelessWidget {
  const _PositionLabel({required this.position});

  final Position position;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PositionIcon(position.name, category: position.category, size: 12),
        const SizedBox(width: 5),
        Text(position.name, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Equipe sem ninguém cadastrado.
///
/// Fica dentro da lista, e não ocupando a tela: acima dele continua havendo o
/// repertório, que é conteúdo de verdade. Um vazio de tela cheia aqui esconderia
/// uma parte funcional da aba.
class _NoMembers extends StatelessWidget {
  const _NoMembers({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      surface: CardSurface.sunken,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            canManage
                ? 'Ninguém cadastrado ainda'
                : 'A equipe ainda não tem integrantes',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            canManage
                ? 'Cadastre as pessoas para poder montar as escalas. Elas não '
                    'precisam ter conta no app.'
                : 'Quando o líder cadastrar as pessoas, elas aparecem aqui.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (canManage) ...[
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => context.push('/equipe/membros/novo'),
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: const Text('Adicionar integrante'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Uma pessoa, como linha do grupo.
class _MemberRow extends ConsumerWidget {
  const _MemberRow({
    required this.member,
    required this.teamId,
    required this.canManage,
    required this.actorIsOwner,
  });

  final Member member;
  final String teamId;
  final bool canManage;
  final bool actorIsOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      // Tocar na pessoa responde para todo mundo: abre o contato (e "Editar"
      // para quem lidera). Antes, para o integrante, a linha não fazia nada e
      // WhatsApp e Ligar ficavam escondidos no ⋮.
      onTap: () => _showMemberSheet(
        context,
        member: member,
        canManage: canManage,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        leading: AppAvatar(
          name: member.displayName,
          imageUrl: member.avatarUrl,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                member.displayName,
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (member.role != 'MEMBER') ...[
              const SizedBox(width: AppSpacing.sm),
              AppBadge(label: member.roleLabel),
            ],
            // A versão curta: a longa ("Em afastamento · até 12 de março ·
            // licença") dividia a linha com o nome e o espremia num celular
            // estreito. A previsão e o motivo ficam na ficha.
            if (member.onLeave) ...[
              const SizedBox(width: AppSpacing.sm),
              const OnLeaveBadge(),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Antes era "Vocalista, Violao" em texto corrido. Com o icone na
            // frente de cada uma da para saber o que a pessoa faz sem ler a
            // linha inteira -- que e o que se faz ao procurar alguem na lista.
            if (member.positions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final position in member.positions)
                      _PositionLabel(position: position),
                  ],
                ),
              ),
            if (!member.hasAccount)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Ainda sem conta no app',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        trailing: _MemberMenu(
          member: member,
          teamId: teamId,
          canManage: canManage,
          actorIsOwner: actorIsOwner,
        ),
      ),
    );
  }
}

/// O que quem lidera faz com uma pessoa, nas duas arrumações: editar,
/// convidar, redefinir senha, remover. Falar com ela é de todo mundo, e mora
/// na folha que abre ao tocar na linha ([_showMemberSheet]).
///
/// O menu some quando não sobra nada para oferecer, em vez de abrir vazio.
class _MemberMenu extends ConsumerWidget {
  const _MemberMenu({
    required this.member,
    required this.teamId,
    required this.canManage,
    required this.actorIsOwner,
  });

  final Member member;
  final String teamId;
  final bool canManage;

  /// Um líder não redefine a senha do dono: a rota devolve a senha temporária
  /// a quem chamou, e isso seria entrar na conta dele.
  final bool actorIsOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // O contato saiu daqui e foi para a folha que abre ao tocar na pessoa. O
    // menu ficou com o que é de quem lidera — e some para quem não lidera.
    final itens = <PopupMenuEntry<String>>[
      if (canManage) const PopupMenuItem(value: 'edit', child: Text('Editar')),
      // Só para quem ainda não tem conta: é a linha em que o líder percebe
      // que falta convidar, e até aqui o caminho era sair desta lista e
      // procurar "Convites" nas configurações.
      if (canManage && !member.hasAccount)
        const PopupMenuItem(value: 'invite', child: Text('Convidar')),
      // O "esqueci minha senha" deste app, enquanto não há e-mail de
      // recuperação. Só faz sentido para quem já tem conta.
      if (canManage && member.hasAccount && (!member.isOwner || actorIsOwner))
        const PopupMenuItem(
          value: 'reset-password',
          child: Text('Redefinir senha'),
        ),
      if (canManage && !member.isOwner)
        PopupMenuItem(
          value: 'remove',
          child: Text(
            'Remover da equipe',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ];

    if (itens.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      tooltip: 'Opções de ${member.displayName}',
      onSelected: (action) => _onAction(context, ref, action),
      itemBuilder: (menuContext) => itens,
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    if (action == 'edit') {
      context.push('/equipe/membros/editar', extra: member);
      return;
    }

    if (action == 'invite') {
      await copyIndividualInvite(
        context,
        ref,
        teamId: teamId,
        membershipId: member.id,
        displayName: member.displayName,
      );
      return;
    }

    if (action == 'reset-password') {
      await resetMemberPassword(
        context,
        ref,
        teamId: teamId,
        member: member,
      );
      return;
    }

    final confirmed = await showConfirmDialog(
      context,
      title: 'Remover ${member.displayName}?',
      message: 'As escalas passadas continuam como estão. As escalas futuras '
          'perdem esta pessoa.',
      confirmLabel: 'Remover',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(teamRepositoryProvider).removeMember(teamId, member.id);
      ref.invalidate(membersProvider(teamId));
      if (context.mounted) {
        showAppSnackBar(
          context,
          '${member.displayName} saiu da equipe.',
          tone: AppTone.success,
        );
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, e.message, tone: AppTone.danger);
      }
    }
  }
}

/// Quem faz aniversário nos próximos dois meses.
///
/// **É o uso que justifica o campo existir.** Uma data de nascimento guardada e
/// nunca mostrada seria mais um telefone: coletado e esquecido. Aqui ela vira a
/// única coisa que a equipe faz com ela — lembrar de parabenizar.
///
/// O ano não aparece. Quem lê quer saber **quando**, e anunciar a idade de todo
/// mundo na tela da equipe é uma decisão que ninguém tomou.
class _Birthdays extends StatelessWidget {
  const _Birthdays({required this.members, required this.canManage});

  final List<Member> members;
  final bool canManage;

  /// A janela: um mês à frente. Com dois meses, numa equipe de vinte pessoas,
  /// a lista virava um bloco de quatro ou cinco linhas antes dos integrantes.
  static const int windowDays = 30;

  @override
  Widget build(BuildContext context) {
    final comData = members.where((m) => m.birthDate != null).toList();
    final proximos = comData
        .where((m) => m.daysToBirthday! <= windowDays)
        .toList()
      ..sort((a, b) => a.daysToBirthday!.compareTo(b.daysToBirthday!));

    if (proximos.isEmpty) {
      // A explicação só vale a pena quando ninguém preencheu **e** existe
      // alguém que poderia: com a equipe inteira sem conta, a linha viraria
      // uma cobrança impossível de atender.
      final alguemPodePreencher = members.any((m) => m.hasAccount);
      if (!canManage || comData.isNotEmpty || !alguemPodePreencher) {
        return const SizedBox.shrink();
      }

      return const Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.xl),
        child: AppGroup(
          children: [
            AppGroupRow(
              icon: Icons.cake_outlined,
              title: 'Aniversários',
              subtitle: 'Ninguém informou a data ainda. Cada pessoa preenche '
                  'a sua em Perfil → Meus dados.',
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: AppGroup(
        children: [
          // **Uma linha, e não um bloco.** Os aniversários ficam antes dos
          // integrantes, e um grupo com uma linha por pessoa empurrava a lista
          // — que é o conteúdo da aba. A linha resume; o toque abre todos.
          AppGroupRow(
            icon: Icons.cake_outlined,
            title: 'Aniversários',
            subtitle: birthdaySummary(proximos),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (_) => _BirthdaySheet(members: proximos),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Ana hoje · João em 12 dias · +1": os dois mais próximos, e quantos faltam.
String birthdaySummary(List<Member> proximos) {
  String quando(int dias) => switch (dias) {
        0 => 'hoje',
        1 => 'amanhã',
        _ => 'em $dias dias',
      };
  final partes = [
    for (final member in proximos.take(2))
      '${member.displayName} ${quando(member.daysToBirthday!)}',
    if (proximos.length > 2) '+${proximos.length - 2}',
  ];
  return partes.join(' · ');
}

class _BirthdaySheet extends StatelessWidget {
  const _BirthdaySheet({required this.members});

  final List<Member> members;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Text(
                'Aniversários do próximo mês',
                style: theme.textTheme.titleLarge,
              ),
            ),
            for (final member in members)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                ),
                leading: AppAvatar(
                  name: member.displayName,
                  imageUrl: member.avatarUrl,
                  radius: 20,
                ),
                title: Text(
                  member.displayName,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  formatBirthday(member.birthDate!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                trailing: _CountdownLabel(days: member.daysToBirthday!),
              ),
          ],
        ),
      ),
    );
  }
}

/// A folha que abre ao tocar numa pessoa: falar com ela, e editar para quem
/// lidera.
///
/// **Falar com alguém da equipe não é privilégio de liderança.** WhatsApp e
/// telefone aparecem para todo mundo, desde que haja número.
Future<void> _showMemberSheet(
  BuildContext context, {
  required Member member,
  required bool canManage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final phone = member.phoneDigits;

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                ),
                leading: AppAvatar(
                  name: member.displayName,
                  imageUrl: member.avatarUrl,
                ),
                title: Text(
                  member.displayName,
                  style: theme.textTheme.titleMedium,
                ),
                subtitle: member.positions.isEmpty
                    ? null
                    : Text(member.positions.map((p) => p.name).join(' · ')),
              ),
              const Divider(height: AppSpacing.md),
              if (phone != null) ...[
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  leading: const Icon(Icons.chat_outlined),
                  title: const Text('WhatsApp'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    openWhatsApp(context, phone);
                  },
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  leading: const Icon(Icons.call_outlined),
                  title: const Text('Ligar'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    callPhone(context, phone);
                  },
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.md,
                  ),
                  child: Text(
                    'Sem telefone cadastrado.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (canManage)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Editar'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.push('/equipe/membros/editar', extra: member);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// "Hoje", "Amanhã", "em 12 dias" — a distância, não a data.
///
/// A data já está na linha de baixo. O que muda a atitude de quem lê é saber
/// se dá para deixar para depois.
class _CountdownLabel extends StatelessWidget {
  const _CountdownLabel({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (days == 0) {
      return const AppBadge(
        label: 'Hoje',
        tone: AppTone.primary,
        emphasis: BadgeEmphasis.solid,
      );
    }

    if (days == 1) {
      return const AppBadge(label: 'Amanhã', tone: AppTone.primary);
    }

    return Text(
      'em $days dias',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Quantas sugestões estão de pé, na linha do menu.
///
/// **Sem push no projeto, é por este número que o líder descobre que alguém
/// sugeriu alguma coisa** — sugestão que ninguém vê é sugestão que ninguém faz
/// duas vezes. Só para quem pode responder: para o integrante, uma contagem
/// que ele não pode resolver seria enfeite.
///
/// Falha ou carregamento não desenham nada: a linha existe e funciona sem o
/// selo, e um erro aqui não pode virar um "!" vermelho no menu da equipe.
class _SuggestionCountBadge extends ConsumerWidget {
  const _SuggestionCountBadge({required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final abertas = ref.watch(openSuggestionCountProvider(teamId));
    final total = abertas.valueOrNull ?? 0;
    final scheme = Theme.of(context).colorScheme;

    // A seta vem junto: ocupando o lugar do `trailing`, o selo apagava a seta
    // da linha — e sem sugestão aberta a linha ficava sem seta nenhuma, ao
    // lado de "Repertório" com a sua.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (total > 0) ...[
          AppBadge(
            label: '$total',
            tone: AppTone.primary,
            emphasis: BadgeEmphasis.solid,
            semanticsLabel: total == 1
                ? '1 sugestão aguardando resposta'
                : '$total sugestões aguardando resposta',
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        Icon(
          Icons.chevron_right_rounded,
          size: 20,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
        ),
      ],
    );
  }
}
