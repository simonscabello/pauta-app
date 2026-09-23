import 'package:flutter/material.dart';

import '../../core/responsive/app_breakpoints.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_status_colors.dart';
import 'app_avatar.dart';
import 'app_badge.dart';
import 'app_brand_mark.dart';

/// Um destino da barra lateral. `route` é sempre uma rota que **existe** no
/// `app_router.dart` — a barra expõe melhor o que o app já faz, não inventa
/// lugar novo para ir.
class AppNavDestination {
  const AppNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.route,
    this.badge,
    this.alsoMatches = const [],
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;

  /// Um número ao lado do nome (sugestões esperando resposta). Nulo ou zero:
  /// nada. O número aparecia no ladrilho da Home e não aqui, que é onde o
  /// olho está no monitor.
  final int? badge;

  /// Outras rotas que acendem este destino, além das que começam por [route].
  /// "Relatórios do repertório" moram em `/equipe/musicas/...`, mas se chega a
  /// eles por Gerenciar equipe — e era "Repertório" que acendia.
  final List<String> alsoMatches;
}

/// Um bloco de destinos, com um rótulo por cima.
///
/// Sete itens seguidos leem-se como uma lista de compras. Três blocos de dois
/// ou três leem-se como um mapa do app — e é o rótulo que faz "Convites" e
/// "Gerenciar equipe" se explicarem sem precisar de subtítulo.
class AppNavSection {
  const AppNavSection({this.title, required this.destinations});

  final String? title;
  final List<AppNavDestination> destinations;
}

/// Navegação lateral do desktop.
///
/// **Pura apresentação**: recebe destinos, quem está usando e o que fazer, e
/// não conhece Riverpod nem go_router. Quem monta os dados é a casca
/// (`MainShell`), que é onde já vivia a decisão de navegação.
///
/// Dois formatos, o mesmo widget: aberta (rótulo ao lado do ícone) no monitor,
/// recolhida (só ícone, com dica ao passar o mouse) em tablet e em janela
/// estreita. A lista **rola**: um celular deitado tem 375px de altura, e uma
/// barra que não rola vira `RenderFlex overflow` na primeira rotação.
class AppSideNav extends StatelessWidget {
  const AppSideNav({
    super.key,
    required this.sections,
    required this.currentPath,
    required this.expanded,
    required this.userName,
    required this.onSelect,
    required this.onLogout,
    this.avatarUrl,
    this.teamName,
    this.teams = const [],
    this.activeTeamId,
    this.onTeamChanged,
    this.profileRoute = '/perfil',
  });

  final List<AppNavSection> sections;
  final String currentPath;
  final bool expanded;
  final String userName;
  final String? avatarUrl;
  final String? teamName;
  final List<({String id, String name})> teams;
  final String? activeTeamId;
  final ValueChanged<String>? onTeamChanged;
  final ValueChanged<String> onSelect;
  final VoidCallback onLogout;
  final String profileRoute;

