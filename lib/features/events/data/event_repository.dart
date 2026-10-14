import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/read_cache.dart';
import '../../../core/storage/shared_preferences_provider.dart';
import '../domain/event_change.dart';
import '../domain/event_models.dart';
import '../domain/service_moments.dart';

final readCacheProvider = Provider<ReadCache>((ref) {
  return ReadCache(ref.watch(sharedPreferencesProvider));
});

class EventRepository {
  const EventRepository(this._dio, this._cache);

  final Dio _dio;
  final ReadCache _cache;

  Future<CachedValue<List<Event>>> list(
    String teamId, {
    String scope = 'upcoming',
    int limit = 20,
  }) async {
    // Consultas maiores da Agenda não substituem o cache de 20 itens da Home.
    final cacheScope = limit == 20 ? scope : '$scope.$limit';
    try {
      final response = await _dio.get<List<dynamic>>(
        '/teams/$teamId/events',
        queryParameters: {'scope': scope, 'limit': limit},
      );
      final maps = response.data!
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      await _cache.saveAgenda(teamId, cacheScope, maps);
      return CachedValue(
        data: maps.map(Event.fromJson).toList(),
        fromCache: false,
      );
    } on DioException catch (e) {
      final cached = _cache.readAgenda(teamId, cacheScope);
      if (cached != null) {
        return CachedValue(
          data: cached.data.map(Event.fromJson).toList(),
          fromCache: true,
          cachedAt: cached.cachedAt,
        );
      }
      throw ApiException.fromDio(e);
    }
  }

