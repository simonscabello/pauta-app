import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/core/network/api_exception.dart';
import 'package:louvor_app/core/storage/read_cache.dart';
import 'package:louvor_app/features/events/data/agenda_provider.dart';
import 'package:louvor_app/features/events/data/event_repository.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
  });

  group('cálculo do recorte do mês no fuso da equipe', () {
    test('respeita virada de mês em America/Sao_Paulo (UTC já no mês seguinte)',
        () {
      // 2026-10-01 01:30 UTC == 2026-09-30 22:30 em São Paulo (UTC-3).
      final beforeMidnightSp = DateTime.utc(2026, 10, 1, 1, 30);
      expect(
        agendaMonthInTimezone(beforeMidnightSp, 'America/Sao_Paulo'),
        DateTime(2026, 9),
      );
      expect(
        agendaMonthRange(beforeMidnightSp, timezone: 'America/Sao_Paulo'),
        (from: '2026-09-01', to: '2026-09-30'),
      );

      // Um segundo antes da meia-noite em São Paulo: ainda setembro.
      final lastSecondSepSp = DateTime.utc(2026, 10, 1, 2, 59, 59);
      expect(
        agendaMonthRange(lastSecondSepSp, timezone: 'America/Sao_Paulo'),
        (from: '2026-09-01', to: '2026-09-30'),
      );

      // Meia-noite exata em São Paulo (03:00 UTC): virou outubro.
      final midnightOctSp = DateTime.utc(2026, 10, 1, 3, 0);
      expect(
        agendaMonthInTimezone(midnightOctSp, 'America/Sao_Paulo'),
        DateTime(2026, 10),
      );
      expect(
        agendaMonthRange(midnightOctSp, timezone: 'America/Sao_Paulo'),
        (from: '2026-10-01', to: '2026-10-31'),
      );
    });

    test('respeita virada de ano em America/Sao_Paulo', () {
      // 2027-01-01 02:59 UTC == 2026-12-31 23:59 em São Paulo.
      expect(
        agendaMonthRange(
          DateTime.utc(2027, 1, 1, 2, 59),
          timezone: 'America/Sao_Paulo',
        ),
        (from: '2026-12-01', to: '2026-12-31'),
      );
      // 2027-01-01 03:00 UTC == 2027-01-01 00:00 em São Paulo.
      expect(
        agendaMonthRange(
          DateTime.utc(2027, 1, 1, 3, 0),
          timezone: 'America/Sao_Paulo',
        ),
        (from: '2027-01-01', to: '2027-01-31'),
      );
    });

    test('trata fevereiro bissexto, não-bissexto, fuso positivo e fuso vazio',
        () {
      expect(
        agendaMonthRange(DateTime(2024, 2)),
        (from: '2024-02-01', to: '2024-02-29'),
      );
      expect(
        agendaMonthRange(DateTime(2026, 2)),
        (from: '2026-02-01', to: '2026-02-28'),
      );
      // 2026-09-30 23:00 UTC == 2026-10-01 08:00 em Tóquio (UTC+9).
      expect(
        agendaMonthRange(
          DateTime.utc(2026, 9, 30, 23, 0),
          timezone: 'Asia/Tokyo',
        ),
        (from: '2026-10-01', to: '2026-10-31'),
      );
      // Fuso vazio cai no padrão America/Sao_Paulo.
      expect(
        agendaMonthRange(DateTime.utc(2026, 10, 1, 1, 30), timezone: ''),
        (from: '2026-09-01', to: '2026-09-30'),
      );
    });
  });

  test('agendaMonthProvider consulta listRange sem disparar scope=past',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository =
        _SpyRepository(ReadCache(await SharedPreferences.getInstance()));
    final container = ProviderContainer(
      overrides: [
        eventRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      agendaMonthProvider(('t1', DateTime(2026, 8))).future,
    );

    expect(result.data, hasLength(1));
    expect(result.fromCache, isFalse);
    expect(repository.listScopes, isEmpty);
    expect(repository.rangeCalls, [(from: '2026-08-01', to: '2026-08-31')]);
  });

  test(
      'listRange preserva cache da Home e lê cache offline inclusive de mês vazio',
      () async {
    SharedPreferences.setMockInitialValues({});
    final cache = ReadCache(await SharedPreferences.getInstance());
    final dio = Dio();
    addTearDown(dio.close);
    var offline = false;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (offline) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
            return;
          }
          final from = options.queryParameters['from'] as String?;
          if (from == '2026-08-01') {
            handler.resolve(
              Response<List<dynamic>>(
                requestOptions: options,
                data: const <dynamic>[],
                statusCode: 200,
              ),
            );
            return;
          }
          handler.resolve(
            Response<List<dynamic>>(
              requestOptions: options,
              data: [_json(0), _json(1)],
              statusCode: 200,
            ),
          );
        },
      ),
    );

    final repository = EventRepository(dio, cache);
    await repository.list('t1');
    await repository.listRange('t1', from: '2026-09-01', to: '2026-09-30');
    await repository.listRange('t1', from: '2026-08-01', to: '2026-08-31');

    expect(cache.readAgenda('t1', 'upcoming')!.data, hasLength(2));
    expect(
      cache.readAgenda('t1', 'range.2026-09-01.2026-09-30')!.data,
      hasLength(2),
    );
    expect(
      cache.readAgenda('t1', 'range.2026-08-01.2026-08-31')!.data,
      isEmpty,
    );

    offline = true;
    final cachedSep = await repository.listRange(
      't1',
      from: '2026-09-01',
      to: '2026-09-30',
    );
    expect(cachedSep.fromCache, isTrue);
    expect(cachedSep.cachedAt, isNotNull);
    expect(cachedSep.data, hasLength(2));

    // Mês sem escala visitado online continua acessível offline com selo.
    final cachedEmptyAug = await repository.listRange(
      't1',
      from: '2026-08-01',
      to: '2026-08-31',
    );
    expect(cachedEmptyAug.fromCache, isTrue);
    expect(cachedEmptyAug.cachedAt, isNotNull);
    expect(cachedEmptyAug.data, isEmpty);

    // Mês nunca visitado offline falha em vez de fingir vazio.
    await expectLater(
      repository.listRange('t1', from: '2026-07-01', to: '2026-07-31'),
      throwsA(isA<ApiException>()),
    );
  });
}

Map<String, dynamic> _json(int i) => {
      'id': 'e$i',
      'teamId': 't1',
      'startsAt': '2026-09-13T12:00:00Z',
      'status': 'PUBLISHED',
      'timezone': 'America/Sao_Paulo',
    };

class _SpyRepository extends EventRepository {
  _SpyRepository(ReadCache cache) : super(Dio(), cache);

  final List<String> listScopes = [];
  final List<({String from, String to})> rangeCalls = [];

  @override
  Future<CachedValue<List<Event>>> list(
    String teamId, {
    String scope = 'upcoming',
    int limit = 20,
  }) async {
    listScopes.add(scope);
    return const CachedValue(data: [], fromCache: false);
  }

  @override
  Future<CachedValue<List<Event>>> listRange(
    String teamId, {
    required String from,
    required String to,
    bool cache = true,
  }) async {
    rangeCalls.add((from: from, to: to));
    return CachedValue(
      data: [Event.fromJson(_json(0))],
      fromCache: false,
    );
  }
}
