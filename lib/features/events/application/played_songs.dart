import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/shared_preferences_provider.dart';
import '../domain/event_models.dart';

/// As músicas já tocadas de **uma** escala, marcadas neste aparelho.
///
/// É anotação de quem está no culto, e não dado da equipe: fica no aparelho,
/// e marcar em outra escala recomeça a lista, para nada se acumular.
typedef PlayedSongs = ({String? eventId, Set<String> slots});

class PlayedSongsController extends StateNotifier<PlayedSongs> {
  PlayedSongsController(this._prefs) : super(_read(_prefs));

  static const _key = 'played_songs';

  final SharedPreferences? _prefs;

  static PlayedSongs _read(SharedPreferences? prefs) {
    final saved = prefs?.getStringList(_key) ?? const [];
    return (eventId: saved.firstOrNull, slots: saved.skip(1).toSet());
  }

  static String _slot(EventSong song) => '${song.serviceId}:${song.songId}';

  bool isPlayed(String eventId, EventSong song) =>
      state.eventId == eventId && state.slots.contains(_slot(song));

  Future<void> toggle(String eventId, EventSong song) async {
    final slots = {if (state.eventId == eventId) ...state.slots};
    if (!slots.remove(_slot(song))) slots.add(_slot(song));
    state = (eventId: eventId, slots: slots);
    try {
      await _prefs?.setStringList(_key, [eventId, ...slots]);
    } catch (_) {
      // Marcação que não gravou vale só para esta sessão.
    }
  }
}

final playedSongsProvider =
    StateNotifierProvider<PlayedSongsController, PlayedSongs>((ref) {
  SharedPreferences? prefs;
  try {
    prefs = ref.watch(sharedPreferencesProvider);
  } catch (_) {
    prefs = null;
  }
  return PlayedSongsController(prefs);
});
