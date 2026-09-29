import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../domain/team_whatsapp.dart';

class WhatsAppRepository {
  const WhatsAppRepository(this._dio);

  final Dio _dio;

  Future<TeamWhatsApp> status(String teamId) {
    return _guard(() async {
      final response =
          await _dio.get<Map<String, dynamic>>('/teams/$teamId/whatsapp');
      return TeamWhatsApp.fromJson(response.data!);
    });
  }

  /// Gera um código novo (o anterior deixa de valer).
  Future<TeamWhatsApp> createLinkCode(String teamId) {
    return _guard(() async {
      final response = await _dio
          .post<Map<String, dynamic>>('/teams/$teamId/whatsapp/link-code');
      return TeamWhatsApp.fromJson(response.data!);
    });
  }

  Future<void> unlink(String teamId) {
    return _guard(() => _dio.delete<void>('/teams/$teamId/whatsapp'));
  }

  /// Manda o texto da escala ao grupo da equipe. Devolve o nome do grupo.
  Future<String?> sendSchedule(String eventId, String text) {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/events/$eventId/whatsapp',
        data: {'text': text},
      );
      return response.data?['groupName'] as String?;
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

final whatsAppRepositoryProvider = Provider<WhatsAppRepository>((ref) {
  return WhatsAppRepository(ref.watch(dioProvider));
});

/// O estado do grupo do WhatsApp da equipe. **Só para quem lidera**: o
/// servidor responde 403 ao integrante, e quem chama confere o papel antes.
final teamWhatsAppProvider =
    FutureProvider.autoDispose.family<TeamWhatsApp, String>((ref, teamId) {
  return ref.watch(whatsAppRepositoryProvider).status(teamId);
});
