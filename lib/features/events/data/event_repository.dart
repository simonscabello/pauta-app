import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/read_cache.dart';
import '../../../core/storage/shared_preferences_provider.dart';
import '../../songs/data/song_repository.dart';
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
  /// equipe), em ordem cronológica. É como a agenda carrega o mês exibido no
  /// calendário (inclusive meses passados e meses sem escala), com cache
  /// offline próprio por recorte.
  Future<CachedValue<List<Event>>> listRange(
    String teamId, {
    required String from,
    required String to,
    // Falso para o pré-carregamento: a janela muda todo dia, e gravar cada
    // recorte encheria o armazenamento sem ninguém voltar a ele.
    bool cache = true,
  }) async {
    final cacheScope = 'range.$from.$to';
    try {
      final response = await _dio.get<List<dynamic>>(
        '/teams/$teamId/events',
        queryParameters: {'from': from, 'to': to, 'limit': 100},
      );
      final maps = response.data!
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (cache) {
        // Falha ao gravar (cota da Web) não derruba o mês que veio da rede.
        try {
          await _cache.saveAgenda(teamId, cacheScope, maps);
        } catch (_) {}
      }
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
    String? rehearsalNotes,
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
          if (rehearsalAt != null && (rehearsalNotes?.isNotEmpty ?? false))
            'rehearsalNotes': rehearsalNotes,
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
    String? rehearsalNotes,
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
          if (rehearsalNotes != null) 'rehearsalNotes': rehearsalNotes,
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

  /// "Confirmo" ou "não posso" de quem está escalado.
  Future<Event> respond(String eventId, {required bool confirmed}) async {
    return _guard(() async {
      final response = await _dio.put<Map<String, dynamic>>(
        '/events/$eventId/confirmation',
        data: {'status': confirmed ? 'CONFIRMED' : 'DECLINED'},
      );
      return Event.fromJson(response.data!);
    });
  }

  /// O endereço público da escala, só de leitura. Cria o link na primeira
  /// vez e devolve o mesmo nas seguintes.
  ///
  /// [showNames] muda se a página mostra quem serve; nulo mantém como está.
  Future<({String url, bool showNames})> publicLink(
    String eventId, {
    bool? showNames,
  }) async {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/events/$eventId/public-link',
        data: {if (showNames != null) 'showNames': showNames},
      );
      return (
        url: '${AppConfig.apiBaseUrl}/e/${response.data!['token']}',
        showNames: response.data!['showNames'] != false,
      );
    });
  }

  /// "Vou" ou "não vou" ao ensaio da escala.
  Future<Event> answerRehearsal(String eventId, {required bool attending}) {
    return _guard(() async {
      final response = await _dio.put<Map<String, dynamic>>(
        '/events/$eventId/rehearsal-attendance',
        data: {'attending': attending},
      );
      return Event.fromJson(response.data!);
    });
  }

  Future<void> revokePublicLink(String eventId) async {
    return _guard(() async {
      await _dio.delete<void>('/events/$eventId/public-link');
    });
  }

  /// "Posso cobrir" quem respondeu que não pode ([forMembershipId]).
  Future<Event> offerCover(String eventId, String forMembershipId) =>
      _cover('put', eventId, forMembershipId);

  /// Desistir da oferta (ou, para quem lidera, dispensá-la).
  Future<Event> withdrawCover(String eventId, String forMembershipId) =>
      _cover('delete', eventId, forMembershipId);

  /// Quem lidera aceita a oferta: a pessoa entra nas mesmas funções.
  Future<Event> approveCover(String eventId, String forMembershipId) =>
      _cover('post', eventId, forMembershipId, suffix: '/approve');

  Future<Event> _cover(
    String method,
    String eventId,
    String forMembershipId, {
    String suffix = '',
  }) {
    return _guard(() async {
      final response = await _dio.request<Map<String, dynamic>>(
        '/events/$eventId/cover/$forMembershipId$suffix',
        options: Options(method: method),
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
                  // O momento da lista da equipe. Quando vai, é ele que manda;
                  // a chave e o nome ao lado servem ao servidor de antes dele.
                  if (song.momentId != null) 'momentId': song.momentId,
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

  /// O tom e a versão da cifra que valem em cada música da escala, por
  /// `culto:música`. Leve de propósito: o leitor de cifra pergunta a cada
  /// poucos segundos no ensaio.
  Future<Map<String, LiveSong>> liveSongs(String eventId) async {
    return _guard(() async {
      final response = await _dio.get<List<dynamic>>('/events/$eventId/songs');
      return {
        for (final item in response.data!.cast<Map<String, dynamic>>())
          '${item['serviceId']}:${item['songId']}': (
            key: item['key'] as String?,
            // A API anterior às versões não manda o campo.
            hasChordVersion: item.containsKey('chordVersionId'),
            chordVersionId: item['chordVersionId'] as String?,
          ),
      };
    });
  }

  /// Muda só o tom de uma música desta escala, sem avisar a equipe no celular
  /// — quem está com a cifra aberta vê mudar sozinho.
  Future<void> setSongKey(String eventId, EventSong song, String? key) async {
    return _guard(() async {
      await _dio.patch<void>(
        '/events/$eventId/songs/${song.songId}',
        data: {'serviceId': song.serviceId, 'keyOverride': key},
      );
    });
  }

  /// A versão da cifra de uma música desta escala (nulo = a original).
  Future<void> setSongChordVersion(
    String eventId,
    EventSong song,
    String? versionId,
  ) async {
    return _guard(() async {
      await _dio.patch<void>(
        '/events/$eventId/songs/${song.songId}/chord-version',
        data: {'serviceId': song.serviceId, 'chordVersionId': versionId},
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

/// O que o leitor aberto confere de cada música da escala.
typedef LiveSong = ({String? key, bool hasChordVersion, String? chordVersionId});

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
  final repo = ref.watch(eventRepositoryProvider);
  final result = repo.list(teamId, scope: scope);
  if (scope == 'upcoming') {
    // Modo culto sem rede: as escalas mais próximas (até uma semana) vão para o
    // aparelho com a letra e a cifra, mesmo que ninguém a tenha aberto.
    unawaited(
      result.then((list) async {
        if (list.fromCache) return;
        // As três mais próximas: cobre o domingo com manhã e noite e o culto
        // do meio da semana sem multiplicar as chamadas.
        final next = list.data
            .where(
              (e) =>
                  !e.isDraft &&
                  e.startsAt.difference(DateTime.now()).inDays <= 7,
            )
            .take(3);
        for (final item in next) {
          final event = await repo.find(item.id);
          if (event.fromCache) return;
          await ref.read(songRepositoryProvider).prefetch(
                teamId,
                event.data.songs.map((song) => song.songId),
              );
        }
      }).catchError((_) {}),
    );
  }
  return result;
});

final eventHistoryProvider =
    FutureProvider.autoDispose.family<List<EventChange>, String>(
  (ref, eventId) => ref.watch(eventRepositoryProvider).history(eventId),
);

final eventProvider =
    FutureProvider.autoDispose.family<CachedValue<Event>, String>(
  (ref, eventId) async {
    final result = await ref.watch(eventRepositoryProvider).find(eventId);
    // Com a escala aberta e a rede de pé, a cifra e a letra das músicas dela
    // vão para o aparelho em segundo plano: é no ensaio que a rede cai.
    if (!result.fromCache && result.data.songs.isNotEmpty) {
      unawaited(
        ref.read(songRepositoryProvider).prefetch(
              result.data.teamId,
              result.data.songs.map((song) => song.songId),
            ),
      );
    }
    return result;
  },
);
