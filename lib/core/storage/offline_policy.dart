import 'package:timezone/timezone.dart' as tz;

import '../../features/events/domain/event_models.dart';

/// Horizonte de pré-carregamento para quem está escalado: próximos 30 dias.
const kMemberPrefetchWindowDays = 30;

/// Intervalo mínimo entre sincronizações automáticas de abertura/retorno do app
/// e teto padrão quando uma escala legada não traz `updatedAt`.
const kOfflineRefreshInterval = Duration(hours: 6);

/// Intervalo de renovação em segundo plano de uma música já guardada (abrir a
/// música com rede e editar cifra/letra já renovam na hora).
const kOfflineSongRefreshInterval = Duration(hours: 24);

/// Intervalo mínimo entre limpezas completas do cache offline.
const kOfflinePruneInterval = Duration(days: 1);

/// Teto de requisições GET por passada de sincronização offline.
/// A API limita 120 req/min por IP e vários aparelhos dividem o Wi-Fi da igreja;
/// o que não couber fica para a próxima passada.
const kMaxOfflineRequestsPerPass = 20;

/// Tempo sem abrir uma música fora de qualquer escala guardada antes de
/// removê-la do aparelho.
const kUnusedSongRetention = Duration(days: 60);

/// Folga após o fim do culto antes de remover a escala passada do aparelho.
const kPastEventRetention = Duration(days: 7);

/// Teto de músicas guardadas fora das escalas ativas, para o `localStorage`
/// da Web não estourar.
const kMaxCachedSongs = 150;

/// Teto de tamanho aproximado (em bytes UTF-8) para escalas e músicas no
/// cache offline. O `localStorage` dos navegadores costuma ficar em ~5 MB;
/// 2 MB deixam folga para a agenda, preferências e o resto do app.
const kMaxOfflineCacheBytes = 2 * 1024 * 1024;

/// Último dia civil (inclusive) que o pré-carregamento deve cobrir a partir de
/// [todayCivil] (meia-noite UTC representando o dia civil da equipe).
///
/// - Integrante: [todayCivil] + 30 dias.
/// - Liderança: até o fim do mês seguinte, garantindo ao menos os mesmos
///   30 dias (caso de 30–31 de janeiro, quando fevereiro tem menos de 30 dias).
DateTime offlinePrefetchWindowEnd({
  required DateTime todayCivil,
  required bool canManage,
}) {
  final today = DateTime.utc(todayCivil.year, todayCivil.month, todayCivil.day);
  final thirtyDays = today.add(const Duration(days: kMemberPrefetchWindowDays));
  if (!canManage) return thirtyDays;
  final endOfNextMonth = DateTime.utc(today.year, today.month + 2, 0);
  return endOfNextMonth.isAfter(thirtyDays) ? endOfNextMonth : thirtyDays;
}

/// Escolhe quais escalas devem ser pré-carregadas para o modo culto offline,
/// em ordem cronológica (a mais próxima primeiro).
///
/// Regras:
/// - Apenas escalas **publicadas** (`!isDraft`) cujo dia civil ainda não
///   passou (hoje entra inteiro, mesmo depois do primeiro culto).
/// - Para quem **não** lidera (`!canManage`): apenas escalas em que a pessoa
///   está escalada (em alguma função ou ministrando) nos próximos 30 dias.
/// - Para quem **lidera** (`canManage`): todas as escalas publicadas da equipe
///   até o fim do mês seguinte (e ao menos os próximos 30 dias).
List<Event> selectEventsForOfflinePrefetch(
  Iterable<Event> events, {
  required String? membershipId,
  required bool canManage,
  required DateTime now,
}) {
  final nowUtc = now.toUtc();
  final selected = <Event>[];

  for (final event in events) {
    if (event.isDraft) continue;

    final tzName =
        event.timezone.isEmpty ? 'America/Sao_Paulo' : event.timezone;
    final today = _civilDateInZone(nowUtc, tzName);
    final eventDay = _civilDateInZone(event.startsAt.toUtc(), tzName);

    if (eventDay.isBefore(today)) continue;

    final windowEnd = offlinePrefetchWindowEnd(
      todayCivil: today,
      canManage: canManage,
    );
    if (eventDay.isAfter(windowEnd)) continue;

    if (!canManage) {
      final assigned = membershipId != null &&
          membershipId.isNotEmpty &&
          (event.positionsForMembership(membershipId).isNotEmpty ||
              event.minister?.membershipId == membershipId);
      if (!assigned) continue;
    }

    selected.add(event);
  }

  selected.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return selected;
}

