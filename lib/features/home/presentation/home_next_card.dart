import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_hero_card.dart';
import '../../../shared/widgets/position_icon.dart';
import '../../events/domain/event_datetime.dart';
import '../../events/domain/event_models.dart';
import '../../events/presentation/event_schedule_facts.dart';
import '../domain/home_summary.dart';

/// A sobrancelha da manchete: "HOJE · MINHA PRÓXIMA ESCALA".
///
/// Rascunho só chega aqui para quem gerencia — a equipe não recebe escala não
/// publicada. Dizer isso na sobrancelha evita que quem monta a escala leia o
/// próprio rascunho como compromisso firmado.
String heroEyebrow({required int? daysAway, required bool isDraft}) {
  final parts = [
    if (daysAway == 0) 'HOJE',
    if (daysAway == 1) 'AMANHÃ',
    'MINHA PRÓXIMA ESCALA',
    if (isDraft) 'RASCUNHO',
  ];
  return parts.join(' · ');
}

/// A manchete da Home: **a sua** próxima escala.
///
/// A agenda destaca a próxima escala da equipe; esta destaca a próxima em que
/// você entra. Quase sempre são a mesma escala — e é exatamente por isso que a
/// diferença precisa estar dita na sobrancelha: quando a equipe toca no domingo
/// e você só no seguinte, a agenda respondia "domingo" a quem perguntou "quando
/// eu toco?".
///
/// Mesma casca da manchete da agenda ([AppHeroCard]), outro conteúdo. O que
/// entra aqui é o que a pessoa precisa para se preparar, na ordem em que ela
/// pergunta: quando, onde eu entro, quantas músicas, quando é o ensaio.
///
/// **Nada é inventado para preencher a linha.** Sem ensaio, não há linha de
/// ensaio; sem saber o repertório, não há linha de repertório — ver
/// [scheduleSongCount].
class MyNextScheduleCard extends StatelessWidget {
  const MyNextScheduleCard({
    super.key,
    required this.event,
    required this.positions,
    this.following,
    this.daysAway,
  });

  final Event event;

  /// Dias civis até a escala (0 hoje, 1 amanhã). Vira o começo da sobrancelha
  /// — "HOJE · MINHA PRÓXIMA ESCALA" — no lugar do aviso que repetia a
  /// manchete logo abaixo dela.
  final int? daysAway;

  /// As funções em que a pessoa está escalada nesta escala. Nunca vazio: sem
  /// função não haveria escala minha para mostrar.
  final List<String> positions;

  /// A escala seguinte **em que você entra**, quando existe.
  ///
  /// **Uma linha, e não um bloco.** A Home teve por um tempo um grupo
  /// "Próximas escalas" com três linhas da equipe — que é exatamente o que a
  /// aba Agenda mostra, e ocupando um terço da tela para isso. A pergunta que
  /// sobrava depois da manchete era só "e depois, quando eu toco de novo?", e
  /// ela cabe numa linha. O resto continua sendo trabalho da agenda.
  final Event? following;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timezone =
        event.timezone.isEmpty ? 'America/Sao_Paulo' : event.timezone;
    final facts = ScheduleFacts.of(event, timezone);
    final songs = _songsLabel(event);
    final rehearsal = _rehearsalLabel(event, timezone);

    return AppHeroCard(
      onTap: () => context.push('/agenda/${event.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  heroEyebrow(daysAway: daysAway, isDraft: event.isDraft),
                  style: AppTypography.eyebrow(context).copyWith(
                    color: AppColors.onHeroVariant,
                  ),
                ),
              ),
              // A seta diz que o cartão abre a escala. Era um botão "Ver
              // escala" no pé da manchete: uma segunda porta para o mesmo
              // lugar, com ~68px de altura, num cartão que já é todo tocável.
              const Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppColors.onHeroVariant,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            heroDateText(
              context,
              formatEventWeekdayDate(event.startsAt, timezone),
            ),
            style: theme.textTheme.displaySmall?.copyWith(
              color: AppColors.onHero,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          if (event.hasTitle) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              event.title!,
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.onHeroVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _MyPositions(positions: positions),
          const SizedBox(height: AppSpacing.md),
          // Em `Wrap` e não em `Row`: com a fonte do sistema aumentada, ou num
          // culto com três horários, os blocos não cabem lado a lado e
          // precisam empilhar em vez de espremer.
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              _Fact(
                icon: Icons.schedule_rounded,
                label: facts.times,
                detail: rehearsal,
              ),
              if (songs != null)
                _Fact(icon: Icons.music_note_rounded, label: songs),
            ],
          ),
          if (following != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _AfterThis(event: following!),
          ],
        ],
      ),
    );
  }

  /// "5 músicas", "Músicas a definir", ou nada quando o app não sabe.
  static String? _songsLabel(Event event) {
    // A escala em que as músicas saem no culto não tem nada a definir: dizer
    // que tem transformaria o combinado da equipe em cobrança na primeira tela
    // que a pessoa abre.
    if (event.isRepertoireOnTheFly) return 'Repertório na hora';

    final count = scheduleSongCount(event);
    return switch (count) {
      null => null,
      0 => 'Músicas a definir',
      1 => '1 música',
      _ => '$count músicas',
    };
  }

  /// "Ensaio sábado · 19:30". Nulo quando não há ensaio — e a linha some.
  ///
  /// A ausência de ensaio é dita na agenda ("Sem ensaio") porque lá a linha
  /// pertence à escala e quem a recebe precisa saber que não haverá. Aqui a
  /// pergunta é outra — "o que eu preciso fazer?" —, e uma linha para dizer
  /// que não há nada a fazer é linha gasta.
  static String? _rehearsalLabel(Event event, String timezone) {
    final rehearsalAt = event.rehearsalAt;
    if (rehearsalAt == null) return null;

    final time = formatEventTime(rehearsalAt, timezone);
    if (isSameLocalDay(rehearsalAt, event.startsAt, timezone)) {
      return 'Ensaio às $time';
    }
    return 'Ensaio ${formatEventWeekdayName(rehearsalAt, timezone)} · $time';
  }
}

