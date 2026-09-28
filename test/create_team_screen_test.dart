import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:louvor_app/core/storage/shared_preferences_provider.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/auth/application/auth_controller.dart';
import 'package:louvor_app/features/auth/domain/auth_models.dart';
import 'package:louvor_app/features/team/data/team_repository.dart';
import 'package:louvor_app/features/team/domain/team_models.dart';
import 'package:louvor_app/features/team/presentation/create_team_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Em produção (28/09/2026) a tela criava a equipe e ficava parada: quem
/// achou que nada tinha acontecido tocou de novo, e nasceram três equipes com
/// o mesmo nome. Estes testes travam a saída e o toque repetido.
void main() {
  const usuario = AuthUser(
    id: 'u1',
    name: 'Samuel',
    email: 'samuel@teste.com',
    mustChangePassword: false,
  );

  TeamSummary resumo(String id, String nome) => TeamSummary(
        membershipId: 'm-$id',
        teamId: id,
        name: nome,
        role: 'OWNER',
        displayName: 'Samuel',
      );

  Future<({_FakeTeamRepository repo, ProviderContainer container})> montar(
    WidgetTester tester, {
    List<TeamSummary> equipesAntes = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = _FakeTeamRepository();

    final router = GoRouter(
      initialLocation: '/equipe/nova',
      routes: [
        GoRoute(
          path: '/equipe/nova',
          builder: (_, __) => const CreateTeamScreen(),
        ),
        GoRoute(
          path: '/inicio',
          builder: (_, __) => const Scaffold(body: Text('Início')),
        ),
      ],
    );
    addTearDown(router.dispose);

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        teamRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            AuthState.signedIn(usuario, equipesAntes),
            () => AuthState.signedIn(usuario, [
              ...equipesAntes,
              for (final t in repo.criadas) resumo(t.id, t.name),
            ]),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (repo: repo, container: container);
  }

  testWidgets('depois de criar, vai para o início', (tester) async {
    final m = await montar(tester);

    await tester.enterText(find.byType(TextFormField), 'Louvor Esperança');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    m.repo.responder();
    await tester.pumpAndSettle();

    expect(find.text('Início'), findsOneWidget);
    expect(m.repo.criadas, hasLength(1));
  });

  testWidgets('Enter e toque durante a criação não criam outra equipe',
      (tester) async {
    final m = await montar(tester);

    await tester.enterText(find.byType(TextFormField), 'Louvor Esperança');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    // Botão e campo se travam no carregamento, e `_submit` também.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    m.repo.responder();
    await tester.pumpAndSettle();

    expect(m.repo.chamadas, 1);
  });

  testWidgets('quem já tinha equipe passa a ver a que acabou de criar',
      (tester) async {
    final m = await montar(
      tester,
      equipesAntes: [resumo('antiga', 'Ministério de Louvor')],
    );
    expect(m.container.read(activeTeamIdProvider), 'antiga');

    await tester.enterText(find.byType(TextFormField), 'Louvor Esperança');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    m.repo.responder();
    await tester.pumpAndSettle();

    expect(m.container.read(activeTeamIdProvider), 'nova-1');
  });
}

class _FakeTeamRepository implements TeamRepository {
  final criadas = <Team>[];
  int chamadas = 0;
  final _pendentes = <Completer<Team>>[];

  /// Conclui as criações em andamento, como o servidor responderia.
  void responder() {
    for (final c in _pendentes) {
      final team = Team(
        id: 'nova-${criadas.length + 1}',
        name: 'Louvor Esperança',
        timezone: 'America/Sao_Paulo',
      );
      criadas.add(team);
      c.complete(team);
    }
    _pendentes.clear();
  }

  @override
  Future<Team> create({required String name}) {
    chamadas++;
    final c = Completer<Team>();
    _pendentes.add(c);
    return c.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, this._initial, this._depois);

  final AuthState _initial;
  final AuthState Function() _depois;

  @override
  Future<void> bootstrap() async {
    state = _initial;
  }

  @override
  Future<void> reloadTeams() async {
    state = _depois();
  }
}
