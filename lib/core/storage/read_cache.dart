import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import 'offline_policy.dart';

/// Cache de leitura da agenda, do culto aberto e da música (letra e cifra)
/// (Etapa 7). Somente leitura, só texto (nunca áudio), com renovação por
/// `updatedAt`/tempo e limpeza com teto de bytes apenas na Web (`localStorage`).
class ReadCache {
  ReadCache(
    this._prefs, {
    int? maxCacheBytes = kIsWeb ? kMaxOfflineCacheBytes : null,
    int? maxCachedSongs = kIsWeb ? kMaxCachedSongs : null,
  })  : _maxCacheBytes = maxCacheBytes,
        _maxCachedSongs = maxCachedSongs;

  final SharedPreferences _prefs;
  final int? _maxCacheBytes;
  final int? _maxCachedSongs;

  static int _sessionEpoch = 0;

  static const _agendaPrefix = 'cache.agenda.';
  static const _eventPrefix = 'cache.event.';
  static const _songPrefix = 'cache.song.';
  static const _offlinePrefix = 'cache.offline.';
  static const _lastSyncKey = '${_offlinePrefix}lastSyncAt';
  static const _lastPruneKey = '${_offlinePrefix}lastPruneAt';

  /// Teto de bytes ativo para escalas e músicas (2 MB na Web; nulo no Android).
  int? get maxCacheBytes => _maxCacheBytes;

  /// Teto de músicas guardadas (ativo na Web; nulo no Android).
  int? get maxCachedSongs => _maxCachedSongs;

  /// Número da sessão atual do cache. Avança de forma síncrona no logout e no
  /// [clearAll] para impedir que requisições da conta anterior gravem dados
  /// após sair.
  int get sessionEpoch => _sessionEpoch;

  /// Avança o número de sessão imediatamente, invalidando escritas antigas.
  int bumpSession() => ++_sessionEpoch;

  bool isSessionCurrent(int expectedSession) =>
      _sessionEpoch == expectedSession;

  bool _canWrite(int? expectedSession) =>
      expectedSession == null || isSessionCurrent(expectedSession);

  Future<void> saveAgenda(
    String teamId,
    String scope,
    List<Map<String, dynamic>> events, {
    DateTime? now,
    int? expectedSession,
  }) async {
    if (!_canWrite(expectedSession)) return;
    final payload = jsonEncode({
      'cachedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'events': events,
    });
    await _writeString(
      '$_agendaPrefix$teamId.$scope',
      payload,
      now: now,
      expectedSession: expectedSession,
    );
  }

