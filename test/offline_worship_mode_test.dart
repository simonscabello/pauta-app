import 'dart:async';
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
import 'package:louvor_app/features/events/data/event_repository.dart';
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

    test('sem updatedAt remoto (músicas na escala) renova a cada 24 horas', () {
      expect(
        needsOfflineRefresh(
          cachedAt: base.subtract(const Duration(hours: 23, minutes: 59)),
          now: base,
          maxAge: kOfflineSongRefreshInterval,
        ),
        isFalse,
      );
      expect(
        needsOfflineRefresh(
          cachedAt: base.subtract(const Duration(hours: 24)),
          now: base,
          maxAge: kOfflineSongRefreshInterval,
        ),
        isTrue,
      );
    });

    test('limpeza automática (prune) roda no máximo uma vez por dia', () {
      expect(shouldRunOfflinePrune(lastPruneAt: null, now: base), isTrue);
      expect(
        shouldRunOfflinePrune(
          lastPruneAt: base.subtract(const Duration(hours: 23, minutes: 59)),
          now: base,
        ),
        isFalse,
      );
      expect(
        shouldRunOfflinePrune(
          lastPruneAt: base.subtract(const Duration(hours: 24)),
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

    test('teto de bytes nunca apaga música de escala dentro da janela de pré-carregamento',
        () {
      final plan = planOfflineCacheCleanup(
        now: now,
        maxCachedSongs: 100,
        maxCacheBytes: 1500,
        events: [
          // Ambas dentro da janela de pré-carregamento (+2d e +25d).
          CachedEventMeta(
            id: 'e-near',
            startsAt: now.add(const Duration(days: 2)),
            cachedAt: now,
            songIds: {'s-near'},
            sizeBytes: 200,
          ),
          CachedEventMeta(
            id: 'e-far-in-window',
            startsAt: now.add(const Duration(days: 25)),
            cachedAt: now,
            songIds: {'s-far-in-window'},
            sizeBytes: 200,
          ),
          // Fora da janela (aberta manualmente para daqui a 90 dias).
          CachedEventMeta(
            id: 'e-beyond-window',
            startsAt: now.add(const Duration(days: 90)),
            cachedAt: now,
            songIds: {'s-beyond-window'},
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
            id: 's-far-in-window',
            cachedAt: now,
            lastOpenedAt: null,
            sizeBytes: 800,
          ),
          CachedSongMeta(
            id: 's-beyond-window',
            cachedAt: now,
            lastOpenedAt: null,
            sizeBytes: 800,
          ),
        ],
      );

      // Total inicial = 3000 > 1500 -> remove só a música fora da janela;
      // as de e-near e e-far-in-window ficam intactas (sem laço de GETs).
      expect(plan.songIdsToRemove, {'s-beyond-window'});
    });

    test('no Android (sem teto de bytes) só valem 7 dias de escalas passadas e 60 dias de músicas ociosas',
        () async {
      final prefs = await SharedPreferences.getInstance();
      // Em VM/Android (`!kIsWeb`), `ReadCache(prefs)` não impõe teto de bytes.
      final cache = ReadCache(prefs);
      expect(cache.maxCacheBytes, isNull);
      expect(cache.maxCachedSongs, isNull);

      await cache.saveEvent(
        'e-future',
        _eventJson(
          'e-future',
          now.add(const Duration(days: 3)),
          songs: [
            {'songId': 's-big', 'serviceId': 'srv1', 'title': 'Grande'},
          ],
        ),
        now: now,
      );
      // Música aberta recentemente com conteúdo grande (fora do teto da Web).
      await cache.saveSong(
        's-big',
        {'id': 's-big', 'title': 'Grande', 'lyrics': 'A' * 5000},
        markOpened: true,
        now: now.subtract(const Duration(days: 5)),
      );
      await cache.saveSong(
        's-recent-orphan',
        {'id': 's-recent-orphan', 'title': 'Recente', 'lyrics': 'B' * 5000},
        markOpened: true,
        now: now.subtract(const Duration(days: 10)),
      );
      await cache.saveSong(
        's-old-orphan',
        {'id': 's-old-orphan', 'title': 'Antiga', 'lyrics': 'C' * 100},
        markOpened: true,
        now: now.subtract(const Duration(days: 61)),
      );

      final plan = await cache.prune(now: now);
      expect(plan.songIdsToRemove, {'s-old-orphan'});
      expect(cache.readSong('s-big'), isNotNull);
      expect(cache.readSong('s-recent-orphan'), isNotNull);
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
    test('pré-carrega escalas selecionadas, renova só quando updatedAt muda ou músicas após 24 h',
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

      // Passam-se 6 horas desde a última sync -> sincronização agendada roda,
      // mas músicas ainda têm < 24 h e não são refeitas.
      eventFetches.clear();
      songFetches.clear();
      currentNow = currentNow.add(const Duration(hours: 6));
      await coordinator.syncIfDue();
      expect(eventFetches, isEmpty);
      expect(songFetches, isEmpty);

      // Passam-se 24 horas desde a gravação das músicas -> agora renovam;
      // escalas inalteradas continuam sem refazer GET.
      currentNow = currentNow.add(const Duration(hours: 18));
      await coordinator.syncIfDue();
      expect(eventFetches, isEmpty);
      expect(songFetches, ['s-e1', 's-e2']);
    });

    test('orçamento de bytes na Web vale antes de baixar (mais próxima primeiro) e não entra em laço',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.utc(2026, 11, 10, 12, 0);
      final fetchedEvents = <String>[];
      final fetchedSongs = <String>[];

      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final path = options.path;
            if (path.startsWith('/events/')) {
              final id = path.split('/').last;
              fetchedEvents.add(id);
              final days = id == 'e1' ? 2 : (id == 'e2' ? 9 : 16);
              return handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _eventJson(
                    id,
                    now.add(Duration(days: days)),
                    assigned: ['m1'],
                    updatedAt: now,
                    songs: [
                      {'songId': 's-$id', 'serviceId': 'srv1', 'title': 'M $id'},
                    ],
                  ),
                ),
              );
            }
            if (path.startsWith('/teams/t1/songs/')) {
              final songId = path.split('/').last;
              fetchedSongs.add(songId);
              return handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'id': songId,
                    'title': 'Música $songId',
                    'lyrics': 'L' * 700,
                    'chords': 'C' * 700,
                    'chordsKey': 'G',
                  },
                ),
              );
            }
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );

      // Teto apertado simulando o `localStorage` da Web: cabe e1 (~450 B) +
      // s-e1 (~1500 B), mas já estoura antes de e2/s-e2 e e3/s-e3.
      final webCache = ReadCache(prefs, maxCacheBytes: 1500, maxCachedSongs: 150);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          readCacheProvider.overrideWithValue(webCache),
          dioProvider.overrideWithValue(dio),
          offlineClockProvider.overrideWithValue(() => now),
          authControllerProvider.overrideWith(
            (ref) => _StaticAuthController(ref, _signedInState('u1', 'm1', 't1')),
          ),
        ],
      );
      addTearDown(container.dispose);

      const team = TeamSummary(
        membershipId: 'm1',
        teamId: 't1',
        name: 'Louvor',
        role: 'MEMBER',
        displayName: 'Maria',
      );
      final upcoming = [
        _event('e3', now.add(const Duration(days: 16)), assigned: ['m1'], updatedAt: now),
        _event('e1', now.add(const Duration(days: 2)), assigned: ['m1'], updatedAt: now),
        _event('e2', now.add(const Duration(days: 9)), assigned: ['m1'], updatedAt: now),
      ];

      final coordinator = container.read(offlineSyncCoordinatorProvider);
      await coordinator.syncFromUpcoming(team: team, upcomingEvents: upcoming);

      // Escala mais próxima (e1) e sua música entram primeiro; para quando o
      // orçamento acaba, sem baixar e2 nem e3.
      expect(fetchedEvents, ['e1']);
      expect(fetchedSongs, ['s-e1']);
      expect(webCache.readEvent('e1'), isNotNull);
      expect(webCache.readSong('s-e1'), isNotNull);
      expect(webCache.readEvent('e2'), isNull);
      expect(webCache.readEvent('e3'), isNull);

      // Rodar prune não apaga s-e1 (está dentro da janela de pré-carregamento).
      final prunePlan = await webCache.prune(now: now);
      expect(prunePlan.songIdsToRemove, isEmpty);
      expect(webCache.readSong('s-e1'), isNotNull);

      // Nova reconstrução do upcoming (ex.: abrir a Home de novo): ZERO GETs!
      fetchedEvents.clear();
      fetchedSongs.clear();
      await coordinator.syncFromUpcoming(team: team, upcomingEvents: upcoming);
      expect(fetchedEvents, isEmpty);
      expect(fetchedSongs, isEmpty);
      expect(webCache.readSong('s-e1'), isNotNull);
    });

    test('limita cada passada a no máximo 20 GETs e o restante fica para a próxima',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.utc(2026, 11, 10, 12, 0);
      var totalGets = 0;

      // 12 escalas, cada uma com 2 músicas exclusivas = 12 + 24 = 36 GETs ao todo.
      final upcoming = [
        for (var i = 1; i <= 12; i++)
          _event(
            'e$i',
            now.add(Duration(days: i)),
            assigned: ['m1'],
            updatedAt: now,
          ),
      ];

      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            totalGets++;
            final path = options.path;
            if (path.startsWith('/events/')) {
              final id = path.split('/').last;
              final index = int.parse(id.substring(1));
              return handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _eventJson(
                    id,
                    now.add(Duration(days: index)),
                    assigned: ['m1'],
                    updatedAt: now,
                    songs: [
                      {'songId': 's-$id-a', 'serviceId': 'srv1', 'title': 'A'},
                      {'songId': 's-$id-b', 'serviceId': 'srv1', 'title': 'B'},
                    ],
                  ),
                ),
              );
            }
            if (path.startsWith('/teams/t1/songs/')) {
              final songId = path.split('/').last;
              return handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'id': songId, 'title': songId, 'lyrics': 'Letra'},
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
          offlineClockProvider.overrideWithValue(() => now),
          authControllerProvider.overrideWith(
            (ref) => _StaticAuthController(ref, _signedInState('u1', 'm1', 't1')),
          ),
        ],
      );
      addTearDown(container.dispose);

      const team = TeamSummary(
        membershipId: 'm1',
        teamId: 't1',
        name: 'Louvor',
        role: 'MEMBER',
        displayName: 'Maria',
      );
      final coordinator = container.read(offlineSyncCoordinatorProvider);

      // Passada 1: teto exato de 20 GETs.
      await coordinator.syncFromUpcoming(team: team, upcomingEvents: upcoming);
      expect(totalGets, kMaxOfflineRequestsPerPass);
      final cache = container.read(readCacheProvider);
      expect(cache.readEvent('e1'), isNotNull);
      expect(cache.readEvent('e12'), isNull);

      // Passada 2: busca os 16 GETs restantes, completando todas as 12 escalas
      // e 24 músicas sem repetir o que já está guardado.
      totalGets = 0;
      await coordinator.syncFromUpcoming(team: team, upcomingEvents: upcoming);
      expect(totalGets, 16);
      expect(cache.summary(), const OfflineCacheSummary(scheduleCount: 12, songCount: 24));

      // Passada 3: tudo já em cache -> 0 GETs.
      totalGets = 0;
      await coordinator.syncFromUpcoming(team: team, upcomingEvents: upcoming);
      expect(totalGets, 0);
    });

    test('logout durante sincronização em andamento impede escrita tardia, não grava lastSyncAt e libera a próxima conta',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.utc(2026, 11, 10, 12, 0);
      final accountAGetCompleter = Completer<void>();
      final accountAGetStarted = Completer<void>();
      final requests = <String>[];

      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            final path = options.path;
            requests.add(path);
            if (path == '/teams/t1/events') {
              return handler.resolve(
                Response<List<dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    _eventJson(
                      'e-account-a',
                      now.add(const Duration(days: 2)),
                      assigned: ['m1'],
                      updatedAt: now,
                    ),
                    _eventJson(
                      'e-account-a-2',
                      now.add(const Duration(days: 5)),
                      assigned: ['m1'],
                      updatedAt: now,
                    ),
                  ],
                ),
              );
            }
            if (path == '/events/e-account-a') {
              if (!accountAGetStarted.isCompleted) {
                accountAGetStarted.complete();
              }
              await accountAGetCompleter.future;
              return handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _eventJson(
                    'e-account-a',
                    now.add(const Duration(days: 2)),
                    assigned: ['m1'],
                    updatedAt: now,
                    songs: [
                      {'songId': 's-account-a', 'serviceId': 'srv1', 'title': 'Secreta'},
                    ],
                  ),
                ),
              );
            }
            if (path == '/teams/t2/events') {
              return handler.resolve(
                Response<List<dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    _eventJson(
                      'e-account-b',
                      now.add(const Duration(days: 3)),
                      assigned: ['m2'],
                      updatedAt: now,
                    ),
                  ],
                ),
              );
            }
            if (path == '/events/e-account-b') {
              return handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _eventJson(
                    'e-account-b',
                    now.add(const Duration(days: 3)),
                    assigned: ['m2'],
                    updatedAt: now,
                  ),
                ),
              );
            }
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );

      late _MutableAuthController auth;
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dioProvider.overrideWithValue(dio),
          offlineClockProvider.overrideWithValue(() => now),
          authControllerProvider.overrideWith((ref) {
            auth = _MutableAuthController(
              ref,
              _signedInState('uA', 'm1', 't1'),
            );
            return auth;
          }),
        ],
      );
      addTearDown(container.dispose);

      final coordinator = container.read(offlineSyncCoordinatorProvider);
      final cache = container.read(readCacheProvider);

      // Inicia sincronização da conta A e aguarda pausar no meio do GET /events/e-account-a.
      final syncA = coordinator.syncIfDue(force: true);
      await accountAGetStarted.future;

      // Logout real: clearAll (em nova instância, como AuthController faz) + signedOut.
      await ReadCache(prefs).clearAll();
      auth.setAuthState(const AuthState.signedOut());

      // Conta B entra ANTES mesmo de o GET antigo da conta A terminar:
      // _syncAllInFlight/_inFlightTeams foram zerados e lastSyncAt está vazio.
      auth.setAuthState(_signedInState('uB', 'm2', 't2'));
      await coordinator.syncIfDue();

      expect(cache.readEvent('e-account-b'), isNotNull);
      expect(cache.readEvent('e-account-a'), isNull);

      // Agora o GET atrasado da conta A termina: não pode gravar JSON da conta A
      // nem disparar músicas ou e-account-a-2.
      accountAGetCompleter.complete();
      await syncA;

      expect(cache.readEvent('e-account-a'), isNull);
      expect(cache.readSong('s-account-a'), isNull);
      expect(requests, isNot(contains('/events/e-account-a-2')));
      expect(requests, isNot(contains('/teams/t1/songs/s-account-a')));
      expect(cache.readEvent('e-account-b'), isNotNull);
    });

    test('logout antes da próxima conta não deixa lastSyncAt pular a sincronização seguinte',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.utc(2026, 11, 10, 12, 0);
      final getCompleter = Completer<void>();
      final getStarted = Completer<void>();

      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            if (options.path == '/teams/t1/events') {
              return handler.resolve(
                Response<List<dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    _eventJson(
                      'e-a',
                      now.add(const Duration(days: 2)),
                      assigned: ['m1'],
                      updatedAt: now,
                    ),
                  ],
                ),
              );
            }
            if (options.path == '/events/e-a') {
              if (!getStarted.isCompleted) getStarted.complete();
              await getCompleter.future;
              return handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _eventJson(
                    'e-a',
                    now.add(const Duration(days: 2)),
                    assigned: ['m1'],
                    updatedAt: now,
                  ),
                ),
              );
            }
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );

      late _MutableAuthController auth;
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dioProvider.overrideWithValue(dio),
          offlineClockProvider.overrideWithValue(() => now),
          authControllerProvider.overrideWith((ref) {
            auth = _MutableAuthController(
              ref,
              _signedInState('uA', 'm1', 't1'),
            );
            return auth;
          }),
        ],
      );
      addTearDown(container.dispose);

      final coordinator = container.read(offlineSyncCoordinatorProvider);
      final cache = container.read(readCacheProvider);
      final syncA = coordinator.syncIfDue(force: true);
      await getStarted.future;

      await ReadCache(prefs).clearAll();
      auth.setAuthState(const AuthState.signedOut());

      getCompleter.complete();
      await syncA;

      // Nem a escala nem o lastSyncAt foram gravados após o logout.
      expect(cache.readEvent('e-a'), isNull);
      expect(cache.readLastSyncAt(), isNull);
    });

    test('404/403 pula apenas aquela escala e segue; 429 interrompe a passada inteira',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.utc(2026, 11, 10, 12, 0);
      final requestedEvents = <String>[];
      final requestedSongs = <String>[];

      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final path = options.path;
            if (path.startsWith('/events/')) {
              final id = path.split('/').last;
              requestedEvents.add(id);
              if (id == 'e-deleted') {
                return handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.badResponse,
                    response: Response(requestOptions: options, statusCode: 404),
                  ),
                );
              }
              if (id == 'e-unpublished') {
                return handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.badResponse,
                    response: Response(requestOptions: options, statusCode: 403),
                  ),
                );
              }
              if (id == 'e-rate-limit') {
                return handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.badResponse,
                    response: Response(requestOptions: options, statusCode: 429),
                  ),
                );
              }
              return handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _eventJson(
                    id,
                    now.add(const Duration(days: 4)),
                    assigned: ['m1'],
                    updatedAt: now,
                    songs: [
                      {'songId': 's-missing', 'serviceId': 'srv1', 'title': 'Sumiu'},
                      {'songId': 's-ok-$id', 'serviceId': 'srv1', 'title': 'Ok'},
                    ],
                  ),
                ),
              );
            }
            if (path.startsWith('/teams/t1/songs/')) {
              final songId = path.split('/').last;
              requestedSongs.add(songId);
              if (songId == 's-missing') {
                return handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.badResponse,
                    response: Response(requestOptions: options, statusCode: 404),
                  ),
                );
              }
              return handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'id': songId, 'title': songId, 'lyrics': 'Letra'},
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
          offlineClockProvider.overrideWithValue(() => now),
          authControllerProvider.overrideWith(
            (ref) => _StaticAuthController(ref, _signedInState('u1', 'm1', 't1')),
          ),
        ],
      );
      addTearDown(container.dispose);

      const team = TeamSummary(
        membershipId: 'm1',
        teamId: 't1',
        name: 'Louvor',
        role: 'MEMBER',
        displayName: 'Maria',
      );
      final coordinator = container.read(offlineSyncCoordinatorProvider);
      final cache = container.read(readCacheProvider);

      await coordinator.syncFromUpcoming(
        team: team,
        upcomingEvents: [
          _event('e-deleted', now.add(const Duration(days: 1)), assigned: ['m1']),
          _event('e-unpublished', now.add(const Duration(days: 2)), assigned: ['m1']),
          _event('e-ok', now.add(const Duration(days: 3)), assigned: ['m1']),
          _event('e-rate-limit', now.add(const Duration(days: 4)), assigned: ['m1']),
          _event('e-after-429', now.add(const Duration(days: 5)), assigned: ['m1']),
        ],
      );

      // 404 e 403 foram puladas, e-ok foi baixada (pulando s-missing 404 e
      // salvando s-ok-e-ok), e o 429 interrompeu antes de e-after-429.
      expect(
        requestedEvents,
        ['e-deleted', 'e-unpublished', 'e-ok', 'e-rate-limit'],
      );
      expect(requestedSongs, ['s-missing', 's-ok-e-ok']);
      expect(cache.readEvent('e-ok'), isNotNull);
      expect(cache.readSong('s-ok-e-ok'), isNotNull);
      expect(cache.readEvent('e-after-429'), isNull);
    });

    test('429 ao baixar música interrompe a passada inteira sem seguir para a próxima escala',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.utc(2026, 11, 10, 12, 0);
      final requestedEvents = <String>[];
      final requestedSongs = <String>[];

      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final path = options.path;
            if (path.startsWith('/events/')) {
              final id = path.split('/').last;
              requestedEvents.add(id);
              return handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _eventJson(
                    id,
                    now.add(const Duration(days: 2)),
                    assigned: ['m1'],
                    updatedAt: now,
                    songs: [
                      {'songId': 's-429', 'serviceId': 'srv1', 'title': 'M1'},
                      {'songId': 's-never', 'serviceId': 'srv1', 'title': 'M2'},
                    ],
                  ),
                ),
              );
            }
            if (path.startsWith('/teams/t1/songs/')) {
              final songId = path.split('/').last;
              requestedSongs.add(songId);
              return handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response(requestOptions: options, statusCode: 429),
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
          offlineClockProvider.overrideWithValue(() => now),
          authControllerProvider.overrideWith(
            (ref) => _StaticAuthController(ref, _signedInState('u1', 'm1', 't1')),
          ),
        ],
      );
      addTearDown(container.dispose);

      const team = TeamSummary(
        membershipId: 'm1',
        teamId: 't1',
        name: 'Louvor',
        role: 'MEMBER',
        displayName: 'Maria',
      );
      await container.read(offlineSyncCoordinatorProvider).syncFromUpcoming(
        team: team,
        upcomingEvents: [
          _event('e1', now.add(const Duration(days: 2)), assigned: ['m1']),
          _event('e2', now.add(const Duration(days: 5)), assigned: ['m1']),
        ],
      );

      expect(requestedEvents, ['e1']);
      expect(requestedSongs, ['s-429']);
    });

    test('syncFromUpcoming usa listRange com cache: false e não roda prune a cada abertura; prune roda no máximo 1x/dia na sync agendada',
        () async {
      final prefs = await SharedPreferences.getInstance();
      var currentNow = DateTime.utc(2026, 11, 10, 12, 0);
      var rangeCalled = false;

      // Escala passada (> 7d) pré-existente no cache + lastSyncAt recente para
      // isolar `syncFromUpcoming` da sync agendada automática de abertura.
      final cache = ReadCache(prefs);
      await cache.saveLastSyncAt(currentNow);
      await cache.saveEvent(
        'e-expired',
        _eventJson('e-expired', currentNow.subtract(const Duration(days: 15))),
        now: currentNow.subtract(const Duration(days: 15)),
      );

      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final path = options.path;
            if (path == '/teams/t1/events' &&
                options.queryParameters.containsKey('from')) {
              rangeCalled = true;
              return handler.resolve(
                Response<List<dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    _eventJson(
                      'e-from-range',
                      currentNow.add(const Duration(days: 25)),
                      assigned: ['m1'],
                      updatedAt: currentNow,
                    ),
                  ],
                ),
              );
            }
            if (path == '/teams/t1/events') {
              return handler.resolve(
                Response<List<dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <dynamic>[],
                ),
              );
            }
            if (path.startsWith('/events/')) {
              final id = path.split('/').last;
              return handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: _eventJson(
                    id,
                    currentNow.add(const Duration(days: 25)),
                    assigned: ['m1'],
                    updatedAt: currentNow,
                  ),
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
          readCacheProvider.overrideWithValue(cache),
          dioProvider.overrideWithValue(dio),
          offlineClockProvider.overrideWithValue(() => currentNow),
          authControllerProvider.overrideWith(
            (ref) => _StaticAuthController(ref, _signedInState('u1', 'm1', 't1')),
          ),
        ],
      );
      addTearDown(container.dispose);

      // 20 escalas nos primeiros 5 dias -> não cobrem a janela de 30 dias.
      final twentyShort = [
        for (var i = 0; i < 20; i++)
          _event(
            'short-$i',
            currentNow.add(Duration(hours: 6 * (i + 1))),
            assigned: ['m2'],
          ),
      ];
      const team = TeamSummary(
        membershipId: 'm1',
        teamId: 't1',
        name: 'Louvor',
        role: 'MEMBER',
        displayName: 'Maria',
      );
      final coordinator = container.read(offlineSyncCoordinatorProvider);
      await coordinator.syncFromUpcoming(
        team: team,
        upcomingEvents: twentyShort,
      );

      expect(rangeCalled, isTrue);
      expect(cache.readEvent('e-from-range'), isNotNull);
      // Nenhum recorte `cache.agenda.t1.range.*` gravado pelo pré-carregamento.
      expect(
        prefs.getKeys().where((k) => k.startsWith('cache.agenda.t1.range.')),
        isEmpty,
      );
      // `syncFromUpcoming` não executou prune.
      expect(cache.readEvent('e-expired'), isNotNull);
      expect(cache.readLastPruneAt(), isNull);

      // Na sincronização agendada (6 h depois), o prune roda 1 vez e grava lastPruneAt.
      currentNow = currentNow.add(const Duration(hours: 6));
      await coordinator.syncIfDue();
      expect(cache.readEvent('e-expired'), isNull);
      expect(cache.readLastPruneAt(), currentNow);

      // 6 h depois (ainda < 24 h desde o último prune), nova sync agendada NÃO
      // roda prune de novo.
      await cache.saveEvent(
        'e-expired-2',
        _eventJson('e-expired-2', currentNow.subtract(const Duration(days: 15))),
        now: currentNow.subtract(const Duration(days: 15)),
      );
      currentNow = currentNow.add(const Duration(hours: 6));
      await coordinator.syncIfDue();
      expect(cache.readEvent('e-expired-2'), isNotNull);

      // Passadas 24 h desde o último prune, a sync agendada limpa de novo.
      currentNow = currentNow.add(const Duration(hours: 18));
      await coordinator.syncIfDue();
      expect(cache.readEvent('e-expired-2'), isNull);

      // Se listRange vier do cache (fromCache: true), deve ser ignorado.
      final now = DateTime.utc(2026, 11, 10, 12, 0);
      await cache.saveLastSyncAt(now);
      await cache.saveAgenda(
        't1',
        'range.2026-11-10.2026-12-10',
        [
          _eventJson(
            'e-stale-range',
            now.add(const Duration(days: 20)),
            assigned: ['m1'],
            updatedAt: now,
          ),
        ],
        now: now,
      );
      final offlineDio = Dio();
      addTearDown(offlineDio.close);
      offlineDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/teams/t1/events' &&
                options.queryParameters.containsKey('from')) {
              return handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionError,
                ),
              );
            }
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );
      final container2 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          readCacheProvider.overrideWithValue(cache),
          dioProvider.overrideWithValue(offlineDio),
          offlineClockProvider.overrideWithValue(() => now),
          authControllerProvider.overrideWith(
            (ref) => _StaticAuthController(ref, _signedInState('u1', 'm1', 't1')),
          ),
        ],
      );
      addTearDown(container2.dispose);
      await container2.read(offlineSyncCoordinatorProvider).syncFromUpcoming(
        team: team,
        upcomingEvents: twentyShort,
      );
      expect(cache.readEvent('e-stale-range'), isNull);
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

AuthState _signedInState(String userId, String membershipId, String teamId) {
  return AuthState.signedIn(
    AuthUser(
      id: userId,
      name: 'Maria',
      email: '$userId@teste.com',
      mustChangePassword: false,
    ),
    [
      TeamSummary(
        membershipId: membershipId,
        teamId: teamId,
        name: 'Louvor',
        role: 'MEMBER',
        displayName: 'Maria',
      ),
    ],
  );
}

class _StaticAuthController extends AuthController {
  _StaticAuthController(super.ref, this._initial);

  final AuthState _initial;

  @override
  Future<void> bootstrap() async {
    state = _initial;
  }
}

class _MutableAuthController extends AuthController {
  _MutableAuthController(super.ref, AuthState initial) {
    state = initial;
  }

  void setAuthState(AuthState next) {
    state = next;
  }

  @override
  Future<void> bootstrap() async {}
}
