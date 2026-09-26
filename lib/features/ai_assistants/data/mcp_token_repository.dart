import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../domain/mcp_token.dart';

/// As chaves com que os assistentes de IA leem o Pauta (`/users/me/mcp-tokens`).
///
/// São rotas da API de sempre, com o JWT do app: a chave do MCP não abre
/// nenhuma delas, então uma chave vazada não cria outra.
class McpTokenRepository {
  const McpTokenRepository(this._dio);

  final Dio _dio;

  /// As que não foram revogadas, vencidas incluídas.
  Future<List<McpToken>> list() {
    return _guard(() async {
      final response = await _dio.get<List<dynamic>>('/users/me/mcp-tokens');
      return response.data!
          .map((e) => McpToken.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// Cria a chave e devolve o valor inteiro **uma vez**.
  ///
  /// A senha vai de novo no corpo, como na exclusão da conta: um access token
  /// esquecido num aparelho não pode bastar para abrir uma credencial que dura
  /// meses. Senha errada volta 403 `INVALID_PASSWORD` (e não 401, que o
  /// interceptor trataria como sessão vencida).
  Future<CreatedMcpToken> create({
    required String name,
    required String password,
    required int expiresInDays,
  }) {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/users/me/mcp-tokens',
        data: {
          'name': name,
          'password': password,
          'expiresInDays': expiresInDays,
        },
      );
      return CreatedMcpToken.fromJson(response.data!);
    });
  }

  /// Revogar de novo não é erro (204 outra vez). É também como a vencida sai
  /// da lista: a listagem só devolve as que não foram revogadas.
  Future<void> revoke(String id) {
    return _guard(() async {
      await _dio.delete<void>('/users/me/mcp-tokens/$id');
    });
  }

  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final mcpTokenRepositoryProvider = Provider<McpTokenRepository>((ref) {
  return McpTokenRepository(ref.watch(dioProvider));
});

/// A lista da tela. `autoDispose` e sem cache de leitura: o "usada hoje" muda
/// a cada pergunta feita ao assistente, e uma lista guardada diria o contrário.
final mcpTokensProvider = FutureProvider.autoDispose<List<McpToken>>((ref) {
  return ref.watch(mcpTokenRepositoryProvider).list();
});

/// O relógio das duas telas, fixável nos testes (como o da Home).
final aiAssistantsClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);