  CachedPayload<List<Map<String, dynamic>>>? readAgenda(
    String teamId,
    String scope,
  ) {
    final raw = _prefs.getString('$_agendaPrefix$teamId.$scope');
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final events = (json['events'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return CachedPayload(
      cachedAt: DateTime.parse(json['cachedAt'] as String).toUtc(),
      data: events,
    );
  }

  Future<void> saveEvent(
    String eventId,
    Map<String, dynamic> event, {
    DateTime? now,
    int? expectedSession,
  }) async {
    if (!_canWrite(expectedSession)) return;
    final payload = jsonEncode({
      'cachedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'event': event,
    });
    await _writeString(
      '$_eventPrefix$eventId',
      payload,
      now: now,
      expectedSession: expectedSession,
    );
  }

  Future<void> removeEvent(String eventId) async {
    await _prefs.remove('$_eventPrefix$eventId');
  }

  /// Guarda o detalhe da música (letra, cifra e versões).
  ///
  /// Quando [markOpened] é `true` (aberta pela pessoa), registra `lastOpenedAt`
  /// agora. Quando `false` (pré-carregamento em segundo plano), preserva o
  /// `lastOpenedAt` que já existia — ou grava `null` para que a limpeza saiba
  /// que ela só entrou por pré-carregamento e nunca foi aberta diretamente.
  Future<void> saveSong(
    String songId,
    Map<String, dynamic> song, {
    bool markOpened = true,
    DateTime? now,
    int? expectedSession,
  }) async {
    if (!_canWrite(expectedSession)) return;
    final clock = (now ?? DateTime.now()).toUtc();
    DateTime? lastOpenedAt;
    if (markOpened) {
      lastOpenedAt = clock;
    } else {
      final existing = readSongEntry(songId);
      lastOpenedAt = existing?.lastOpenedAt;
    }

    final payload = jsonEncode({
      'cachedAt': clock.toIso8601String(),
      'lastOpenedAt': lastOpenedAt?.toUtc().toIso8601String(),
      'song': song,
    });
    await _writeString(
      '$_songPrefix$songId',
      payload,
      now: clock,
      expectedSession: expectedSession,
    );
  }

  /// Marca que uma música já guardada foi aberta sem rede, renovando o prazo
  /// de 60 dias dela na limpeza.
  Future<void> touchSongOpened(
    String songId, {
    DateTime? now,
    int? expectedSession,
  }) async {
    if (!_canWrite(expectedSession)) return;
    final existing = readSongEntry(songId);
    if (existing == null) return;
    final clock = (now ?? DateTime.now()).toUtc();
    final payload = jsonEncode({
      'cachedAt': existing.cachedAt.toUtc().toIso8601String(),
      'lastOpenedAt': clock.toIso8601String(),
      'song': existing.data,
    });
    await _writeString(
      '$_songPrefix$songId',
      payload,
      now: clock,
      expectedSession: expectedSession,
    );
  }

  CachedPayload<Map<String, dynamic>>? readSong(String songId) {
    final entry = readSongEntry(songId);
    if (entry == null) return null;
    return CachedPayload(cachedAt: entry.cachedAt, data: entry.data);
  }

  CachedSongPayload? readSongEntry(String songId) {
    final raw = _prefs.getString('$_songPrefix$songId');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = DateTime.parse(json['cachedAt'] as String).toUtc();
      // Compatibilidade com cache gravado antes de `lastOpenedAt` existir:
      // chave ausente usa `cachedAt` para não apagar músicas abertas antes da
      // atualização; chave presente com `null` significa "só pré-carregada".
      final DateTime? lastOpenedAt;
      if (!json.containsKey('lastOpenedAt')) {
        lastOpenedAt = cachedAt;
      } else {
        final rawOpened = json['lastOpenedAt'] as String?;
        lastOpenedAt =
            rawOpened == null ? null : DateTime.parse(rawOpened).toUtc();
      }
      final data = Map<String, dynamic>.from(json['song'] as Map);
      return CachedSongPayload(
        cachedAt: cachedAt,
        lastOpenedAt: lastOpenedAt,
        updatedAt: _parseSongUpdatedAt(data),
        data: data,
      );
    } catch (_) {
      return null;
    }
  }

  DateTime? readEventUpdatedAt(String eventId) {
    final cached = readEvent(eventId);
    if (cached == null) return null;
    return _parseUtc(cached.data['updatedAt']);
  }

  DateTime? readLastSyncAt() {
    final raw = _prefs.getString(_lastSyncKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> saveLastSyncAt(
    DateTime at, {
    int? expectedSession,
  }) async {
    if (!_canWrite(expectedSession)) return;
    try {
      await _prefs.setString(_lastSyncKey, at.toUtc().toIso8601String());
    } catch (_) {
      // Sem espaço no armazenamento: não pode quebrar o fluxo do app.
    }
  }

  DateTime? readLastPruneAt() {
    final raw = _prefs.getString(_lastPruneKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> saveLastPruneAt(
    DateTime at, {
    int? expectedSession,
  }) async {
    if (!_canWrite(expectedSession)) return;
    try {
      await _prefs.setString(_lastPruneKey, at.toUtc().toIso8601String());
    } catch (_) {}
  }

  /// Tamanho total em bytes UTF-8 das escalas e músicas guardadas (sem
  /// decodificar JSON).
  int offlineBytes() {
    var total = 0;
    for (final key in _prefs.getKeys()) {
      if (key.startsWith(_eventPrefix) || key.startsWith(_songPrefix)) {
        final raw = _prefs.getString(key);
        if (raw != null) {
          total += utf8.encode(raw).length;
        }
      }
    }
    return total;
  }

  int eventByteSize(String eventId) => _keyByteSize('$_eventPrefix$eventId');

  int songByteSize(String songId) => _keyByteSize('$_songPrefix$songId');

  /// Verdadeiro apenas quando há teto de bytes (Web) e o cache offline já o
  /// alcançou — usado antes de baixar novas escalas ou músicas.
  bool isByteBudgetExceeded() {
    final cap = _maxCacheBytes;
    if (cap == null) return false;
    return offlineBytes() >= cap;
  }

  /// Roda [prune] no máximo uma vez a cada [minInterval] (padrão: 1 dia),
  /// evitando decodificar o cache inteiro a cada reconstrução de tela.
  Future<OfflineCacheCleanupPlan?> pruneIfDue({
    DateTime? now,
    Duration minInterval = kOfflinePruneInterval,
    int? expectedSession,
  }) async {
    if (!_canWrite(expectedSession)) return null;
    final clock = (now ?? DateTime.now()).toUtc();
    if (!shouldRunOfflinePrune(
      lastPruneAt: readLastPruneAt(),
      now: clock,
      minInterval: minInterval,
    )) {
      return null;
    }
    final plan = await prune(now: clock, expectedSession: expectedSession);
    if (_canWrite(expectedSession)) {
      await saveLastPruneAt(clock, expectedSession: expectedSession);
    }
    return plan;
  }

  /// Executa a limpeza com base nas regras puras de [planOfflineCacheCleanup]
  /// e apaga do aparelho as escalas antigas e músicas ociosas/excedentes.
  Future<OfflineCacheCleanupPlan> prune({
    DateTime? now,
    Duration pastEventRetention = kPastEventRetention,
    Duration unusedSongRetention = kUnusedSongRetention,
    int? maxCachedSongs,
    int? maxCacheBytes,
    int? expectedSession,
  }) async {
    if (!_canWrite(expectedSession)) {
      return const OfflineCacheCleanupPlan(
        eventIdsToRemove: {},
        songIdsToRemove: {},
      );
    }
    final events = <CachedEventMeta>[];
    final songs = <CachedSongMeta>[];
    final corruptedKeys = <String>[];

    for (final key in _prefs.getKeys().toList()) {
      if (key.startsWith(_eventPrefix)) {
        final raw = _prefs.getString(key);
        if (raw == null) continue;
        final id = key.substring(_eventPrefix.length);
        final meta = _parseEventMeta(id, raw);
        if (meta == null) {
          corruptedKeys.add(key);
        } else {
          events.add(meta);
        }
      } else if (key.startsWith(_songPrefix)) {
        final raw = _prefs.getString(key);
        if (raw == null) continue;
        final id = key.substring(_songPrefix.length);
        final meta = _parseSongMeta(id, raw);
        if (meta == null) {
          corruptedKeys.add(key);
        } else {
          songs.add(meta);
        }
      }
    }

    final plan = planOfflineCacheCleanup(
      events: events,
      songs: songs,
      now: now ?? DateTime.now(),
      pastEventRetention: pastEventRetention,
      unusedSongRetention: unusedSongRetention,
      maxCachedSongs: maxCachedSongs ?? _maxCachedSongs,
      maxCacheBytes: maxCacheBytes ?? _maxCacheBytes,
    );

    for (final key in corruptedKeys) {
      if (!_canWrite(expectedSession)) return plan;
      await _prefs.remove(key);
    }
    for (final id in plan.eventIdsToRemove) {
      if (!_canWrite(expectedSession)) return plan;
      await _prefs.remove('$_eventPrefix$id');
    }
    for (final id in plan.songIdsToRemove) {
      if (!_canWrite(expectedSession)) return plan;
      await _prefs.remove('$_songPrefix$id');
    }

    return plan;
  }

  /// Quantas escalas e músicas estão guardadas neste aparelho agora (conta só
  /// as chaves gravadas, sem decodificar o JSON na thread principal).
  OfflineCacheSummary summary() {
    var schedules = 0;
    var songs = 0;
    for (final key in _prefs.getKeys()) {
      if (key.startsWith(_eventPrefix)) {
        final raw = _prefs.getString(key);
        if (raw != null && raw.isNotEmpty) {
          schedules++;
        }
      } else if (key.startsWith(_songPrefix)) {
        final raw = _prefs.getString(key);
        if (raw != null && raw.isNotEmpty) {
          songs++;
        }
      }
    }
    return OfflineCacheSummary(scheduleCount: schedules, songCount: songs);
  }

  /// Apaga tudo o que o cache guardou: agenda, escalas, músicas e controle de
  /// sincronização de todas as equipes.
  /// Chamado no logout e quando a conta é excluída -- os nomes da equipe
  /// ficariam no aparelho depois de a pessoa ter saído ou pedido para sumir.
  Future<void> clearAll() async {
    // Avança a sessão antes de qualquer `await`: requisições em andamento da
    // conta anterior não conseguem mais gravar nada depois deste ponto.
    bumpSession();
    final keys = _prefs.getKeys().where(
          (key) =>
              key.startsWith(_agendaPrefix) ||
              key.startsWith(_eventPrefix) ||
              key.startsWith(_songPrefix) ||
              key.startsWith(_offlinePrefix),
        );
    for (final key in keys.toList()) {
      await _prefs.remove(key);
    }
  }

  CachedPayload<Map<String, dynamic>>? readEvent(String eventId) {
    final raw = _prefs.getString('$_eventPrefix$eventId');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return CachedPayload(
        cachedAt: DateTime.parse(json['cachedAt'] as String).toUtc(),
        data: Map<String, dynamic>.from(json['event'] as Map),
      );
    } catch (_) {
      return null;
    }
  }

  int _keyByteSize(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return 0;
    return utf8.encode(raw).length;
  }

  Future<void> _writeString(
    String key,
    String value, {
    DateTime? now,
    int? expectedSession,
  }) async {
    if (!_canWrite(expectedSession)) return;
    try {
      await _prefs.setString(key, value);
    } catch (_) {
      // Na Web o `localStorage` pode atingir a cota: limpa e tenta uma vez
      // antes de desistir sem derrubar a leitura.
      try {
        await prune(now: now, expectedSession: expectedSession);
        if (!_canWrite(expectedSession)) return;
        await _prefs.setString(key, value);
      } catch (_) {}
    }
  }

  static CachedEventMeta? _parseEventMeta(String id, String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = DateTime.parse(json['cachedAt'] as String).toUtc();
      final event = json['event'] as Map<String, dynamic>;
      final startsAt = DateTime.parse(event['startsAt'] as String).toUtc();
      final timezone = event['timezone'] as String? ?? 'America/Sao_Paulo';
      DateTime? lastServiceAt;
      final services = event['services'] as List<dynamic>? ?? const [];
      for (final item in services) {
        if (item is Map && item['startsAt'] is String) {
          final parsed = DateTime.parse(item['startsAt'] as String).toUtc();
          if (lastServiceAt == null || parsed.isAfter(lastServiceAt)) {
            lastServiceAt = parsed;
          }
        }
      }
      final songIds = <String>{};
      final songs = event['songs'] as List<dynamic>? ?? const [];
      for (final item in songs) {
        if (item is Map && item['songId'] is String) {
          songIds.add(item['songId'] as String);
        }
      }
      return CachedEventMeta(
        id: id,
        startsAt: startsAt,
        lastServiceAt: lastServiceAt,
        timezone: timezone,
        cachedAt: cachedAt,
        songIds: songIds,
        sizeBytes: utf8.encode(raw).length,
      );
    } catch (_) {
      return null;
    }
  }

  static CachedSongMeta? _parseSongMeta(String id, String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = DateTime.parse(json['cachedAt'] as String).toUtc();
      final DateTime? lastOpenedAt;
      if (!json.containsKey('lastOpenedAt')) {
        lastOpenedAt = cachedAt;
      } else {
        final rawOpened = json['lastOpenedAt'] as String?;
        lastOpenedAt =
            rawOpened == null ? null : DateTime.parse(rawOpened).toUtc();
      }
      return CachedSongMeta(
        id: id,
        cachedAt: cachedAt,
        lastOpenedAt: lastOpenedAt,
        sizeBytes: utf8.encode(raw).length,
      );
    } catch (_) {
      return null;
    }
  }

  static DateTime? _parseSongUpdatedAt(Map<String, dynamic> song) {
    var latest = _parseUtc(song['updatedAt']);
    final versions = song['chordVersions'] as List<dynamic>? ?? const [];
    for (final v in versions) {
      if (v is Map) {
        final versionUpdated = _parseUtc(v['updatedAt']);
        if (versionUpdated != null &&
            (latest == null || versionUpdated.isAfter(latest))) {
          latest = versionUpdated;
        }
      }
    }
    return latest;
  }

  static DateTime? _parseUtc(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}

class CachedPayload<T> {
  const CachedPayload({required this.cachedAt, required this.data});

  final DateTime cachedAt;
  final T data;
}

class CachedSongPayload extends CachedPayload<Map<String, dynamic>> {
  const CachedSongPayload({
    required super.cachedAt,
    required super.data,
    required this.lastOpenedAt,
    this.updatedAt,
  });

  final DateTime? lastOpenedAt;
  final DateTime? updatedAt;
}

class CachedValue<T> {
  const CachedValue({
    required this.data,
    required this.fromCache,
    this.cachedAt,
  });

  final T data;
  final bool fromCache;
  final DateTime? cachedAt;
}
