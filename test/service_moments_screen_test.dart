import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/features/events/domain/service_moments.dart';
import 'package:louvor_app/features/team/data/team_repository.dart';
import 'package:louvor_app/features/team/presentation/service_moments_screen.dart';

/// A tela "Momentos do culto": a lista na ordem do culto, com a alça de
/// arrastar, e os excluídos à parte, com "Restaurar".
void main() {
  Widget tela(List<TeamMoment> moments) => ProviderScope(
        overrides: [
          allServiceMomentsProvider.overrideWith((ref, _) async => moments),
        ],
        child: const MaterialApp(home: ServiceMomentsScreen(teamId: 't1')),
      );

  testWidgets('os ativos na ordem, e os excluídos à parte', (tester) async {
    await tester.pumpWidget(
      tela(const [
        TeamMoment(id: 'a', name: 'Abertura', systemKey: 'ABERTURA'),
        TeamMoment(id: 'c', name: 'Santa Ceia', sortOrder: 1),
        TeamMoment(
          id: 'p',
          name: 'Prelúdio',
          systemKey: 'PRELUDIO',
          isActive: false,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Abertura'), findsOneWidget);
    expect(find.text('Santa Ceia'), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(2));
    expect(find.text('Excluídos'), findsOneWidget);
    expect(find.text('Restaurar'), findsOneWidget);
  });

  testWidgets('sem excluídos, a seção não aparece', (tester) async {
    await tester.pumpWidget(
      tela(const [TeamMoment(id: 'a', name: 'Abertura', systemKey: 'ABERTURA')]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Excluídos'), findsNothing);
  });

  testWidgets('tocar abre a edição, com "Excluir momento"', (tester) async {
    await tester.pumpWidget(
      tela(const [TeamMoment(id: 'c', name: 'Santa Ceia')]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Santa Ceia'));
    await tester.pumpAndSettle();

    expect(find.text('Editar momento'), findsOneWidget);
    expect(find.text('Excluir momento'), findsOneWidget);
  });
}
