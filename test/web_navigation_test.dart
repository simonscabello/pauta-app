import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/core/router/page_title.dart';
import 'package:louvor_app/shared/widgets/app_side_nav.dart';

void main() {
  group('título da aba', () {
    test('diz a página, e não só "Pauta"', () {
      expect(pageTitleFor('/inicio'), 'Início · Pauta');
      expect(pageTitleFor('/agenda/abc'), 'Escala · Pauta');
      expect(pageTitleFor('/agenda/abc/escalar'), 'Escalar equipe · Pauta');
      expect(pageTitleFor('/equipe/musicas/uso'), 'Relatórios do repertório · Pauta');
      expect(pageTitleFor('/equipe/musicas/xyz'), 'Música · Pauta');
      expect(pageTitleFor('/rota/que/nao/existe'), 'Pauta');
    });
  });

  group('barra lateral', () {
    const sections = [
      AppNavSection(
        destinations: [
          AppNavDestination(
            icon: Icons.library_music_outlined,
            selectedIcon: Icons.library_music_rounded,
            label: 'Repertório',
            route: '/equipe/musicas',
          ),
          AppNavDestination(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings_rounded,
            label: 'Gerenciar equipe',
            route: '/equipe/gerenciar',
            alsoMatches: ['/equipe/musicas/uso'],
          ),
        ],
      ),
    ];

    test('os relatórios acendem Gerenciar equipe, e não Repertório', () {
      expect(
        AppSideNav.selectedRouteFor(sections, '/equipe/musicas/uso'),
        '/equipe/gerenciar',
      );
      expect(
        AppSideNav.selectedRouteFor(sections, '/equipe/musicas/abc'),
        '/equipe/musicas',
      );
    });
  });
}
