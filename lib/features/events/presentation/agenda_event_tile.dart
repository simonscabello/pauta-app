import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_date_badge.dart';
import '../../../shared/widgets/app_pressable.dart';
import '../../../shared/widgets/you_highlight.dart';
import '../domain/event_datetime.dart';
import '../domain/event_models.dart';
import '../domain/open_date.dart';
import 'event_schedule_facts.dart';

/// Uma escala como linha de lista.
///
/// **Linha, e não cartão.** Uma agenda em que cada data é um cartão com sua
/// moldura e sua sombra vira uma pilha de caixinhas: o olho para em cada
/// fronteira e a lista deixa de ser varrida. Aqui a superfície é do grupo (ver
/// `AppGroup`) e a separação é um fio — o que permite ler oito datas de relance,
/// que é o que a tela precisa entregar depois da manchete.
///
/// **O bloco de data abre a linha.** Ele é a coluna fixa que dá prumo à lista:
/// o número sempre no mesmo lugar, e o título sempre começando na mesma
/// margem. A data por extenso continua ao lado, porque "13" sozinho não diz
/// domingo nem setembro.
///
/// **Duas arrumações, o mesmo conteúdo.** No celular tudo se empilha à direita
/// do bloco: é a única forma de caber em 375px. Onde há largura, a mesma linha
/// vira colunas — data, horários, sua função — e a lista passa a ser lida de
/// cima a baixo por coluna, que é o que faz uma agenda de trinta escalas
/// funcionar num monitor. As duas usam exatamente os mesmos campos do modelo.
///
/// **A data por extenso vem sem o dia da semana** ("21 de setembro"): o bloco
/// ao lado já diz "DOM 21", e "Domingo, 21 de setembro" repetia as duas
/// informações na mesma linha.
///
/// **Sem menu na linha.** Quem lidera tinha um ⋮ em cada escala com um item
/// só, "Duplicar escala" — que também está no menu do detalhe. Numa agenda de
/// oito escalas eram oito ícones iguais disputando a coluna da seta.
class CompactScheduleTile extends StatelessWidget {
  const CompactScheduleTile({
    super.key,
    required this.event,
    required this.canManage,
    required this.membershipId,
    this.wide = false,
  });

  final Event event;
  final bool canManage;
  final String membershipId;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final timezone =
        event.timezone.isEmpty ? 'America/Sao_Paulo' : event.timezone;
    final youPositions = event.personalRolesFor(membershipId);
    final facts = ScheduleFacts.of(event, timezone);
    // Rascunho fala do que falta para publicar; escala publicada sem
    // repertório fala do repertório. Uma das duas, ou nenhuma.
    final temEstado = event.warnings.unavailableAssigned.isNotEmpty ||
        event.isDraft ||
        event.servicesWithoutSongs.isNotEmpty ||
        event.isRepertoireOnTheFly;

    final dateBadge = AppDateBadge(
      weekday: formatEventBadgeWeekday(event.startsAt, timezone),
      day: formatEventDayNumber(event.startsAt, timezone),
      // Violeta onde você entra. É o mesmo sinal da pílula "VOCÊ", antecipado
      // para a coluna que o olho percorre — quem rola a agenda procurando os
      // próprios domingos para nos blocos tingidos antes de ler qualquer linha.
      tone: youPositions.isEmpty ? DateBadgeTone.normal : DateBadgeTone.primary,
    );

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // O bloco ao lado já diz "QUI 24"; repetir "24 de setembro" aqui era
        // a mesma data duas vezes. A linha diz o dia da semana por extenso e
        // o mês — o que o bloco não diz.
        Text(
          scheduleRowHeading(event.startsAt, timezone),
          style: theme.textTheme.titleMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (event.hasTitle)
          Text(
            event.title!,
            style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );

    final timesText = Text(
      facts.summary,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        fontFeatures: AppTypography.tabular,
      ),
    );

    final trailing = Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, right: 4),
      child: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
      ),
    );

    return AppPressable(
      onTap: () => context.push('/agenda/${event.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  dateBadge,
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(width: 230, child: title),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(child: timesText),
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(
                    width: 200,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (temEstado)
                          ScheduleStatusLines(
                            event: event,
                            alignment: CrossAxisAlignment.end,
                          ),
                        if (youPositions.isNotEmpty) ...[
                          if (temEstado) const SizedBox(height: AppSpacing.xs),
                          YouHighlight(positionNames: youPositions),
                        ],
                      ],
                    ),
                  ),
                  trailing,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  dateBadge,
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 3),
                        timesText,
                        if (youPositions.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          // Alinhado à esquerda e sem esticar: a pílula tem a
                          // largura do que diz. Numa `Column` `stretch` ela
                          // atravessaria a linha inteira e viraria uma faixa.
                          Align(
                            alignment: Alignment.centerLeft,
                            child: YouHighlight(positionNames: youPositions),
                          ),
                        ],
                        if (temEstado) ...[
                          const SizedBox(height: AppSpacing.sm),
                          ScheduleStatusLines(event: event),
                        ],
                      ],
                    ),
                  ),
                  trailing,
                ],
              ),
      ),
    );
  }
}

/// Uma data da grade que ainda não virou escala, na arrumação de
/// [CompactScheduleTile] — e de propósito mais apagada que ela.
///
/// Data e horários no cinza do texto de apoio, bloco de data sem tinta, sem
/// selo e sem linha de estado: não há nada a resolver ainda, e pintar de âmbar
/// todo domingo do mês faria a cor de "isto precisa de você" perder o sentido
/// nas escalas que realmente travaram. O que a linha promete é o toque, e quem
/// diz isso é o "+" à direita, no lugar onde as escalas existentes têm a seta.
class OpenDateTile extends StatelessWidget {
  const OpenDateTile({super.key, required this.date, required this.wide});

