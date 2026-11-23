import 'event_models.dart';

String formatDuration(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

String? setlistDurationLabel(List<EventSong> songs) {
  var totalSeconds = 0;
  var missing = 0;
  for (final song in songs) {
    final duration = song.durationSeconds;
    if (duration == null) {
      missing++;
    } else {
      totalSeconds += duration;
    }
  }
  if (missing == songs.length) return null;

  final label = 'Cerca de ${(totalSeconds / 60).ceil()} min';
  if (missing == 0) return label;
  return '$label ($missing ${missing == 1 ? 'música' : 'músicas'} sem duração)';
}
