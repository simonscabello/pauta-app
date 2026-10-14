import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:louvor_app/features/events/domain/listen_playlist.dart';
import 'package:louvor_app/features/events/domain/schedule_calendar.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// "Ouvir as músicas" e "Adicionar ao calendário", os dois atalhos da escala
/// para quem toca. Funções puras sobre o `Event`: o que se trava aqui é a
/// ordem do culto, a música repetida entre manhã e noite e o formato que a
/// agenda do celular aceita.
void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    await initializeDateFormatting('pt_BR');
  });

  group('id do vídeo', () {
    test('lê os formatos que aparecem no repertório', () {
      expect(
        youtubeVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(youtubeVideoId('https://youtu.be/dQw4w9WgXcQ?si=abc'), 'dQw4w9WgXcQ');
      expect(
        youtubeVideoId('https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=10'),
        'dQw4w9WgXcQ',
      );
      expect(
        youtubeVideoId('https://www.youtube.com/shorts/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        youtubeVideoId('https://music.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('endereço que não é de vídeo não vira id', () {
      expect(youtubeVideoId(null), isNull);
      expect(youtubeVideoId(''), isNull);
      expect(youtubeVideoId('https://www.youtube.com/@canal'), isNull);
      expect(youtubeVideoId('https://open.spotify.com/track/abc'), isNull);
      expect(youtubeVideoId('https://www.youtube.com/watch?v=curto'), isNull);
    });
  });

  group('ouvir as músicas', () {
    test('na ordem do culto, sem repetir a música da manhã à noite', () {
      final escala = _event(
        songs: [
          _song('s1', 'manha', 'aaaaaaaaaaa'),
          _song('s2', 'manha', 'bbbbbbbbbbb'),
          _song('s1', 'noite', 'aaaaaaaaaaa'),
          _song('s3', 'noite', 'ccccccccccc'),
          _song('s4', 'noite', null),
        ],
      );

      expect(
        youtubeListenUrl(escala),
        'https://www.youtube.com/watch_videos?video_ids='
        'aaaaaaaaaaa,bbbbbbbbbbb,ccccccccccc',
      );
      expect(youtubeListenCount(escala), 3);
    });

    test('com um vídeo só, o próprio vídeo; sem nenhum, nada', () {
      expect(
        youtubeListenUrl(_event(songs: [_song('s1', 'manha', 'aaaaaaaaaaa')])),
        'https://www.youtube.com/watch?v=aaaaaaaaaaa',
      );
      expect(
        youtubeListenUrl(_event(songs: [_song('s1', 'manha', null)])),
        isNull,
      );
    });
  });

  group('calendário', () {
    test('um compromisso por culto e um para o ensaio, em UTC e com CRLF', () {
      final ics = buildScheduleIcs(
        _event(
          rehearsalAt: '2026-10-17T22:00:00.000Z',
          location: 'Templo, sala 2',
        ),
        now: DateTime.utc(2026, 10, 14, 12),
      );

      expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(ics, endsWith('END:VCALENDAR\r\n'));
      expect('BEGIN:VEVENT'.allMatches(ics), hasLength(3));
      expect(ics, contains('DTSTART:20261018T120000Z'));
      expect(ics, contains('DTEND:20261018T140000Z'));
      expect(ics, contains('SUMMARY:Culto · Manhã'));
      expect(ics, contains('SUMMARY:Ensaio'));
      // A vírgula tem sentido no formato e precisa de escape.
      expect(ics, contains(r'LOCATION:Templo\, sala 2'));
    });

    test('o Google Agenda recebe o primeiro culto e os outros na descrição', () {
      final url = Uri.parse(googleCalendarUrl(_event()));
      expect(url.host, 'calendar.google.com');
      expect(
        url.queryParameters['dates'],
        '20261018T120000Z/20261018T140000Z',
      );
      expect(url.queryParameters['text'], 'Culto · Manhã');
      expect(url.queryParameters['details'], contains('Noite'));
    });

    test('o arquivo leva a data no nome', () {
      expect(scheduleIcsFileName(_event()), 'escala-2026-10-18.ics');
    });
  });
}

Event _event({
  List<Map<String, dynamic>> songs = const [],
  String? rehearsalAt,
  String? location,
}) =>
    Event.fromJson({
      'id': 'e1',
      'teamId': 't1',
      'title': null,
      'startsAt': '2026-10-18T12:00:00.000Z',
      'rehearsalAt': rehearsalAt,
      'location': location,
      'notes': null,
      'colorPalette': null,
      'status': 'PUBLISHED',
      'timezone': 'America/Sao_Paulo',
      'assignments': const [],
      'services': [
        {
          'id': 'manha',
          'label': 'Manhã',
          'startsAt': '2026-10-18T12:00:00.000Z',
        },
        {
          'id': 'noite',
          'label': 'Noite',
          'startsAt': '2026-10-18T22:00:00.000Z',
        },
      ],
      'songs': songs,
    });

Map<String, dynamic> _song(String id, String serviceId, String? video) => {
      'songId': id,
      'serviceId': serviceId,
      'title': 'Música $id',
      'position': 0,
      if (video != null) 'youtubeUrl': 'https://www.youtube.com/watch?v=$video',
    };