  final OpenDate date;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final timezone = date.timezone;

    final dateBadge = AppDateBadge(
      weekday: formatEventBadgeWeekday(date.startsAt, timezone),
      day: formatEventDayNumber(date.startsAt, timezone),
      tone: DateBadgeTone.muted,
    );

    final title = Text(
      formatEventDayMonth(date.startsAt, timezone),
      style: theme.textTheme.titleMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    final times = Text(
      [
        for (final service in date.services)
          '${service.label} ${formatEventTime(service.startsAt, timezone)}',
      ].join('  ·  '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
        fontFeatures: AppTypography.tabular,
      ),
    );

    return AppPressable(
      onTap: () => context.push('/agenda/novo?data=${date.dateParam}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment:
              wide ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            dateBadge,
            const SizedBox(width: AppSpacing.md),
            if (wide) ...[
              SizedBox(width: 230, child: title),
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: times),
            ] else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 3),
                    times,
                  ],
                ),
              ),
            const SizedBox(width: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: Icon(
                Icons.add_circle_outline_rounded,
                size: 20,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// O estado da escala no item da agenda: até duas linhas curtas.
///
/// **Rascunho** responde "dá para publicar?"; **repertório em aberto**
/// responde "as músicas já saíram?". São perguntas diferentes desde que a
/// escala passou a poder ir para a equipe sem música -- juntar as duas numa
/// linha só fazia "falta música" parecer impedimento, que é justamente o que
/// ele deixou de ser.
///
/// Daí os tons: âmbar no que a liderança precisa resolver para publicar,
/// ardósia no que é só notícia -- para a equipe inteira, inclusive quem só
/// quer saber se já pode ensaiar.
class ScheduleStatusLines extends StatelessWidget {
  const ScheduleStatusLines({
    super.key,
    required this.event,
    this.alignment = CrossAxisAlignment.start,
  });

  final Event event;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final cores = AppStatusColors.of(context);
    final semRepertorio = event.servicesWithoutSongs;
    final blockers = event.publicationBlockers;
    // Ocupa o **mesmo lugar** da linha de repertório pendente, e não uma linha
    // a mais: as duas respondem à pergunta "e as músicas?", e nunca as duas ao
    // mesmo tempo -- `servicesWithoutSongs` já vem vazio neste modo.
    final naHora = event.isRepertoireOnTheFly;

    final naoPodem = event.warnings.unavailableAssigned;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        // **Quem está escalado e avisou que não pode**, antes de tudo. A
        // linha da escala não mudava, e o líder só descobria abrindo aquele
        // domingo. Só quem lidera recebe este dado da API.
        if (naoPodem.isNotEmpty) ...[
          _StatusLine(
            icon: Icons.event_busy_rounded,
            text: naoPodem.length == 1
                ? '${naoPodem.single.displayName} não pode'
                : '${naoPodem.length} escalados não podem',
            palette: cores.danger,
          ),
          if (event.isDraft ||
              naHora ||
              semRepertorio.isNotEmpty)
            const SizedBox(height: AppSpacing.xs),
        ],
        // Um sinal só para o rascunho. Havia a etiqueta "Rascunho" em cima do
        // título e esta linha embaixo, as duas em âmbar, dizendo o mesmo
        // estado duas vezes na mesma linha da agenda.
        if (event.isDraft)
          _StatusLine(
            icon: blockers.isEmpty
                ? Icons.check_circle_outline
                : Icons.pending_actions,
            text: blockers.isEmpty
                ? 'Rascunho · pronta para publicar'
                : 'Rascunho · falta ${blockers.join(' e ')}',
            palette: cores.warning,
          ),
        if (naHora) ...[
          if (event.isDraft) const SizedBox(height: AppSpacing.xs),
          _StatusLine(
            icon: Icons.bolt_rounded,
            text: 'Repertório definido na hora',
            palette: cores.info,
          ),
        ] else if (semRepertorio.isNotEmpty) ...[
          if (event.isDraft) const SizedBox(height: AppSpacing.xs),
          _StatusLine(
            icon: Icons.music_note_outlined,
            // Sem nenhuma música, nomear os cultos só repetiria a linha de
            // horários logo acima.
            text: event.hasNoSongs
                ? 'Músicas a definir'
                : 'Músicas a definir: ${semRepertorio.join(' e ')}',
            palette: cores.info,
          ),
        ],
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.text,
    required this.palette,
  });

  final IconData icon;
  final String text;
  final StatusPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: palette.foreground),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            text,
            // 13px, e não os 11,5 do rótulo miúdo: "Rascunho · falta equipe"
            // é informação que pede providência, e em corpo de legenda
            // esmaecido ela não era lida (WCAG 1.4.4).
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.foreground,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

/// "Quinta, setembro" — o título da linha de escala, ao lado do bloco "QUI 24".
///
/// O bloco já dá o número; a linha completa com o que ele não tem: o dia da
/// semana por extenso (quem lê "QUI" de relance confunde com "QUA") e o mês,
/// que separa o 4 de outubro do 4 de setembro numa lista que atravessa meses.
@visibleForTesting
String scheduleRowHeading(DateTime utc, String timezone) {
  final local = eventLocalTime(utc, timezone);
  final mes = DateFormat('MMMM', 'pt_BR').format(local);
  return '${capitalizeWeekday(formatEventWeekdayName(utc, timezone))}, $mes';
}
