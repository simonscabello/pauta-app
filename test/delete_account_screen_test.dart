import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/auth/domain/auth_models.dart';
import 'package:louvor_app/features/profile/presentation/delete_account_screen.dart';

/// Excluir a conta: a tela diz o que acontece antes de pedir a senha, e o dono
/// com gente na equipe não chega à senha -- a posse precisa passar antes.
void main() {
  const equipe = TeamRef(teamId: 't1', name: 'Louvor Central');

  testWidgets('dono com outros integrantes não vê o campo de senha',
      (tester) async {
    await _pump(
      tester,
      const AccountDeletionPreview(blockedBy: [equipe], teamsDeleted: []),
    );

    expect(find.text('Passe a posse antes'), findsOneWidget);
    expect(find.textContaining('Louvor Central'), findsOneWidget);
    expect(find.text('Abrir integrantes'), findsOneWidget);
    expect(find.text('Sua senha'), findsNothing);
    expect(find.text('Excluir minha conta'), findsNothing);
  });

  testWidgets('equipe que vai junto é dita antes da senha', (tester) async {
    await _pump(
      tester,
      const AccountDeletionPreview(blockedBy: [], teamsDeleted: [equipe]),
    );

    expect(find.text('A equipe vai junto'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('A equipe vai junto')).dy,
      lessThan(tester.getTopLeft(find.text('Sua senha')).dy),
    );
  });

  testWidgets('sem senha não pede confirmação', (tester) async {
    await _pump(
      tester,
      const AccountDeletionPreview(blockedBy: [], teamsDeleted: []),
    );

    expect(find.text('A equipe vai junto'), findsNothing);
    await tester.tap(find.text('Excluir minha conta'));
    await tester.pumpAndSettle();

    expect(find.text('Informe sua senha.'), findsOneWidget);
    expect(find.text('Excluir sua conta?'), findsNothing);
  });

  testWidgets('cabe em 320px com fonte grande', (tester) async {
    await _pump(
      tester,
      const AccountDeletionPreview(blockedBy: [], teamsDeleted: [equipe]),
      size: const Size(320, 2000),
      textScale: 1.6,
    );
    expect(tester.takeException(), isNull);

    await _pump(
      tester,
      const AccountDeletionPreview(blockedBy: [equipe], teamsDeleted: []),
      size: const Size(320, 2000),
      textScale: 1.6,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  AccountDeletionPreview preview, {
  Size size = const Size(400, 1600),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/perfil/dados/excluir',
    routes: [
      GoRoute(
        path: '/perfil/dados/excluir',
        builder: (_, __) => const DeleteAccountScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountDeletionPreviewProvider.overrideWith((ref) async => preview),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
