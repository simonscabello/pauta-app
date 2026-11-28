import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/core/network/dio_client.dart';
import 'package:louvor_app/core/storage/offline_policy.dart';
import 'package:louvor_app/core/storage/read_cache.dart';
import 'package:louvor_app/core/storage/shared_preferences_provider.dart';
import 'package:louvor_app/features/auth/application/auth_controller.dart';
import 'package:louvor_app/features/auth/domain/auth_models.dart';
import 'package:louvor_app/features/events/application/offline_sync_coordinator.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    tzdata.initializeTimeZones();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('seleção de escalas para o modo culto offline', () {
    // 10/11/2026 15:00 UTC = 10/11/2026 12:00 America/Sao_Paulo.
    final now = DateTime.utc(2026, 11, 10, 15, 0);

    test('integrante pré-carrega todas as publicadas em que está escalado em 30 dias (não só 3)',
        () {
      final events = [
        // Ontem: fica de fora.
        _event('past', DateTime.utc(2026, 11, 9, 22, 0), assigned: ['m1']),
        // Hoje (mesmo após o horário do primeiro culto: dia civil ainda é hoje).
        _event('today', DateTime.utc(2026, 11, 10, 12, 0), assigned: ['m1']),
        // 4 escalas nos próximos 30 dias (mais do que o antigo teto de 3).
        _event('d5', DateTime.utc(2026, 11, 15, 12, 0), assigned: ['m1']),
        _event('d12', DateTime.utc(2026, 11, 22, 12, 0), assigned: ['m1']),
        _event('d19', DateTime.utc(2026, 11, 29, 12, 0), ministerId: 'm1'),
        _event('d30', DateTime.utc(2026, 12, 10, 12, 0), assigned: ['m1']),
        // Dia +31: passa dos 30 dias.
        _event('d31', DateTime.utc(2026, 12, 11, 12, 0), assigned: ['m1']),
        // Rascunho: nunca entra.
        _event(
          'draft',
          DateTime.utc(2026, 11, 16, 12, 0),
          status: 'DRAFT',
          assigned: ['m1'],
        ),
        // Escala de outra pessoa: não entra para integrante.
        _event('other', DateTime.utc(2026, 11, 18, 12, 0), assigned: ['m2']),
      ];

      final selected = selectEventsForOfflinePrefetch(
        events.reversed, // fora de ordem para validar ordenação
        membershipId: 'm1',
        canManage: false,
        now: now,
      );

      expect(
        selected.map((e) => e.id).toList(),
        ['today', 'd5', 'd12', 'd19', 'd30'],
      );
    });

    test('liderança pré-carrega todas as publicadas da equipe até o fim do mês seguinte',
        () {
      final events = [
        _event('past', DateTime.utc(2026, 11, 9, 12, 0), assigned: ['m2']),
        _event(
          'this-month-other',
          DateTime.utc(2026, 11, 22, 12, 0),
          assigned: ['m2'],
        ),
        _event(
          'next-month-end',
          DateTime.utc(2026, 12, 31, 22, 0),
          assigned: ['m2'],
        ),
        // Rascunho no mês seguinte continua de fora.
        _event(
          'next-month-draft',
          DateTime.utc(2026, 12, 20, 12, 0),
          status: 'DRAFT',
          assigned: ['m1'],
        ),
        // Dois meses depois: fora.
        _event('jan-1', DateTime.utc(2027, 1, 1, 12, 0), assigned: ['m1']),
      ];

      final selected = selectEventsForOfflinePrefetch(
        events,
        membershipId: 'm1',
        canManage: true,
        now: now,
      );

      expect(
        selected.map((e) => e.id).toList(),
        ['this-month-other', 'next-month-end'],
      );
    });

    test('virada de ano e janeiro curto respeitam mês seguinte e piso de 30 dias',
        () {
      // 15/12/2026 -> mês seguinte vai até 31/01/2027.
      expect(
        offlinePrefetchWindowEnd(
          todayCivil: DateTime.utc(2026, 12, 15),
          canManage: true,
        ),
        DateTime.utc(2027, 1, 31),
      );

      // 30/01/2027 -> fim de fevereiro é 28/02 (29 dias), mas piso é 30 dias (01/03).
      expect(
        offlinePrefetchWindowEnd(
          todayCivil: DateTime.utc(2027, 1, 30),
          canManage: true,
        ),
        DateTime.utc(2027, 3, 1),
      );
    });

    test('respeita o fuso horário da equipe na virada do dia', () {
      // 11/11/2026 01:00 UTC = 10/11/2026 22:00 em São Paulo (ainda hoje!).
      final nowLateNight = DateTime.utc(2026, 11, 11, 1, 0);
      final eventSameCivilDay =
          _event('sp-night', DateTime.utc(2026, 11, 10, 23, 0), assigned: ['m1']);
      final eventYesterday =
          _event('sp-prev', DateTime.utc(2026, 11, 9, 23, 0), assigned: ['m1']);

      final selected = selectEventsForOfflinePrefetch(
        [eventYesterday, eventSameCivilDay],
        membershipId: 'm1',
        canManage: false,
        now: nowLateNight,
      );

      expect(selected.map((e) => e.id).toList(), ['sp-night']);
    });
  });

  group('política de renovação', () {
    final base = DateTime.utc(2026, 11, 10, 12, 0);

    test('sem cópia em cache sempre renova', () {
      expect(
        needsOfflineRefresh(cachedAt: null, now: base),
        isTrue,
      );
    });

    test('com updatedAt comparável renova imediatamente quando muda e pula quando igual',
        () {
      final v1 = DateTime.utc(2026, 11, 10, 10, 0);
      final v2 = DateTime.utc(2026, 11, 10, 11, 59);

      // Mudou há 1 minuto -> renova imediatamente (sem esperar 6 h).
      expect(
        needsOfflineRefresh(
          cachedAt: DateTime.utc(2026, 11, 10, 11, 58),
          cachedUpdatedAt: v1,
          remoteUpdatedAt: v2,
          now: base,
        ),
        isTrue,
      );

      // Igual mesmo após 24 h -> não renova à toa.
      expect(
        needsOfflineRefresh(
          cachedAt: base.subtract(const Duration(hours: 24)),
          cachedUpdatedAt: v1,
          remoteUpdatedAt: v1,
          now: base,
        ),
        isFalse,
      );
    });

    test('sem updatedAt remoto (músicas na escala) renova a cada 6 horas', () {
      expect(
        needsOfflineRefresh(
          cachedAt: base.subtract(const Duration(hours: 5, minutes: 59)),
          now: base,
        ),
        isFalse,
      );
      expect(
        needsOfflineRefresh(
          cachedAt: base.subtract(const Duration(hours: 6)),
          now: base,
        ),
        isTrue,
      );
    });

    test('sincronização automática respeita o intervalo mínimo de 6 horas', () {
      expect(shouldRunScheduledSync(lastSyncAt: null, now: base), isTrue);
      expect(
        shouldRunScheduledSync(
          lastSyncAt: base.subtract(const Duration(hours: 5, minutes: 59)),
          now: base,
        ),
        isFalse,
      );
      expect(
        shouldRunScheduledSync(
          lastSyncAt: base.subtract(const Duration(hours: 6)),
          now: base,
        ),
        isTrue,
      );
    });
  });

  group('limpeza e teto do cache offline', () {
    final now = DateTime.utc(2026, 11, 27, 12, 0);

    test('remove escalas passadas (> 7d) e músicas órfãs não abertas há 60 dias',
        () {
      final plan = planOfflineCacheCleanup(
        now: now,
        events: [
          // Passada há 8 dias -> sai, e a música exclusiva dela (s-old-event)
          // deixa de estar referenciada.
          CachedEventMeta(
            id: 'e-expired',
            startsAt: now.subtract(const Duration(days: 8)),
            cachedAt: now.subtract(const Duration(days: 10)),
            songIds: {'s-old-event', 's-shared'},
            sizeBytes: 1000,
          ),
          // Futura -> fica, protegendo s-shared e s-upcoming.
          CachedEventMeta(
            id: 'e-future',
            startsAt: now.add(const Duration(days: 3)),
            cachedAt: now.subtract(const Duration(hours: 2)),
            songIds: {'s-shared', 's-upcoming'},
            sizeBytes: 1000,
          ),
        ],
        songs: [
          // Só estava na escala expirada e nunca foi aberta -> sai.
          CachedSongMeta(
            id: 's-old-event',
            cachedAt: now.subtract(const Duration(days: 10)),
            lastOpenedAt: null,
            sizeBytes: 500,
          ),
          // Compartilhada com escala futura -> fica mesmo sem ter sido aberta há 90 dias.
          CachedSongMeta(
            id: 's-shared',
            cachedAt: now.subtract(const Duration(days: 90)),
            lastOpenedAt: now.subtract(const Duration(days: 90)),
            sizeBytes: 500,
          ),
          // Na escala futura e nunca aberta -> fica.
          CachedSongMeta(
            id: 's-upcoming',
            cachedAt: now.subtract(const Duration(hours: 2)),
            lastOpenedAt: null,
            sizeBytes: 500,
          ),
          // Fora de qualquer escala, aberta há 59 dias -> fica.
          CachedSongMeta(
            id: 's-recent',
            cachedAt: now.subtract(const Duration(days: 59)),
            lastOpenedAt: now.subtract(const Duration(days: 59)),
            sizeBytes: 500,
          ),
          // Fora de qualquer escala, aberta há 60 dias -> sai.
          CachedSongMeta(
            id: 's-stale',
            cachedAt: now.subtract(const Duration(days: 60)),
            lastOpenedAt: now.subtract(const Duration(days: 60)),
            sizeBytes: 500,
          ),
        ],
      );

      expect(plan.eventIdsToRemove, {'e-expired'});
      expect(plan.songIdsToRemove, {'s-old-event', 's-stale'});
    });

    test('teto de quantidade remove primeiro músicas fora de escalas (LRU)', () {
      final plan = planOfflineCacheCleanup(
        now: now,
        maxCachedSongs: 2,
        events: [
          CachedEventMeta(
            id: 'e1',
            startsAt: now.add(const Duration(days: 2)),
            cachedAt: now,
            songIds: {'s-event'},
            sizeBytes: 100,
          ),
        ],
        songs: [
          CachedSongMeta(
            id: 's-event',
            cachedAt: now.subtract(const Duration(days: 40)),
            lastOpenedAt: null,
            sizeBytes: 100,
          ),
          CachedSongMeta(
            id: 's-older',
            cachedAt: now.subtract(const Duration(days: 20)),
            lastOpenedAt: now.subtract(const Duration(days: 20)),
            sizeBytes: 100,
          ),
          CachedSongMeta(
            id: 's-newer',
            cachedAt: now.subtract(const Duration(days: 5)),
            lastOpenedAt: now.subtract(const Duration(days: 5)),
            sizeBytes: 100,
          ),
        ],
      );

      expect(plan.songIdsToRemove, {'s-older'});
    });

    test('teto de bytes protege localStorage mesmo quando só escalas sobram', () {
      final plan = planOfflineCacheCleanup(
        now: now,
        maxCachedSongs: 100,
        maxCacheBytes: 1500,
        events: [
          CachedEventMeta(
            id: 'e-near',
            startsAt: now.add(const Duration(days: 2)),
            cachedAt: now,
            songIds: {'s-near'},
            sizeBytes: 200,
          ),
          CachedEventMeta(
            id: 'e-far',
            startsAt: now.add(const Duration(days: 25)),
            cachedAt: now,
            songIds: {'s-far'},
            sizeBytes: 200,
          ),
        ],
        songs: [
          CachedSongMeta(
            id: 's-near',
            cachedAt: now,
            lastOpenedAt: null,
            sizeBytes: 800,
          ),
          CachedSongMeta(
            id: 's-far',
            cachedAt: now,
            lastOpenedAt: null,
            sizeBytes: 800,
          ),
        ],
      );

      // Total inicial = 200 + 200 + 800 + 800 = 2000 > 1500 -> remove a da
      // escala mais distante primeiro, preservando a escala mais próxima.
      expect(plan.songIdsToRemove, {'s-far'});
    });

    test('ReadCache.prune aplica a limpeza, preserva lastOpenedAt e atualiza resumo',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = ReadCache(prefs);

      // Escala futura com s1.
      await cache.saveEvent(
        'e-future',
        _eventJson(
          'e-future',
          now.add(const Duration(days: 4)),
          songs: [
            {'songId': 's1', 'serviceId': 'srv1', 'title': 'Música 1'},
          ],
        ),
        now: now,
      );
      // Escala passada há 15 dias com s2.
      await cache.saveEvent(
        'e-old',
        _eventJson(
          'e-old',
          now.subtract(const Duration(days: 15)),
          songs: [
            {'songId': 's2', 'serviceId': 'srv1', 'title': 'Música 2'},
          ],
        ),
        now: now.subtract(const Duration(days: 15)),
      );

      // s1 pré-carregada (nunca aberta), protegida por e-future.
      await cache.saveSong(
        's1',
        {'id': 's1', 'title': 'M1'},
        markOpened: false,
        now: now,
      );
      // s2 pré-carregada para e-old (nunca aberta) -> deve sair.
      await cache.saveSong(
        's2',
        {'id': 's2', 'title': 'M2'},
        markOpened: false,
        now: now.subtract(const Duration(days: 15)),
      );
      // s3 aberta há 10 dias -> deve ficar.
      await cache.saveSong(
        's3',
        {'id': 's3', 'title': 'M3'},
        markOpened: true,
        now: now.subtract(const Duration(days: 10)),
      );
      // Refetch em segundo plano NÃO pode apagar o lastOpenedAt de s3.
      await cache.saveSong(
        's3',
        {'id': 's3', 'title': 'M3 v2'},
        markOpened: false,
        now: now,
      );
      expect(
        cache.readSongEntry('s3')?.lastOpenedAt,
        now.subtract(const Duration(days: 10)),
      );
      // s4 aberta há 70 dias e fora de escalas -> deve sair.
      await cache.saveSong(
        's4',
        {'id': 's4', 'title': 'M4'},
        markOpened: true,
        now: now.subtract(const Duration(days: 70)),
      );
      // s5 em formato legado (sem chave lastOpenedAt), gravada há 5 dias -> fica.
      await prefs.setString(
        'cache.song.s5',
        jsonEncode({
          'cachedAt': now.subtract(const Duration(days: 5)).toIso8601String(),
          'song': {'id': 's5', 'title': 'Legado'},
        }),
      );

      final plan = await cache.prune(now: now);
      expect(plan.eventIdsToRemove, {'e-old'});
      expect(plan.songIdsToRemove, {'s2', 's4'});
      expect(cache.readEvent('e-future'), isNotNull);
      expect(cache.readEvent('e-old'), isNull);
      expect(cache.readSong('s1'), isNotNull);
      expect(cache.readSong('s2'), isNull);
      expect(cache.readSong('s3'), isNotNull);
      expect(cache.readSong('s4'), isNull);
      expect(cache.readSong('s5'), isNotNull);

      expect(
        cache.summary(),
        const OfflineCacheSummary(scheduleCount: 1, songCount: 3),
      );
      expect(
        formatOfflineAvailability(cache.summary()),
        'Disponível sem internet: 1 escala, 3 músicas',
      );
    });
  });

  group('OfflineSyncCoordinator (sem rede real)', () {
    test('pré-carrega escalas selecionadas, renova só quando updatedAt muda ou após 6 h',
        () async {
      final prefs = await SharedPreferences.getInstance();
      var currentNow = DateTime.utc(2026, 11, 10, 12, 0);
      var e1UpdatedAt = DateTime.utc(2026, 11, 10, 10, 0);

      final eventFetches = <String>[];
      final songFetches = <String>[];

      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final path = options.path;
            if (path == '/teams/t1/events') {
              return handler.resolve(
                Response<List<dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    _eventJson(
                      'e1',
                      currentNow.add(const Duration(days: 3)),
                      assigned: ['m1'],
                      updatedAt: e1UpdatedAt,
                    ),
                    _eventJson(
                      'e2',
                      currentNow.add(const Duration(days: 10)),
                      assigned: ['m1'],
                      updatedAt: DateTime.utc(2026, 11, 10, 10, 0),
                    ),
                    _eventJson(
                      'e-other',
                      currentNow.add(const Duration(days: 5)),
                      assigned: ['m2'],
                    ),
                    _eventJson(
                      'e-draft',
                      currentNow.add(const Duration(days: 6)),
                      status: 'DRAFT',
                      assigned: ['m1'],
                    ),
                  ],
                ),
              );
            }
            if (path.startsWith('/events/')) {
              final id = path.split('/').last;
              eventFetches.add(id);
              return handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _eventJson(
                    id,
                    currentNow.add(Duration(days: id == 'e1' ? 3 : 10)),
                    assigned: ['m1'],
                    updatedAt: id == 'e1'
                        ? e1UpdatedAt
                        : DateTime.utc(2026, 11, 10, 10, 0),
                    songs: [
                      {
                        'songId': 's-$id',
                        'serviceId': 'srv1',
                        'title': 'Música $id',
                      },
                    ],
                  ),
                ),
              );
            }
            if (path.startsWith('/teams/t1/songs/')) {
              final songId = path.split('/').last;
              songFetches.add(songId);
              return handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'id': songId,
                    'title': 'Música $songId',
                    'lyrics': 'Letra',
                    'chords': '[G]Acorde',
                    'chordsKey': 'G',
                  },
                ),
              );
            }
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dioProvider.overrideWithValue(dio),
          offlineClockProvider.overrideWithValue(() => currentNow),
          authControllerProvider.overrideWith(
            (ref) => _StaticAuthController(
              ref,
              AuthState.signedIn(
                const AuthUser(
                  id: 'u1',
                  name: 'Maria',
                  email: 'maria@teste.com',
                  mustChangePassword: false,
                ),
                const [
                  TeamSummary(
                    membershipId: 'm1',
                    teamId: 't1',
                    name: 'Louvor',
                    role: 'MEMBER',
                    displayName: 'Maria',
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final coordinator = container.read(offlineSyncCoordinatorProvider);
      await coordinator.syncIfDue(force: true);

      expect(eventFetches, ['e1', 'e2']);
      expect(songFetches, ['s-e1', 's-e2']);
      expect(
        container.read(offlineCacheSummaryProvider),
        const OfflineCacheSummary(scheduleCount: 2, songCount: 2),
      );

      // 1 hora depois: syncIfDue não refaz nada (dentro da janela de 6 h).
      eventFetches.clear();
      songFetches.clear();
      currentNow = currentNow.add(const Duration(hours: 1));
      await coordinator.syncIfDue();
      expect(eventFetches, isEmpty);
      expect(songFetches, isEmpty);

      // Escala e1 muda de updatedAt e a lista chega fresca -> só e1 é buscada!
      e1UpdatedAt = DateTime.utc(2026, 11, 10, 12, 30);
      await coordinator.syncFromUpcoming(
        team: const TeamSummary(
          membershipId: 'm1',
          teamId: 't1',
          name: 'Louvor',
          role: 'MEMBER',
          displayName: 'Maria',
        ),
        upcomingEvents: [
          Event.fromJson(
            _eventJson(
              'e1',
              currentNow.add(const Duration(days: 3)),
              assigned: ['m1'],
              updatedAt: e1UpdatedAt,
            ),
          ),
          Event.fromJson(
            _eventJson(
              'e2',
              currentNow.add(const Duration(days: 10)),
              assigned: ['m1'],
              updatedAt: DateTime.utc(2026, 11, 10, 10, 0),
            ),
          ),
        ],
      );
      expect(eventFetches, ['e1']);
      expect(songFetches, isEmpty); // músicas ainda têm < 6 h

      // Passam-se 6 horas desde a última sync -> músicas (sem updatedAt remoto)
      // são renovadas; escalas inalteradas não precisam ser refeitas.
      eventFetches.clear();
      songFetches.clear();
      currentNow = currentNow.add(const Duration(hours: 6));
      await coordinator.syncIfDue();
      expect(eventFetches, isEmpty);
      expect(songFetches, ['s-e1', 's-e2']);
    });
  });
}

