import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../domain/copilot_models.dart';

/// As rotas dos copilotos de IA. Todas são da liderança, e só valem nas
/// equipes em que o Pauta Admin ligou o recurso -- quem decide é o servidor;
/// o app só esconde o botão.
class CopilotRepository {
  const CopilotRepository(this._dio);

  final Dio _dio;

  Future<AiFeatures> features(String teamId) => _guard(() async {
        final res =
            await _dio.get<Map<String, dynamic>>('/teams/$teamId/ai-features');
        return AiFeatures.fromJson(res.data!);
      });

  // --- Copiloto de Escalas -------------------------------------------------

  String _base(String teamId) => '/teams/$teamId/schedule-copilot';

  Future<MonthPreview> monthPreview(String teamId, String month) =>
      _guard(() async {
        final res = await _dio
            .get<Map<String, dynamic>>('${_base(teamId)}/months/$month');
        return MonthPreview.fromJson(res.data!);
      });

  /// Gera a proposta do mês. A formação vem junto e é gravada como a de
  /// costume.
  Future<ScheduleCopilotSession> generate(
    String teamId, {
    required String month,
    required bool includeDrafts,
    required List<WeekdayLineup> lineups,
  }) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '${_base(teamId)}/sessions',
          data: {
            'month': month,
            'mode': includeDrafts ? 'INCLUDE_DRAFTS' : 'EMPTY_ONLY',
            'lineups': [
              for (final lineup in lineups)
                {
                  'weekday': lineup.weekday,
                  'positions': [
                    for (final p in lineup.positions)
                      {'positionId': p.positionId, 'count': p.count},
                  ],
                },
            ],
          },
        );
        return ScheduleCopilotSession.fromJson(res.data!);
      });

  Future<ScheduleCopilotSession> session(String teamId, String sessionId) =>
      _guard(() async {
        final res = await _dio
            .get<Map<String, dynamic>>('${_base(teamId)}/sessions/$sessionId');
        return ScheduleCopilotSession.fromJson(res.data!);
      });

  /// Uma edição: `SET`, `CLEAR`, `REPLACE`, `UNLOCK_SLOT`, `LOCK_DAY`,
  /// `UNLOCK_DAY`, `REGENERATE` ou `REVERT`. Devolve a proposta inteira.
  Future<ScheduleCopilotSession> edit(
    String teamId,
    String sessionId, {
    required int baseVersion,
    required String action,
    String? dateKey,
    String? positionId,
    int? slotIndex,
    String? membershipId,
    int? toVersion,
  }) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '${_base(teamId)}/sessions/$sessionId/edits',
          data: {
            'baseVersion': baseVersion,
            'action': action,
            if (dateKey != null) 'dateKey': dateKey,
            if (positionId != null) 'positionId': positionId,
            if (slotIndex != null) 'slotIndex': slotIndex,
            if (membershipId != null) 'membershipId': membershipId,
            if (toVersion != null) 'toVersion': toVersion,
          },
        );
        return ScheduleCopilotSession.fromJson(res.data!);
      });

  Future<List<CommitResult>> commit(
    String teamId,
    String sessionId, {
    required int version,
    required List<String> dateKeys,
  }) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '${_base(teamId)}/sessions/$sessionId/commit',
          data: {'version': version, 'dateKeys': dateKeys},
        );
        return ((res.data!['results'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(CommitResult.fromJson)
            .toList();
      });

  Future<void> discard(String teamId, String sessionId) => _guard(
        () => _dio.post<void>('${_base(teamId)}/sessions/$sessionId/discard'),
      );

  // --- Copiloto de Repertório ----------------------------------------------

  Future<RepertoireSuggestion> suggestRepertoire(
    String eventId, {
    required String serviceId,
    required String theme,
    String? context,
    int? count,
  }) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/events/$eventId/repertoire-copilot/sessions',
          data: {
            'serviceId': serviceId,
            'theme': theme,
            if (context != null && context.trim().isNotEmpty)
              'context': context.trim(),
            if (count != null) 'count': count,
          },
        );
        return RepertoireSuggestion.fromJson(res.data!);
      });

  Future<RepertoireSuggestion> refineRepertoire(
    String eventId,
    String sessionId, {
    required int baseVersion,
    required String instruction,
    required List<String> lockedSongIds,
  }) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/events/$eventId/repertoire-copilot/sessions/$sessionId/refine',
          data: {
            'baseVersion': baseVersion,
            'instruction': instruction,
            'lockedSongIds': lockedSongIds,
          },
        );
        return RepertoireSuggestion.fromJson(res.data!);
      });

  /// Só registro, para a métrica: as músicas entram no formulário e são
  /// salvas pelo caminho de sempre.
  Future<void> markApplied(
    String eventId,
    String sessionId,
    List<String> songIds,
  ) =>
      _guard(
        () => _dio.post<void>(
          '/events/$eventId/repertoire-copilot/sessions/$sessionId/applied',
          data: {'songIds': songIds},
        ),
      );

  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final copilotRepositoryProvider = Provider<CopilotRepository>((ref) {
  return CopilotRepository(ref.watch(dioProvider));
});

/// O que a liderança desta equipe pode usar. **Só para quem lidera**: o
/// servidor responde 403 ao integrante, e quem chama confere o papel antes.
/// Falhar aqui (rede, servidor antigo) é "nenhum copiloto", e não erro na
/// tela: os botões só não aparecem.
final aiFeaturesProvider =
    FutureProvider.autoDispose.family<AiFeatures, String>((ref, teamId) async {
  try {
    return await ref.watch(copilotRepositoryProvider).features(teamId);
  } on ApiException {
    return AiFeatures.none;
  }
});