  /// A rota selecionada é a **mais específica** que prefixa o caminho atual.
  ///
  /// Sem isso `/equipe/musicas` acenderia "Equipe" (porque `/equipe` prefixa o
  /// caminho) em vez de "Repertório", e a barra mentiria sobre onde a pessoa
  /// está — que é a única coisa que uma barra lateral precisa acertar.
  @visibleForTesting
  static String? selectedRouteFor(
    List<AppNavSection> sections,
    String currentPath, {
    String profileRoute = '/perfil',
  }) {
    String? best;
    var bestLength = -1;
    for (final section in sections) {
      for (final destination in section.destinations) {
        // A rota mais específica ganha, contando também as rotas a mais do
        // destino: `/equipe/musicas/uso` casa com Repertório pelo prefixo e
        // com Gerenciar equipe por [AppNavDestination.alsoMatches], e o
        // prefixo mais longo decide.
        for (final prefix in [destination.route, ...destination.alsoMatches]) {
          final matches =
              currentPath == prefix || currentPath.startsWith('$prefix/');
          if (matches && prefix.length > bestLength) {
            best = destination.route;
            bestLength = prefix.length;
          }
        }
      }
    }
    if (best != null) return best;
    if (currentPath == profileRoute ||
        currentPath.startsWith('$profileRoute/')) {
      return profileRoute;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected =
        selectedRouteFor(sections, currentPath, profileRoute: profileRoute);

    return Container(
      width: expanded
          ? AppBreakpoints.sideNavWidth
          : AppBreakpoints.sideNavRailWidth,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(expanded: expanded, teamName: teamName),
            if (expanded && teams.length > 1)
              _TeamSwitcher(
                teams: teams,
                activeTeamId: activeTeamId,
                onChanged: onTeamChanged,
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final section in sections) ...[
                      if (expanded && section.title != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.xl,
                            AppSpacing.lg,
                            AppSpacing.lg,
                            AppSpacing.sm,
                          ),
                          child: Text(
                            section.title!.toUpperCase(),
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                          ),
                        )
                      else if (!expanded && section != sections.first)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.sm,
                          ),
                          child: Divider(
                            height: 1,
                            color: scheme.outlineVariant,
                          ),
                        ),
                      for (final destination in section.destinations)
                        _NavItem(
                          destination: destination,
                          selected: destination.route == selected,
                          expanded: expanded,
                          onTap: () => onSelect(destination.route),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            _UserFooter(
              expanded: expanded,
              name: userName,
              avatarUrl: avatarUrl,
              selected: selected == profileRoute,
              onOpenProfile: () => onSelect(profileRoute),
              onLogout: onLogout,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.expanded, this.teamName});

  final bool expanded;
  final String? teamName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!expanded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: AppBrandMark(size: 36)),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppBrandLockup(),
          if (teamName != null && teamName!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Icon(Icons.groups_rounded, size: 14, color: scheme.primary),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    teamName!,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Trocar de equipe sem sair de onde se está.
///
/// A agenda já tinha o seletor no cabeçalho; no desktop ele sobe para a barra
/// porque a equipe ativa vale para **todas** as telas, e não só para a agenda.
class _TeamSwitcher extends StatelessWidget {
  const _TeamSwitcher({
    required this.teams,
    required this.activeTeamId,
    required this.onChanged,
  });

  final List<({String id, String name})> teams;
  final String? activeTeamId;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: PopupMenuButton<String>(
        tooltip: 'Trocar equipe',
        initialValue: activeTeamId,
        onSelected: onChanged,
        itemBuilder: (_) => [
          for (final team in teams)
            PopupMenuItem(value: team.id, child: Text(team.name)),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Trocar equipe',
                  style: Theme.of(context).textTheme.labelMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.unfold_more_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uma linha da barra.
///
/// O selecionado é um bloco tingido com o rótulo em negrito, e não uma barra
/// vertical na borda: com a barra, o item aceso e os apagados tinham o mesmo
/// peso de texto, e a pessoa precisava procurar o marcador para saber onde
/// estava. O `hoverColor` do `InkWell` cuida do mouse — discreto, um degrau.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final AppNavDestination destination;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurface;

    final content = Row(
      mainAxisAlignment:
          expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
      children: [
        Badge(
          // Recolhida, a barra só tem o ícone: o número vai nele.
          isLabelVisible: !expanded && (destination.badge ?? 0) > 0,
          label: Text('${destination.badge ?? 0}'),
          child: Icon(
            selected ? destination.selectedIcon : destination.icon,
            size: 21,
            color:
                selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          ),
        ),
        if (expanded) ...[
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              destination.label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: foreground,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if ((destination.badge ?? 0) > 0)
            AppBadge(
              label: '${destination.badge}',
              tone: AppTone.primary,
              emphasis: BadgeEmphasis.solid,
              semanticsLabel: '${destination.badge} aguardando resposta',
            ),
        ],
      ],
    );

    final button = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? AppSpacing.md : AppSpacing.sm,
        vertical: 2,
      ),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          hoverColor: scheme.onSurface.withValues(alpha: 0.05),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.touchTarget,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: expanded ? AppSpacing.md : 0,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );

    // A dica é o que torna a barra recolhida utilizável: sem ela são seis
    // ícones mudos numa coluna de 76px.
    return expanded
        ? Semantics(selected: selected, child: button)
        : Tooltip(
            message: destination.label,
            child: Semantics(
              selected: selected,
              label: destination.label,
              child: button,
            ),
          );
  }
}

class _UserFooter extends StatelessWidget {
  const _UserFooter({
    required this.expanded,
    required this.name,
    required this.avatarUrl,
    required this.selected,
    required this.onOpenProfile,
    required this.onLogout,
  });

  final bool expanded;
  final String name;
  final String? avatarUrl;
  final bool selected;
  final VoidCallback onOpenProfile;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final danger = AppStatusColors.of(context).danger.foreground;

    final logout = Tooltip(
      message: 'Sair da conta',
      child: IconButton(
        onPressed: onLogout,
        icon: Icon(Icons.logout_rounded, size: 20, color: danger),
      ),
    );

    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          children: [
            Tooltip(
              message: 'Perfil',
              child: IconButton(
                onPressed: onOpenProfile,
                icon: AppAvatar(name: name, imageUrl: avatarUrl, radius: 14),
              ),
            ),
            logout,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: selected ? scheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: InkWell(
                onTap: onOpenProfile,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                hoverColor: scheme.onSurface.withValues(alpha: 0.05),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      AppAvatar(name: name, imageUrl: avatarUrl, radius: 16),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: selected
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurface,
                              ),
                            ),
                            Text(
                              'Perfil',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          logout,
        ],
      ),
    );
  }
}
