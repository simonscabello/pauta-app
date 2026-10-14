import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/responsive/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_primary_action.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/contact_actions.dart';
import '../../../shared/widgets/on_leave_badge.dart';
import '../../../shared/widgets/position_icon.dart';
import '../../auth/application/auth_controller.dart';
import '../../invites/presentation/invite_actions.dart';
import '../data/team_repository.dart';
import '../domain/team_models.dart';
import 'reset_password_action.dart';

/// Integrantes: a lista das pessoas da equipe, numa tela só dela.
///
/// **Ela era a aba Equipe inteira.** Repertório e sugestões vinham em cima e a
/// configuração ficava atrás de uma engrenagem; numa equipe de vinte e poucas
/// pessoas, a lista empurrava tudo para baixo e a aba virava "rolar até achar".
/// Agora a aba é o painel da equipe ([TeamHubScreen]) e a lista é uma linha
/// dele, como Funções e Convites.
///
/// Tocar numa pessoa abre WhatsApp e telefone para todo mundo; o ⋮ (editar,
/// convidar, redefinir senha, remover) é só de quem lidera.
class TeamMembersScreen extends ConsumerWidget {
  const TeamMembersScreen({super.key, required this.teamId});

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

    final adicionar = AppPrimaryAction(
      label: wide ? 'Adicionar integrante' : 'Adicionar',
      icon: Icons.person_add_rounded,
      onPressed: () => context.push('/equipe/integrantes/novo'),
    );
    final headerAction = canManage ? adicionar.headerAction(context) : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Integrantes'),
        actions: [if (headerAction != null) headerAction],
      ),
      floatingActionButton: canManage ? adicionar.fab(context) : null,
      body: SafeArea(
        top: false,
        child: AppContentWidth.wide(
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
                    AppSpacing.lg,
                    AppSpacing.screenPadding,
                    canManage && !wide
                        ? AppSpacing.fabClearance
                        : AppSpacing.xxl,
                  ),
                  children: [
                    if (list.isEmpty)
                      _NoMembers(canManage: canManage)
                    else if (constraints.maxWidth >= 860)
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
                        dividerIndent: AppSpacing.lg + 40 + AppSpacing.md,
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
              onPressed: () => context.push('/equipe/integrantes/novo'),
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
      context.push('/equipe/integrantes/editar', extra: member);
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
                    context.push('/equipe/integrantes/editar', extra: member);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}