/// Decide se uma cópia em cache (escala ou música) precisa ser buscada de novo
/// no servidor.
///
/// - Sem cópia local (`cachedAt == null`): sempre busca.
/// - Quando a API informa [remoteUpdatedAt] e a cópia guardada também tem
///   [cachedUpdatedAt]: renova **imediatamente** se forem diferentes e pula se
///   forem iguais.
/// - Sem versão comparável (ex.: músicas dentro da escala, que não trazem
///   `updatedAt` do servidor, ou cache legado): renova depois de [maxAge]
///   (padrão: 6 horas).
bool needsOfflineRefresh({
  required DateTime? cachedAt,
  DateTime? cachedUpdatedAt,
  DateTime? remoteUpdatedAt,
  required DateTime now,
  Duration maxAge = kOfflineRefreshInterval,
}) {
  if (cachedAt == null) return true;

  if (remoteUpdatedAt != null && cachedUpdatedAt != null) {
    return !remoteUpdatedAt.toUtc().isAtSameMomentAs(cachedUpdatedAt.toUtc());
  }

  return now.toUtc().difference(cachedAt.toUtc()) >= maxAge;
}

/// Decide se uma sincronização automática (abertura/retorno do app) já pode
/// rodar de novo, respeitando o teto de uma vez a cada [minInterval] (6 h).
bool shouldRunScheduledSync({
  required DateTime? lastSyncAt,
  required DateTime now,
  Duration minInterval = kOfflineRefreshInterval,
}) {
  if (lastSyncAt == null) return true;
  return now.toUtc().difference(lastSyncAt.toUtc()) >= minInterval;
}

/// Decide se a limpeza completa do cache offline já pode rodar de novo
/// (no máximo uma vez por dia, evitando decodificar o cache a cada abertura).
bool shouldRunOfflinePrune({
  required DateTime? lastPruneAt,
  required DateTime now,
  Duration minInterval = kOfflinePruneInterval,
}) {
  if (lastPruneAt == null) return true;
  return now.toUtc().difference(lastPruneAt.toUtc()) >= minInterval;
}

/// Metadados de uma escala guardada no aparelho, para a limpeza pura.
class CachedEventMeta {
  const CachedEventMeta({
    required this.id,
    required this.startsAt,
    this.lastServiceAt,
    this.timezone = 'America/Sao_Paulo',
    required this.cachedAt,
    required this.songIds,
    required this.sizeBytes,
  });

  final String id;
  final DateTime startsAt;
  final DateTime? lastServiceAt;
  final String timezone;
  final DateTime cachedAt;
  final Set<String> songIds;
  final int sizeBytes;

  DateTime get effectiveEnd => (lastServiceAt ?? startsAt).toUtc();
}

/// Metadados de uma música guardada no aparelho, para a limpeza pura.
class CachedSongMeta {
  const CachedSongMeta({
    required this.id,
    required this.cachedAt,
    this.lastOpenedAt,
    required this.sizeBytes,
  });

  final String id;
  final DateTime cachedAt;

  /// Quando a pessoa abriu esta música. Nulo quando ela só entrou em segundo
  /// plano pelo pré-carregamento e nunca foi aberta diretamente.
  final DateTime? lastOpenedAt;
  final int sizeBytes;