/// "E depois: Domingo, 20 de setembro" — a sua escala seguinte, numa linha.
///
/// Fica **dentro** da manchete, e não num bloco abaixo dela: é a continuação
/// da mesma frase ("você toca dia 13… e depois dia 20"), e um cartão próprio
/// daria a duas datas o mesmo peso, quando só a primeira é a que a pessoa veio
/// buscar. Sem escala seguinte, a linha não existe — nada é inventado para
/// preencher a manchete.
class _AfterThis extends StatelessWidget {
  const _AfterThis({required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timezone =
        event.timezone.isEmpty ? 'America/Sao_Paulo' : event.timezone;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.event_repeat_rounded,
            size: 16,
            color: AppColors.onHeroVariant,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'E depois: ${formatEventWeekdayDate(event.startsAt, timezone)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onHeroVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Onde você entra, em destaque.
///
/// Sem o prefixo "VOCÊ:" do chip da agenda: ali ele separa a sua linha das
/// outras pessoas da escala, e aqui o cartão inteiro já é sobre você — repetir
/// o pronome seria explicar o óbvio no lugar mais nobre da tela.
class _MyPositions extends StatelessWidget {
  const _MyPositions({required this.positions});

  final List<String> positions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Com exatamente uma função, o ícone dela — "você toca bateria" fica
    // visível antes de o texto ser lido. Com duas ou mais não há ícone que
    // represente o conjunto, e a estrela continua. Mesma regra do
    // `YouHighlight`.
    final single = positions.length == 1 ? positions.first : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: single == null
              ? const Icon(
                  Icons.star_rounded,
                  size: 18,
                  color: AppColors.onHero,
                )
              : PositionIcon(single, size: 16, color: AppColors.onHero),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            positions.join(' · '),
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.onHero,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Um fato da escala, com ícone: horário (e o ensaio embaixo), repertório.
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, this.detail});

  final IconData icon;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      // Teto de largura para o `Wrap` ter onde quebrar: sem ele, um bloco com
      // três horários ocupa a linha inteira e empurra o repertório para baixo
      // mesmo num monitor.
      constraints: const BoxConstraints(maxWidth: 320),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: AppColors.onHeroVariant),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.onHero,
                    fontFeatures: AppTypography.tabular,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (detail != null)
                  Text(
                    detail!,
                    // O ensaio é o que o membro precisa saber da semana: 14px,
                    // e não o corpo de legenda.
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.onHeroVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A manchete quando não há escala sua à frente.
///
/// **Não é um erro, e não pode parecer um.** Ficar de fora das próximas escalas
/// é o estado normal de metade da equipe em qualquer domingo. Por isso o bloco
/// continua sendo a manchete violeta, com a mesma presença — o que muda é a
/// frase — em vez de virar uma caixa cinza de "nada encontrado".
///
/// Duas situações, duas frases: **você** está livre, ou a **equipe** ainda não
/// marcou nada. Dizer "você está livre" a quem abre o app numa equipe sem
/// nenhuma escala seria responder à pergunta errada.
class NoScheduleCard extends StatelessWidget {
  const NoScheduleCard({
    super.key,
    required this.hasSchedules,
    required this.canManage,
  });

  /// A equipe tem escalas à frente — só não têm você.
  final bool hasSchedules;

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, title, message) = hasSchedules
        ? (
            Icons.weekend_rounded,
            'Você está livre por enquanto',
            'Não encontramos nenhuma participação sua nas próximas escalas.',
          )
        : (
            Icons.event_available_outlined,
            'Nada marcado por enquanto',
            canManage
                ? 'Crie a primeira escala e a equipe já vai saber onde entra.'
                : 'Quando a liderança criar uma escala, ela aparece aqui.',
          );

    final createFirst = !hasSchedules && canManage;

    return AppHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MINHA PRÓXIMA ESCALA',
            style: AppTypography.eyebrow(context).copyWith(
              color: AppColors.onHeroVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Icon(icon, size: 32, color: AppColors.onHeroVariant),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: AppColors.onHero,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.onHeroVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Align(
            alignment: Alignment.centerRight,
            child: createFirst
                ? HeroActionButton(
                    label: 'Criar escala',
                    icon: Icons.add_rounded,
                    onPressed: () => context.push('/agenda/novo'),
                  )
                : HeroActionButton(
                    label: 'Ver agenda da equipe',
                    // `go`, e não `push`: a agenda é uma aba, e empilhá-la
                    // sobre a Home deixaria a barra inferior apontando para um
                    // lugar e a tela mostrando outro.
                    onPressed: () => context.go('/agenda'),
                  ),
          ),
        ],
      ),
    );
  }
}
