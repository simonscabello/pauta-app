import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button_styles.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_notice.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/section_header.dart';
import '../../events/domain/event_datetime.dart';
import '../../team/data/team_repository.dart';
import '../../team/domain/team_models.dart';
import '../data/invite_repository.dart';
import '../domain/invite_models.dart';
import '../../onboarding/domain/member_tour.dart';
import '../../onboarding/presentation/tour_target.dart';

/// Tela do líder: gera o convite geral da equipe e um convite individual por
/// membro que ainda não tem conta.
///
/// Esta era a tela mais atrasada do app, e por motivos concretos: usava `Card`
/// cru em vez do cartão do app, mostrava `Text('$e')` — a exceção do Dart, com
/// pilha e tudo — quando a lista de integrantes falhava, e **apagava um convite
/// no primeiro toque**, sem perguntar, num ícone de lixeira ao lado do botão de
/// copiar.
///
/// **Só o convite geral é cartão.** O código dele é o produto desta tela: tem
/// tamanho, espaçamento de leitura e um botão de largura inteira, porque o que
/// se faz aqui é copiar e colar no grupo do WhatsApp. Os individuais eram um
/// cartão igual por pessoa — cinco pessoas sem conta davam cinco caixas de
/// código e cinco botões cheios. Agora são linhas de um grupo, com "Copiar" e o
/// cancelamento no ⋮.
class InvitesScreen extends ConsumerWidget {
  const InvitesScreen({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invites = ref.watch(invitesProvider(teamId));

    return Scaffold(
      appBar: AppBar(title: const Text('Convites')),
      // Sem a barra inferior nesta rota, ninguem consome o recuo dos botoes de
      // navegacao do Android -- o fim da lista ficava por baixo deles.
      body: SafeArea(
        top: false,
        child: AppContentWidth.reading(
          child: invites.when(
            loading: () => const AppListSkeleton(itemCount: 3),
            error: (error, _) => AppErrorState(
              message: error is ApiException
                  ? error.message
                  : 'Não foi possível carregar os convites.',
              onRetry: () => ref.invalidate(invitesProvider(teamId)),
            ),
            data: (list) {
              final general =
                  list.where((invite) => !invite.isIndividual).toList();

              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(invitesProvider(teamId));
                  ref.invalidate(membersProvider(teamId));
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.lg,
                    AppSpacing.screenPadding,
                    AppSpacing.xxl,
                  ),
                  children: [
                    const SectionHeader(
                      title: 'Convite geral',
                      subtitle: 'Qualquer pessoa com este código entra na '
                          'equipe como membro.',
                    ),
                    if (general.isNotEmpty) ...[
                      // O alvo do tour do líder: o código que se manda à
                      // equipe. Sem código ainda, o botão de gerar.
                      TourTarget(
                        id: TourTargetIds.invitesGeneral,
                        child: _GeneralInviteCard(
                          invite: general.first,
                          teamId: teamId,
                        ),
                      ),
                      // Códigos gerais anteriores ainda valem até vencer: ficam
                      // como linhas, para não somar outro botão cheio.
                      if (general.length > 1) ...[
                        const SizedBox(height: AppSpacing.md),
                        AppGroup(
                          children: [
                            for (final invite in general.skip(1))
                              _InviteRow(
                                teamId: teamId,
                                invite: invite,
                                icon: Icons.link_rounded,
                                title: invite.formattedCode,
                              ),
                          ],
                        ),
                      ],
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    if (general.isEmpty)
                      TourTarget(
                        id: TourTargetIds.invitesGeneral,
                        child: _GenerateButton(teamId: teamId, first: true),
                      )
                    else
                      _GenerateButton(teamId: teamId, first: false),
                    const SizedBox(height: AppSpacing.xxl),
                    _IndividualSection(teamId: teamId, invites: list),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _IndividualSection extends ConsumerWidget {
  const _IndividualSection({required this.teamId, required this.invites});

  final String teamId;
  final List<Invite> invites;

  static const _title = 'Convites individuais';
  static const _subtitle = 'Quem aceitar assume o cadastro que você já criou, '
      'com as funções preenchidas.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider(teamId));

    const header = SectionHeader(title: _title, subtitle: _subtitle);

    return members.when(
      loading: () => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ),
        ],
      ),
      // Antes: `Text('$e')`. A pessoa recebia o objeto de exceção do Dart na
      // tela, sem nada a fazer com ele.
      error: (error, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          AppNotice(
            tone: AppTone.danger,
            icon: Icons.error_outline_rounded,
            title: 'Não foi possível carregar os integrantes',
            message: error is ApiException
                ? error.message
                : 'Puxe a tela para baixo para tentar de novo.',
          ),
        ],
      ),
      data: (all) {
        final pending = all.where((m) => !m.hasAccount).toList();

        if (pending.isEmpty) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              AppNotice(
                tone: AppTone.success,
                icon: Icons.check_circle_outline_rounded,
                title: 'Todo mundo já tem conta',
                message: 'Nenhum convite individual pendente.',
              ),
            ],
          );
        }

        return AppGroup(
          title: _title,
          subtitle: _subtitle,
          children: [
            for (final member in pending)
              _MemberInviteRow(
                teamId: teamId,
                member: member,
                invite: invites
                    .where((i) => i.forMembershipId == member.id)
                    .firstOrNull,
              ),
          ],
        );
      },
    );
  }
}

/// Uma pessoa sem conta: com convite, a linha do convite; sem, "Convidar".
class _MemberInviteRow extends ConsumerStatefulWidget {
  const _MemberInviteRow({
    required this.teamId,
    required this.member,
    required this.invite,
  });

