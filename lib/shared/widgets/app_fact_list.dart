import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import 'app_card.dart';

/// Um fato de [AppFactList]: rótulo à esquerda, valor em destaque à direita.
class AppFact {
  const AppFact({
    required this.label,
    required this.value,
    required this.icon,
    this.hint,
    this.highlight = false,
  });

  final String label;

  /// O valor. Com `\n`, uma linha por item (um culto por linha).
  final String value;
  final IconData icon;

  /// Linha de apoio embaixo do valor ("equipe: G", "domingo").
  final String? hint;

  /// Valor e ícone na cor da marca — o que é decisão da equipe, ou sobre você.
  final bool highlight;
}

/// Os fatos que respondem à primeira pergunta de uma tela, um por linha.
///
/// O cabeçalho das telas de detalhe: a escala (Cultos · Ensaio · Sua função),
/// a música (Tom · Tipo · Andamento), a música dentro da escala e o evento da
/// equipe (Data · Horário).
///
/// **Linhas, e não colunas.** Isto já foi uma faixa de colunas iguais
/// separadas por fios (`AppFactsStrip`), e ela falhava justamente no que mais
/// importa: cada fato tinha um terço da largura, então "Vocal · Teclado"
/// quebrava em duas linhas, "Culto da Terceira Idade" encolhia até virar
/// letra miúda e o "10:45" do ensaio flutuava no meio de uma coluna vazia.
/// Para caber, ela trocava ícone por nada e encolhia texto, e cada escala
/// saía com um desenho diferente. Numa linha o valor tem a largura toda: o
/// rótulo fica à esquerda, o valor à direita, e o que for comprido quebra
/// dentro do próprio lado — nada encolhe e nada vira reticências.
class AppFactList extends StatelessWidget {
  const AppFactList({super.key, required this.facts});

  final List<AppFact> facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < facts.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: AppSpacing.lg + _FactRow.badgeSize + AppSpacing.md,
                color: theme.colorScheme.outlineVariant,
              ),
            _FactRow(fact: facts[i]),
          ],
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.fact});

  final AppFact fact;

  static const badgeSize = 36.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final multiline = fact.value.contains('\n') || fact.hint != null;

    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: fact.highlight ? scheme.primary : scheme.onSurface,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        // Valor de uma linha: tudo no meio. Valor de várias linhas (dois
        // cultos): ícone e rótulo ficam na altura da primeira, que é onde o
        // olho começa a ler.
        crossAxisAlignment:
            multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Container(
            width: badgeSize,
            height: badgeSize,
            decoration: BoxDecoration(
              color: fact.highlight
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(
              fact.icon,
              size: 20,
              color: fact.highlight
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 2,
            child: Padding(
              padding: EdgeInsets.only(top: multiline ? 8 : 0),
              child: Text(
                fact.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 3,
            child: Padding(
              padding: EdgeInsets.only(top: multiline ? 6 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final line in fact.value.split('\n'))
                    Text(line, textAlign: TextAlign.end, style: valueStyle),
                  if (fact.hint != null)
                    Text(
                      fact.hint!,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
