import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date/report_period.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../domain/moment_suggestion.dart';
import '../domain/repertoire_health.dart';
import '../domain/song_history.dart';
import '../domain/song_models.dart';
import '../domain/song_usage.dart';

class SongRepository {
  const SongRepository(this._dio);

  final Dio _dio;

  Future<List<Song>> list(
    String teamId, {
    String? search,
    bool includeArchived = false,
    Set<String> themes = const {},
  }) async {
    return _guard(() async {
      final response = await _dio.get<List<dynamic>>(
        '/teams/$teamId/songs',
        queryParameters: {
          if (search != null && search.trim().isNotEmpty) 'search': search,
          if (includeArchived) 'includeArchived': true,
          // Separados por vírgula, num parâmetro só: o servidor aceita as duas
          // formas, e esta é a que sobrevive a proxy que reordena parâmetro
          // repetido.
          if (themes.isNotEmpty) 'themes': themes.join(','),
        },
      );
      return response.data!
          .map((e) => Song.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// Só as músicas que a equipe está aprendendo.
  ///
  /// Filtrado no servidor (`?isNew=true`), e não aqui: quem pede é a Home, e
  /// trazer o acervo inteiro para mostrar quatro linhas é o custo que a Home
  /// prometeu não pagar.
  Future<List<Song>> learning(String teamId) async {
    return _guard(() async {
      final response = await _dio.get<List<dynamic>>(
        '/teams/$teamId/songs',
        queryParameters: {'isNew': true},
      );
      return response.data!
          .map((e) => Song.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// Única chamada que traz a letra.
  Future<Song> find(String teamId, String songId) async {
    return _guard(() async {
      final response =
          await _dio.get<Map<String, dynamic>>('/teams/$teamId/songs/$songId');
      return Song.fromJson(response.data!);
    });
  }

  Future<Song> create(String teamId, Map<String, dynamic> body) async {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/teams/$teamId/songs',
        data: body,
      );
      return Song.fromJson(response.data!);
    });
  }

  Future<Song> update(
    String teamId,
    String songId,
    Map<String, dynamic> body,
  ) async {
    return _guard(() async {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/teams/$teamId/songs/$songId',
        data: body,
      );
      return Song.fromJson(response.data!);
    });
  }

  /// Histórico de uso: o que a equipe cantou, quando e em que tom.
  Future<SongUsageReport> usage(
    String teamId, {
    required ReportPeriod period,
    int? weekday,
  }) async {
    return _guard(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/teams/$teamId/reports/songs',
        queryParameters: {
          ...period.toQuery(),
          if (weekday != null) 'weekday': weekday,
        },
      );
      return SongUsageReport.fromJson(response.data!);
    });
  }

  /// O histórico de todas as músicas já cantadas, **numa chamada só**, indexado
  /// pelo id. O seletor da escala desenha dezenas de linhas; pedir o histórico
  /// de cada uma seria uma requisição por linha na rede do celular.
  Future<Map<String, SongHistory>> songContext(String teamId) async {
    return _guard(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/teams/$teamId/reports/song-context',
      );
      final songs = response.data!['songs'] as List<dynamic>? ?? const [];
      return {
        for (final item in songs)
          if (SongHistory.fromJson(item as Map<String, dynamic>)
              case final history)
            history.songId: history,
      };
    });
  }

