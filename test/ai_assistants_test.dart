import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:louvor_app/core/config/app_config.dart';
import 'package:louvor_app/core/network/api_exception.dart';
import 'package:louvor_app/core/router/page_title.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/ai_assistants/data/mcp_token_repository.dart';
import 'package:louvor_app/features/ai_assistants/domain/mcp_token.dart';
import 'package:louvor_app/features/ai_assistants/presentation/ai_assistants_screen.dart';
import 'package:louvor_app/features/ai_assistants/presentation/new_ai_key_screen.dart';
import 'package:louvor_app/shared/widgets/form_scaffold.dart';
import 'package:louvor_app/shared/widgets/unsaved_changes_guard.dart';

/// Perfil › Assistentes de IA: as chaves com que Claude, Cursor e VS Code
/// leem o Pauta. O que se protege aqui é o que não tem volta — a chave aparece
/// uma vez só, e revogar derruba o assistente na hora.
void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('frases e regras', () {
    test('o final da chave sai da dica da API', () {
      expect(_token(hint: 'x9Qa').ending, 'x9Qa');
    });

    test('último uso: hoje, ontem, uma data ou nunca', () {
      String uso(DateTime? em) =>
          mcpUsageLabel(_token(lastUsedAt: em), _agora);

      expect(uso(DateTime(2026, 9, 26, 0, 5)), 'usada hoje');
      expect(uso(DateTime(2026, 9, 25, 23, 50)), 'usada ontem');
      expect(uso(DateTime(2026, 9, 22, 15)), 'usada em 22 de setembro');
      expect(uso(DateTime(2025, 12, 30)), 'usada em 30 de dezembro de 2025');
      expect(uso(null), 'nunca usada');
    });

    test('âmbar na última semana; vencida pelo relógio, mesmo sem o '
        'servidor dizer', () {
      McpTokenState estado(DateTime vence) =>
          mcpTokenState(_token(expiresAt: vence), _agora);

      expect(estado(DateTime(2026, 12, 25, 10)), McpTokenState.active);
      expect(estado(DateTime(2026, 10, 4, 9)), McpTokenState.active);
      expect(estado(DateTime(2026, 10, 3, 9)), McpTokenState.expiring);
      expect(estado(DateTime(2026, 9, 26, 22)), McpTokenState.expiring);
      // Venceu às 9h de hoje; a lista foi carregada ontem, com `expired`
      // ainda falso.
      expect(estado(DateTime(2026, 9, 26, 9)), McpTokenState.expired);
    });

    test('o selo conta os dias do calendário', () {
      expect(mcpExpiringLabel(0), 'Vence hoje');
      expect(mcpExpiringLabel(1), 'Vence amanhã');
      expect(mcpExpiringLabel(3), 'Vence em 3 dias');
      expect(
        mcpTokenDaysLeft(_token(expiresAt: DateTime(2026, 9, 29, 1)), _agora),
        3,
      );
    });

    test('a data leva o ano só quando não é o deste ano', () {
      expect(mcpDayLabel(DateTime(2026, 12, 25), _agora), '25 de dezembro');
      expect(mcpDayLabel(DateTime(2027, 3, 25), _agora), '25 de março de 2027');
      expect(
        mcpNewTokenUntilLabel(90, _agora),
        'Vale até 25 de dezembro de 2026. Depois, é só criar outra.',
      );
      expect(mcpValidityOptionLabel(180), '6 meses');
      expect(mcpValidityOptionLabel(365), '1 ano');
    });

    test('as que valem primeiro, da mais nova; as vencidas no fim', () {
      final antigaDeUmAno = _token(
        id: 'a',
        createdAt: DateTime(2026, 3, 1),
        expiresAt: DateTime(2027, 3, 1),
      );
      final nova = _token(
        id: 'b',
        createdAt: DateTime(2026, 9, 20),
        expiresAt: DateTime(2026, 12, 19),
      );
      final vencida = _token(
        id: 'c',
        createdAt: DateTime(2026, 8, 1),
        expiresAt: DateTime(2026, 8, 31),
        expired: true,
      );

      final ordem = sortMcpTokens([vencida, antigaDeUmAno, nova], _agora);

      expect(ordem.map((t) => t.id), ['b', 'a', 'c']);
      expect(activeMcpTokenCount(ordem, _agora), 2);
      expect(mcpActiveCountLabel(2), '2 de 10 ativas');
    });

    test('o comando do Claude Code e o cabeçalho, inteiros e encurtados', () {
      expect(
        claudeCodeMcpCommand(url: 'https://api.test/mcp', secret: _segredo),
        'claude mcp add --transport http pauta https://api.test/mcp '
        '--header "Authorization: Bearer $_segredo"',
      );
      expect(mcpAuthorizationHeader(_segredo), 'Authorization: Bearer $_segredo');
      expect(
        mcpAuthorizationHeaderPreview(_segredo),
        'Authorization: Bearer pauta_mcp_U9u6…k3Fq',
      );
      expect(AppConfig.mcpUrl, '${AppConfig.apiBaseUrl}/mcp');
    });

    test('lê a lista e a resposta da criação no formato da API', () {
      final json = {
        'id': '6f1c2c1e-0000-4000-8000-000000000001',
        'name': 'Claude no notebook',
        'tokenHint': 'pauta_mcp_...k3Fq',
        'scopes': ['mcp:read'],
        'createdAt': '2026-09-26T13:00:00.000Z',
        'expiresAt': '2026-12-25T13:00:00.000Z',
        'lastUsedAt': null,
        'expired': false,
      };

      final chave = McpToken.fromJson(json);
      expect(chave.name, 'Claude no notebook');
      expect(chave.ending, 'k3Fq');
      expect(chave.lastUsedAt, isNull);
      expect(chave.expiresAt, DateTime.utc(2026, 12, 25, 13));

      final criada = CreatedMcpToken.fromJson({...json, 'token': _segredo});
      expect(criada.secret, _segredo);
      expect(criada.token.id, chave.id);
    });

    test('título da aba das duas telas', () {
      expect(pageTitleFor('/perfil/assistentes'), 'Assistentes de IA · Pauta');
      expect(pageTitleFor('/perfil/assistentes/nova'), 'Nova chave · Pauta');
    });
  });

  group('lista de chaves', () {
    testWidgets('sem chave: explica, oferece "Criar chave" e avisa quem ainda '
        'não aceita', (tester) async {
      final semantica = tester.ensureSemantics();
      await _pump(tester, _Repositorio([]));

      expect(find.text('O que o assistente pode fazer'), findsOneWidget);
      expect(find.text('Ler o que você já vê no app'), findsOneWidget);
      expect(
        find.text('Criar, mudar ou apagar qualquer coisa'),
        findsOneWidget,
      );
      expect(
        find.text('Ver e-mail, telefone ou ano de nascimento de alguém'),
        findsOneWidget,
      );
      expect(find.text('Nenhuma chave ainda'), findsOneWidget);
      expect(find.textContaining('o ChatGPT ainda não aceitam'), findsOneWidget);
      expect(find.text('Suas chaves'), findsNothing);

      // "Pode" e "Não pode" chegam ao leitor de tela por extenso.
      expect(
        find.bySemanticsLabel('Não pode: Criar, mudar ou apagar qualquer coisa'),
        findsOneWidget,
      );
      semantica.dispose();

      await tester.tap(find.text('Criar chave'));
      await tester.pumpAndSettle();
      expect(find.text('Nova chave'), findsOneWidget);
    });

    testWidgets('ativa, vencendo e vencida, cada uma com o seu prazo',
        (tester) async {
      await _pump(tester, _Repositorio(_tresChaves()));

      expect(find.text('Suas chaves'), findsOneWidget);
      expect(find.text('2 de 10 ativas'), findsOneWidget);

      expect(find.text('Claude no notebook'), findsOneWidget);
      expect(find.text('Termina em k3Fq · usada hoje'), findsOneWidget);
      expect(find.text('Vale até 25 de dezembro'), findsOneWidget);

      expect(find.text('Cursor no trabalho'), findsOneWidget);
      expect(
        find.text('Termina em 9xTe · usada em 22 de setembro'),
        findsOneWidget,
      );
      expect(find.text('Vence em 3 dias'), findsOneWidget);

      expect(find.text('Claude no PC da igreja'), findsOneWidget);
      expect(
        find.text('Termina em Qm2L · venceu em 10 de setembro'),
        findsOneWidget,
      );
      expect(find.text('Vencida'), findsOneWidget);

      // A vencida vai para o fim, mesmo tendo sido criada antes da que vence.
      expect(
        tester.getTopLeft(find.text('Cursor no trabalho')).dy,
        lessThan(tester.getTopLeft(find.text('Claude no PC da igreja')).dy),
      );

      expect(find.text('Criar outra chave'), findsOneWidget);
      expect(find.text('Como conectar'), findsOneWidget);
      expect(find.text(AppConfig.mcpUrl), findsOneWidget);
      expect(
        find.text('Trocar a senha revoga todas as chaves de uma vez.'),
        findsOneWidget,
      );
    });

    testWidgets('revogar pergunta antes, e "Voltar" não revoga nada',
        (tester) async {
      final repositorio = _Repositorio(_tresChaves());
      await _pump(tester, repositorio);

      await tester.tap(find.byTooltip('Mais opções de Cursor no trabalho'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revogar chave'));
      await tester.pumpAndSettle();

      expect(find.text('Revogar “Cursor no trabalho”?'), findsOneWidget);
      expect(find.textContaining('perde o acesso na hora'), findsOneWidget);

      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();

      expect(repositorio.revogadas, isEmpty);
      expect(find.text('Cursor no trabalho'), findsOneWidget);
    });

    testWidgets('revogar confirma, tira da lista e avisa', (tester) async {
      final repositorio = _Repositorio(_tresChaves());
      await _pump(tester, repositorio);

      await tester.tap(find.byTooltip('Mais opções de Cursor no trabalho'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revogar chave'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revogar'));
      await tester.pumpAndSettle();

      expect(repositorio.revogadas, ['cursor']);
      expect(find.text('Chave revogada.'), findsOneWidget);
      expect(find.text('Cursor no trabalho'), findsNothing);
      expect(find.text('1 de 10 ativas'), findsOneWidget);
    });

    testWidgets('a vencida sai da lista sem pergunta', (tester) async {
      final repositorio = _Repositorio(_tresChaves());
      await _pump(tester, repositorio);

      await tester.tap(find.byTooltip('Mais opções de Claude no PC da igreja'));
      await tester.pumpAndSettle();
      expect(find.text('Revogar chave'), findsNothing);
      await tester.tap(find.text('Remover da lista'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(repositorio.revogadas, ['igreja']);
      expect(find.text('Chave removida da lista.'), findsOneWidget);
      expect(find.text('Claude no PC da igreja'), findsNothing);
    });

    testWidgets('com 10 ativas, "Criar outra chave" apaga e diz por quê',
        (tester) async {
      await _pump(
        tester,
        _Repositorio([
          for (var i = 0; i < 10; i++)
            _token(
              id: 'k$i',
              name: 'Chave $i',
              expiresAt: DateTime(2026, 12, 25),
            ),
        ]),
        size: const Size(400, 2400),
      );

      expect(find.text('10 de 10 ativas'), findsOneWidget);
      final botao = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Criar outra chave'),
          matching: find.byWidgetPredicate((w) => w is TextButton),
        ),
      );
      expect(botao.onPressed, isNull);
      expect(find.textContaining('Revogue uma para criar outra'), findsOneWidget);
    });

    testWidgets('o endereço do servidor se copia', (tester) async {
      final area = _AreaDeTransferencia(tester);
      await _pump(tester, _Repositorio(_tresChaves()));

      await tester.tap(find.byTooltip('Copiar o endereço do servidor'));
      await tester.pumpAndSettle();

      expect(area.texto, AppConfig.mcpUrl);
      expect(find.text('Endereço copiado.'), findsOneWidget);
    });
  });

  group('nova chave', () {
    testWidgets('senha errada vai para o campo, e não para a faixa',
        (tester) async {
      final repositorio = _Repositorio([])
        ..erro = const ApiException(
          'Senha incorreta.',
          statusCode: 403,
          code: 'INVALID_PASSWORD',
        );
      await _pump(tester, repositorio, rota: '/perfil/assistentes/nova');

      await _preencher(tester, nome: 'Claude no notebook', senha: 'errada');
      await tester.tap(find.text('Criar chave'));
      await tester.pumpAndSettle();

      expect(find.text('Senha incorreta.'), findsOneWidget);
      expect(find.byType(FormErrorBanner), findsNothing);
      expect(find.text('Nova chave'), findsOneWidget);
    });

    testWidgets('limite atingido vai para a faixa, com a frase do servidor',
        (tester) async {
      final repositorio = _Repositorio([])
        ..erro = const ApiException(
          'Você já tem 10 chaves ativas. Revogue uma antes de criar outra.',
          statusCode: 409,
          code: 'MCP_TOKEN_LIMIT',
        );
      await _pump(tester, repositorio, rota: '/perfil/assistentes/nova');

      await _preencher(tester, nome: 'Mais uma', senha: 'senhaFinal789');
      await tester.tap(find.text('Criar chave'));
      await tester.pumpAndSettle();

      expect(find.byType(FormErrorBanner), findsOneWidget);
      expect(
        find.text(
          'Você já tem 10 chaves ativas. Revogue uma antes de criar outra.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('o 429 chega em inglês e sai em português', (tester) async {
      final repositorio = _Repositorio([])
        ..erro = const ApiException(
          'ThrottlerException: Too Many Requests',
          statusCode: 429,
          code: 'TOO_MANY_REQUESTS',
        );
      await _pump(tester, repositorio, rota: '/perfil/assistentes/nova');

      await _preencher(tester, nome: 'Claude', senha: 'x');
      await tester.tap(find.text('Criar chave'));
      await tester.pumpAndSettle();

      expect(
        find.text('Muitas tentativas seguidas. Espere um minuto e tente de '
            'novo.'),
        findsOneWidget,
      );
      expect(find.textContaining('Throttler'), findsNothing);
    });

    testWidgets('nome e senha são obrigatórios', (tester) async {
      final repositorio = _Repositorio([]);
      await _pump(tester, repositorio, rota: '/perfil/assistentes/nova');

      await _preencher(tester, nome: '   ', senha: '');
      await tester.tap(find.text('Criar chave'));
      await tester.pumpAndSettle();

      expect(find.text('Dê um nome para a chave.'), findsOneWidget);
      expect(find.text('Informe sua senha.'), findsOneWidget);
      expect(repositorio.pedido, isNull);
    });

    testWidgets('o prazo escolhido vai no pedido, e a data acompanha',
        (tester) async {
      final repositorio = _Repositorio([]);
      await _pump(tester, repositorio, rota: '/perfil/assistentes/nova');

      expect(
        find.text('Vale até 25 de dezembro de 2026. Depois, é só criar outra.'),
        findsOneWidget,
      );
      await tester.tap(find.text('1 ano'));
      await tester.pumpAndSettle();
      expect(
        find.text('Vale até 26 de setembro de 2027. Depois, é só criar outra.'),
        findsOneWidget,
      );

      await _preencher(
        tester,
        nome: '  Claude no notebook  ',
        senha: 'senhaFinal789',
      );
      await tester.tap(find.text('Criar chave'));
      await tester.pumpAndSettle();

      expect(repositorio.pedido, {
        'name': 'Claude no notebook',
        'password': 'senhaFinal789',
        'expiresInDays': 365,
      });
    });

    testWidgets('"Melhor fazer no computador" só fora da Web', (tester) async {
      await _pump(
        tester,
        _Repositorio([]),
        rota: '/perfil/assistentes/nova',
        sugerirComputador: true,
      );
      expect(find.text('Melhor fazer no computador'), findsOneWidget);

      await _pump(
        tester,
        _Repositorio([]),
        rota: '/perfil/assistentes/nova',
        sugerirComputador: false,
      );
      expect(find.text('Melhor fazer no computador'), findsNothing);
    });

    testWidgets('criada: a chave aparece uma vez e "Copiar chave" copia',
        (tester) async {
      final area = _AreaDeTransferencia(tester);
      await _criar(tester, _Repositorio([]));

      expect(find.text('Chave criada'), findsOneWidget);
      expect(find.text('Copie agora: ela só aparece esta vez'), findsOneWidget);
      expect(find.text('Chave “Claude no notebook”'), findsOneWidget);
      expect(_textoSelecionavel(tester, _segredo), isTrue);

      await tester.tap(find.text('Copiar chave'));
      await tester.pumpAndSettle();

      expect(area.texto, _segredo);
      expect(find.text('Chave copiada.'), findsOneWidget);
    });

    testWidgets('Claude Code: o comando leva o endereço e a chave',
        (tester) async {
      final area = _AreaDeTransferencia(tester);
      await _criar(tester, _Repositorio([]));
      final comando =
          claudeCodeMcpCommand(url: AppConfig.mcpUrl, secret: _segredo);

      expect(_textoSelecionavel(tester, comando), isTrue);
      await tester.ensureVisible(find.text('Copiar comando'));
      await tester.tap(find.text('Copiar comando'));
      await tester.pumpAndSettle();

      expect(area.texto, comando);
      expect(
        find.text('Comando copiado. É só colar no terminal.'),
        findsOneWidget,
      );
    });

    testWidgets('Outros apps: endereço e cabeçalho, e o cabeçalho leva a '
        'chave inteira', (tester) async {
      final area = _AreaDeTransferencia(tester);
      await _criar(tester, _Repositorio([]));

      await tester.ensureVisible(find.text('Outros apps'));
      await tester.tap(find.text('Outros apps'));
      await tester.pumpAndSettle();

      expect(find.text('Endereço'), findsOneWidget);
      expect(
        find.text('Authorization: Bearer pauta_mcp_U9u6…k3Fq'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Copiar o endereço'));
      await tester.pumpAndSettle();
      expect(area.texto, AppConfig.mcpUrl);

      await tester.tap(find.byTooltip('Copiar o cabeçalho, com a chave inteira'));
      await tester.pumpAndSettle();
      expect(area.texto, 'Authorization: Bearer $_segredo');
      expect(find.text('Cabeçalho copiado.'), findsOneWidget);
    });

    testWidgets('sair sem copiar pergunta, e "Ficar e copiar" fica',
        (tester) async {
      await _criar(tester, _Repositorio([]));

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Sair sem copiar a chave?'), findsOneWidget);

      await tester.tap(find.text('Ficar e copiar'));
      await tester.pumpAndSettle();
      expect(find.text('Chave criada'), findsOneWidget);
      expect(_textoSelecionavel(tester, _segredo), isTrue);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sair assim mesmo'));
      await tester.pumpAndSettle();

      // Pergunta uma vez só, e a lista já volta com a chave nova.
      expect(find.text('Sair sem copiar a chave?'), findsNothing);
      expect(find.text('Suas chaves'), findsOneWidget);
      expect(find.text('Claude no notebook'), findsOneWidget);
    });

    testWidgets('depois de copiar, sair não pergunta', (tester) async {
      _AreaDeTransferencia(tester);
      await _criar(tester, _Repositorio([]));

      await tester.tap(find.text('Copiar chave'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Concluir'));
      await tester.tap(find.text('Concluir'));
      await tester.pumpAndSettle();

      expect(find.text('Sair sem copiar a chave?'), findsNothing);
      expect(find.text('Suas chaves'), findsOneWidget);
    });

    testWidgets('"Concluir" sem copiar pergunta; navegar por fora também',
        (tester) async {
      final router = await _criar(tester, _Repositorio([]));

      await tester.ensureVisible(find.text('Concluir'));
      await tester.tap(find.text('Concluir'));
      await tester.pumpAndSettle();
      expect(find.text('Sair sem copiar a chave?'), findsOneWidget);
      await tester.tap(find.text('Ficar e copiar'));
      await tester.pumpAndSettle();
      expect(find.text('Chave criada'), findsOneWidget);

      // A barra lateral e o voltar do navegador passam pelo `onExit` da rota:
      // a pergunta é a mesma, e não o "Sair sem salvar?" dos formulários.
      router.go('/inicio');
      await tester.pumpAndSettle();
      expect(find.text('Sair sem copiar a chave?'), findsOneWidget);
      expect(find.text('Sair sem salvar?'), findsNothing);

      await tester.tap(find.text('Sair assim mesmo'));
      await tester.pumpAndSettle();
      expect(find.text('Início'), findsOneWidget);
      expect(UnsavedChangesGuard.hasUnsavedChanges, isFalse);
    });
  });

  group('telas estreitas e fonte grande', () {
    for (final escala in [1.0, 1.6]) {
      testWidgets('lista, formulário e chave criada cabem em 320px a ${escala}x',
          (tester) async {
        const tamanho = Size(320, 3200);

        await _pump(
          tester,
          _Repositorio(_tresChaves()),
          size: tamanho,
          textScale: escala,
        );
        expect(tester.takeException(), isNull);

        await _pump(
          tester,
          _Repositorio([]),
          size: tamanho,
          textScale: escala,
        );
        expect(tester.takeException(), isNull);

        await _criar(
          tester,
          _Repositorio([]),
          size: tamanho,
          textScale: escala,
          sugerirComputador: true,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Outros apps'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

final _agora = DateTime(2026, 9, 26, 10);

/// Uma chave como a API devolve: `pauta_mcp_` e 43 caracteres base64url.
const _segredo = 'pauta_mcp_U9u63JxF71mKiuvJiqtboLgekcNRoW9EIdxrW6dk3Fq';

McpToken _token({
  String id = 't1',
  String name = 'Claude no notebook',
  String hint = 'k3Fq',
  DateTime? createdAt,
  DateTime? expiresAt,
  DateTime? lastUsedAt,
  bool expired = false,
}) {
  return McpToken(
    id: id,
    name: name,
    tokenHint: 'pauta_mcp_...$hint',
    createdAt: createdAt ?? DateTime(2026, 9, 1),
    expiresAt: expiresAt ?? DateTime(2026, 12, 25, 10),
    lastUsedAt: lastUsedAt,
    expired: expired,
  );
}

/// As três do protótipo: usada hoje, vencendo em 3 dias, vencida.
List<McpToken> _tresChaves() => [
      _token(
        id: 'notebook',
        name: 'Claude no notebook',
        hint: 'k3Fq',
        createdAt: DateTime(2026, 9, 20),
        lastUsedAt: DateTime(2026, 9, 26, 9, 30),
        expiresAt: DateTime(2026, 12, 25, 10),
      ),
      _token(
        id: 'igreja',
        name: 'Claude no PC da igreja',
        hint: 'Qm2L',
        createdAt: DateTime(2026, 8, 11),
        lastUsedAt: DateTime(2026, 9, 1),
        expiresAt: DateTime(2026, 9, 10, 12),
        expired: true,
      ),
      _token(
        id: 'cursor',
        name: 'Cursor no trabalho',
        hint: '9xTe',
        createdAt: DateTime(2026, 6, 29),
        lastUsedAt: DateTime(2026, 9, 22, 15),
        expiresAt: DateTime(2026, 9, 29, 9),
      ),
    ];

class _Repositorio extends McpTokenRepository {
  _Repositorio(this.chaves) : super(Dio());

  List<McpToken> chaves;
  final revogadas = <String>[];
  Map<String, Object>? pedido;
  ApiException? erro;

  @override
  Future<List<McpToken>> list() async => List.of(chaves);

  @override
  Future<CreatedMcpToken> create({
    required String name,
    required String password,
    required int expiresInDays,
  }) async {
    pedido = {
      'name': name,
      'password': password,
      'expiresInDays': expiresInDays,
    };
    final falha = erro;
    if (falha != null) throw falha;

    final chave = McpToken(
      id: 'nova',
      name: name,
      tokenHint: 'pauta_mcp_...k3Fq',
      createdAt: _agora,
      expiresAt: _agora.add(Duration(days: expiresInDays)),
    );
    chaves = [chave, ...chaves];
    return CreatedMcpToken(token: chave, secret: _segredo);
  }

  @override
  Future<void> revoke(String id) async {
    revogadas.add(id);
    chaves = chaves.where((c) => c.id != id).toList();
  }
}

/// A área de transferência do sistema, falsa: guarda o que foi copiado.
class _AreaDeTransferencia {
  _AreaDeTransferencia(WidgetTester tester) {
    final mensageiro = tester.binding.defaultBinaryMessenger;
    mensageiro.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        texto = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => mensageiro.setMockMethodCallHandler(SystemChannels.platform, null),
    );
  }

  String? texto;
}

bool _textoSelecionavel(WidgetTester tester, String texto) => tester
    .widgetList<SelectableText>(find.byType(SelectableText))
    .any((w) => w.data == texto);

Future<void> _preencher(
  WidgetTester tester, {
  required String nome,
  required String senha,
}) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Nome da chave'),
    nome,
  );
  await tester.enterText(find.widgetWithText(TextFormField, 'Sua senha'), senha);
  await tester.pump();
}

/// Abre o formulário, cria "Claude no notebook" e para na chave criada.
Future<GoRouter> _criar(
  WidgetTester tester,
  _Repositorio repositorio, {
  Size size = const Size(400, 1800),
  double textScale = 1.0,
  bool sugerirComputador = false,
}) async {
  final router = await _pump(
    tester,
    repositorio,
    rota: '/perfil/assistentes/nova',
    size: size,
    textScale: textScale,
    sugerirComputador: sugerirComputador,
  );
  await _preencher(tester, nome: 'Claude no notebook', senha: 'senhaFinal789');
  await tester.ensureVisible(find.text('Criar chave'));
  await tester.tap(find.text('Criar chave'));
  await tester.pumpAndSettle();
  return router;
}

/// As rotas como no app: a lista dentro do Perfil e o formulário dentro da
/// lista, com o `onExit` que protege a chave.
Future<GoRouter> _pump(
  WidgetTester tester,
  _Repositorio repositorio, {
  String rota = '/perfil/assistentes',
  Size size = const Size(400, 1800),
  double textScale = 1.0,
  bool sugerirComputador = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: rota,
    routes: [
      GoRoute(
        path: '/perfil',
        builder: (_, __) => const Scaffold(body: Text('Perfil')),
        routes: [
          GoRoute(
            path: 'assistentes',
            builder: (_, __) => const AiAssistantsScreen(),
            routes: [
              GoRoute(
                path: 'nova',
                onExit: confirmLeaveIfUnsaved,
                builder: (_, __) =>
                    NewAiKeyScreen(suggestComputer: sugerirComputador),
              ),
            ],
          ),
          GoRoute(
            path: 'ajuda',
            builder: (_, __) => const Scaffold(body: Text('Ajuda')),
          ),
        ],
      ),
      GoRoute(
        path: '/inicio',
        builder: (_, __) => const Scaffold(body: Text('Início')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      // Uma árvore nova a cada chamada: sem a chave, o teste que monta duas
      // telas seguidas reaproveitaria o estado da primeira.
      key: UniqueKey(),
      overrides: [
        mcpTokenRepositoryProvider.overrideWithValue(repositorio),
        aiAssistantsClockProvider.overrideWithValue(() => _agora),
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
  return router;
}
