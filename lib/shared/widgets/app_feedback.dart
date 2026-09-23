import 'package:flutter/material.dart';

import '../../core/responsive/app_breakpoints.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_status_colors.dart';

/// Avisa que a ação terminou — e diz **como** terminou.
///
/// O app inteiro usava `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))`
/// escrito à mão, sempre na mesma barra cinza-escura. "Convite copiado" e "Não
/// foi possível remover" chegavam idênticos, e a única forma de saber o
/// desfecho era ler a frase até o fim — em uma barra que some em quatro
/// segundos. A cor e o ícone respondem antes da leitura; o texto confirma.
///
/// Também **substitui a barra anterior** em vez de enfileirar: tocar duas vezes
/// num botão gerava duas barras em sequência, e a segunda parecia um erro novo.
void showAppSnackBar(
  BuildContext context,
  String message, {
  AppTone tone = AppTone.info,
  SnackBarAction? action,
}) {
  final scheme = Theme.of(context).colorScheme;
  final palette = AppStatusColors.of(context).resolve(tone, scheme);

  final icon = switch (tone) {
    AppTone.success => Icons.check_circle_rounded,
    AppTone.warning => Icons.warning_amber_rounded,
    AppTone.danger => Icons.error_rounded,
    AppTone.info || AppTone.neutral || AppTone.primary => Icons.info_rounded,
  };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: palette.container,
        // Erro fica mais tempo: costuma trazer o motivo, e o motivo é uma
        // frase inteira.
        duration: Duration(seconds: tone == AppTone.danger ? 6 : 4),
        // Numa janela larga a barra atravessava o monitor inteiro para dizer
        // duas palavras, longe de onde o olho estava.
        width: AppBreakpoints.of(context).isWide ? 520 : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: BorderSide(color: palette.foreground.withValues(alpha: 0.35)),
        ),
        content: Row(
          children: [
            Icon(icon, size: 20, color: palette.onContainer),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.onContainer,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ],
        ),
        // A ação na cor do texto do aviso: com a cor padrão (a da marca) ela
        // sumia sobre o verde e o âmbar dos avisos de sucesso e de atenção.
        action: action == null
            ? null
            : SnackBarAction(
                label: action.label,
                onPressed: action.onPressed,
                textColor: palette.onContainer,
              ),
      ),
    );
}

/// Pergunta antes de fazer o que não tem volta.
///
/// Era um `AlertDialog` remontado à mão em cada tela — cinco cópias, e o botão
/// vermelho aparecia em três delas. Aqui a regra fica em um lugar: **ação
/// destrutiva é vermelha e nunca é o padrão do teclado**; cancelar é sempre a
/// saída fácil.
///
/// Devolve `false` quando a pessoa fecha por fora do diálogo — não existe
/// "talvez" numa confirmação.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  // Obrigatório: o botão diz o que acontece ("Excluir escala", "Sair"). Um
  // "Confirmar" padrão deixava a regra do app a um parâmetro esquecido.
  required String confirmLabel,
  String cancelLabel = 'Cancelar',
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}
