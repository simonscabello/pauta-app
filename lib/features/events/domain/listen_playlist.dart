import 'event_models.dart';

/// O id do vídeo de um endereço do YouTube, ou nulo quando o endereço não é
/// de um vídeo.
///
/// Os formatos que aparecem no repertório: `youtube.com/watch?v=`,
/// `youtu.be/`, `youtube.com/shorts/`, `youtube.com/embed/` e o
/// `music.youtube.com/watch?v=`.
String? youtubeVideoId(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  final valido = RegExp(r'^[A-Za-z0-9_-]{11}$');

  String? id;
  if (host == 'youtu.be') {
    id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
  } else if (host.endsWith('youtube.com')) {
    final segments = uri.pathSegments;
    if (segments.isNotEmpty && segments.first == 'watch') {
      id = uri.queryParameters['v'];
    } else if (segments.length >= 2 &&
        (segments.first == 'shorts' || segments.first == 'embed' || segments.first == 'live')) {
      id = segments[1];
    }
  }
  return id != null && valido.hasMatch(id) ? id : null;
}

/// O endereço que toca as músicas da escala em sequência, no YouTube, ou nulo
/// quando nenhuma tem vídeo.
///
/// Na ordem do culto (manhã antes da noite, e a ordem de cada culto). A mesma
/// música nos dois cultos entra uma vez: quem ensaia quer ouvi-la, não ouvi-la
/// duas vezes. Com mais de uma, é o `watch_videos` do YouTube, que monta uma
/// lista temporária sem conta nem chave; com uma só, o próprio vídeo.
String? youtubeListenUrl(Event event) {
  final ids = <String>[];
  for (final grupo in event.songsByService) {
    for (final song in grupo.songs) {
      final id = youtubeVideoId(song.youtubeUrl);
      if (id != null && !ids.contains(id)) ids.add(id);
    }
  }
  if (ids.isEmpty) return null;
  if (ids.length == 1) return 'https://www.youtube.com/watch?v=${ids.first}';
  return 'https://www.youtube.com/watch_videos?video_ids=${ids.join(',')}';
}

/// Quantas músicas da escala têm vídeo -- o número que o botão diz.
int youtubeListenCount(Event event) {
  final ids = <String>{};
  for (final song in event.songs) {
    final id = youtubeVideoId(song.youtubeUrl);
    if (id != null) ids.add(id);
  }
  return ids.length;
}
