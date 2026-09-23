import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Cache de leitura da agenda e do culto aberto (Etapa 7). Sem sync.
class ReadCache {
  ReadCache(this._prefs);

  final SharedPreferences _prefs;

  static const _agendaPrefix = 'cache.agenda.';
  static const _eventPrefix = 'cache.event.';

  Future<void> saveAgenda(
    String teamId,
    String scope,
    List<Map<String, dynamic>> events,
  ) async {
    final payload = jsonEncode({
      'cachedAt': DateTime.now().toUtc().toIso8601String(),
      'events': events,
    });
    await _prefs.setString('$_agendaPrefix$teamId.$scope', payload);
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
    Map<String, dynamic> event,
  ) async {
    final payload = jsonEncode({
      'cachedAt': DateTime.now().toUtc().toIso8601String(),
      'event': event,
    });
    await _prefs.setString('$_eventPrefix$eventId', payload);
  }

  /// Apaga tudo o que o cache guardou: agenda e escalas de todas as equipes.
  /// Chamado quando a conta é excluída -- os nomes da equipe ficariam no
  /// aparelho depois de a pessoa ter pedido para sumir.
  Future<void> clearAll() async {
    final keys = _prefs.getKeys().where(
          (key) => key.startsWith(_agendaPrefix) || key.startsWith(_eventPrefix),
        );
    for (final key in keys.toList()) {
      await _prefs.remove(key);
    }
  }

  CachedPayload<Map<String, dynamic>>? readEvent(String eventId) {
    final raw = _prefs.getString('$_eventPrefix$eventId');
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return CachedPayload(
      cachedAt: DateTime.parse(json['cachedAt'] as String).toUtc(),
      data: Map<String, dynamic>.from(json['event'] as Map),
    );
  }
}

class CachedPayload<T> {
  const CachedPayload({required this.cachedAt, required this.data});

  final DateTime cachedAt;
  final T data;
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
