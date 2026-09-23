import 'package:flutter/material.dart';

import '../../core/responsive/app_breakpoints.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_status_colors.dart';
import 'app_bottom_action_bar.dart';
import 'app_brand_mark.dart';
import 'app_notice.dart';
import 'unsaved_changes_guard.dart';

export 'app_notice.dart' show AppNotice;

/// Moldura comum das telas de formulario (login, cadastro, troca de senha).
///
/// **Com barra no topo, o título não se repete no corpo.** Sete formulários
/// diziam "Nova escala" na barra e "Nova escala" de novo logo abaixo, em corpo
/// grande, com 32px de folga antes e depois: quase 120px para repetir uma
/// palavra antes do primeiro campo. Agora [title] só existe quando acrescenta
/// algo que a barra não diz — o nome da música que está sendo editada, a
/// saudação do login —, e [subtitle] só quando explica alguma coisa.
///
/// [bottomAction] é o botão principal dos formulários longos, preso ao rodapé
/// (ver [AppBottomActionBar]). Nos curtos o botão continua em [children], no
/// fim.
class FormScaffold extends StatelessWidget {
  const FormScaffold({
    super.key,
    required this.children,
    this.title,
    this.subtitle,
    this.appBar,
    this.showBrand = false,
    this.bottomAction,
    this.isDirty,
  });

  final String? title;
  final String? subtitle;
  final List<Widget> children;
  final PreferredSizeWidget? appBar;
  final bool showBrand;
  final Widget? bottomAction;

  /// Com alteração por salvar, sair pergunta antes (ver
  /// [UnsavedChangesGuard]). Nulo nos formulários que não guardam trabalho —
  /// login, cadastro —, onde voltar não perde nada.
  final bool Function()? isDirty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasBar = appBar != null;
    final hasHeading = title != null || subtitle != null;

    // Mesma coluna do formulário: o botão preso embaixo tem a largura dos
    // campos, e não a da tela de leitura.
    final formWidth = AppBreakpoints.of(context).isDesktop
        ? AppBreakpoints.formMaxWidthDesktop
        : AppSpacing.formMaxWidth;

    final scaffold = Scaffold(
      appBar: appBar,
      bottomNavigationBar: bottomAction == null
          ? null
          : AppBottomActionBar(action: bottomAction!, maxWidth: formWidth),
      body: SafeArea(
        // Alinhado ao topo quando há AppBar: centralizar deixava um vazio
        // grande entre a barra e o título do formulário.
        child: Align(
          alignment: hasBar ? Alignment.topCenter : Alignment.center,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              // Logo abaixo da barra basta a folga de um bloco; a folga grande
              // é do formulário que abre sozinho no meio da tela (login).
              hasBar ? AppSpacing.xl : AppSpacing.xxl,
              AppSpacing.screenPadding,
              AppSpacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                // Mesma coluna de sempre no celular e no tablet; um pouco mais
                // larga no monitor (ver `formMaxWidthDesktop`).
                maxWidth: formWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showBrand) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: AppBrandLockup(),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                  if (title != null)
                    Text(title!, style: theme.textTheme.headlineMedium),
                  if (title != null && subtitle != null)
                    const SizedBox(height: AppSpacing.sm),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: (title == null
                              ? theme.textTheme.bodyMedium
                              : theme.textTheme.bodyLarge)
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  if (hasHeading)
                    SizedBox(
                      height: title == null ? AppSpacing.xl : AppSpacing.xxl,
                    ),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (isDirty == null) return scaffold;
    return UnsavedChangesGuard(isDirty: isDirty!, child: scaffold);
  }
}

/// Faixa de erro exibida acima dos botoes dos formularios.
///
/// É um [AppNotice] no tom de erro, com `liveRegion` ligado: é o que faz o
/// leitor de tela **anunciar** o erro quando ele aparece. Sem isso, quem toca
/// em "Entrar" com a senha errada não recebe resposta nenhuma.
class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AppNotice(
      message: message,
      tone: AppTone.danger,
      liveRegion: true,
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
    );
  }
}
