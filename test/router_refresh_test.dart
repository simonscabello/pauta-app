import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:louvor_app/core/router/app_router.dart';
import 'package:louvor_app/features/auth/application/auth_controller.dart';
import 'package:louvor_app/features/auth/domain/auth_models.dart';
import 'package:louvor_app/shared/domain/person_fields.dart';

/// "Salvar" em "Meus dados" mostrava "Dados atualizados." e a tela ficava
/// aberta: salvar muda o estado de auth, o roteador era avisado de qualquer
/// mudança, e o go_router reaplicava `/perfil/dados` **depois** do `pop` que
/// vinha logo em seguida. Agora só avisa o que as rotas leem.
void main() {
  const user = AuthUser(
    id: 'u1',
    name: 'Maria',
    email: 'maria@teste.com',
    mustChangePassword: false,
  );
  const team = TeamSummary(
    membershipId: 'm1',
    teamId: 't1',
    name: 'Louvor',
    role: 'MEMBER',
    displayName: 'Maria',
  );

  group('o que avisa o roteador', () {
    final base = routeRelevantAuthKey(AuthState.signedIn(user, const [team]));

    test('dados do perfil não avisam', () {
      final editado = AuthUser(
        id: 'u1',
        name: 'Maria Silva',
        email: 'maria.silva@teste.com',
        mustChangePassword: false,
        birthDate: DateTime(1990, 3, 12),
        gender: Gender.female,
        avatarUrl: '/uploads/avatars/x.jpg',
      );
      const apelido = TeamSummary(
        membershipId: 'm1',
        teamId: 't1',
        name: 'Louvor da Manhã',
        role: 'MEMBER',
        displayName: 'Mari',
      );
      expect(
        routeRelevantAuthKey(AuthState.signedIn(editado, const [apelido])),
        base,
      );
    });

    test('status, conta, equipes e papel avisam', () {
      const lider = TeamSummary(
        membershipId: 'm1',
        teamId: 't1',
        name: 'Louvor',
        role: 'LEADER',
        displayName: 'Maria',
      );
      const outra = TeamSummary(
        membershipId: 'm2',
        teamId: 't2',
        name: 'Coral',
        role: 'MEMBER',
        displayName: 'Maria',
      );
      for (final state in [
        const AuthState.signedOut(),
        AuthState.signedIn(user, const [lider]),
        AuthState.signedIn(user, const [team, outra]),
        AuthState.signedIn(user, const []),
        AuthState.signedIn(
          const AuthUser(
            id: 'u2',
            name: 'Maria',
            email: 'maria@teste.com',
            mustChangePassword: false,
          ),
          const [team],
        ),
      ]) {
        expect(routeRelevantAuthKey(state), isNot(base));
      }
    });
  });

  testWidgets('salvar e voltar: o pop não é desfeito pelo aviso de auth',
      (tester) async {
    late _FakeAuthController auth;
    final refreshProvider = Provider((ref) => AuthRefreshNotifier(ref));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => auth = _FakeAuthController(
              ref,
              AuthState.signedIn(user, const [team]),
            ),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            final router = GoRouter(
              initialLocation: '/perfil',
              refreshListenable: ref.read(refreshProvider),
              routes: [
                ShellRoute(
                  builder: (_, __, child) => Scaffold(body: child),
                  routes: [
                    GoRoute(
                      path: '/perfil',
                      builder: (_, __) => const Text('perfil'),
                      routes: [
                        GoRoute(
                          path: 'dados',
                          onExit: (_, __) => true,
                          // Como `EditProfileScreen._save`: grava, o estado
                          // de auth muda, e a tela fecha.
                          builder: (context, __) => TextButton(
                            onPressed: () async {
                              await Future<void>.delayed(
                                const Duration(milliseconds: 10),
                              );
                              auth.replace(
                                AuthState.signedIn(
                                  const AuthUser(
                                    id: 'u1',
                                    name: 'Maria',
                                    email: 'maria@teste.com',
                                    mustChangePassword: false,
                                    gender: Gender.female,
                                  ),
                                  const [team],
                                ),
                              );
                              if (context.mounted) context.pop();
                            },
                            child: const Text('Salvar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            );
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.text('perfil')));

    router.push('/perfil/dados');
    await tester.pumpAndSettle();
    expect(find.text('Salvar'), findsOneWidget);

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(find.text('Salvar'), findsNothing);
    expect(find.text('perfil'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      '/perfil',
    );
  });
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, this._initial);

  final AuthState _initial;

  @override
  Future<void> bootstrap() async {
    state = _initial;
  }

  void replace(AuthState next) => state = next;
}