  final String teamId;
  final Member member;
  final Invite? invite;

  @override
  ConsumerState<_MemberInviteRow> createState() => _MemberInviteRowState();
}

class _MemberInviteRowState extends ConsumerState<_MemberInviteRow> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;
    if (invite != null) {
      return _InviteRow(
        teamId: widget.teamId,
        invite: invite,
        icon: Icons.person_outline_rounded,
        title: widget.member.displayName,
      );
    }

    return AppGroupRow(
      icon: Icons.person_outline_rounded,
      title: widget.member.displayName,
      subtitle: 'Ainda sem convite',
      trailing: TextButton(
        style: AppButtonStyles.compactText,
        onPressed: _loading ? null : _generate,
        child: _loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Convidar'),
      ),
    );
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    try {
      await ref
          .read(inviteRepositoryProvider)
          .create(widget.teamId, membershipId: widget.member.id);
      ref.invalidate(invitesProvider(widget.teamId));
      if (mounted) {
        showAppSnackBar(
          context,
          'Convite de ${widget.member.displayName} gerado.',
          tone: AppTone.success,
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        showAppSnackBar(context, e.message, tone: AppTone.danger);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

/// Um convite como linha: nome (ou código), validade, "Copiar" e ⋮.
class _InviteRow extends ConsumerWidget {
  const _InviteRow({
    required this.teamId,
    required this.invite,
    required this.icon,
    required this.title,
  });

  final String teamId;
  final Invite invite;
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expires = DateFormat('d/M', 'pt_BR').format(invite.expiresAt);
    final soon = _expiringSoon(invite);

    return AppGroupRow(
      icon: icon,
      title: title,
      subtitle: [
        if (title != invite.formattedCode) invite.formattedCode,
        soon ? 'vence em $expires' : 'vale até $expires',
        if (invite.maxUses != null) _usesLabel(invite),
      ].join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            style: AppButtonStyles.compactText,
            onPressed: () => _copyInvite(context, invite),
            child: const Text('Copiar'),
          ),
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (_) => _revokeInvite(context, ref, teamId, invite),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'cancelar',
                child: Text('Cancelar convite'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GeneralInviteCard extends ConsumerWidget {
  const _GeneralInviteCard({required this.invite, required this.teamId});

  final Invite invite;
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final expires = DateFormat("d 'de' MMMM", 'pt_BR').format(invite.expiresAt);
    final expiringSoon = _expiringSoon(invite);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // O código é o produto desta tela. Numa caixa própria, grande e com
          // espaçamento de leitura -- quem digita à mão precisa distinguir
          // caractere por caractere, e antes ele era uma linha de texto entre
          // outras.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: scheme.outlineVariant),
            ),
            // Numa linha só, encolhendo se precisar: quebrado em dois
            // ("4H8GK-NJ929-QCYZ9-" / "Z9SYG") o código parecia terminar no
            // hífen, e é justamente quem digita à mão que lê esta caixa.
            child: SelectionArea(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  invite.formattedCode,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              AppBadge(
                icon: Icons.schedule_rounded,
                label: 'Vale até $expires',
                tone: expiringSoon ? AppTone.warning : AppTone.neutral,
                semanticsLabel: expiringSoon
                    ? 'Atenção: este convite vence em $expires'
                    : 'Vale até $expires',
              ),
              if (invite.maxUses != null) ...[
                const SizedBox(width: AppSpacing.sm),
                AppBadge(label: capitalizeWeekday(_usesLabel(invite))),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // Copiar ocupa a largura toda: é o que se faz aqui em 99 de 100
          // visitas. Cancelar é texto discreto abaixo — era um ícone de
          // lixeira encostado no botão de copiar, e apagava sem perguntar.
          FilledButton.icon(
            onPressed: () => _copyInvite(context, invite),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copiar convite'),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: () => _revokeInvite(context, ref, teamId, invite),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('Cancelar este convite'),
          ),
        ],
      ),
    );
  }
}

/// "Ainda não usado", "usado", "2 de 5 usos". "0 de 1 usos" era a conta
/// escrita em vez da frase — e o convite individual sempre tem um uso só.
String _usesLabel(Invite invite) {
  final max = invite.maxUses!;
  if (max == 1) return invite.uses == 0 ? 'ainda não usado' : 'já usado';
  return '${invite.uses} de $max usos';
}

bool _expiringSoon(Invite invite) =>
    invite.expiresAt.difference(DateTime.now()).inDays <= 2;

/// Copia a mensagem pronta para colar no grupo do WhatsApp -- e assim que a
/// equipe vai receber o convite na pratica.
Future<void> _copyInvite(BuildContext context, Invite invite) async {
  await Clipboard.setData(ClipboardData(text: invite.shareMessage));

  if (context.mounted) {
    showAppSnackBar(
      context,
      'Convite copiado. É só colar no WhatsApp.',
      tone: AppTone.success,
    );
  }
}

Future<void> _revokeInvite(
  BuildContext context,
  WidgetRef ref,
  String teamId,
  Invite invite,
) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Cancelar este convite?',
    message: 'O código para de funcionar na hora. Quem já entrou com ele '
        'continua na equipe.',
    confirmLabel: 'Cancelar convite',
    cancelLabel: 'Voltar',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;

  try {
    await ref.read(inviteRepositoryProvider).revoke(teamId, invite.id);
    ref.invalidate(invitesProvider(teamId));
    if (context.mounted) {
      showAppSnackBar(
        context,
        'Convite cancelado.',
        tone: AppTone.success,
      );
    }
  } on ApiException catch (e) {
    if (context.mounted) {
      showAppSnackBar(context, e.message, tone: AppTone.danger);
    }
  }
}

/// Gera um código geral. O primeiro é o botão principal da tela; depois que
/// já existe um, "Gerar outro código" vira botão de texto — o principal passa
/// a ser "Copiar convite".
class _GenerateButton extends ConsumerStatefulWidget {
  const _GenerateButton({required this.teamId, required this.first});

  final String teamId;
  final bool first;

  @override
  ConsumerState<_GenerateButton> createState() => _GenerateButtonState();
}

class _GenerateButtonState extends ConsumerState<_GenerateButton> {
  bool _loading = false;

  Future<void> _generate() async {
    setState(() => _loading = true);

    try {
      await ref.read(inviteRepositoryProvider).create(widget.teamId);
      ref.invalidate(invitesProvider(widget.teamId));
      if (mounted) {
        showAppSnackBar(
          context,
          'Código gerado.',
          tone: AppTone.success,
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        showAppSnackBar(context, e.message, tone: AppTone.danger);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _loading
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.add_rounded, size: 18);

    if (widget.first) {
      return FilledButton.icon(
        onPressed: _loading ? null : _generate,
        icon: icon,
        label: const Text('Gerar convite geral'),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _loading ? null : _generate,
        icon: icon,
        label: const Text('Gerar outro código'),
      ),
    );
  }
}
