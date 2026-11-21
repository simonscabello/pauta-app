import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/core/storage/read_cache.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:louvor_app/features/songs/data/song_repository.dart';
import 'package:louvor_app/features/songs/domain/song_models.dart';
import 'package:louvor_app/features/songs/presentation/lyrics_reader.dart';

Future<void> _open(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const sheet = '[Intro]\n[D] [A/C#] [Bm7(b5)]\n\n[D]Em tua [A/C#]casa '
      'cantamos juntos esta frase comprida que precisa quebrar.';

  testWidgets('320 px, fonte 1.3x, ajuste da letra e do tom da cifra',
      (tester) async {
    const song = Song(
      id: '1',
      title: 'Em tua casa',
      chordsKey: 'D',
      defaultKey: 'E',
      chords: sheet,
    );
    await _open(tester, const SongLyricsScreen(song: song, chordMode: true));

    expect(find.text('B/D#'), findsNWidgets(2));
    final fontBefore =
        tester.widget<Text>(find.text('B/D#').first).style!.fontSize!;
    await tester.tap(find.byTooltip('Aparência da leitura'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Aumentar a letra'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byTooltip('Aumentar a letra'))).pop();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Aumentar a letra'), findsNothing);
    expect(
      tester.widget<Text>(find.text('B/D#').first).style!.fontSize,
      greaterThan(fontBefore),
    );
    await tester.tap(find.byTooltip('Subir meio tom'));
    await tester.pumpAndSettle();
    expect(find.text('C/E'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Baixar meio tom'));
    await tester.pumpAndSettle();
    expect(find.text('B/D#'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('destino anotado permite ajustar a partir do tom escrito',
      (tester) async {
    const song = Song(
      id: '1',
      title: 'Em tua casa',
      chordsKey: 'D',
      defaultKey: 'G (capo 2)',
      chords: sheet,
    );
    await _open(tester, const SongLyricsScreen(song: song, chordMode: true));
    expect(find.text('A cifra está como foi escrita, em D.'), findsOneWidget);
    expect(find.text('A/C#'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Baixar meio tom'));
    await tester.pumpAndSettle();
    expect(find.text('Ab/C'), findsNWidgets(2));
    expect(find.textContaining('como foi escrita'), findsNothing);
  });

  testWidgets('sem o tom escrito, mantém a cifra original e avisa',
      (tester) async {
    const song =
        Song(id: '1', title: 'Em tua casa', chords: sheet, defaultKey: 'E');
    await _open(tester, const SongLyricsScreen(song: song, chordMode: true));
    expect(
      find.text('O tom em que a cifra foi escrita não foi informado.'),
      findsOneWidget,
    );
    expect(find.text('A/C#'), findsNWidgets(2));
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
      'Próxima usa o tom de cada música e oferece o site quando falta cifra',
      (tester) async {
    final teams = <String>[];
    const songs = [
      EventSong(songId: '1', serviceId: 'culto', title: 'Primeira', key: 'F'),
      EventSong(songId: '2', serviceId: 'culto', title: 'Segunda', key: 'Bb'),
      EventSong(
        songId: '3',
        serviceId: 'culto',
        title: 'Terceira',
        chordsUrl: 'https://example.org/terceira',
      ),
    ];
    await _open(
      tester,
      const EventLyricsScreen(
        teamId: 'equipe',
        songs: songs,
        initialIndex: 0,
        chordMode: true,
      ),
      overrides: [
        songProvider.overrideWith((ref, args) async {
          teams.add(args.teamId);
          return CachedValue(
            fromCache: false,
            data: Song(
              id: args.songId,
              title: 'Ensaio',
              defaultKey: 'C',
              chordsKey: 'D',
              chords: args.songId == '3' ? null : '[A/C#]Canto',
            ),
          );
        }),
      ],
    );
    expect(find.text('C/E'), findsOneWidget);
    await tester.tap(find.byTooltip('Baixar meio tom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Próxima: Segunda'));
    await tester.pumpAndSettle();
    expect(find.text('2 de 3'), findsOneWidget);
    expect(find.text('F/A'), findsOneWidget);
    await tester.tap(find.text('Próxima: Terceira'));
    await tester.pumpAndSettle();
    expect(
      find.text('A cifra desta música ainda não foi guardada no Pauta.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Abrir no site'), findsOneWidget);
    expect(teams, ['equipe', 'equipe', 'equipe']);
    expect(tester.takeException(), isNull);
  });
}
