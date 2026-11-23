import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/core/storage/read_cache.dart';
import 'package:louvor_app/core/storage/shared_preferences_provider.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/auth/application/auth_controller.dart';
import 'package:louvor_app/features/auth/domain/auth_models.dart';
import 'package:louvor_app/features/events/data/event_repository.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:louvor_app/features/songs/data/song_repository.dart';
import 'package:louvor_app/features/songs/domain/song_models.dart';
import 'package:louvor_app/features/songs/presentation/lyrics_reader.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, this._initial) {
    state = _initial;
  }

  final AuthState _initial;

  @override
  Future<void> bootstrap() async {
    state = _initial;
  }
}

/// A escala no servidor, reduzida ao tom da única música.
class _Escala extends EventRepository {
  _Escala(ReadCache cache) : super(Dio(), cache);

  String? key = 'D';
  final saved = <String?>[];

  @override
  Future<Map<String, LiveSong>> liveSongs(String eventId) async => {
        'culto:1': (key: key, hasChordVersion: false, chordVersionId: null),
      };

  @override
  Future<void> setSongKey(String eventId, EventSong song, String? key) async {
    saved.add(key);
    this.key = key;
  }
}

Future<_Escala> _openReader(WidgetTester tester, {required String role}) async {
  SharedPreferences.setMockInitialValues({});
  final escala = _Escala(ReadCache(await SharedPreferences.getInstance()));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eventRepositoryProvider.overrideWithValue(escala),
        songProvider.overrideWith(
          (ref, args) async => CachedValue(
            fromCache: false,
            data: Song(
              id: args.songId,
              title: 'Primeira',
              chordsKey: 'D',
              chords: '[A]Canto',
            ),
          ),
        ),
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            AuthState.signedIn(
              const AuthUser(
                id: '1',
                name: 'Simon',
                email: 'simon@teste.com',
                mustChangePassword: false,
              ),
              [
                TeamSummary(
                  membershipId: 'm1',
                  teamId: 'equipe',
                  name: 'Louvor',
                  role: role,
                  displayName: 'Simon',
                ),
              ],
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const EventLyricsScreen(
          teamId: 'equipe',
          eventId: 'escala',
          songs: [
            EventSong(songId: '1', serviceId: 'culto', title: 'Primeira', key: 'D'),
          ],
          initialIndex: 0,
          chordMode: true,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return escala;
}

void main() {
  testWidgets('o tom muda no servidor e a cifra aberta acompanha',
      (tester) async {
    final escala = await _openReader(tester, role: 'MEMBER');
    expect(find.text('A'), findsOneWidget);

    // A transposição pessoal vale até o tom combinado mudar.
    await tester.tap(find.byTooltip('Subir meio tom'));
    await tester.pump();
    expect(find.text('Eb'), findsOneWidget);
    expect(find.textContaining('para todos'), findsNothing);

    escala.key = 'F';
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Tom mudou para F.'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('quem lidera grava para todos o tom que acertou no ensaio',
      (tester) async {
    final escala = await _openReader(tester, role: 'LEADER');
    expect(find.textContaining('para todos'), findsNothing);

    await tester.tap(find.byTooltip('Subir meio tom'));
    await tester.tap(find.byTooltip('Subir meio tom'));
    await tester.pump();
    await tester.tap(find.text('Usar E para todos'));
    await tester.pumpAndSettle();
    expect(escala.saved, ['E']);
    expect(find.text('Tom E para todos nesta escala.'), findsOneWidget);
    expect(find.textContaining('Usar '), findsNothing);

    // A consulta seguinte devolve o tom que ele mesmo gravou: nada a avisar.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.textContaining('Tom mudou'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a rolagem automática anda, pausa no toque e guarda a velocidade',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: SongLyricsScreen(
            song: Song(
              id: '1',
              title: 'Longa',
              lyrics: List.generate(200, (i) => 'Linha $i').join('\n'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    double offset() =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;

    await tester.tap(find.byTooltip('Velocidade da rolagem'));
    await tester.pump();
    expect(prefs.getInt('lyrics_scroll_speed'), 2);

    await tester.tap(find.byTooltip('Rolar sozinho'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    final rolou = offset();
    expect(rolou, greaterThan(0));

    final toque = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await toque.up();
    expect(offset(), rolou);
    expect(find.byTooltip('Rolar sozinho'), findsOneWidget);
  });
}
