import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_elevation.dart';
import '../../core/theme/app_spacing.dart';
import 'app_pressable.dart';

/// Como o cartão se separa da página.
enum CardSurface {
  /// **O padrão.** Superfície de cartão, fio de cabelo, nenhuma sombra.
  plain,

  /// Preenchimento discreto, sem borda — para blocos de apoio dentro de uma
  /// tela que já tem cartões, quando mais um contorno viraria ruído.
  sunken,

  /// Sombra de verdade. Só para o que realmente paira sobre o conteúdo.
  floating,
}

/// Superfície padrão de conteúdo.
///
/// **O cartão perdeu a sombra, e isso foi a maior mudança visual do app.** Cada
/// cartão trazia duas camadas de sombra; uma agenda com seis escalas empilhava
/// doze, e a tela lia-se como peças soltas pairando em cima de um fundo — o
/// efeito "tudo flutuando" que dá a qualquer app cara de modelo pronto.
///
/// O que separa o cartão da página agora é **cor** (a página desceu um passo em
/// `AppColors` para pagar por isso) mais um fio de `outlineVariant`, que no tema
/// claro faz o branco sobre quase-branco existir sem depender de sombra. É a
/// mesma razão de sempre — a sombra nunca foi o que fazia o cartão existir —
/// levada até o fim.
///
/// Uma consequência que vale nomear: o cartão continua legível com "reduzir
/// transparência" ligado no sistema, e em impressão.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.color,
    this.gradient,
    this.margin,
    this.surface = CardSurface.plain,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  /// Rampa no lugar da cor chapada. **Só a manchete da agenda usa isto**, e o
  /// parâmetro existe para que ela continue sendo um [AppCard] — mesmo raio,
  /// mesmo recorte, mesma resposta ao toque — em vez de um `Container` paralelo
  /// que iria envelhecer sozinho. Com rampa não há borda: quem separa o bloco
  /// da página é a própria diferença de tinta.
  final Gradient? gradient;

  final EdgeInsetsGeometry? margin;
  final CardSurface surface;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(borderRadius ?? AppSpacing.radiusLg);

    final background = gradient != null
        ? null
        : color ??
            switch (surface) {
              CardSurface.plain => scheme.surfaceContainerLowest,
              CardSurface.sunken => AppColors.sunken(scheme),
              CardSurface.floating => scheme.surfaceContainerLowest,
            };

    final padded =
        padding == null ? child : Padding(padding: padding!, child: child);

    // No claro o bloco rebaixado é um tom abaixo da página ([AppColors.sunken]),
    // e o botão tonal ("Escolher músicas", "Pôr no culto") tem quase esse
    // mesmo tom: dentro dele o botão perdia a forma. Aqui dentro ele fica
    // branco, como a superfície do cartão — o mesmo degrau que tem sobre a
    // página.
    final content = surface == CardSurface.sunken &&
            color == null &&
            scheme.brightness == Brightness.light
        ? Theme(
            data: Theme.of(context).copyWith(
              colorScheme: scheme.copyWith(
                secondaryContainer: scheme.surfaceContainerLowest,
              ),
            ),
            child: padded,
          )
        : padded;

    return Container(
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        color: background,
        gradient: gradient,
        borderRadius: radius,
        border: gradient != null
            ? null
            : switch (surface) {
                CardSurface.plain => Border.all(color: scheme.outlineVariant),
                CardSurface.sunken => null,
                CardSurface.floating => null,
              },
        boxShadow: surface == CardSurface.floating
            ? AppElevation.floating(scheme)
            : AppElevation.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : AppPressable(
              onTap: onTap,
              borderRadius: radius,
              child: content,
            ),
    );
  }
}
