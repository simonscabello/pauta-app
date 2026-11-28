import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/date/civil_date.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/offline_policy.dart';
import '../../../core/storage/read_cache.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../songs/data/song_repository.dart';
import '../data/event_repository.dart';
import '../domain/event_models.dart';

/// Relógio injetável do pré-carregamento offline, para testes determinísticos.
final offlineClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Incrementado sempre que escalas ou músicas entram ou saem do cache local,
/// para telas como o Perfil atualizarem a contagem sem polling.
final offlineCacheRevisionProvider = StateProvider<int>((ref) => 0);

/// Quantas escalas e músicas estão guardadas neste aparelho agora.
final offlineCacheSummaryProvider = Provider<OfflineCacheSummary>((ref) {
  ref.watch(offlineCacheRevisionProvider);
  try {
    return ref.watch(readCacheProvider).summary();
  } catch (_) {
    return const OfflineCacheSummary(scheduleCount: 0, songCount: 0);
  }
});

/// Mantém as escalas e cifras do modo culto prontas no aparelho.
///
/// - Ao abrir ou retomar o app com rede (no máximo uma vez a cada 6 h),
///   verifica as equipes do usuário e atualiza o que mudou.
/// - Quando a lista `upcoming` chega fresca da rede (Home/Agenda), reage de
///   imediato a escalas novas ou editadas (`updatedAt`), sem esperar as 6 h.
/// - Só baixa texto (JSON da escala + letra/cifra das músicas), nunca áudio.
/// - Limita cada passada a [kMaxOfflineRequestsPerPass] GETs (20) e renova
///   músicas já guardadas a cada 24 h (abrir com rede e editar renovam na hora).
/// - Respeita o orçamento de bytes na Web antes de baixar (escala mais próxima
///   primeiro) e roda a limpeza completa no máximo uma vez por dia, apenas na
///   sincronização agendada.
class OfflineSyncCoordinator with WidgetsBindingObserver {
  OfflineSyncCoordinator(
    this._ref, {
    int maxRequestsPerPass = kMaxOfflineRequestsPerPass,
  }) : _maxRequestsPerPass = maxRequestsPerPass {
    _attachLifecycle();
    _ref.listen<AuthState>(
      authControllerProvider,
      (previous, next) {
        final readyNow =
            next.status == AuthStatus.authenticated && next.teams.isNotEmpty;
        final wasReady = previous?.status == AuthStatus.authenticated &&
            (previous?.teams.isNotEmpty ?? false);
        final wasSignedIn = previous?.status == AuthStatus.authenticated;
        final signedOutNow = next.status != AuthStatus.authenticated;
        final userChanged = previous?.user?.id != null &&
            previous?.user?.id != next.user?.id;

        if ((!readyNow && wasReady) ||
            (wasSignedIn && signedOutNow) ||
            userChanged) {
          _invalidateSession();
          notifyCacheChanged();
        }
        if (readyNow && (!wasReady || userChanged)) {
          unawaited(syncIfDue());
        }
      },
      fireImmediately: true,
    );
  }

  final Ref _ref;
  final int _maxRequestsPerPass;
  bool _lifecycleAttached = false;
  bool _disposed = false;
  int _localSession = 0;
  Future<void>? _syncAllInFlight;
  final Map<String, Future<_SyncPassOutcome>> _inFlightTeams = {};
  final Set<String> _syncedTeamsInWindow = {};
  DateTime? _windowStartedAt;

  void _attachLifecycle() {
    try {
      WidgetsBinding.instance.addObserver(this);
      _lifecycleAttached = true;
    } catch (_) {
      // Em testes unitários puros sem WidgetsBinding, o coordenador ainda
      // funciona pelas chamadas diretas.
    }
  }

  void dispose() {
    _disposed = true;
    _localSession++;
    _syncAllInFlight = null;
    _inFlightTeams.clear();
    if (_lifecycleAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleAttached = false;
    }
  }

  void _invalidateSession() {
    _localSession++;
    _readCacheOrNull()?.bumpSession();
    _syncAllInFlight = null;
    _inFlightTeams.clear();
    _syncedTeamsInWindow.clear();
    _windowStartedAt = null;
  }