  DateTime get recencyAnchor => (lastOpenedAt ?? cachedAt).toUtc();
}

/// Resultado da limpeza planejada: quais chaves de escala e de música apagar.
class OfflineCacheCleanupPlan {
  const OfflineCacheCleanupPlan({
    required this.eventIdsToRemove,
    required this.songIdsToRemove,
  });

  final Set<String> eventIdsToRemove;
  final Set<String> songIdsToRemove;

  bool get isEmpty => eventIdsToRemove.isEmpty && songIdsToRemove.isEmpty;
}

/// Planeja o que apagar do aparelho para manter o cache enxuto e sob o teto.
///
/// Ordem:
/// 1. Remove escalas passadas há mais de [pastEventRetention] (padrão: 7 dias).
/// 2. Coleta todas as músicas referenciadas por alguma escala que ficou e
///    protege em definitivo as músicas de escalas dentro da janela de
///    pré-carregamento (nunca são apagadas pela limpeza, evitando laço de
///    baixar e apagar).
/// 3. Remove músicas fora dessas escalas que nunca foram abertas pelo usuário
///    (`lastOpenedAt == null`) ou cuja última abertura passou de
///    [unusedSongRetention] (60 dias).
/// 4. Quando há teto ativo (Web: [maxCachedSongs] / [maxCacheBytes]; no
///    Android ambos são nulos), remove primeiro músicas fora de escalas
///    guardadas (mais antigas primeiro) e, se ainda passar de [maxCacheBytes],
///    só remove músicas de escalas fora da janela de pré-carregamento (ex.:
///    passadas na folga de 7 dias ou futuras além da janela).
OfflineCacheCleanupPlan planOfflineCacheCleanup({
  required List<CachedEventMeta> events,
  required List<CachedSongMeta> songs,
  required DateTime now,
  Duration pastEventRetention = kPastEventRetention,
  Duration unusedSongRetention = kUnusedSongRetention,
  int? maxCachedSongs = kMaxCachedSongs,
  int? maxCacheBytes = kMaxOfflineCacheBytes,
}) {
  final nowUtc = now.toUtc();
  final eventCutoff = nowUtc.subtract(pastEventRetention);

  final eventIdsToRemove = <String>{};
  final keptEvents = <CachedEventMeta>[];
  for (final event in events) {
    if (event.effectiveEnd.isBefore(eventCutoff)) {
      eventIdsToRemove.add(event.id);
    } else {
      keptEvents.add(event);
    }
  }

  final earliestEventBySong = <String, DateTime>{};
  final protectedSongIds = <String>{};
  for (final event in keptEvents) {
    final startUtc = event.startsAt.toUtc();
    final tzName =
        event.timezone.isEmpty ? 'America/Sao_Paulo' : event.timezone;
    final today = _civilDateInZone(nowUtc, tzName);
    final eventDay = _civilDateInZone(startUtc, tzName);
    final windowEnd = offlinePrefetchWindowEnd(
      todayCivil: today,
      canManage: true,
    );
    final inPrefetchWindow =
        !eventDay.isBefore(today) && !eventDay.isAfter(windowEnd);

    for (final songId in event.songIds) {
      final current = earliestEventBySong[songId];
      if (current == null || startUtc.isBefore(current)) {
        earliestEventBySong[songId] = startUtc;
      }
      if (inPrefetchWindow) {
        protectedSongIds.add(songId);
      }
    }
  }
  final referencedSongIds = earliestEventBySong.keys.toSet();

  final songIdsToRemove = <String>{};
  final keptSongs = <CachedSongMeta>[];
  for (final song in songs) {
    final referenced = referencedSongIds.contains(song.id);
    if (!referenced) {
      final openedAt = song.lastOpenedAt?.toUtc();
      if (openedAt == null || nowUtc.difference(openedAt) >= unusedSongRetention) {
        songIdsToRemove.add(song.id);
        continue;
      }
    }
    keptSongs.add(song);
  }

  if (maxCachedSongs == null && maxCacheBytes == null) {
    return OfflineCacheCleanupPlan(
      eventIdsToRemove: eventIdsToRemove,
      songIdsToRemove: songIdsToRemove,
    );
  }

  var totalBytes = keptEvents.fold<int>(0, (sum, e) => sum + e.sizeBytes) +
      keptSongs.fold<int>(0, (sum, s) => sum + s.sizeBytes);

  bool overSongLimit(int count) =>
      maxCachedSongs != null && count > maxCachedSongs;
  bool overByteLimit(int bytes) =>
      maxCacheBytes != null && bytes > maxCacheBytes;

  // Teto: primeiro descarta músicas fora de escalas guardadas (LRU).
  final unreferenced = keptSongs
      .where((s) => !referencedSongIds.contains(s.id))
      .toList()
    ..sort((a, b) => a.recencyAnchor.compareTo(b.recencyAnchor));

  var remainingSongCount = keptSongs.length;
  for (final song in unreferenced) {
    if (!overSongLimit(remainingSongCount) && !overByteLimit(totalBytes)) {
      break;
    }
    songIdsToRemove.add(song.id);
    remainingSongCount--;
    totalBytes -= song.sizeBytes;
  }

  // Se ainda passar do teto de bytes, só sacrifica músicas de escalas FORA da
  // janela de pré-carregamento (ex.: passadas recentes ou futuras além do
  // horizonte). Músicas de escalas dentro da janela nunca são removidas.
  if (overByteLimit(totalBytes)) {
    final evictableReferenced = keptSongs
        .where(
          (s) =>
              referencedSongIds.contains(s.id) &&
              !protectedSongIds.contains(s.id),
        )
        .toList()
      ..sort((a, b) {
        final byEvent = earliestEventBySong[b.id]!
            .compareTo(earliestEventBySong[a.id]!);
        if (byEvent != 0) return byEvent;
        return a.recencyAnchor.compareTo(b.recencyAnchor);
      });

    for (final song in evictableReferenced) {
      if (!overByteLimit(totalBytes)) break;
      songIdsToRemove.add(song.id);
      totalBytes -= song.sizeBytes;
    }
  }

  return OfflineCacheCleanupPlan(
    eventIdsToRemove: eventIdsToRemove,
    songIdsToRemove: songIdsToRemove,
  );
}

