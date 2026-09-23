import 'package:flutter/material.dart';

import '../../../core/date/civil_date.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_month_grid.dart';

/// Calendário de consulta, independente dos modelos de escala e de Riverpod.
/// Segue a semana e as cores do seletor de indisponibilidade; aqui o passado
/// também é selecionável.
///
/// **O dia com compromisso é um dia pintado, não um dia com um ponto.** O ponto
/// de 5px embaixo do número era o desenho anterior, e ele pedia atenção para
/// ser notado: quem abre a agenda de relance — que é como ela é usada — via
/// trinta números iguais. Agora o dia marcado ganha o fundo de
/// `primaryContainer`, o número em negrito e um traço embaixo; o mês inteiro se
/// lê sem procurar. O traço fica porque cor sozinha não é sinal para quem não
/// distingue as duas, e porque é ele que conta **quantos** compromissos o dia
/// tem (um por compromisso, até três).
///
/// **Quatro estados, quatro desenhos diferentes**, e é isso que a tela precisa
/// garantir: dia comum (sem fundo), hoje (moldura), dia com compromisso (fundo
/// claro + traço) e dia selecionado (fundo cheio, da cor da marca). Selecionado
/// **com** compromisso é o fundo cheio com o traço por cima, em `onPrimary` —
/// selecionar um dia não pode apagar a informação que trouxe o dedo até ele.
///
/// **O que o traço significa é de quem chama** ([legend]): a agenda inteira
/// pinta os dias com algo marcado -- escala ou evento --, e o recorte pessoal
/// pinta os dias que são seus.
/// É o mesmo desenho dizendo duas coisas, e o rótulo embaixo é o que separa as
/// duas — inclusive para quem ouve a tela.
class AgendaCalendar extends StatelessWidget {
  const AgendaCalendar({
    super.key,
    required this.month,
    required this.selectedDay,
    required this.today,
    required this.markedDays,
    required this.onSelected,
    required this.onMonthChanged,
    required this.onToday,
    this.legend = 'Com compromisso',
    this.collapsed = false,
    this.onToggleCollapsed,
  });

  final DateTime month;

  /// Nulo quando nenhum dia está escolhido — trocar de mês não escolhe o dia
  /// 1 por conta própria.
  final DateTime? selectedDay;

  /// Recolhido, o calendário mostra só a semana do dia escolhido (ou de hoje).
  /// No celular o mês inteiro empurrava a lista para depois de uma tela e
  /// meia; recolher devolve a lista à primeira dobra.
  final bool collapsed;
  final VoidCallback? onToggleCollapsed;
  final DateTime today;

  /// Dia (`AAAA-MM-DD`) -> quantos compromissos ele tem.
  ///
  /// É um mapa e não um conjunto porque o número aparece: o traço embaixo do
  /// dia se repete uma vez por compromisso, e a leitura de tela diz "2
  /// compromissos" em vez de só "com compromisso".
  final Map<String, int> markedDays;
  final ValueChanged<DateTime> onSelected;
  final ValueChanged<DateTime> onMonthChanged;
  final VoidCallback onToday;

  /// O que um dia marcado quer dizer. Vai na legenda e na leitura de tela.
  final String legend;

  /// Quantos traços cabem embaixo do número sem virar tracejado.
  ///
  /// Acima disto a contagem some do desenho e fica só na leitura de tela e na
  /// lista do dia: três domingos de vigília não precisam de sete riscos de
  /// 4px para dizer "tem bastante coisa aqui".
  static const int maxMarks = AppMonthGrid.maxMarks;

  /// O dia cuja semana aparece recolhida: o escolhido, senão hoje (quando é
  /// este mês), senão o primeiro do mês.
  DateTime get _weekAnchor {
    final escolhido = selectedDay;
    if (escolhido != null &&
        escolhido.year == month.year &&
        escolhido.month == month.month) {
      return escolhido;
    }
    if (today.year == month.year && today.month == month.month) return today;
    return DateTime(month.year, month.month);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Mês anterior',
                onPressed: () => onMonthChanged(
                  DateTime(month.year, month.month - 1),
                ),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  monthYearLabel(month),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Próximo mês',
                onPressed: () => onMonthChanged(
                  DateTime(month.year, month.month + 1),
                ),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              // No cabeçalho, e não na legenda: ao lado de "Com compromisso"
              // e "Hoje" um terceiro botão espremia a legenda numa coluna de
              // letras em tela estreita.
              if (onToggleCollapsed != null)
                IconButton(
                  tooltip: collapsed
                      ? 'Mostrar o mês inteiro'
                      : 'Mostrar só a semana',
                  onPressed: onToggleCollapsed,
                  icon: Icon(
                    collapsed
                        ? Icons.unfold_more_rounded
                        : Icons.unfold_less_rounded,
                  ),
                ),
            ],
          ),
          AppMonthGrid(
            month: month,
            today: today,
            keyPrefix: 'agenda-day-',
            onTap: onSelected,
            onlyWeekOf: collapsed ? _weekAnchor : null,
            describe: (day) {
              final count = markedDays[dateKey(day)] ?? 0;
              return AppMonthDay(
                selected: selectedDay != null &&
                    dateKey(day) == dateKey(selectedDay!),
                marks: count,
                detail: count == 0
                    ? null
                    : count == 1
                        ? '1 compromisso'
                        : '$count compromissos',
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: [
                const AppDayLegendChip(),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    legend,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                TextButton(onPressed: onToday, child: const Text('Hoje')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
