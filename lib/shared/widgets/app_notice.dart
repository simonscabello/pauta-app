import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_status_colors.dart';

/// Um aviso dentro da página: erro de formulário, alguém que não pode no dia,
/// versão nova disponível.
///
/// **Existe porque havia seis desenhos para a mesma coisa.** Faixa com barra
/// lateral no erro de formulário e na indisponibilidade, bloco lavanda na
/// atualização, caixa tingida própria nos convites, bloco colorido no resumo da
/// escalação. Cada um com raio, folga e tipografia seus — e a pessoa não tinha
/// como saber que eram o mesmo tipo de recado.
///
/// **Sem barra lateral.** A barra de cor encostada num cartão arredondado é o
/// enfeite mais reconhecível de interface montada com peça pronta, e aqui ela
/// não dizia nada que o fundo tingido e o ícone já não dissessem.
///
/// A cor sai de [AppTone]: escolher o tom é escolher o significado.
class AppNotice extends StatelessWidget {
  const AppNotice({
    super.key,
    required this.message,
    this.title,
    this.tone = AppTone.info,
    this.icon,
    this.action,
    this.liveRegion = false,
    this.margin,
  });

  final String message;
  final String? title;
  final AppTone tone;

  /// Nulo usa o ícone do tom.
  final IconData? icon;

  /// Uma ação curta à direita ("Atualizar"). Botão de texto, nunca cheio: o
  /// aviso não é a ação principal da tela.
  final Widget? action;

  /// Anuncia o aviso ao leitor de tela quando ele aparece. Ligado nos erros:
  /// sem isso, quem toca em "Entrar" com a senha errada não ouve resposta.
  final bool liveRegion;

  final EdgeInsetsGeometry? margin;

  static IconData _iconFor(AppTone tone) => switch (tone) {
        AppTone.danger => Icons.error_outline_rounded,
        AppTone.warning => Icons.warning_amber_rounded,
        AppTone.success => Icons.check_circle_outline_rounded,
        AppTone.info ||
        AppTone.neutral ||
        AppTone.primary =>
          Icons.info_outline_rounded,
      };

  /// Abaixo desta largura a ação vai para baixo do texto.
  static const double _stackBelow = 480;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette =
        AppStatusColors.of(context).resolve(tone, theme.colorScheme);

    return Semantics(
      liveRegion: liveRegion,
      container: true,
      child: Container(
        margin: margin,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          action == null ? AppSpacing.lg : AppSpacing.sm,
          AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: palette.container,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        // Estreito, a ação desce para baixo do texto: ao lado dele, um botão
        // comprido ("Ver em Ministério de Louvor", "Tirar de todas as
        // funções") espremia a frase numa coluna de uma palavra por linha.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final icone =
                Icon(icon ?? _iconFor(tone), size: 20, color: palette.onContainer);
            final textos = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: palette.onContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: (title == null
                          ? theme.textTheme.bodyMedium
                          : theme.textTheme.bodySmall)
                      ?.copyWith(color: palette.onContainer),
                ),
              ],
            );
            final acao = action == null
                ? null
                : TextButtonTheme(
                    data: TextButtonThemeData(
                      style: TextButton.styleFrom(
                        foregroundColor: palette.onContainer,
                        minimumSize:
                            const Size(0, AppSpacing.compactButtonHeight),
                      ),
                    ),
                    child: action!,
                  );

            if (acao != null && constraints.maxWidth < _stackBelow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      icone,
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: textos),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(left: 20 + AppSpacing.md),
                    child: acao,
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: action == null
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                icone,
                const SizedBox(width: AppSpacing.md),
                Expanded(child: textos),
                if (acao != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  acao,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
