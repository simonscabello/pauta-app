import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/core/storage/shared_preferences_provider.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/auth/application/auth_controller.dart';
import 'package:louvor_app/features/auth/domain/auth_models.dart';
import 'package:louvor_app/features/suggestions/data/suggestion_repository.dart';
import 'package:louvor_app/features/team/data/team_repository.dart';
import 'package:louvor_app/features/team/domain/team_models.dart';
import 'package:louvor_app/features/team/presentation/team_hub_screen.dart';
import 'package:louvor_app/features/whatsapp/data/whatsapp_repository.dart';
import 'package:louvor_app/features/whatsapp/domain/team_whatsapp.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A aba Equipe é um menu por assunto, e o que cada um vê depende do papel.
/// O que se trava aqui: quem não lidera vê só o que pode abrir (e nenhum grupo
/// vazio), quem lidera vê os quatro grupos, e a linha do WhatsApp segue o
/// servidor.
void main() {
  const members = [
    Member(
      id: 'm1',
      displayName: 'Samuel',
      role: 'OWNER',
      hasAccount: true,
      positions: [],
    ),
    Member(
      id: 'm2',
      displayName: 'Maria',
      role: 'MEMBER',
      hasAccount: true,
      positions: [],
    ),
  ];

  testWidgets('quem não lidera vê Músicas e Pessoas, só o que pode abrir',
      (tester) async {
    await _pumpHub(tester, role: 'MEMBER', members: members);

    expect(find.text('Repertório'), findsOneWidget);
    expect(find.text('Sugestões'), findsOneWidget);
    expect(find.text('Integrantes'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    for (final texto in [
      'Relatórios do repertório',
      'Funções',
      'Convites',
      'Escalas',
      'Cultos da igreja',
      'Quem não pode',
      'Participação',
      'Configurações',
      'Dados da equipe',
      'Grupo do WhatsApp',
    ]) {
      expect(find.text(texto), findsNothing, reason: texto);
    }
  });

  testWidgets('quem lidera vê os quatro grupos', (tester) async {
    await _pumpHub(tester, role: 'LEADER', members: members);

    for (final texto in [
      'Músicas',
      'Pessoas',
      'Escalas',
      'Configurações',
      'Relatórios do repertório',
      'Funções',
      'Convites',
      'Cultos da igreja',
      'Quem não pode',
      'Participação',
      'Dados da equipe',
    ]) {
      expect(find.text(texto), findsOneWidget, reason: texto);
    }
    // O envio pelo WhatsApp está desligado no servidor.
    expect(find.text('Grupo do WhatsApp'), findsNothing);
  });

  testWidgets('a linha do WhatsApp aparece com o envio ligado',
      (tester) async {
    await _pumpHub(
      tester,
      role: 'OWNER',
      members: members,
      whatsApp: const TeamWhatsApp(available: true, connected: true),
    );

    expect(find.text('Grupo do WhatsApp'), findsOneWidget);
  });
}

Future<void> _pumpHub(
  WidgetTester tester, {
  required String role,
  required List<Member> members,
  TeamWhatsApp whatsApp = TeamWhatsApp.off,
}) async {
  tester.view.physicalSize = const Size(400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            AuthState.signedIn(
              const AuthUser(
                id: '1',
                name: 'Samuel',
                email: 'samuel@teste.com',
                mustChangePassword: false,
              ),
              [
                TeamSummary(
                  membershipId: 'm1',
                  teamId: 't1',
                  name: 'Ministerio de Louvor',
                  role: role,
                  displayName: 'Samuel',
                ),
              ],
            ),
          ),
        ),
        membersProvider.overrideWith((ref, _) async => members),
        openSuggestionCountProvider.overrideWith((ref, _) async => 0),
        teamWhatsAppProvider.overrideWith((ref, _) async => whatsApp),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const TeamHubScreen(teamId: 't1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, this._initial);

  final AuthState _initial;

  @override
  Future<void> bootstrap() async {
    state = _initial;
  }
}
