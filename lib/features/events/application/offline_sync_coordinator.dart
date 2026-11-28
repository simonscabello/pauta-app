import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/date/civil_date.dart';
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
/// - Limpa escalas passadas e músicas ociosas (> 60 dias fora de escalas
///   guardadas) e respeita teto para não estourar o `localStorage` da Web.
class OfflineSyncCoordinator with WidgetsBindingObserver {
  OfflineSyncCoordinator(this._ref) {
    _attachLifecycle();
    _ref.listen<AuthState>(
      authControllerProvider,
      (previous, next) {
        final readyNow =
            next.status == AuthStatus.authenticated && next.teams.isNotEmpty;
        final wasReady = previous?.status == AuthStatus.authenticated &&
            (previous?.teams.isNotEmpty ?? false);
        if (readyNow && !wasReady) {
          unawaited(syncIfDue());
        } else if (!readyNow && wasReady) {
          _syncedTeamsInWindow.clear();
          _windowStartedAt = null;
          notifyCacheChanged();
        }
      },
      fireImmediately: true,
    );
  }

  final Ref _ref;
  bool _lifecycleAttached = false;
  bool _disposed = false;
  Future<void>? _syncAllInFlight;
  final Map<String, Future<void>> _inFlightTeams = {};
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
    if (_lifecycleAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleAttached = false;
    }
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

    final now = _ref.read(offlineClockProvider)().toUtc();
    if (!force &&
        !shouldRunScheduledSync(
          lastSyncAt: cache.readLastSyncAt(),
          now: now,
        )) {
      return;
    }

    final eventRepo = _ref.read(eventRepositoryProvider);
    var anyOnline = false;

    for (final team in auth.teams) {
      if (_disposed) return;
      final inFlight = _inFlightTeams[team.teamId];
      if (inFlight != null) {
        await inFlight;
        continue;
      }
      try {
        final list = await eventRepo.list(team.teamId, scope: 'upcoming');
        if (list.fromCache) {
          // Sem conexão agora: tenta de novo na próxima abertura.
          break;
        }
        anyOnline = true;
        await syncFromUpcoming(
          team: team,
          upcomingEvents: list.data,
          now: now,
        );
      } catch (_) {
        // Falha de rede ou sessão: o modo offline nunca derruba a navegação.
        break;
      }
    }

    if (anyOnline && !_disposed) {
      await cache.saveLastSyncAt(now);
      notifyCacheChanged();
    }
  }

  /// Pré-carrega a partir de uma listagem `upcoming` recém-chegada da rede.
  ///
  /// Escalas cujo `updatedAt` mudou são renovadas na hora; escalas inalteradas
  /// não refazem `GET /events/:id`; músicas só são buscadas quando ainda não
  /// estão no aparelho ou quando passaram de 6 h.
  Future<void> syncFromUpcoming({
    required TeamSummary team,
    required List<Event> upcomingEvents,
    DateTime? now,
  }) async {
    if (_disposed) return;
    final existing = _inFlightTeams[team.teamId];
    if (existing != null) {
      await existing;
      return;
    }

    final future = _runSyncFromUpcoming(
      team: team,
      upcomingEvents: upcomingEvents,
      now: now,
    );
    _inFlightTeams[team.teamId] = future;
    try {
      await future;
    } finally {
      if (identical(_inFlightTeams[team.teamId], future)) {
        _inFlightTeams.remove(team.teamId);
      }
    }
  }

  Future<void> _runSyncFromUpcoming({
    required TeamSummary team,
    required List<Event> upcomingEvents,
    DateTime? now,
  }) async {
    final cache = _readCacheOrNull();
    if (cache == null) return;

    final clock = (now ?? _ref.read(offlineClockProvider)()).toUtc();
    final eventRepo = _ref.read(eventRepositoryProvider);
    final songRepo = _ref.read(songRepositoryProvider);

    var candidates = upcomingEvents;
    // A consulta padrão da Home traz 20 itens. Em equipes que escalam por
    // culto (3–4 por domingo), 20 itens podem não cobrir os 30 dias ou o
    // mês seguinte — aí completamos com `listRange` (limite 100).
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
      if (lastDay.isBefore(windowEnd)) {
        try {
          candidates = await eventRepo.listRange(
            team.teamId,
            from: dateKey(today),
            to: dateKey(windowEnd),
          );
        } catch (_) {
          // Segue com os 20 que já vieram.
        }
      }
    }

    final selected = selectEventsForOfflinePrefetch(
      candidates,
      membershipId: team.membershipId,
      canManage: team.canManage,
      now: clock,
    );

    for (final item in selected) {
      if (_disposed) return;
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
        try {
          final fetched = await eventRepo.find(item.id);
          if (fetched.fromCache) return;
          fullEvent = fetched.data;
        } catch (_) {
          // Sem rede ou escala indisponível: para de tentar nesta passada.
          return;
        }
      } else {
        fullEvent = Event.fromJson(cached!.data);
      }

      if (fullEvent.songs.isNotEmpty) {
        await songRepo.prefetch(
          team.teamId,
          fullEvent.songs.map((song) => song.songId),
          now: clock,
        );
      }
    }

    await cache.prune(now: clock);
    _recordTeamSynced(team.teamId, clock, cache);
    notifyCacheChanged();
  }

  void _recordTeamSynced(String teamId, DateTime now, ReadCache cache) {
    if (_windowStartedAt == null ||
        now.difference(_windowStartedAt!) >= kOfflineRefreshInterval) {
      _windowStartedAt = now;
      _syncedTeamsInWindow.clear();
    }
    _syncedTeamsInWindow.add(teamId);

    final teams = _ref.read(authControllerProvider).teams;
    if (teams.isNotEmpty &&
        teams.every((t) => _syncedTeamsInWindow.contains(t.teamId))) {
      unawaited(cache.saveLastSyncAt(now));
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

/// Observado pelo widget raiz ([LouvorApp]) para viver durante toda a sessão.
final offlineSyncCoordinatorProvider = Provider<OfflineSyncCoordinator>((ref) {
  final coordinator = OfflineSyncCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
