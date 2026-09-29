import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/whatsapp/data/whatsapp_repository.dart';
import 'package:louvor_app/features/whatsapp/domain/team_whatsapp.dart';
import 'package:louvor_app/features/whatsapp/presentation/whatsapp_group_screen.dart';

/// Gerenciar equipe › Grupo do WhatsApp. O que se protege: a tela some quando
/// o servidor não tem o envio ligado, o código só é gerado com o número
/// conectado, e o grupo aparece sozinho depois que o código é colado.
void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('modelo', () {
    test('lê o estado do servidor', () {
      final estado = TeamWhatsApp.fromJson({
        'available': true,
        'connected': true,
        'phoneNumber': '5527999990000',
        'group': {'name': 'Louvor SIBB', 'linkedAt': '2026-09-28T20:00:00.000Z'},
        'linkCode': null,
      });

      expect(estado.canSend, isTrue);
      expect(estado.group!.label, 'Louvor SIBB');
      expect(estado.linkCode, isNull);
    });

    test('sem grupo, ou com o envio desligado, não há botão', () {
      expect(_estado().canSend, isFalse);
      expect(TeamWhatsApp.off.canSend, isFalse);
      expect(
        TeamWhatsApp.fromJson({
          'available': false,
          'connected': false,
          'group': {'name': 'X', 'linkedAt': '2026-09-28T20:00:00.000Z'},
        }).canSend,
        isFalse,
      );
    });

    test('o número sai no formato brasileiro, e o resto cru', () {
      expect(formatWhatsAppNumber('5527999990000'), '+55 27 99999-0000');
      expect(formatWhatsAppNumber('552733334444'), '+55 27 3333-4444');
      expect(formatWhatsAppNumber('351912345678'), '+351912345678');
    });
  });

  group('tela', () {
    testWidgets('desligado no servidor: diz isso e não oferece nada',
        (tester) async {
      await _pump(tester, _FakeRepository(TeamWhatsApp.off));

      expect(find.text('Envio pelo WhatsApp desligado'), findsOneWidget);
      expect(find.text('Gerar código'), findsNothing);
    });

    testWidgets('sem grupo: o número do Pauta e o código, e o grupo aparece '
        'sozinho depois de colado', (tester) async {
      final repo = _FakeRepository(_estado());
      await _pump(tester, repo);

      expect(find.textContaining('+55 27 99999-0000'), findsOneWidget);
      await tester.tap(find.text('Gerar código'));
      await tester.pumpAndSettle();

      expect(find.text('PAUTA-K7M2QX'), findsOneWidget);
      expect(find.text('Copiar código'), findsOneWidget);

      // Alguém colou o código no grupo; a tela pergunta de novo sozinha.
      repo.state = _estado(group: _grupo);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(find.text('Louvor SIBB'), findsOneWidget);
      expect(find.text('Grupo vinculado: Louvor SIBB.'), findsOneWidget);
      expect(find.text('PAUTA-K7M2QX'), findsNothing);

      await _desmontar(tester);
    });

    testWidgets('número desconectado: avisa e não gera código', (tester) async {
      await _pump(tester, _FakeRepository(_estado(connected: false)));

      expect(find.text('Número do Pauta desconectado'), findsOneWidget);
      final botao = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Gerar código'),
      );
      expect(botao.onPressed, isNull);
    });

    testWidgets('com grupo: o nome, trocar e desvincular', (tester) async {
      final repo = _FakeRepository(_estado(group: _grupo));
      await _pump(tester, repo);

      expect(find.text('Louvor SIBB'), findsOneWidget);
      expect(find.text('Gerar código'), findsNothing);

      await tester.tap(find.text('Desvincular'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Desvincular'));
      await tester.pumpAndSettle();

      expect(repo.unlinked, isTrue);
      expect(find.text('Gerar código'), findsOneWidget);
    });

    testWidgets('cabe em 320px com fonte grande', (tester) async {
      await _pump(
        tester,
        _FakeRepository(_estado(code: _codigo)),
        size: const Size(320, 1600),
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
      await _desmontar(tester);
    });
  });
}

final _grupo = WhatsAppGroup(
  name: 'Louvor SIBB',
  linkedAt: DateTime(2026, 9, 28),
);

final _codigo = WhatsAppLinkCode(
  code: 'PAUTA-K7M2QX',
  expiresAt: DateTime(2026, 9, 28, 21, 30),
);

TeamWhatsApp _estado({
  bool connected = true,
  WhatsAppGroup? group,
  WhatsAppLinkCode? code,
}) =>
    TeamWhatsApp(
      available: true,
      connected: connected,
      phoneNumber: '5527999990000',
      group: group,
      linkCode: code,
    );

class _FakeRepository extends WhatsAppRepository {
  _FakeRepository(this.state) : super(Dio());

  TeamWhatsApp state;
  bool unlinked = false;

  @override
  Future<TeamWhatsApp> status(String teamId) async => state;

  @override
  Future<TeamWhatsApp> createLinkCode(String teamId) async {
    state = _estado(
      connected: state.connected,
      group: state.group,
      code: _codigo,
    );
    return state;
  }

  @override
  Future<void> unlink(String teamId) async {
    unlinked = true;
    state = _estado(connected: state.connected);
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeRepository repo, {
  Size size = const Size(400, 1600),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        whatsAppRepositoryProvider.overrideWithValue(repo),
        teamWhatsAppProvider.overrideWith((ref, teamId) => repo.status(teamId)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const WhatsAppGroupScreen(teamId: 't1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Com código pendente a tela vigia o grupo num `Timer`; desmontar a tela é o
/// que o cancela antes de o teste acabar.
Future<void> _desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}
