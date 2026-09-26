import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_group.dart';
import '../../auth/application/auth_controller.dart';
import '../data/team_repository.dart';

/// Tudo o que só o dono e os líderes fazem, num lugar só.
///
/// Antes eram dois ícones na barra da tela de Equipe — um de corrente e um de
/// igreja. Ninguém adivinha que "corrente" é convite, e a barra ia crescer a
/// cada configuração nova. Aqui cada item tem nome e uma linha dizendo o que
/// faz, e acrescentar o próximo não custa mais espaço.
///
/// **Dois grupos**: o que se configura uma vez (**Equipe**) e o que se consulta
/// ao planejar (**Acompanhamento**). Eram oito linhas numa lista só, com os
/// dados da equipe no fim, depois dos relatórios.
///
/// **O repertório saiu daqui.** Ele estava nesta lista, e esta lista só se
/// alcança pelo ícone de engrenagem, que só aparece para quem lidera — ou seja:
/// o integrante que precisa da cifra e do tom antes do ensaio **não tinha como
/// abrir o repertório**, embora o servidor sempre tenha deixado ele ler. Agora
/// o repertório é uma entrada da aba Equipe, para todo mundo, e aqui ficam só
/// a configuração e os relatórios.
class ManageTeamScreen extends ConsumerWidget {
  const ManageTeamScreen({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamProvider(teamId));
    // O nome que a sessão já conhece, enquanto a equipe carrega. O "Equipe"
    // provisório aparecia logo acima do grupo "Equipe", e a tela abria
    // dizendo a mesma palavra duas vezes.
    final teamName = ref
        .watch(authControllerProvider)
        .teams
        .where((t) => t.teamId == teamId)
        .firstOrNull
        ?.name;

    return Scaffold(
      appBar: AppBar(title: const Text('Gerenciar equipe')),
      body: SafeArea(
        top: false,
        child: AppContentWidth.reading(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.lg,
              AppSpacing.screenPadding,
              AppSpacing.xxl,
            ),
            children: [
              // O nome da equipe como manchete da tela: é o assunto de tudo que
              // vem abaixo. A frase de apoio que vinha embaixo repetia a barra.
              Text(
                team.valueOrNull?.name ?? teamName ?? '',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xl),
              AppGroup(
                title: 'Equipe',
                children: [
                  AppGroupRow(
                    icon: Icons.tune_rounded,
                    title: 'Dados da equipe',
                    subtitle: 'O nome que aparece para os integrantes',
                    onTap: () => context.push('/equipe/dados'),
                  ),
                  AppGroupRow(
                    icon: Icons.church_outlined,
                    title: 'Cultos da igreja',
                    subtitle: 'Os horários que se repetem toda semana',
                    onTap: () => context.push('/equipe/cultos'),
                  ),
                  AppGroupRow(
                    icon: Icons.music_note_outlined,
                    title: 'Funções',
                    subtitle: 'Vocal, instrumentos, multimídia e som',
                    onTap: () => context.push('/equipe/funcoes'),
                  ),
                  AppGroupRow(
                    icon: Icons.link_rounded,
                    title: 'Convites',
                    subtitle: 'Códigos para as pessoas entrarem na equipe',
                    onTap: () => context.push('/equipe/convites'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              AppGroup(
                title: 'Acompanhamento',
                children: [
                  AppGroupRow(
                    icon: Icons.event_busy_rounded,
                    title: 'Quem não pode',
                    subtitle: 'O mês e quem mais avisou que não podia',
                    onTap: () => context.push('/equipe/indisponibilidade'),
                  ),
                  AppGroupRow(
                    icon: Icons.balance_rounded,
                    title: 'Participação',
                    subtitle: 'Quem mais serviu, e em que função',
                    onTap: () => context.push('/equipe/participacao'),
                  ),
                  // Uso e Análise viraram uma tela com duas abas: eram duas
                  // linhas vizinhas para perguntas vizinhas.
                  AppGroupRow(
                    icon: Icons.insights_rounded,
                    title: 'Relatórios do repertório',
                    subtitle: 'O que se repete, o que sumiu, o que foi cantado',
                    onTap: () => context.push('/equipe/musicas/saude'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
