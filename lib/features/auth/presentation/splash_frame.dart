import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_brand_mark.dart';

/// O fundo violeta com a marca, usado pela [SplashScreen] e pela
/// [UnlockScreen].
///
/// **Existe para a marca não pular.** As duas telas repetiam o mesmo layout
/// em dois arquivos, e eles já tinham divergido: qualquer ajuste numa delas
/// movia a marca na hora em que a abertura vira desbloqueio. Agora só o que
/// vai embaixo ([below]) muda — o indicador, ou as saídas do desbloqueio.
///
/// A rolagem mora aqui: as saídas com uma mensagem de erro numa tela baixa
/// passam da altura, e o frame rola em vez de estourar. Com conteúdo que
/// cabe, o bloco fica no centro da viewport.
class SplashFrame extends StatelessWidget {
  const SplashFrame({
    super.key,
    required this.below,
    this.subtitle = defaultSubtitle,
  });

  static const defaultSubtitle = 'Sua equipe no mesmo ritmo.';

  final Widget below;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A mesma cor da abertura nativa do Android e do boot da Web: o primeiro
      // frame do Flutter substitui o splash do sistema sem um clarão ou uma
      // troca de marca.
      backgroundColor: AppColors.brandDeepViolet,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPadding,
                    vertical: AppSpacing.xxl,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(
                          child: AppBrandGlyph(size: 96, onDark: true),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          'PAUTA',
                          textAlign: TextAlign.center,
                          style: AppTypography.wordmark(
                            context,
                            size: 34,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.brandLavender,
                                  ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        below,
                      ],
                    ),
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

/// O indicador da abertura, o mesmo nas duas telas.
class SplashProgress extends StatelessWidget {
  const SplashProgress({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: Colors.white,
          backgroundColor: Color(0x4DFFFFFF),
        ),
      ),
    );
  }
}
