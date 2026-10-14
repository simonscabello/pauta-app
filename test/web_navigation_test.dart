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
      expect(pageTitleFor('/equipe/integrantes'), 'Integrantes · Pauta');
      expect(
        pageTitleFor('/equipe/integrantes/novo'),
        'Adicionar integrante · Pauta',
      );
      expect(pageTitleFor('/rota/que/nao/existe'), 'Pauta');
    });
  });

  group('barra lateral', () {
    const sections = [
      AppNavSection(
        destinations: [
          AppNavDestination(
            icon: Icons.groups_outlined,
            selectedIcon: Icons.groups_rounded,
            label: 'Equipe',
            route: '/equipe',
            alsoMatches: ['/equipe/musicas/uso'],
          ),
          AppNavDestination(
            icon: Icons.library_music_outlined,
            selectedIcon: Icons.library_music_rounded,
            label: 'Repertório',
            route: '/equipe/musicas',
          ),
        ],
      ),
    ];

    test('os relatórios acendem Equipe, e não Repertório', () {
      expect(
        AppSideNav.selectedRouteFor(sections, '/equipe/musicas/uso'),
        '/equipe',
      );
      expect(
        AppSideNav.selectedRouteFor(sections, '/equipe/musicas/abc'),
        '/equipe/musicas',
      );
    });
  });
}
