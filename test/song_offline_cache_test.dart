import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/core/network/api_exception.dart';
import 'package:louvor_app/core/network/dio_client.dart';
import 'package:louvor_app/core/storage/read_cache.dart';
import 'package:louvor_app/core/storage/shared_preferences_provider.dart';
import 'package:louvor_app/features/songs/data/song_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A cifra e a letra sem rede: o detalhe da música passa pelo cache de
/// leitura, como a agenda e a escala.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('songProvider devolve a cópia guardada sem rede, mas não num 404',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var requests = 0;
    var offline = false;
    int? status;
    final dio = Dio();
    addTearDown(dio.close);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          if (offline) {
            return handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
          }
          if (status != null) {
            return handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response(requestOptions: options, statusCode: status),
              ),
            );
          }
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'id': 's1',
                'title': 'Aclame ao Senhor',
                'chords': '[D]Canto',
                'chordsKey': 'D',
              },
            ),
          );
        },
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dioProvider.overrideWithValue(dio),
      ],
    );
    addTearDown(container.dispose);
    const args = (teamId: 't1', songId: 's1');
    container.listen(songProvider(args), (_, __) {});

    expect((await container.read(songProvider(args).future)).fromCache, false);

    offline = true;
    container.invalidate(songProvider(args));
    final cached = await container.read(songProvider(args).future);
    expect(cached.fromCache, isTrue);
    expect(cached.cachedAt, isNotNull);
    expect(cached.data.chords, '[D]Canto');

    // A música apagada (ou a equipe que a pessoa deixou) não volta pelo cache.
    offline = false;
    status = 404;
    container.invalidate(songProvider(args));
    await expectLater(
      container.read(songProvider(args).future),
      throwsA(isA<ApiException>()),
    );

    // A escala aberta há pouco não busca de novo a música já guardada.
    status = null;
    requests = 0;
    await container.read(songRepositoryProvider).prefetch('t1', ['s1', 's1']);
    expect(requests, 0);

    // O logout limpa o cache de leitura, e a música vai junto.
    await ReadCache(prefs).clearAll();
    expect(ReadCache(prefs).readSong('s1'), isNull);
    await container.read(songRepositoryProvider).prefetch('t1', ['s1']);
    expect(requests, 1);
  });
}
