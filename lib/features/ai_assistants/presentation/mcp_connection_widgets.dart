import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_button_styles.dart';
import '../../../shared/widgets/app_feedback.dart';

/// Copia e diz que copiou. Devolve `false` quando a área de transferência
/// recusou — no navegador isso acontece fora de contexto seguro —, e aí o
/// aviso manda selecionar à mão, que as caixas de texto permitem.
Future<bool> copyWithFeedback(
  BuildContext context,
  String text, {
  required String message,
}) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (_) {
    if (context.mounted) {
      showAppSnackBar(
        context,
        'Não foi possível copiar. Selecione o texto e copie à mão.',
        tone: AppTone.danger,
      );
    }
    return false;
  }
  if (context.mounted) {
    showAppSnackBar(context, message, tone: AppTone.success);
  }
  return true;
}

/// Texto que se cola num terminal ou num arquivo de configuração: fonte
/// monoespaçada, selecionável e quebrando em qualquer caractere.
///
/// Monoespaçada pelo mesmo motivo da senha temporária: a chave é base64url, e
/// `l`/`1` e `O`/`0` precisam ser distinguíveis para quem confere de olho.
class McpCodeBlock extends StatelessWidget {
  const McpCodeBlock({
    super.key,
    required this.text,
    this.emphasis = false,
    this.semanticsLabel,
  });

  final String text;

  /// A chave em si: maior e na cor da marca. O comando fica no tom do texto.
  final bool emphasis;

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base =
        emphasis ? theme.textTheme.titleSmall : theme.textTheme.bodySmall;

    return Semantics(
      label: semanticsLabel,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: scheme.outlineVariant),
        ),
        // O texto vai como é, sem caractere invisível para ajudar a quebrar a
        // linha: selecionar e copiar à mão (o plano B quando a área de
        // transferência recusa) levaria o invisível junto, e a chave colada
        // não funcionaria. Palavra maior que a linha o Flutter quebra sozinho.
        child: SelectableText(
          text,
          style: base?.copyWith(
            fontFamily: 'monospace',
            height: 1.5,
            letterSpacing: emphasis ? 0.3 : 0,
            fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400,
            color: emphasis ? scheme.primary : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Uma linha de grupo com um valor para copiar: o rótulo, o valor em fonte
/// monoespaçada e "Copiar" à direita. Mesmas medidas do `AppGroupRow`, que
/// só aceita subtítulo em texto corrido.
class McpCopyRow extends StatelessWidget {
  const McpCopyRow({
    super.key,
    required this.label,
    required this.value,
    required this.onCopy,
    this.icon,
    this.copyTooltip,
  });

  final String label;

  /// O que a linha mostra. Pode ser uma versão encurtada do que se copia.
  final String value;

  final VoidCallback onCopy;
  final IconData? icon;

  /// Para o leitor de tela: "Copiar" sozinho não diz o quê.
  final String? copyTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 22, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Tooltip(
            message: copyTooltip ?? 'Copiar $label',
            child: TextButton(
              style: AppButtonStyles.compactText,
              onPressed: onCopy,
              child: const Text('Copiar'),
            ),
          ),
        ],
      ),
    );
  }
}