Event _event(
  String id,
  DateTime startsAt, {
  String status = 'PUBLISHED',
  List<String> assigned = const [],
  String? ministerId,
  DateTime? updatedAt,
}) {
  return Event.fromJson(
    _eventJson(
      id,
      startsAt,
      status: status,
      assigned: assigned,
      ministerId: ministerId,
      updatedAt: updatedAt,
    ),
  );
}

Map<String, dynamic> _eventJson(
  String id,
  DateTime startsAt, {
  String status = 'PUBLISHED',
  List<String> assigned = const [],
  String? ministerId,
  DateTime? updatedAt,
  List<Map<String, dynamic>> songs = const [],
}) {
  return {
    'id': id,
    'teamId': 't1',
    'title': 'Culto $id',
    'startsAt': startsAt.toUtc().toIso8601String(),
    'status': status,
    'timezone': 'America/Sao_Paulo',
    if (updatedAt != null) 'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (ministerId != null)
      'minister': {'membershipId': ministerId, 'displayName': 'Pessoa'},
    'assignments': [
      if (assigned.isNotEmpty)
        {
          'positionId': 'p1',
          'positionName': 'Guitarra',
          'sortOrder': 0,
          'members': [
            for (final m in assigned)
              {
                'id': 'a-$m',
                'membershipId': m,
                'displayName': 'Membro $m',
              },
          ],
        },
    ],
    'services': [
      {
        'id': 'srv1',
        'label': 'Culto',
        'startsAt': startsAt.toUtc().toIso8601String(),
      },
    ],
    'songs': songs,
  };
}

class _StaticAuthController extends AuthController {
  _StaticAuthController(super.ref, this._initial);

  final AuthState _initial;

  @override
  Future<void> bootstrap() async {
    state = _initial;
  }
}