/// Resumo do que está guardado no aparelho para leitura sem rede.
class OfflineCacheSummary {
  const OfflineCacheSummary({
    required this.scheduleCount,
    required this.songCount,
  });

  final int scheduleCount;
  final int songCount;

  @override
  bool operator ==(Object other) =>
      other is OfflineCacheSummary &&
      other.scheduleCount == scheduleCount &&
      other.songCount == songCount;

  @override
  int get hashCode => Object.hash(scheduleCount, songCount);
}

/// "3 escalas, 12 músicas" (ou singular: "1 escala, 1 música").
String formatOfflineCounts(int scheduleCount, int songCount) {
  final escalas = scheduleCount == 1 ? '1 escala' : '$scheduleCount escalas';
  final musicas = songCount == 1 ? '1 música' : '$songCount músicas';
  return '$escalas, $musicas';
}

/// "Disponível sem internet: 3 escalas, 12 músicas".
String formatOfflineAvailability(OfflineCacheSummary summary) {
  return 'Disponível sem internet: '
      '${formatOfflineCounts(summary.scheduleCount, summary.songCount)}';
}

DateTime _civilDateInZone(DateTime utc, String timezone) {
  try {
    final local = tz.TZDateTime.from(utc, tz.getLocation(timezone));
    return DateTime.utc(local.year, local.month, local.day);
  } catch (_) {
    // Em testes unitários sem `tzdata.initializeTimeZones()`, cai em UTC para
    // manter a função pura sem depender de inicialização global.
    return DateTime.utc(utc.year, utc.month, utc.day);
  }
}
