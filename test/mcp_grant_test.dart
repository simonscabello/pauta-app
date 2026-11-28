import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/features/ai_assistants/domain/mcp_token.dart';

void main() {
  test('conexão pelo navegador: domínio do CIMD e a escrita no subtítulo', () {
    final grant = McpGrant.fromJson({
      'id': 'g1',
      'clientId': 'https://claude.ai/oauth/mcp-client.json',
      'clientName': 'Claude',
      'scopes': ['mcp:read', 'mcp:write'],
      'createdAt': '2026-11-27T12:00:00.000Z',
    });
    expect(grant.clientHost, 'claude.ai');
    expect(grant.canWrite, isTrue);
    expect(grant.subtitle, startsWith('claude.ai · Conectado em '));
    expect(grant.subtitle, endsWith('Também cria escalas'));
  });

  test('cliente registrado (DCR) sem nome nem domínio', () {
    final grant = McpGrant.fromJson({
      'id': 'g2',
      'clientId': '3f1c7d8e-0000-4000-8000-000000000000',
      'clientName': '',
      'scopes': ['mcp:read'],
      'createdAt': '2026-11-27T12:00:00.000Z',
    });
    expect(grant.clientName, 'Assistente');
    expect(grant.clientHost, isNull);
    expect(grant.canWrite, isFalse);
  });
}