  /// As escalas de um recorte de dias (`AAAA-MM-DD`, inclusivos, no fuso da
  /// equipe), em ordem cronológica. É como a agenda completa um mês que as
  /// listas de próximas e passadas não cobrem inteiro.
  Future<List<Event>> listRange(
    String teamId, {
    required String from,
    required String to,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/teams/$teamId/events',
        queryParameters: {'from': from, 'to': to, 'limit': 100},
      );
      return response.data!
          .map((e) => Event.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<CachedValue<Event>> find(String eventId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/events/$eventId');
      final map = Map<String, dynamic>.from(response.data!);
      await _cache.saveEvent(eventId, map);
      return CachedValue(data: Event.fromJson(map), fromCache: false);
    } on DioException catch (e) {
      final cached = _cache.readEvent(eventId);
      if (cached != null) {
        return CachedValue(
          data: Event.fromJson(cached.data),
          fromCache: true,
          cachedAt: cached.cachedAt,
        );
      }
      throw ApiException.fromDio(e);
    }
  }

  Future<Event> create(
    String teamId, {
    required String title,
    required List<Map<String, String?>> services,
    String? rehearsalAt,
    String? location,
    String? notes,
    String? colorPalette,
    RepertoireMode repertoireMode = RepertoireMode.planned,
  }) async {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/teams/$teamId/events',
        data: {
          'title': title,
          'services': services,
          if (rehearsalAt != null) 'rehearsalAt': rehearsalAt,
          if (location != null && location.isNotEmpty) 'location': location,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
          if (colorPalette != null && colorPalette.isNotEmpty)
            'colorPalette': colorPalette,
          // Sempre presente, inclusive no valor padrão: o campo é curto e
          // mandá-lo sempre poupa de descobrir, meses depois, que a escala
          // nasceu com o default de um servidor mais antigo.
          'repertoireMode': repertoireMode.wire,
        },
      );
      return Event.fromJson(response.data!);
    });
  }

  Future<GeneratedSchedules> generate(
    String teamId, {
    required int weeks,
  }) async {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/teams/$teamId/events/generate',
        data: {'weeks': weeks},
      );
      return GeneratedSchedules.fromJson(response.data!);
    });
  }

  Future<Event> update(
    String eventId, {
    String? title,
    List<Map<String, String?>>? services,
    String? rehearsalAt,
    bool removeRehearsalAt = false,
    String? location,
    String? notes,
    String? colorPalette,
    RepertoireMode? repertoireMode,
    DateTime? expectedUpdatedAt,
  }) async {
    return _guard(() async {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/events/$eventId',
        data: {
          if (title != null) 'title': title,
          // Omitir preserva os cultos que já existem: editar só o local não
          // pode apagar os horários.
          if (services != null) 'services': services,
          if (removeRehearsalAt) 'rehearsalAt': null,
          if (rehearsalAt != null) 'rehearsalAt': rehearsalAt,
          if (location != null) 'location': location,
          if (notes != null) 'notes': notes,
          if (colorPalette != null) 'colorPalette': colorPalette,
          if (repertoireMode != null) 'repertoireMode': repertoireMode.wire,
          if (expectedUpdatedAt != null)
            'expectedUpdatedAt': expectedUpdatedAt.toUtc().toIso8601String(),
        },
      );
      return Event.fromJson(response.data!);
    });
  }

  /// Histórico da escala. Liberado para a equipe inteira: quem mais quer saber
  /// quem o tirou da escala é justamente quem não a monta.
  Future<List<EventChange>> history(String eventId) async {
    return _guard(() async {
      final response =
          await _dio.get<List<dynamic>>('/events/$eventId/history');
      return response.data!
          .map((e) => EventChange.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> remove(String eventId) async {
    return _guard(() async {
      await _dio.delete<void>('/events/$eventId');
    });
  }

  Future<Event> publish(String eventId) async {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/events/$eventId/publish',
      );
      return Event.fromJson(response.data!);
    });
  }

  Future<Event> unpublish(String eventId) async {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/events/$eventId/unpublish',
      );
      return Event.fromJson(response.data!);
    });
  }

  Future<Event> duplicate(String eventId, {required String startsAt}) async {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/events/$eventId/duplicate',
        data: {'startsAt': startsAt},
      );
      return Event.fromJson(response.data!);
    });
  }

  Future<Event> replaceAssignments(
    String eventId,
    List<Map<String, Object?>> assignments, {
    String? ministerMembershipId,
    DateTime? expectedUpdatedAt,
  }) async {
    return _guard(() async {
      final response = await _dio.put<Map<String, dynamic>>(
        '/events/$eventId/assignments',
        data: {
          'assignments': assignments
              .map(
                (item) => {
                  'membershipId': item['membershipId'],
                  'positionId': item['positionId'],
                  if (item['note'] is String &&
                      (item['note']! as String).isNotEmpty)
                    'note': item['note'],
                },
              )
              .toList(),
          // Sempre presente: `null` é o pedido de limpar, e omitir significaria
          // "não mexe" -- o que deixaria o ministrante antigo preso na escala.
          'ministerMembershipId': ministerMembershipId,
          if (expectedUpdatedAt != null)
            'expectedUpdatedAt': expectedUpdatedAt.toUtc().toIso8601String(),
        },
      );
      return Event.fromJson(response.data!);
    });
  }

  /// Substitui o repertório inteiro, na ordem da lista.
  ///
  /// Bulk como a escalação: a pessoa arrasta, tira, acrescenta e salva de uma
  /// vez. Item a item deixaria a escala pela metade se a rede caísse no meio.
  Future<Event> replaceSongs(
    String eventId,
    List<EventSong> songs,
  ) async {
    return _guard(() async {
      final response = await _dio.put<Map<String, dynamic>>(
        '/events/$eventId/songs',
        data: {
          'songs': songs
              .map(
                (song) => {
                  'songId': song.songId,
                  // Em qual culto ela entra. Obrigatório: o servidor não
                  // escolhe por nós entre a manhã e a noite.
                  'serviceId': song.serviceId,
                  // A posição não vai: quem numera é o servidor, a partir da
                  // ordem — agora dentro de cada culto. Mandar índice abriria
                  // espaço para buraco e repetido.
                  if (song.keyOverride != null && song.keyOverride!.isNotEmpty)
                    'keyOverride': song.keyOverride,
                  if (song.note != null && song.note!.isNotEmpty)
                    'note': song.note,
                  // O momento do culto, quando escolhido. Ausente é ausente:
                  // mandar `null` ou omitir dá no mesmo no servidor, e nada
                  // preenche "Momento de Louvor" por dedução.
                  if (song.moment != null) 'moment': song.moment,
                  // Só faz sentido em "Outro"; o servidor limpa nos demais,
                  // mas mandar o que não vale já seria dizer duas coisas.
                  if (song.moment == otherServiceMoment &&
                      (song.momentLabel?.isNotEmpty ?? false))
                    'momentLabel': song.momentLabel,
                  // `isNew` não vai: quem decide isso é o histórico da equipe,
                  // no servidor. Mandá-lo daqui seria deixar a tela opinar
                  // sobre um fato que ela não tem como conhecer.
                  //
                  // Os hinários também não: são do cadastro da música, e esta
                  // tela monta o repertório de um domingo.
                },
              )
              .toList(),
        },
      );
      return Event.fromJson(response.data!);
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

class GeneratedSchedules {
  const GeneratedSchedules({
    required this.createdCount,
    required this.skippedCount,
  });

  factory GeneratedSchedules.fromJson(Map<String, dynamic> json) {
    return GeneratedSchedules(
      createdCount: json['createdCount'] as int? ?? 0,
      skippedCount: json['skippedCount'] as int? ?? 0,
    );
  }

  final int createdCount;
  final int skippedCount;
}

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(
    ref.watch(dioProvider),
    ref.watch(readCacheProvider),
  );
});

typedef EventsQuery = (String teamId, String scope);

final eventsProvider = FutureProvider.autoDispose
    .family<CachedValue<List<Event>>, EventsQuery>((ref, query) {
  final (teamId, scope) = query;
  return ref.watch(eventRepositoryProvider).list(teamId, scope: scope);
});

final eventHistoryProvider =
    FutureProvider.autoDispose.family<List<EventChange>, String>(
  (ref, eventId) => ref.watch(eventRepositoryProvider).history(eventId),
);

final eventProvider =
    FutureProvider.autoDispose.family<CachedValue<Event>, String>(
  (ref, eventId) {
    return ref.watch(eventRepositoryProvider).find(eventId);
  },
);
