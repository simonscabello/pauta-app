import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/core/storage/shared_preferences_provider.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/songs/domain/song_models.dart';
import 'package:louvor_app/features/songs/presentation/lyrics_reader.dart';
import 'package:louvor_app/features/songs/presentation/reader_appearance.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  test('todo fundo tem texto, rótulo e acordes legíveis de longe', () {
    for (final p in ReaderPalette.all) {
      expect(_contrast(p.background, p.text), greaterThan(7), reason: p.label);
      expect(
        _contrast(p.background, p.muted),
        greaterThan(4.5),
        reason: p.label,
      );
      for (final c in ChordColor.all) {
        expect(
          _contrast(p.background, c.on(p.brightness)),
          greaterThan(4.5),
          reason: '${c.label} sobre ${p.label}',
        );
      }
    }
    // "Do app": o fundo do próprio tema, com as mesmas cores de acorde.
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      for (final c in ChordColor.all) {
        expect(
          _contrast(theme.scaffoldBackgroundColor, c.on(theme.brightness)),
          greaterThan(4.5),
          reason: '${c.label} sobre o tema ${theme.brightness.name}',
        );
      }
    }
  });

  testWidgets('fundo e cor dos acordes escolhidos valem no leitor e ficam',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const song = Song(
      id: '1',
      title: 'Em tua casa',
      chordsKey: 'D',
      defaultKey: 'D',
      chords: '[D]Em tua [A]casa',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const SongLyricsScreen(song: song, chordMode: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Color background() =>
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor ??
        Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor;
    Color chord() => tester.widget<Text>(find.text('A')).style!.color!;

    // Sem escolha: o fundo de sempre do app; só os acordes ganham cor.
    expect(background(), AppTheme.light.scaffoldBackgroundColor);
    expect(chord(), ChordColor.all.first.onLight);

    await tester.tap(find.byTooltip('Aparência da leitura'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Preto'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Amarelo'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Aparência da leitura'))).pop();
    await tester.pumpAndSettle();

    expect(background(), ReaderPalette.black.background);
    expect(chord(), const Color(0xFFFFD43B));
    expect(prefs.getString('reader_palette'), 'black');
    expect(prefs.getString('reader_chord_color'), 'yellow');
    expect(tester.takeException(), isNull);
  });
}
