import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../onboarding/domain/member_tour.dart';
import '../../onboarding/presentation/tour_target.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/section_header.dart';
import '../../songs/data/song_repository.dart';
import '../../suggestions/data/suggestion_repository.dart';
import '../domain/learning_songs.dart';

/// Os atalhos da Home.
///
/// **Nenhum destino novo.** Repertório, Músicas novas, Sugestões e Minha
/// disponibilidade já existem no app — na barra lateral do monitor, e atrás de
/// dois toques no celular. O que a Home acrescenta é o caminho curto: são as
/// telas que a equipe abre entre um domingo e outro. **Minha disponibilidade**
/// era a mais escondida: no celular só se chegava nela pelo Perfil, e é
/// justamente a que tem prazo.
///
/// **Músicas novas é atalho, e não lista.** A Home já mostrou as músicas em
/// aprendizado num cartão próprio, e ele saiu a pedido: a Home não lista nada.
/// O atalho diz quantas há para estudar e abre a aba "Novas" do repertório. A
/// contagem vem de `learningSongsProvider`, que o servidor filtra
/// (`?isNew=true`) — a Home não paga o acervo inteiro por um número.
///
/// Quatro, e não seis: a Home não é um painel de controle. Cada atalho a mais
/// rouba peso da manchete, que é a razão de a tela existir.
///
/// **A arrumação muda com a largura, o conteúdo não.** Quatro lado a lado só
/// cabem com largura; no celular são duas linhas de dois, e o título pode
/// quebrar em duas linhas ("Minha disponibilidade") em vez de ser cortado.
class HomeQuickAccess extends ConsumerWidget {
  const HomeQuickAccess({
    super.key,
    required this.teamId,
    required this.canManage,
    this.withSideNav = false,
  });

  /// A barra lateral está à vista (tablet e monitor). Aí só ficam os atalhos
  /// que ela não tem: "Músicas novas", com a contagem, e "Minha
  /// disponibilidade", que é a parada do tour na Home.
  final bool withSideNav;

  final String teamId;

  /// Só quem pode responder uma sugestão vê a contagem delas.
  ///
  /// É a mesma regra do selo na aba Equipe: para quem apenas sugere, um número
  /// que ele não tem como resolver seria enfeite — e a contagem custa uma
  /// requisição que, para essa pessoa, não paga o próprio preço.
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reaproveita o provider do selo da aba Equipe: mesma chave, mesma
    // resposta. Abrir a lista de sugestões logo depois não custa uma segunda
    // ida ao servidor.
    final pending = canManage
        ? ref.watch(openSuggestionCountProvider(teamId)).valueOrNull ?? 0
        : 0;
    // Para a equipe inteira: estudar a música nova é de quem canta.
    final learning =
        ref.watch(learningSongsProvider(teamId)).valueOrNull?.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Acessos rápidos',
          padding: EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.md,
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            // O espaço que o bloco recebeu, e não o da janela: dentro da casca
            // com barra lateral aberta a Home tem menos largura do que o
            // monitor sugere, e é a largura daqui que decide se quatro
            // ladrilhos cabem.
            final quatroEmLinha = constraints.maxWidth >= 640;
            // Em 2×2 o ícone sobe para cima do nome: ao lado dele, sobravam
            // ~100px para o texto, e "disponibilidade" — uma palavra só, que
            // não quebra — saía cortada em "disponibilida…" num celular de
            // 375px. Em cima, o nome tem a largura inteira do ladrilho.
            final empilhado = !quatroEmLinha;

            final repertorio = _QuickCard(
              icon: Icons.library_music_rounded,
              title: 'Repertório',
              stacked: empilhado,
              onTap: () => context.push('/equipe/musicas'),
            );
            final novas = _QuickCard(
              icon: Icons.headphones_rounded,
              title: 'Músicas novas',
              stacked: empilhado,
              subtitle: learningShortcutSubtitle(learning),
              onTap: () => context.push('/equipe/musicas?aba=novas'),
            );
            final sugestoes = _QuickCard(
              icon: Icons.lightbulb_rounded,
              title: 'Sugestões',
              stacked: empilhado,
              badge: pending == 0
                  ? null
                  : AppBadge(
                      label: '$pending',
                      tone: AppTone.primary,
                      emphasis: BadgeEmphasis.solid,
                      semanticsLabel: pending == 1
                          ? '1 sugestão aguardando resposta'
                          : '$pending sugestões aguardando resposta',
                    ),
              onTap: () => context.push('/equipe/sugestoes'),
            );
            final disponibilidade = TourTarget(
              id: TourTargetIds.homeAvailability,
              child: _QuickCard(
                icon: Icons.event_busy_rounded,
                title: 'Minha disponibilidade',
                stacked: empilhado,
                onTap: () => context.push('/disponibilidade'),
              ),
            );

            // `IntrinsicHeight` para os cartões da linha terem a mesma altura:
            // são um conjunto, e um mais alto que o outro por causa do tamanho
            // do título lê-se como desalinho, não como diferença. Dentro de
            // uma lista a altura é ilimitada, e `stretch` sozinho num `Row`
            // pede altura infinita.
            Widget linha(List<Widget> cards) => IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < cards.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.md),
                        Expanded(child: cards[i]),
                      ],
                    ],
                  ),
                );

            if (withSideNav) {
              return linha([novas, disponibilidade]);
            }
            if (quatroEmLinha) {
              return linha([repertorio, novas, sugestoes, disponibilidade]);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                linha([repertorio, novas]),
                const SizedBox(height: AppSpacing.md),
                linha([sugestoes, disponibilidade]),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Um atalho: ícone, nome e, quando há o que contar, uma linha que conta.
///
/// **Baixo, e sem quadrado colorido atrás do ícone.** O ladrilho tinha ~124px
/// de altura, com o ícone num quadrado lavanda e uma legenda fixa ("Cânticos e
/// hinos", "Avise quando não puder") que não dizia nada que o nome já não
/// dissesse. Quatro deles ocupavam mais que a manchete. A legenda ficou só
/// onde ela muda — "3 para estudar" —, e o selo de sugestões continua.
class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.badge,
    this.stacked = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? badge;

  /// Ícone em cima do nome, e não ao lado.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall,
          // Duas linhas, e não reticências: "Minha disponibilidade"
          // cortada em "Minha disponibi…" não se lê.
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 22, color: scheme.primary),
                    const Spacer(),
                    if (badge != null) badge!,
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                texts,
              ],
            )
          : Row(
              children: [
                Icon(icon, size: 22, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: texts),
                if (badge != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  badge!,
                ],
              ],
            ),
    );
  }
}
