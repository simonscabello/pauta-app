import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/shared_preferences_provider.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/onboarding_models.dart';

class OnboardingRepository {
  const OnboardingRepository(this._dio);

  final Dio _dio;

  Future<List<OnboardingRecord>> list() {
    return _guard(() async {
      final response = await _dio.get<List<dynamic>>('/users/me/onboardings');
      return response.data!
          .map((e) => OnboardingRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> record(OnboardingFlow flow, OnboardingOutcome outcome) {
    return _guard(() async {
      await _dio.post<void>(
        '/users/me/onboardings',
        data: {
          'flow': flow.flow,
          'version': flow.version,
          'status': outcome.apiValue,
        },
      );
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

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(ref.watch(dioProvider));
});

/// A resposta que o aparelho ainda não conseguiu entregar ao servidor.
///
/// **O servidor é a fonte da verdade** — é ele que faz o tour não reaparecer
/// num celular novo ou na versão Web. Isto é só a rede de segurança para o
/// caso de a gravação falhar (sinal ruim no fim do tour): sem ela, quem acabou
/// de concluir receberia as boas-vindas de novo na próxima abertura. Guardado
/// por usuário, porque o aparelho troca de dono.
class PendingOnboardings {
  const PendingOnboardings(this._prefs);

  final SharedPreferences _prefs;

  static String _keyFor(String userId) => 'onboarding.pending.$userId';

  Map<String, String> _read(String userId) {
    final raw = _prefs.getString(_keyFor(userId));
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } on Object {
      return {};
    }
  }

  bool contains(String userId, OnboardingFlow flow) =>
      _read(userId).containsKey(flow.key);

  Future<void> add(
    String userId,
    OnboardingFlow flow,
    OnboardingOutcome outcome,
  ) async {
    final pending = _read(userId)..[flow.key] = outcome.apiValue;
    await _prefs.setString(_keyFor(userId), jsonEncode(pending));
  }

  Future<void> remove(String userId, OnboardingFlow flow) async {
    final pending = _read(userId)..remove(flow.key);
    if (pending.isEmpty) {
      await _prefs.remove(_keyFor(userId));
    } else {
      await _prefs.setString(_keyFor(userId), jsonEncode(pending));
    }
  }

  /// O que ficou por entregar, já como assunto + edição.
  List<(OnboardingFlow, OnboardingOutcome)> entries(String userId) {
    return [
      for (final entry in _read(userId).entries)
        if (parseOnboardingKey(entry.key) case final flow?)
          if (OnboardingOutcome.fromApi(entry.value) case final outcome?)
            (flow, outcome),
    ];
  }
}

final pendingOnboardingsProvider = Provider<PendingOnboardings>((ref) {
  return PendingOnboardings(ref.watch(sharedPreferencesProvider));
});

/// Grava a resposta no servidor; falhando, ela fica no aparelho e vai na
/// próxima vez que o app perguntar se deve oferecer o tour.
Future<void> recordOnboardingOutcome(
  Ref ref,
  OnboardingFlow flow,
  OnboardingOutcome outcome,
) async {
  final userId = ref.read(authControllerProvider).user?.id;
  if (userId == null) return;
  final pending = ref.read(pendingOnboardingsProvider);
  // Primeiro no aparelho: se o app fechar no meio da chamada, a resposta não
  // se perde.
  await pending.add(userId, flow, outcome);
  try {
    await ref.read(onboardingRepositoryProvider).record(flow, outcome);
    await pending.remove(userId, flow);
  } on ApiException {
    // Fica pendente; `memberOnboardingDueProvider` reenvia.
  }
}

/// Se as boas-vindas do primeiro acesso devem aparecer para quem está na
/// conta — qualquer papel.
///
/// Observa só o **id** do usuário: trocar de conta no mesmo aparelho refaz a
/// pergunta; mudar o nome ou a foto, não. Antes de perguntar ao servidor,
/// entrega o que ficou pendente — e, havendo pendência deste tour, a resposta
/// já é não.
final memberOnboardingDueProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final userId =
      ref.watch(authControllerProvider.select((state) => state.user?.id));
  if (userId == null) return false;

  const flow = OnboardingFlows.member;
  final pending = ref.read(pendingOnboardingsProvider);
  final repository = ref.read(onboardingRepositoryProvider);

  for (final (pendingFlow, outcome) in pending.entries(userId)) {
    try {
      await repository.record(pendingFlow, outcome);
      await pending.remove(userId, pendingFlow);
    } on ApiException {
      // Continua pendente; tenta de novo na próxima abertura.
    }
  }

  final records = await repository.list();
  return shouldOfferOnboarding(
    flow,
    records: records,
    pendingLocally: pending.contains(userId, flow),
  );
});
