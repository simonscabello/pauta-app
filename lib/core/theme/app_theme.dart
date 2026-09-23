import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_status_colors.dart';
import 'app_typography.dart';

class AppTheme {
  const AppTheme._();

  /// Empacotada em assets/fonts (ver pubspec). Nao ha download em runtime:
  /// a tipografia precisa estar correta ja no primeiro frame, mesmo offline.
  static const String fontFamily = AppTypography.fontFamily;

  static ThemeData get light =>
      _build(AppColors.lightScheme(), AppStatusColors.light);
  static ThemeData get dark =>
      _build(AppColors.darkScheme(), AppStatusColors.dark);

  static ThemeData _build(ColorScheme scheme, AppStatusColors status) {
    // A escala inteira vem de `AppTypography`, e não da do Material com
    // remendos por cima. Antes eram treze `copyWith` sobre `material2021()`
    // ajustando peso e cor mas herdando tamanho e espacejamento — ou seja, a
    // voz continuava sendo a do Material.
    final textTheme = AppTypography.textTheme(scheme);

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [status],
      // Tambem no ThemeData: widgets que nao passam pelo textTheme (tooltip,
      // menus do sistema) herdam a familia daqui.
      fontFamily: fontFamily,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      // Foco visível para quem navega por teclado, teclado externo ou controle
      // adaptativo. O padrão do Flutter é um preto translúcido, que some no
      // tema escuro -- e foco invisível é o mesmo que não ter foco.
      focusColor: scheme.primary.withValues(alpha: 0.18),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        // Fio no lugar de sombra. A barra tem a cor da página, então sem
        // separação o conteúdo simplesmente **sumia por baixo dela** ao rolar:
        // não havia nem borda nem sombra dizendo onde a barra termina. Com
        // `scrolledUnderElevation` a linha só apareceria depois de rolar, e a
        // fronteira do cabeçalho não deveria depender de o usuário ter rolado.
        // O fio também sobrevive a "reduzir transparência" do sistema, que
        // apaga tinta de superfície.
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          // O mesmo raio do `AppCard`: os dois desenham "um cartão", e raios
          // diferentes faziam a mesma coisa parecer duas.
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        // Campo mais alto: 12 de folga vertical dava um campo de ~44px, mais
        // baixo que o botão logo abaixo dele no mesmo formulário. Campo e botão
        // encostados com alturas diferentes é o detalhe que faz um formulário
        // parecer montado em vez de desenhado.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      // A hierarquia dos botões, de cima para baixo:
      //
      //   primária    `FilledButton`        azul cheio — uma por tela
      //   secundária  `FilledButton.tonal`  ardósia — alternativa de igual peso
      //   terciária   `TextButton`          só texto — ação de apoio
      //   destrutiva  vermelho, e só onde já houve confirmação
      //
      // Contornado saiu do caminho principal: borda sem preenchimento fica
      // entre o tonal e o texto sem ser melhor que nenhum dos dois, e três
      // níveis intermediários é o que apaga a hierarquia.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Só altura mínima. `Size.fromHeight` significa largura infinita, e
          // isso quebrava qualquer botão preenchido dentro de uma Row -- era o
          // motivo de "Copiar convite" não aparecer na tela de convites.
          // Nos formulários a largura total continua vindo do
          // `CrossAxisAlignment.stretch` do FormScaffold.
          minimumSize: const Size(0, AppSpacing.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          textStyle: textTheme.labelLarge,
        ).copyWith(side: _focusRing(scheme.onSurface)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          textStyle: textTheme.labelLarge,
        ).copyWith(
          side: _focusRing(
            scheme.primary,
            otherwise: BorderSide(color: scheme.outline),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.touchTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          textStyle: textTheme.labelLarge,
        ).copyWith(side: _focusRing(scheme.primary)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        // O botão flutuante é uma das poucas coisas que **de fato** flutua, e
        // por isso continua sendo uma das poucas com sombra.
        elevation: 3,
        focusElevation: 3,
        hoverElevation: 5,
        highlightElevation: 1,
        extendedTextStyle: textTheme.labelLarge,
        // `radiusXl` e não o raio de controle: com 56px de altura, este é o
        // único botão do app em que o canto de 28 vira pílula — e é o que a
        // identidade pede para a peça que flutua sobre a lista. Continua na
        // escala de raios; não é um número solto.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        // `outline` e não `outlineVariant`: chip aqui é sempre tocável
        // (escolher tipo, andamento, abrir a cifra), e a borda é o que diz onde
        // ele começa. Isso pede os 3:1 do WCAG 1.4.11, que o fio decorativo
        // não tem.
        side: BorderSide(color: scheme.outline),
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(shape),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        // `radiusXl`, como a folha: os dois cobrem a tela, e o que cobre a tela
        // tem o canto mais aberto da escala. Um diálogo com o raio do cartão
        // parece um cartão que escapou da lista.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          // O ícone tem 20-24px; sem piso, a área tocável ficava do tamanho
          // dele. Quem usa o app está com o instrumento na mão.
          minimumSize: const Size(
            AppSpacing.touchTarget,
            AppSpacing.touchTarget,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
        ).copyWith(side: _focusRing(scheme.primary)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        // Piso de altura mesmo em `dense`, que é onde as linhas encolhiam para
        // ~40 e escapavam do dedo.
        minVerticalPadding: AppSpacing.sm,
        minTileHeight: AppSpacing.touchTarget,
        titleTextStyle: textTheme.titleSmall,
        subtitleTextStyle: textTheme.bodySmall,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: scheme.shadow,
        labelTextStyle: WidgetStatePropertyAll(textTheme.bodyMedium),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
      ),
      // As folhas (adicionar culto, editar função, abrir a cifra) herdavam o
      // padrão do Material: cantos e cor diferentes dos cartões da mesma tela.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: scheme.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXl),
          ),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.24),
        selectionHandleColor: scheme.primary,
      ),
    );
  }
}

/// O anel de foco dos botões: 2px quando o foco é de teclado (WCAG 2.4.7).
///
/// O `focusColor` sozinho só clareava o fundo — num botão cheio, e no tema
/// escuro, a diferença não se via, e quem navega pelo Tab não sabia onde
/// estava. O anel aparece só no foco, e some no toque e no mouse.
WidgetStateProperty<BorderSide?> _focusRing(
  Color color, {
  BorderSide? otherwise,
}) {
  return WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused)
        ? BorderSide(color: color, width: 2)
        : otherwise,
  );
}