  bool _isSessionActive(
    int expectedCacheSession,
    int expectedLocalSession,
    ReadCache cache,
  ) {
    return !_disposed &&
        _localSession == expectedLocalSession &&
        cache.isSessionCurrent(expectedCacheSession);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncIfDue());
    }
  }

  ReadCache? _readCacheOrNull() {
    try {
      return _ref.read(readCacheProvider);
    } catch (_) {
      return null;
    }
  }

  void notifyCacheChanged() {
    if (_disposed) return;
    try {
      _ref.read(offlineCacheRevisionProvider.notifier).state++;
    } catch (_) {}
  }

  /// Sincroniza todas as equipes da conta quando já se passaram ao menos 6 h
  /// desde a última sincronização (ou sempre, com [force]).
  Future<void> syncIfDue({bool force = false}) {
    if (_disposed) return Future.value();
    final running = _syncAllInFlight;
    if (running != null) return running;
    final future = _runSyncIfDue(force: force);
    _syncAllInFlight = future;
    return future.whenComplete(() {
      if (identical(_syncAllInFlight, future)) {
        _syncAllInFlight = null;
      }
    });
  }

  Future<void> _runSyncIfDue({required bool force}) async {
    if (_disposed) return;
    final auth = _ref.read(authControllerProvider);
    if (auth.status != AuthStatus.authenticated || auth.teams.isEmpty) return;

    final cache = _readCacheOrNull();
    if (cache == null) return;

    final cacheSession = cache.sessionEpoch;
    final localSession = _localSession;
    final now = _ref.read(offlineClockProvider)().toUtc();
    if (!force &&
        !shouldRunScheduledSync(
          lastSyncAt: cache.readLastSyncAt(),
          now: now,
        )) {
      return;
    }

    // Limpeza completa roda no máximo uma vez por dia (e só na sincronização
    // agendada, nunca a cada reconstrução do `upcoming` na Home). Rodar antes
    // libera espaço de escalas expiradas para o orçamento de bytes da Web.
    final prunePlan = await cache.pruneIfDue(
      now: now,
      expectedSession: cacheSession,
    );
    if (!_isSessionActive(cacheSession, localSession, cache)) return;
    if (prunePlan != null && !prunePlan.isEmpty) {
      notifyCacheChanged();
    }

    final eventRepo = _ref.read(eventRepositoryProvider);
    final budget = _SyncRequestBudget(_maxRequestsPerPass);
    var anyOnline = false;
    var rateLimited = false;

    for (final team in auth.teams) {
      if (!_isSessionActive(cacheSession, localSession, cache)) return;
      if (budget.isExhausted) break;

      final inFlight = _inFlightTeams[team.teamId];
      if (inFlight != null) {
        final outcome = await inFlight;
        if (!_isSessionActive(cacheSession, localSession, cache)) return;
        if (outcome == _SyncPassOutcome.rateLimited) {
          rateLimited = true;
          break;
        }
        continue;
      }

      if (!budget.tryConsume()) break;
      try {
        final list = await eventRepo.list(team.teamId, scope: 'upcoming');
        if (!_isSessionActive(cacheSession, localSession, cache)) return;
        if (list.fromCache) {
          // Sem conexão agora: tenta de novo na próxima abertura.
          break;
        }
        anyOnline = true;
        final outcome = await _syncTeamLocked(
          team: team,
          upcomingEvents: list.data,
          now: now,
          budget: budget,
          cacheSession: cacheSession,
          localSession: localSession,
        );
        if (outcome == _SyncPassOutcome.sessionInvalidated) return;
        if (outcome == _SyncPassOutcome.rateLimited) {
          rateLimited = true;
          break;
        }
        if (outcome == _SyncPassOutcome.networkFailed ||
            outcome == _SyncPassOutcome.budgetReached) {
          break;
        }
      } on ApiException catch (e) {
        if (!_isSessionActive(cacheSession, localSession, cache)) return;
        final status = e.statusCode;
        if (status == 429) {
          rateLimited = true;
          break;
        }
        if (status != null && status >= 400 && status < 500) {
          // 404/403 numa equipe: pula e tenta a próxima.
          continue;
        }
        break;
      } catch (_) {
        // Falha de rede ou sessão: o modo offline nunca derruba a navegação.
        break;
      }
    }

    if (anyOnline &&
        !rateLimited &&
        _isSessionActive(cacheSession, localSession, cache)) {
      await cache.saveLastSyncAt(now, expectedSession: cacheSession);
    }
  }

  /// Pré-carrega a partir de uma listagem `upcoming` recém-chegada da rede.
  ///
  /// Escalas cujo `updatedAt` mudou são renovadas na hora; escalas inalteradas
  /// não refazem `GET /events/:id`; músicas só são buscadas quando ainda não
  /// estão no aparelho ou quando passaram de 24 h.
  Future<void> syncFromUpcoming({
    required TeamSummary team,
    required List<Event> upcomingEvents,
    DateTime? now,
  }) async {
    if (_disposed) return;
    final cache = _readCacheOrNull();
    if (cache == null) return;

    await _syncTeamLocked(
      team: team,
      upcomingEvents: upcomingEvents,
      now: now,
      budget: _SyncRequestBudget(_maxRequestsPerPass),
      cacheSession: cache.sessionEpoch,
      localSession: _localSession,
    );
  }

  Future<_SyncPassOutcome> _syncTeamLocked({
    required TeamSummary team,
    required List<Event> upcomingEvents,
    DateTime? now,
    required _SyncRequestBudget budget,
    required int cacheSession,
    required int localSession,
  }) async {
    if (_disposed) return _SyncPassOutcome.sessionInvalidated;
    final existing = _inFlightTeams[team.teamId];
    if (existing != null) {
      return existing;
    }

    final future = _runSyncFromUpcoming(
      team: team,
      upcomingEvents: upcomingEvents,
      now: now,
      budget: budget,
      cacheSession: cacheSession,
      localSession: localSession,
    );
    _inFlightTeams[team.teamId] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightTeams[team.teamId], future)) {
        _inFlightTeams.remove(team.teamId);
      }
    }
  }

  Future<_SyncPassOutcome> _runSyncFromUpcoming({
    required TeamSummary team,
    required List<Event> upcomingEvents,
    DateTime? now,
    required _SyncRequestBudget budget,
    required int cacheSession,
    required int localSession,
  }) async {
    final cache = _readCacheOrNull();
    if (cache == null ||
        !_isSessionActive(cacheSession, localSession, cache)) {
      return _SyncPassOutcome.sessionInvalidated;
    }

    final clock = (now ?? _ref.read(offlineClockProvider)()).toUtc();
    final eventRepo = _ref.read(eventRepositoryProvider);
    final songRepo = _ref.read(songRepositoryProvider);

    final maxBytes = cache.maxCacheBytes;
    int? currentBytes;
    bool byteBudgetExceeded() {
      if (maxBytes == null) return false;
      currentBytes ??= cache.offlineBytes();
      return currentBytes! >= maxBytes;
    }

    var candidates = upcomingEvents;
    // A consulta padrão da Home traz 20 itens. Em equipes que escalam por
    // culto (3–4 por domingo), 20 itens podem não cobrir os 30 dias ou o
    // mês seguinte — aí completamos com `listRange` (limite 100), sem gravar
    // o recorte no cache e ignorando resposta vinda do cache.
    if (upcomingEvents.length >= 20) {
      final tzName = upcomingEvents.first.timezone.isEmpty
          ? 'America/Sao_Paulo'
          : upcomingEvents.first.timezone;
      final today = _civilDate(clock, tzName);
      final windowEnd = offlinePrefetchWindowEnd(
        todayCivil: today,
        canManage: team.canManage,
      );
      final lastDay = _civilDate(upcomingEvents.last.startsAt.toUtc(), tzName);
      if (lastDay.isBefore(windowEnd) &&
          !budget.isExhausted &&
          !byteBudgetExceeded()) {
        if (budget.tryConsume()) {
          try {
            final range = await eventRepo.listRange(
              team.teamId,
              from: dateKey(today),
              to: dateKey(windowEnd),
              cache: false,
            );
            if (!_isSessionActive(cacheSession, localSession, cache)) {
              return _SyncPassOutcome.sessionInvalidated;
            }
            if (!range.fromCache) {
              candidates = range.data;
            }
          } on ApiException catch (e) {
            if (!_isSessionActive(cacheSession, localSession, cache)) {
              return _SyncPassOutcome.sessionInvalidated;
            }
            if (e.statusCode == 429) {
              return _SyncPassOutcome.rateLimited;
            }
            // Outros erros: segue com os 20 que já vieram.
          } catch (_) {
            if (!_isSessionActive(cacheSession, localSession, cache)) {
              return _SyncPassOutcome.sessionInvalidated;
            }
            // Segue com os 20 que já vieram.
          }
        }
      }
    }

    final selected = selectEventsForOfflinePrefetch(
      candidates,
      membershipId: team.membershipId,
      canManage: team.canManage,
      now: clock,
    );

    var cacheChanged = false;
    var rateLimited = false;
    var networkFailed = false;
    var stoppedEarly = false;

    for (final item in selected) {
      if (!_isSessionActive(cacheSession, localSession, cache)) {
        return _SyncPassOutcome.sessionInvalidated;
      }

      final cached = cache.readEvent(item.id);
      final cachedUpdatedAt = cache.readEventUpdatedAt(item.id);
      final refreshEvent = needsOfflineRefresh(
        cachedAt: cached?.cachedAt,
        cachedUpdatedAt: cachedUpdatedAt,
        remoteUpdatedAt: item.updatedAt,
        now: clock,
      );

      Event fullEvent;
      if (refreshEvent) {
        if (byteBudgetExceeded()) {
          stoppedEarly = true;
          break;
        }
        if (!budget.tryConsume()) {
          stoppedEarly = true;
          break;
        }
        final beforeBytes = maxBytes != null ? cache.eventByteSize(item.id) : 0;
        try {
          final fetched = await eventRepo.find(item.id);
          if (!_isSessionActive(cacheSession, localSession, cache)) {
            return _SyncPassOutcome.sessionInvalidated;
          }
          if (fetched.fromCache) {
            networkFailed = true;
            break;
          }
          fullEvent = fetched.data;
          cacheChanged = true;
          if (maxBytes != null && currentBytes != null) {
            final afterBytes = cache.eventByteSize(item.id);
            currentBytes = currentBytes! + (afterBytes - beforeBytes);
          }
        } on ApiException catch (e) {
          if (!_isSessionActive(cacheSession, localSession, cache)) {
            return _SyncPassOutcome.sessionInvalidated;
          }
          final status = e.statusCode;
          if (status == 429) {
            rateLimited = true;
            break;
          }
          if (status != null && status >= 400 && status < 500) {
            // 404/403 (escala apagada ou despublicada no meio): pula e segue.
            continue;
          }
          networkFailed = true;
          break;
        } catch (_) {
          networkFailed = true;
          break;
        }
      } else {
        fullEvent = Event.fromJson(cached!.data);
      }

      if (fullEvent.songs.isNotEmpty) {
        final songResult = await songRepo.prefetch(
          team.teamId,
          fullEvent.songs.map((song) => song.songId),
          now: clock,
          maxRequests: budget.remaining,
          expectedSession: cacheSession,
          shouldContinue: () =>
              _isSessionActive(cacheSession, localSession, cache) &&
              !byteBudgetExceeded(),
          onSongSaved: maxBytes != null
              ? (deltaBytes) {
                  if (currentBytes != null) {
                    currentBytes = currentBytes! + deltaBytes;
                  }
                }
              : null,
        );
        budget.consumeCount(songResult.requestsMade);
        if (songResult.savedCount > 0) {
          cacheChanged = true;
        }
        if (!_isSessionActive(cacheSession, localSession, cache)) {
          return _SyncPassOutcome.sessionInvalidated;
        }
        if (songResult.rateLimited) {
          rateLimited = true;
          break;
        }
        if (songResult.networkFailed) {
          networkFailed = true;
          break;
        }
        if (songResult.stopped || budget.isExhausted) {
          stoppedEarly = true;
          break;
        }
      }
    }

    if (!_isSessionActive(cacheSession, localSession, cache)) {
      return _SyncPassOutcome.sessionInvalidated;
    }

    if (cacheChanged) {
      notifyCacheChanged();
    }

    if (rateLimited) return _SyncPassOutcome.rateLimited;
    if (networkFailed) return _SyncPassOutcome.networkFailed;
    if (!stoppedEarly) {
      await _recordTeamSynced(
        team.teamId,
        clock,
        cache,
        cacheSession: cacheSession,
        localSession: localSession,
      );
    }
    return stoppedEarly
        ? _SyncPassOutcome.budgetReached
        : _SyncPassOutcome.completed;
  }

  Future<void> _recordTeamSynced(
    String teamId,
    DateTime now,
    ReadCache cache, {
    required int cacheSession,
    required int localSession,
  }) async {
    if (!_isSessionActive(cacheSession, localSession, cache)) return;
    if (_windowStartedAt == null ||
        now.difference(_windowStartedAt!) >= kOfflineRefreshInterval) {
      _windowStartedAt = now;
      _syncedTeamsInWindow.clear();
    }
    _syncedTeamsInWindow.add(teamId);

    final teams = _ref.read(authControllerProvider).teams;
    if (teams.isNotEmpty &&
        teams.every((t) => _syncedTeamsInWindow.contains(t.teamId))) {
      await cache.saveLastSyncAt(now, expectedSession: cacheSession);
    }
  }

  static DateTime _civilDate(DateTime utc, String timezone) {
    try {
      final local = tz.TZDateTime.from(utc, tz.getLocation(timezone));
      return DateTime.utc(local.year, local.month, local.day);
    } catch (_) {
      return DateTime.utc(utc.year, utc.month, utc.day);
    }
  }
}

enum _SyncPassOutcome {
  completed,
  budgetReached,
  rateLimited,
  networkFailed,
  sessionInvalidated,
}

class _SyncRequestBudget {
  _SyncRequestBudget(int maxRequests) : _remaining = maxRequests;

  int _remaining;

  int get remaining => _remaining;
  bool get isExhausted => _remaining <= 0;

  bool tryConsume() {
    if (_remaining <= 0) return false;
    _remaining--;
    return true;
  }

  void consumeCount(int count) {
    _remaining -= count;
    if (_remaining < 0) _remaining = 0;
  }
}

/// Observado pelo widget raiz ([LouvorApp]) para viver durante toda a sessão.
final offlineSyncCoordinatorProvider = Provider<OfflineSyncCoordinator>((ref) {
  final coordinator = OfflineSyncCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
