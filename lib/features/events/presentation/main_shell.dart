import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive/app_breakpoints.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_side_nav.dart';
import '../../auth/application/auth_controller.dart';
import '../../suggestions/data/suggestion_repository.dart';
import '../../team/data/team_repository.dart';

/// Casca com a navegação principal.
///
/// **Duas navegações, uma casca.** No celular são quatro abas na barra
/// inferior (Início, Agenda, Equipe, Perfil): é onde o polegar chega, e o app
/// foi desenhado para isso. A partir de 600px de largura a barra inferior sai e
/// entra uma barra lateral — recolhida (só ícones) em tablet e em janela
/// estreita, aberta no monitor.
///
/// **Início abre a lista porque é a porta de entrada**: é a aba em que o app
/// abre depois do login, e a única que responde "quando *eu* toco?" antes de
/// qualquer outra coisa. A Agenda continua exatamente onde estava, uma aba
/// adiante.
///
/// A troca é por **largura da janela**, não por plataforma: não há `kIsWeb`
/// aqui. Um Android em tablet ganha a barra lateral pelo mesmo motivo que o
/// Chrome ganha, e reduzir a janela do navegador devolve a barra inferior.
///
/// A barra lateral existe porque no monitor as três abas do celular escondiam o
/// resto do app atrás de dois toques (Equipe → engrenagem → Convites). Ela não
/// acrescenta destino nenhum: só põe à vista rotas que já existiam.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  static const _tabs = ['/inicio', '/agenda', '/equipe', '/perfil'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    final name = user?.firstName ?? '?';
    final form = AppBreakpoints.of(context);

    // Um mensageiro só para o conteúdo da casca. Sem ele os avisos subiam no
    // Scaffold da casca, que não sabe da barra de baixo de cada tela: "Escala
    // salva" cobria o "Publicar" por quatro segundos, e no monitor atravessava
    // por cima da barra lateral. Com ele, cada tela é a dona do aviso, e o
    // Flutter já o põe acima da barra de ação dela.
    final content = ScaffoldMessenger(child: child);

    if (form.isWide) {
      return _WideShell(path: path, expanded: form.isDesktop, child: content);
    }

    final index = _tabs.indexOf(path);
    // A barra só aparece nas telas de topo; em formulários e detalhes ela
    // atrapalharia o caminho de volta.
    final showNav = index != -1;

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: content,
      // Fio em cima da barra, como no cabeçalho. Sem ele a barra tem a cor do
      // cartão e o conteúdo passa por baixo sem fronteira nenhuma — e agora que
      // os cartões não projetam sombra, não sobrou nada separando os dois.
      bottomNavigationBar: showNav
          ? DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (selected) =>
                    context.go(_tabs[selected]),
                // O rótulo fica sempre visível. Com `onlyShowSelected` os dois
                // ícones não escolhidos viram desenhos mudos, e "grupo de
                // pessoas" versus "calendário" é justamente o par que quem não
                // tem intimidade com aplicativo não decifra sozinho.
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Início',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.calendar_today_outlined),
                    selectedIcon: Icon(Icons.calendar_today_rounded),
                    label: 'Agenda',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.groups_outlined),
                    selectedIcon: Icon(Icons.groups_rounded),
                    label: 'Equipe',
                  ),
                  NavigationDestination(
                    // O avatar como ícone: a aba é sobre a própria pessoa, e
                    // isso identifica melhor que um boneco genérico.
                    icon: AppAvatar(
                      name: name,
                      imageUrl: user?.avatarUrl,
                      radius: 13,
                    ),
                    label: 'Perfil',
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

/// A casca de tablet e monitor: barra lateral à esquerda, conteúdo à direita.
class _WideShell extends ConsumerWidget {
  const _WideShell({
    required this.path,
    required this.expanded,
    required this.child,
  });

  final String path;
  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final activeTeamId = ref.watch(activeTeamIdProvider);
    final team = auth.teams.where((t) => t.teamId == activeTeamId).firstOrNull ??
        auth.teams.firstOrNull;
    // A mesma regra da agenda: o papel vem da equipe **ativa**, não de
    // `teams.first`. Quem lidera numa equipe e só participa de outra não pode
    // ver "Convites" na barra enquanto a equipe ativa é a segunda.
    final canManage = team?.canManage ?? false;
    // O mesmo número do ladrilho da Home e do selo da aba Equipe (mesma
    // chave de cache): só para quem responde às sugestões.
    final pendingSuggestions = canManage && activeTeamId != null
        ? ref.watch(openSuggestionCountProvider(activeTeamId)).valueOrNull
        : null;

    return Scaffold(
      body: Row(
        children: [
          AppSideNav(
            expanded: expanded,
            currentPath: path,
            userName: auth.user?.firstName ?? '?',
            avatarUrl: auth.user?.avatarUrl,
            teamName: team?.name,
            activeTeamId: activeTeamId,
            teams: [
              for (final item in auth.teams) (id: item.teamId, name: item.name),
            ],
            onTeamChanged: (id) =>
                ref.read(activeTeamIdProvider.notifier).select(id),
            sections: _sectionsFor(
              canManage: canManage,
              pendingSuggestions: pendingSuggestions,
            ),
            // `go`, e não `push`: a barra lateral troca de seção, não empilha.
            // Empilhar aqui faria a pilha crescer a cada clique e o botão
            // "voltar" do navegador percorrer o histórico de cliques na barra.
            onSelect: (route) => context.go(route),
            onLogout: () => _confirmLogout(context, ref),
          ),
          // **Um contêiner semântico só para o conteúdo.** Cada página da
          // casca traz a barreira do Navigator, que bloqueia a semântica de
          // tudo o que foi pintado antes dela no mesmo contêiner — e a barra
          // lateral, à esquerda, era pintada antes. O leitor de tela achava
          // só a área de conteúdo; Início, Agenda e Repertório não existiam.
          Expanded(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  /// Só rotas que existem em `app_router.dart`. Nada aqui é funcionalidade
  /// nova — é o mesmo app, com os caminhos à vista.
  List<AppNavSection> _sectionsFor({
    required bool canManage,
    int? pendingSuggestions,
  }) {
    return [
      AppNavSection(
        destinations: [
          const AppNavDestination(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            label: 'Início',
            route: '/inicio',
          ),
          const AppNavDestination(
            icon: Icons.calendar_today_outlined,
            selectedIcon: Icons.calendar_today_rounded,
            label: 'Agenda',
            route: '/agenda',
          ),
          const AppNavDestination(
            icon: Icons.groups_outlined,
            selectedIcon: Icons.groups_rounded,
            label: 'Equipe',
            route: '/equipe',
          ),
          const AppNavDestination(
            icon: Icons.library_music_outlined,
            selectedIcon: Icons.library_music_rounded,
            label: 'Repertório',
            route: '/equipe/musicas',
          ),
          // Fora do bloco "Gestão" de propósito: sugerir é da equipe inteira.
          AppNavDestination(
            icon: Icons.lightbulb_outline_rounded,
            selectedIcon: Icons.lightbulb_rounded,
            label: 'Sugestões',
            route: '/equipe/sugestoes',
            badge: pendingSuggestions,
          ),
        ],
      ),
      const AppNavSection(
        title: 'Minha participação',
        destinations: [
          AppNavDestination(
            icon: Icons.event_busy_outlined,
            selectedIcon: Icons.event_busy_rounded,
            label: 'Minha disponibilidade',
            route: '/disponibilidade',
          ),
        ],
      ),
      if (canManage)
        const AppNavSection(
          title: 'Gestão',
          destinations: [
            AppNavDestination(
              icon: Icons.link_outlined,
              selectedIcon: Icons.link_rounded,
              label: 'Convites',
              route: '/equipe/convites',
            ),
            // "Quem não pode" é o que mais se consulta na semana de quem
            // monta a escala, e só se chegava a ele por Gerenciar equipe.
            AppNavDestination(
              icon: Icons.event_busy_outlined,
              selectedIcon: Icons.event_busy_rounded,
              label: 'Quem não pode',
              route: '/equipe/indisponibilidade',
            ),
            AppNavDestination(
              icon: Icons.balance_outlined,
              selectedIcon: Icons.balance_rounded,
              label: 'Participação',
              route: '/equipe/participacao',
            ),
            AppNavDestination(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_rounded,
              label: 'Gerenciar equipe',
              route: '/equipe/gerenciar',
              // As telas que só se abrem a partir de Gerenciar equipe.
              alsoMatches: [
                '/equipe/musicas/uso',
                '/equipe/musicas/saude',
                '/equipe/cultos',
                '/equipe/funcoes',
                '/equipe/dados',
              ],
            ),
          ],
        ),
    ];
  }

  /// A mesma pergunta do Perfil: voltar custa digitar e-mail e senha.
  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sair da conta?',
      message: 'Para voltar você vai precisar do e-mail e da senha. As escalas '
          'da equipe continuam onde estão.',
      confirmLabel: 'Sair',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(authControllerProvider.notifier).logout();
  }
}