  Future<RepertoireHealth> repertoireHealth(String teamId) async {
    return _guard(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/teams/$teamId/reports/repertoire-health',
      );
      return RepertoireHealth.fromJson(response.data!);
    });
  }

  /// "Sugestões do Pauta" para um momento do culto desta escala.
  Future<List<MomentSuggestion>> momentSuggestions(
    String eventId,
    String moment,
  ) async {
    return _guard(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/events/$eventId/moment-suggestions',
        queryParameters: {'moment': moment},
      );
      return (response.data!['suggestions'] as List<dynamic>? ?? const [])
          .map((e) => MomentSuggestion.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// Regra 21: música já usada em escala não se exclui. Arquivar tira do
  /// repertório do dia a dia sem quebrar as escalas passadas, e é reversível.
  Future<Song> setArchived(
    String teamId,
    String songId, {
    required bool isArchived,
  }) {
    return update(teamId, songId, {'isArchived': isArchived});
  }

  Future<void> remove(String teamId, String songId) async {
    return _guard(() async {
      await _dio.delete<void>('/teams/$teamId/songs/$songId');
    });
  }

  /// Busca a mesma música no repertório das outras equipes.
  Future<List<CatalogCandidate>> catalog(String teamId, String search) async {
    return _guard(() async {
      final response = await _dio.get<List<dynamic>>(
        '/teams/$teamId/songs/catalog',
        queryParameters: {'search': search},
      );
      return response.data!
          .map((e) => CatalogCandidate.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Song> copyFromCatalog(
    String teamId,
    String sourceSongId, {
    bool isNew = false,
    Set<String> themes = const {},
  }) async {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/teams/$teamId/songs/from-catalog',
        // `isNew` é de quem está adicionando, não da música de origem: que a
        // outra equipe já domine a canção não diz nada sobre esta. Os temas,
        // ao contrário, vêm da origem — estes aqui se somam a eles.
        data: {
          'sourceSongId': sourceSongId,
          'isNew': isNew,
          if (themes.isNotEmpty) 'themes': themes.toList(),
        },
      );
      return Song.fromJson(response.data!);
    });
  }

  Future<List<ExternalCandidate>> searchExternal(
    String teamId,
    String search,
  ) async {
    return _guard(() async {
      final response = await _dio.get<List<dynamic>>(
        '/teams/$teamId/songs/search-external',
        queryParameters: {'search': search},
      );
      return response.data!
          .map((e) => ExternalCandidate.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// Cria a partir da escolha da busca externa. A API vai ao CifraClub
  /// resolver cifra, letra, tom e andamento -- por isso demora mais que as
  /// outras chamadas.
  Future<Song> createFromExternal(
    String teamId,
    ExternalCandidate candidate, {
    bool isNew = false,
    Set<String> themes = const {},
  }) async {
    return _guard(
      () async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/teams/$teamId/songs/from-external',
          data: {
            'title': candidate.title,
            'artist': candidate.artist,
            'isNew': isNew,
            if (themes.isNotEmpty) 'themes': themes.toList(),
            if (candidate.spotifyUrl.isNotEmpty)
              'spotifyUrl': candidate.spotifyUrl,
          },
          options: Options(receiveTimeout: const Duration(seconds: 45)),
        );
        return Song.fromJson(response.data!);
      },
    );
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final songRepositoryProvider = Provider<SongRepository>((ref) {
  return SongRepository(ref.watch(dioProvider));
});

/// Filtro da lista. **São dois acervos, não um.**
///
/// O Cantor Cristão entrou inteiro: 581 hinos num repertório de 861 músicas.
/// Numa lista só, dois terços de tudo o que se rola é hino, e procurar um
/// cântico vira garimpo — por isso não existe mais uma aba "Todas". A primeira
/// aba é "Cânticos", e ela **exclui** os hinos.
///
/// "Hino" aqui é **a música que está em algum hinário**, e não a do Cantor
/// Cristão: a igreja que cantar da Harpa Cristã terá a mesma aba pelo mesmo
/// motivo, sem nada mudar aqui.
///
/// "Hinos" percorre por número, que é a ordem do hinário impresso e a única
/// que serve para quem sabe o hino de cor pelo número.
///
/// "Novas" atravessa os dois: um hino pode estar sendo aprendido tanto quanto
/// um cântico.
///
/// "Arquivadas" não é uma aba: é a tela do arquivo, em `/equipe/musicas/
/// arquivadas`. Música usada em escala não se apaga — as escalas passadas
/// continuam íntegras —, então arquivar é o único jeito de tirar do caminho o
/// que a equipe não canta mais, e o arquivo precisa de uma porta de volta.
enum SongFilter { canticos, hinos, novas, arquivadas }

class SongQuery {
  const SongQuery({
    required this.teamId,
    this.search = '',
    this.filter = SongFilter.canticos,
    this.themes = const {},
  });

  final String teamId;
  final String search;
  final SongFilter filter;

  /// Temas marcados no filtro. Vazio = sem filtro de tema.
  ///
  /// **Somam-se aos outros filtros, não os substituem**: "Hinos" + "Ceia" é o
  /// hino que serve à Santa Ceia, que é exatamente a pergunta de quem monta o
  /// culto. Entre si, os temas são um OU — marcar "Natal" e "Páscoa" mostra as
  /// duas listas juntas, porque marcar dois e receber nada seria lido como
  /// defeito.
  final Set<String> themes;

  @override
  bool operator ==(Object other) =>
      other is SongQuery &&
      other.teamId == teamId &&
      other.search == search &&
      other.filter == filter &&
      // `Set` não tem igualdade estrutural em Dart: sem comparar item a item,
      // dois filtros idênticos seriam chaves diferentes do provider e cada
      // reconstrução da tela dispararia uma consulta nova.
      other.themes.length == themes.length &&
      other.themes.containsAll(themes);

  @override
  int get hashCode => Object.hash(
        teamId,
        search,
        filter,
        // Ordenado: `{A, B}` e `{B, A}` são o mesmo filtro e precisam do mesmo
        // código, senão a comparação acima nunca é alcançada.
        Object.hashAll(themes.toList()..sort()),
      );
}

/// O acervo que o servidor devolve para uma busca, **antes** de separar por
/// aba.
///
/// As abas (Cânticos, Hinos, Novas) são filtro local. Quando cada aba pedia a
/// própria lista, trocar de aba era uma volta de rede com spinner, e a busca
/// não tinha como dizer que "grande" existia em Hinos enquanto a pessoa
/// olhava Cânticos. Com o acervo numa chave só, as abas são recortes dele e
/// as contagens ("Hinos (3)") saem de graça.
///
/// **Fica vivo por alguns minutos** depois de ninguém olhar: o seletor da
/// escala abre e fecha a cada culto, e buscar o acervo inteiro a cada abertura
/// era o spinner que se via ao escolher as músicas da noite.
///
/// Depois de gravar uma música, invalide **este** provider: as listas por aba
/// dependem dele e se refazem juntas.
final songCatalogProvider =
    FutureProvider.autoDispose.family<List<Song>, SongQuery>((ref, query) {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);

  return ref.watch(songRepositoryProvider).list(
        query.teamId,
        search: query.search,
        themes: query.themes,
        // A lista normal já vem sem as arquivadas: o servidor as esconde por
        // padrão. Só o arquivo pede que elas venham.
        includeArchived: query.filter == SongFilter.arquivadas,
      );
});

/// A chave do acervo para esta consulta: a mesma busca e os mesmos temas,
/// com a aba reduzida a "arquivo ou não".
SongQuery _catalogKey(SongQuery query) => SongQuery(
      teamId: query.teamId,
      search: query.search,
      themes: query.themes,
      filter: query.filter == SongFilter.arquivadas
          ? SongFilter.arquivadas
          : SongFilter.canticos,
    );

/// Quantas músicas cada aba tem para esta busca. Nulo enquanto o acervo
/// carrega.
final songTabCountsProvider = Provider.autoDispose
    .family<Map<SongFilter, int>?, SongQuery>((ref, query) {
  final songs = ref.watch(songCatalogProvider(_catalogKey(query))).valueOrNull;
  if (songs == null) return null;
  return {
    SongFilter.canticos: songs.where((s) => !s.isHymn).length,
    SongFilter.hinos: songs.where((s) => s.isHymn).length,
    SongFilter.novas: songs.where((s) => s.isNew).length,
  };
});

/// "Hinos (3)" enquanto há busca: é assim que a aba avisa que o que se
/// procura está nela.
String songTabLabel(String label, int? count) =>
    count == null ? label : '$label ($count)';

final songsProvider =
    FutureProvider.autoDispose.family<List<Song>, SongQuery>((ref, query) async {
  final songs = await ref.watch(songCatalogProvider(_catalogKey(query)).future);

  // O filtro é local: a lista inteira já veio, e ir ao servidor de novo só
  // para esconder linhas gastaria uma volta de rede à toa.
  return switch (query.filter) {
    SongFilter.canticos => songs.where((s) => !s.isHymn).toList(),
    SongFilter.novas => songs.where((s) => s.isNew).toList(),
    // Por número, e não por título: é a ordem do hinário impresso, e é assim
    // que se procura um hino que se sabe de cor pelo número. O número é o da
    // referência principal — a música que está em dois hinários aparece uma
    // vez, no lugar do livro que a equipe escolheu mostrar.
    SongFilter.hinos => songs.where((s) => s.isHymn).toList()
      ..sort((a, b) => a.hymnNumber!.compareTo(b.hymnNumber!)),
    SongFilter.arquivadas => songs.where((s) => s.isArchived).toList(),
  };
});

/// As músicas que a equipe está aprendendo, para o cartão da Home.
///
/// Lista própria, e não o `songsProvider` com a aba "Novas": aquele traz o
/// acervo inteiro e filtra no aparelho, e a Home não pode pagar centenas de
/// músicas para desenhar quatro. Visível para toda a equipe — estudar a música
/// nova é de quem canta.
final learningSongsProvider =
    FutureProvider.autoDispose.family<List<Song>, String>(
  (ref, teamId) => ref.watch(songRepositoryProvider).learning(teamId),
);

final songProvider = FutureProvider.autoDispose
    .family<Song, ({String teamId, String songId})>((ref, args) {
  return ref.watch(songRepositoryProvider).find(args.teamId, args.songId);
});

typedef SongUsageQuery = ({String teamId, ReportPeriod period, int? weekday});

final songUsageProvider =
    FutureProvider.autoDispose.family<SongUsageReport, SongUsageQuery>(
  (ref, query) => ref.watch(songRepositoryProvider).usage(
        query.teamId,
        period: query.period,
        weekday: query.weekday,
      ),
);

/// Histórico por música (id → histórico), para o seletor da escala e a tela
/// da música. **Só para quem lidera**: é relatório, e o servidor responde 403
/// ao integrante — quem observa este provider precisa saber disso antes.
final songHistoryProvider =
    FutureProvider.autoDispose.family<Map<String, SongHistory>, String>(
  (ref, teamId) => ref.watch(songRepositoryProvider).songContext(teamId),
);

final repertoireHealthProvider =
    FutureProvider.autoDispose.family<RepertoireHealth, String>(
  (ref, teamId) => ref.watch(songRepositoryProvider).repertoireHealth(teamId),
);

typedef MomentSuggestionQuery = ({String eventId, String moment});

final momentSuggestionsProvider = FutureProvider.autoDispose
    .family<List<MomentSuggestion>, MomentSuggestionQuery>(
  (ref, query) => ref
      .watch(songRepositoryProvider)
      .momentSuggestions(query.eventId, query.moment),
);

/// Puxar para atualizar: o acervo vem de novo do servidor, e a aba que está
/// na tela espera por ele.
Future<void> refreshSongs(WidgetRef ref, SongQuery query) {
  ref.invalidate(songCatalogProvider);
  return ref.read(songsProvider(query).future);
}
