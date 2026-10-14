import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/app_breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/domain/person_fields.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/greeting_header.dart';
import '../../auth/application/auth_controller.dart';
import '../../onboarding/domain/member_tour.dart';
import '../../onboarding/presentation/tour_target.dart';
import '../../suggestions/data/suggestion_repository.dart';
import '../../whatsapp/data/whatsapp_repository.dart';
import '../data/team_repository.dart';
import '../domain/team_models.dart';

/// A aba Equipe: o painel da equipe, com tudo o que ela tem, por assunto.
///
/// **Era a lista de integrantes com uma engrenagem em cima.** A lista inteira
/// (vinte e poucas pessoas) empurrava o resto para baixo, e a configuração
/// ficava em "Gerenciar equipe", atrás de um ícone que só existia no celular e
/// que ninguém adivinha o que guarda. Agora a aba é um menu: a lista virou a
/// linha "Integrantes", com tela própria ([TeamMembersScreen]), e o que estava
/// em Gerenciar equipe veio para cá, separado por assunto.
///
/// **Quatro grupos**: Músicas, Pessoas, Escalas e Configurações. Quem não
/// lidera vê só as linhas que pode abrir — repertório, sugestões, integrantes e
/// aniversários —, e o grupo sem nenhuma linha some inteiro. As linhas
/// condicionais entram com `if` na lista: o [AppGroup] desenha divisor antes de
/// cada filho, mesmo vazio.
///
/// **O repertório continua para todo mundo.** Ele já esteve atrás da
/// engrenagem, e o integrante que precisava da cifra antes do ensaio não tinha
/// como abri-lo. Quem lidera continua sendo o único que escreve; isso é
/// decidido lá dentro, e não escondendo a porta.
class TeamHubScreen extends ConsumerWidget {
  const TeamHubScreen({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final myTeam = auth.teams.where((t) => t.teamId == teamId).firstOrNull ??
        auth.teams.firstOrNull;
    final canManage = myTeam?.canManage ?? false;
    final wide = AppBreakpoints.of(context).isWide;

    // A lista só dá a contagem e os aniversários: enquanto carrega, ou se
    // falhar, as linhas aparecem sem eles — o menu não espera pela equipe.
    final members = ref.watch(membersProvider(teamId)).valueOrNull;
    final birthdays =
        members == null ? null : _birthdayRow(context, members, canManage);
    // A linha só existe com o envio pelo WhatsApp ligado no servidor. Enquanto
    // carrega, ou se a consulta falhar, ela não aparece -- é a última do
    // grupo, então nenhuma outra muda de lugar por causa dela.
    final whatsApp =
        canManage ? ref.watch(teamWhatsAppProvider(teamId)).valueOrNull : null;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AppContentWidth.reading(
          child: Column(
            children: [
              // O mesmo cabeçalho de Início e Agenda ([TabHeader]): as quatro
              // abas abrem com o título grande.
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
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async =>
                      ref.refresh(membersProvider(teamId).future),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenPadding,
                      AppSpacing.xs,
                      AppSpacing.screenPadding,
                      AppSpacing.xxl,
                    ),
                    children: [
                      // Cada grupo é filho direto da lista: o alvo do tour não
                      // pode morar numa lista preguiçosa.
                      AppGroup(
                        title: 'Músicas',
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
                          // Ao lado do repertório e para todo mundo: quem sugere
                          // é a equipe inteira, e quem sugeriu precisa ver o que
                          // aconteceu.
                          AppGroupRow(
                            icon: Icons.lightbulb_outline_rounded,
                            title: 'Sugestões',
                            subtitle: 'Músicas que a equipe pediu, e por quê',
                            trailing: canManage
                                ? _SuggestionCountBadge(teamId: teamId)
                                : null,
                            onTap: () => context.push('/equipe/sugestoes'),
                          ),
                          // Uso e Análise numa tela só, com duas abas.
                          if (canManage)
                            AppGroupRow(
                              icon: Icons.insights_rounded,
                              title: 'Relatórios do repertório',
                              subtitle:
                                  'O que se repete, o que sumiu, o que foi cantado',
                              onTap: () =>
                                  context.push('/equipe/musicas/saude'),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AppGroup(
                        title: 'Pessoas',
                        children: [
                          AppGroupRow(
                            icon: Icons.people_outline_rounded,
                            title: 'Integrantes',
                            subtitle:
                                'Quem toca, canta e opera, e como falar com cada um',
                            trailing: members == null || members.isEmpty
                                ? null
                                : _CountWithChevron(
                                    label: '${members.length}',
                                    semanticsLabel: members.length == 1
                                        ? '1 integrante'
                                        : '${members.length} integrantes',
                                  ),
                            onTap: () => context.push('/equipe/integrantes'),
                          ),
                          if (birthdays != null) birthdays,
                          if (canManage)
                            AppGroupRow(
                              icon: Icons.music_note_outlined,
                              title: 'Funções',
                              subtitle: 'Vocal, instrumentos, multimídia e som',
                              onTap: () => context.push('/equipe/funcoes'),
                            ),
                          if (canManage)
                            AppGroupRow(
                              icon: Icons.link_rounded,
                              title: 'Convites',
                              subtitle:
                                  'Códigos para as pessoas entrarem na equipe',
                              onTap: () => context.push('/equipe/convites'),
                            ),
                        ],
                      ),
                      if (canManage) ...[
                        const SizedBox(height: AppSpacing.xl),
                        AppGroup(
                          title: 'Escalas',
                          children: [
                            AppGroupRow(
                              icon: Icons.church_outlined,
                              title: 'Cultos da igreja',
                              subtitle: 'Os horários que se repetem toda semana',
                              onTap: () => context.push('/equipe/cultos'),
                            ),
                            AppGroupRow(
                              icon: Icons.flag_outlined,
                              title: 'Momentos do culto',
                              subtitle:
                                  'Abertura, ofertas, Santa Ceia: os da sua igreja',
                              onTap: () => context.push('/equipe/momentos'),
                            ),
                            AppGroupRow(
                              icon: Icons.event_busy_rounded,
                              title: 'Quem não pode',
                              subtitle: 'O mês e quem mais avisou que não podia',
                              onTap: () =>
                                  context.push('/equipe/indisponibilidade'),
                            ),
                            AppGroupRow(
                              icon: Icons.balance_rounded,
                              title: 'Participação',
                              subtitle: 'Quem mais serviu, e em que função',
                              onTap: () =>
                                  context.push('/equipe/participacao'),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        AppGroup(
                          title: 'Configurações',
                          children: [
                            AppGroupRow(
                              icon: Icons.tune_rounded,
                              title: 'Dados da equipe',
                              subtitle: 'O nome que aparece para os integrantes',
                              onTap: () => context.push('/equipe/dados'),
                            ),
                            if (whatsApp != null && whatsApp.available)
                              AppGroupRow(
                                icon: Icons.chat_outlined,
                                title: 'Grupo do WhatsApp',
                                subtitle: whatsApp.group != null
                                    ? 'Vinculado: ${whatsApp.group!.label}'
                                    : 'Mandar a escala para o grupo pelo Pauta',
                                onTap: () => context.push('/equipe/whatsapp'),
                              ),
                          ],
                        ),
                      ],
                    ],
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

/// A janela dos aniversários: um mês à frente. Com dois meses, numa equipe de
/// vinte pessoas, a linha resumia quatro ou cinco nomes.
const int birthdayWindowDays = 30;

/// Quem faz aniversário no próximo mês, como uma linha do grupo Pessoas — ou
/// nada, quando não há o que dizer.
///
/// **É o uso que justifica o campo existir.** Uma data de nascimento guardada e
/// nunca mostrada seria mais um telefone: coletado e esquecido. Aqui ela vira a
/// única coisa que a equipe faz com ela — lembrar de parabenizar.
///
/// O ano não aparece. Quem lê quer saber **quando**, e anunciar a idade de todo
/// mundo na tela da equipe é uma decisão que ninguém tomou.
///
/// Devolve `null` em vez de um widget vazio: a linha entra no grupo com `if`,
/// senão o [AppGroup] desenharia o divisor de uma linha que não existe.
AppGroupRow? _birthdayRow(
  BuildContext context,
  List<Member> members,
  bool canManage,
) {
  final comData = members.where((m) => m.birthDate != null).toList();
  final proximos = comData
      .where((m) => m.daysToBirthday! <= birthdayWindowDays)
      .toList()
    ..sort((a, b) => a.daysToBirthday!.compareTo(b.daysToBirthday!));

  if (proximos.isEmpty) {
    // A explicação só vale a pena quando ninguém preencheu **e** existe
    // alguém que poderia: com a equipe inteira sem conta, a linha viraria
    // uma cobrança impossível de atender.
    final alguemPodePreencher = members.any((m) => m.hasAccount);
    if (!canManage || comData.isNotEmpty || !alguemPodePreencher) return null;

    return const AppGroupRow(
      icon: Icons.cake_outlined,
      title: 'Aniversários',
      subtitle: 'Ninguém informou a data ainda. Cada pessoa preenche '
          'a sua em Perfil → Meus dados.',
    );
  }

  return AppGroupRow(
    icon: Icons.cake_outlined,
    title: 'Aniversários',
    subtitle: birthdaySummary(proximos),
    onTap: () => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _BirthdaySheet(members: proximos),
    ),
  );
}

/// Um número antes da seta, no fim de uma linha do menu.
///
/// A seta vem junto: ocupando o lugar do `trailing`, o selo apagaria a seta da
/// linha.
class _CountWithChevron extends StatelessWidget {
  const _CountWithChevron({required this.label, required this.semanticsLabel});

  final String label;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppBadge(label: label, semanticsLabel: semanticsLabel),
        const SizedBox(width: AppSpacing.xs),
        Icon(
          Icons.chevron_right_rounded,
          size: 20,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.55),
        ),
      ],
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
