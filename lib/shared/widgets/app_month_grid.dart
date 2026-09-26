import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/date/civil_date.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_status_colors.dart';

/// Como um dia se desenha em [AppMonthGrid].
class AppMonthDay {
  const AppMonthDay({
    this.selected = false,
    this.marks = 0,
    this.markTone = AppTone.primary,
    this.enabled = true,
    this.inRange = false,
    this.detail,
    this.icon,
  });

  /// Fundo cheio da marca.
  final bool selected;

  /// Entre as duas pontas de um período escolhido: o fundo claro do dia
  /// marcado, **sem** traço — o traço conta coisas, e aqui não há o que
  /// contar. As pontas são [selected].
  final bool inRange;

  /// Um ícone no lugar dos traços. No seletor de "dias em que não posso" o dia
  /// marcado leva um "×": fundo cheio contra fundo claro (dia de culto) era
  /// diferença só de tom, e cor sozinha não é sinal (WCAG 1.4.1).
  final IconData? icon;

  /// Quantas coisas o dia tem. Pinta o fundo claro e desenha um traço por
  /// coisa, até [AppMonthGrid.maxMarks].
  final int marks;

  /// A família de cor do dia marcado: violeta para compromisso, âmbar para
  /// "alguém não pode".
  final AppTone markTone;

  /// Desligado: não responde ao toque e fica apagado (dia que já passou num
  /// seletor).
  final bool enabled;

  /// O que o leitor de tela diz depois da data ("2 compromissos").
  final String? detail;
}

/// A grade de um mês — **a mesma** nos três calendários do app.
///
/// Eram três desenhos: a agenda pintava o dia marcado de lavanda com traços, o
/// calendário de quem não pode usava círculo âmbar com o número embaixo, e o
/// seletor de dias tinha outro círculo. Três jeitos de dizer "este dia tem
/// alguma coisa" fazem a pessoa reaprender o calendário a cada tela.
///
/// **Quatro estados, quatro desenhos, e nenhum apaga o outro:** dia comum (sem
/// fundo), hoje (moldura de 2px em qualquer estado), marcado (fundo claro +
/// traço) e selecionado (fundo cheio). Selecionado **e** marcado é o fundo
/// cheio com o traço por cima — selecionar não apaga a informação que trouxe o
/// dedo até o dia. O traço fica porque cor sozinha não é sinal para quem não
/// distingue as duas.
///
/// A grade não sabe o que é escala nem indisponibilidade: quem chama descreve
/// cada dia em [describe].
class AppMonthGrid extends StatelessWidget {
  const AppMonthGrid({
    super.key,
    required this.month,
    required this.today,
    required this.describe,
    required this.onTap,
    this.keyPrefix = 'month-day-',
    this.showWeekdays = true,
    this.onlyWeekOf,
  });

  /// Mostra só a semana deste dia (calendário recolhido). Nulo: o mês todo.
  final DateTime? onlyWeekOf;

  /// A linha "D S T Q Q S S". Sai quando quem chama empilha vários meses e
  /// já mostra a linha uma vez, presa no topo.
  final bool showWeekdays;

  final DateTime month;
  final DateTime today;
  final AppMonthDay Function(DateTime day) describe;
  final ValueChanged<DateTime> onTap;

  /// Prefixo da chave de cada célula (`<prefixo>AAAA-MM-DD`), para os testes
  /// acharem o dia.
  final String keyPrefix;

  /// Quantos traços cabem embaixo do número sem virar tracejado.
  static const int maxMarks = 3;

  static const _weekdays = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final leading = DateTime(month.year, month.month).weekday % 7;
    final count = DateTime(month.year, month.month + 1, 0).day;
    final rows = ((leading + count) / 7).ceil();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Sete colunas de pelo menos 44px: abaixo disso, com a fonte do
        // sistema aumentada, a grade rola na horizontal em vez de espremer o
        // número do dia.
        final width = math.max(constraints.maxWidth, 7 * 44.0);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Table(
              children: [
                if (showWeekdays)
                TableRow(
                  children: [
                    for (final label in _weekdays)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: ExcludeSemantics(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                for (var row = 0; row < rows; row++)
                  if (onlyWeekOf == null ||
                      onlyWeekOf!.year != month.year ||
                      onlyWeekOf!.month != month.month ||
                      (leading + onlyWeekOf!.day - 1) ~/ 7 == row)
                  TableRow(
                    children: [
                      for (var col = 0; col < 7; col++)
                        if (row * 7 + col < leading ||
                            row * 7 + col >= leading + count)
                          const SizedBox.shrink()
                        else
                          _cell(
                            context,
                            DateTime(
                              month.year,
                              month.month,
                              row * 7 + col - leading + 1,
                            ),
                          ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cell(BuildContext context, DateTime day) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = describe(day);
    final isToday = dateKey(day) == dateKey(today);
    final marked = state.marks > 0;
    final tinted = marked || state.inRange;
    final palette = AppStatusColors.of(context).resolve(state.markTone, scheme);

    final background = state.selected
        ? scheme.primary
        : tinted
            ? palette.container
            : Colors.transparent;
    final foreground = state.selected
        ? scheme.onPrimary
        : tinted
            ? palette.onContainer
            : scheme.onSurface;

    final label = [
      _capitalize(
        DateFormat("EEEE, d 'de' MMMM 'de' y", 'pt_BR').format(day),
      ),
      if (isToday) 'hoje',
      if (state.detail != null) state.detail!,
    ].join(', ');

    return Semantics(
      key: ValueKey('$keyPrefix${dateKey(day)}'),
      button: state.enabled,
      enabled: state.enabled,
      selected: state.selected,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: state.enabled ? 1 : 0.4,
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: Material(
            color: background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              side: isToday
                  ? BorderSide(
                      color: state.selected ? scheme.onPrimary : scheme.primary,
                      width: 2,
                    )
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: state.enabled ? () => onTap(day) : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSpacing.touchTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${day.day}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          fontWeight: state.selected || isToday || marked
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // O espaço é reservado mesmo vazio: sem isto a grade
                      // sacode meio pixel entre um mês com marcas e outro sem.
                      if (state.icon != null)
                        Icon(state.icon, size: 12, color: foreground)
                      else
                        SizedBox(
                          height: 4,
                          child: marked
                              ? AppDayMarks(
                                  count: state.marks,
                                  color: foreground,
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Os traços embaixo do número: um por coisa, até [AppMonthGrid.maxMarks].
///
/// Traço e não ponto porque ele é mais largo que alto, e é essa proporção que
/// o faz aparecer num quadrado de 44px sem virar uma bolinha disputando espaço
/// com o número.
class AppDayMarks extends StatelessWidget {
  const AppDayMarks({super.key, required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final marks = count.clamp(1, AppMonthGrid.maxMarks);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < marks; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Container(
            width: 6,
            height: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ],
    );
  }
}

/// O dia marcado em miniatura, para a legenda embaixo da grade.
class AppDayLegendChip extends StatelessWidget {
  const AppDayLegendChip({super.key, this.tone = AppTone.primary});

  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = AppStatusColors.of(context).resolve(
      tone,
      Theme.of(context).colorScheme,
    );

    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: palette.container,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
      ),
      alignment: Alignment.center,
      child: AppDayMarks(count: 1, color: palette.onContainer),
    );
  }
}

String _capitalize(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
