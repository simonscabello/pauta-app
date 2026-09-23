import 'package:flutter/material.dart';

import '../../core/responsive/app_breakpoints.dart';
import '../../core/theme/app_spacing.dart';

/// A ação principal de uma tela, no lugar certo para o formato dela.
///
/// No celular é o botão flutuante, onde o polegar chega. Com a barra lateral
/// (tablet e monitor) ela sobe para o cabeçalho, ao lado do título — é o que
/// Início, Agenda e Equipe já faziam. Repertório, Sugestões, Cultos, Funções e
/// Minha disponibilidade mantinham o flutuante no canto de uma tela de 1284px:
/// o mesmo gesto, em dois lugares, conforme a tela.
///
/// Uma só descrição da ação, e cada lado pergunta a sua forma: [fab] para o
/// `floatingActionButton`, [headerAction] para as `actions` da barra.
class AppPrimaryAction {
  const AppPrimaryAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.wrap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  /// Para quem precisa marcar o botão (alvo do tour, por exemplo) nos dois
  /// formatos.
  final Widget Function(Widget button)? wrap;

  Widget _wrap(Widget button) => wrap == null ? button : wrap!(button);

  /// O botão flutuante, só no celular.
  Widget? fab(BuildContext context) {
    if (AppBreakpoints.of(context).isWide) return null;
    return _wrap(
      FloatingActionButton.extended(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }

  /// O botão do cabeçalho, só com a barra lateral à vista.
  Widget? headerAction(BuildContext context) {
    if (!AppBreakpoints.of(context).isWide) return null;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: _wrap(
        FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, AppSpacing.compactButtonHeight),
          ),
        ),
      ),
    );
  }
}
