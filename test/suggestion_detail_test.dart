import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/auth/application/auth_controller.dart';
import 'package:louvor_app/features/auth/domain/auth_models.dart';
import 'package:louvor_app/features/songs/data/song_repository.dart';
import 'package:louvor_app/features/songs/domain/song_models.dart';
import 'package:louvor_app/features/suggestions/data/suggestion_repository.dart';
import 'package:louvor_app/features/suggestions/domain/song_suggestion.dart';
import 'package:louvor_app/features/songs/presentation/song_resources.dart';
import 'package:louvor_app/features/suggestions/presentation/suggestion_detail_screen.dart';

/// A tela de detalhes da sugestão.
///
/// Ela é o lugar onde a sugestão é lida inteira e respondida — a lista virou
/// índice justamente para isto caber aqui. O que estes testes protegem: só o
/// material que existe vira botão, o motivo aparece sem cortar, as decisões só
/// existem para quem pode decidir, e o nome de quem resolveu não vaza.
class _RepositorioFake extends SuggestionRepository {
  _RepositorioFake(this._suggestion) : super(Dio());

  final SongSuggestion _suggestion;

  String? aceitaComSongId;
  bool chamouAceitar = false;

  @override
  Future<SongSuggestion> find(String teamId, String id) async => _suggestion;

  @override
  Future<SongSuggestion> accept(
    String teamId,
    String id, {
    String? songId,
  }) async {
    chamouAceitar = true;
    aceitaComSongId = songId;
    return _suggestion;
  }
}

/// O repertório, para o aceite que cadastra a música no caminho.
class _MusicasFake extends SongRepository {
  _MusicasFake() : super(Dio());

  ExternalCandidate? doSpotify;
  bool? doSpotifyIsNew;
  Map<String, dynamic>? completada;

  @override
  Future<Song> createFromExternal(
    String teamId,
    ExternalCandidate candidate, {
    bool isNew = false,
    Set<String> themes = const {},
  }) async {
    doSpotify = candidate;
    doSpotifyIsNew = isNew;
    return Song(
      id: 'm1',
      title: candidate.title,
      artist: candidate.artist,
      spotifyUrl: candidate.spotifyUrl,
      isNew: isNew,
    );
  }

  @override
  Future<Song> update(
    String teamId,
    String songId,
    Map<String, dynamic> body,
  ) async {
    completada = body;
    return Song(id: songId, title: 'Bondade de Deus');
  }

  @override
  Future<List<CatalogCandidate>> catalog(String teamId, String search) async =>
      [];

  @override
  Future<List<ExternalCandidate>> searchExternal(
    String teamId,
    String search,
  ) async =>
      [];
}

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

SongSuggestion _sugestao({
  String status = 'PENDING',
  String? artist = 'Isaías Saad',
  String? songId,
  String? lyricsUrl = 'https://www.cifraclub.com.br/x/',
  String? spotifyUrl,
  String? youtubeUrl,
  String? declineReason,
  String? targetDate,
  List<String> alsoSuggestedBy = const [],
}) =>
    SongSuggestion.fromJson({
      'id': 'sg1',
      'songId': songId,
      'title': 'Bondade de Deus',
      'artist': artist,
      'lyricsUrl': lyricsUrl,
      'spotifyUrl': spotifyUrl,
      'youtubeUrl': youtubeUrl,
      'targetDate': targetDate,
      'reason': 'A igreja já canta essa nos cultos de oração e a letra fala '
          'exatamente do que o pastor tem pregado neste mês.',
      'status': status,
      'declineReason': declineReason,
      'inRepertoire': songId != null,
      'createdBy': {
        'membershipId': 'm-maria',
        'displayName': 'Maria',
        'avatarUrl': null,
      },
      'createdAt': '2026-09-03T12:00:00.000Z',
      'alsoSuggestedBy': alsoSuggestedBy,
    });

Future<_RepositorioFake> _montar(
  WidgetTester tester, {
  required SongSuggestion suggestion,
  _MusicasFake? musicas,
  String role = 'OWNER',
  ThemeData? theme,
  Size size = const Size(375 * 3, 812 * 3),
  bool comRotas = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final repositorio = _RepositorioFake(suggestion);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        suggestionRepositoryProvider.overrideWithValue(repositorio),
        songRepositoryProvider.overrideWithValue(musicas ?? _MusicasFake()),
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
                  membershipId: 'm-simon',
                  teamId: 't1',
                  name: 'Louvor SIBB',
                  role: role,
                  displayName: 'Simon',
                ),
              ],
            ),
          ),
        ),
      ],
      child: comRotas
          // Só o bastante para ver aonde o atalho leva: a sugestão na raiz e,
          // no lugar da tela da música, o endereço que a rota recebeu.
          ? MaterialApp.router(
              theme: theme ?? AppTheme.light,
              routerConfig: GoRouter(
                routes: [
                  // A sugestão é empilhada à mão por cima de uma rota, como
                  // no app: é essa mistura que o "voltar" precisa respeitar.
                  GoRoute(
                    path: '/',
                    builder: (_, __) => Scaffold(
                      body: Builder(
                        builder: (context) => TextButton(
                          onPressed: () => openSuggestionDetail(
                            context,
                            teamId: 't1',
                            suggestion: suggestion,
                          ),
                          child: const Text('abrir sugestão'),
                        ),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: '/equipe/musicas/:songId',
                    builder: (_, state) => Scaffold(
                      appBar: AppBar(),
                      body: Text('rota ${state.uri}'),
                    ),
                  ),
                ],
              ),
            )
          : MaterialApp(
              theme: theme ?? AppTheme.light,
              home: SuggestionDetailScreen(
                teamId: 't1',
                suggestionId: 'sg1',
                initial: suggestion,
              ),
            ),
    ),
  );
  await tester.pumpAndSettle();
  if (comRotas) {
    await tester.tap(find.text('abrir sugestão'));
    await tester.pumpAndSettle();
  }
  return repositorio;
}

void main() {
  testWidgets('mostra a música, o motivo inteiro e quem sugeriu',
      (tester) async {
    await _montar(tester, suggestion: _sugestao());

    expect(find.text('Bondade de Deus'), findsOneWidget);
    // Em versalete, como na tela da música; o leitor de tela ouve o nome.
    expect(find.text('ISAÍAS SAAD'), findsOneWidget);
    // O motivo é o conteúdo da sugestão: aqui ele não é cortado.
    expect(
      find.textContaining('exatamente do que o pastor tem pregado'),
      findsOneWidget,
    );
    expect(find.text('Sugerida por Maria'), findsOneWidget);
    expect(find.text('Para o repertório'), findsOneWidget);
  });

  testWidgets('só os links que existem viram ladrilho', (tester) async {
    await _montar(
      tester,
      suggestion: _sugestao(youtubeUrl: 'https://youtu.be/x'),
    );

    expect(find.byType(SongResourceRow), findsOneWidget);
    expect(find.text('Letra ou cifra'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    // Link que ninguém mandou não vira ladrilho apagado: promessa falsa.
    expect(find.text('Spotify'), findsNothing);
  });

  testWidgets('sem link nenhum, a faixa de materiais some', (tester) async {
    await _montar(tester, suggestion: _sugestao(lyricsUrl: null));

    expect(find.byType(SongResourceRow), findsNothing);
  });

  testWidgets('as decisões são de quem lidera', (tester) async {
    await _montar(tester, suggestion: _sugestao(), role: 'MEMBER');

    expect(find.text('Aceitar sugestão'), findsNothing);
    expect(find.text('Recusar'), findsNothing);
    // Quem sugeriu continua lendo a própria sugestão -- é para isso que a tela
    // é de todo mundo.
    expect(find.textContaining('A igreja já canta'), findsOneWidget);
  });

  testWidgets('música já no repertório: aceitar é um toque só', (tester) async {
    final repositorio = await _montar(
      tester,
      suggestion: _sugestao(songId: 's1'),
    );

    expect(find.text('Ver no repertório'), findsOneWidget);

    await tester.tap(find.text('Aceitar sugestão'));
    await tester.pumpAndSettle();

    // Nenhum diálogo de cadastro pelo caminho: a música já existe.
    expect(repositorio.chamouAceitar, isTrue);
    expect(repositorio.aceitaComSongId, 's1');
  });

  testWidgets('sem cadastro, aceitar oferece adicionar ao repertório',
      (tester) async {
    final repositorio = await _montar(tester, suggestion: _sugestao());

    await tester.tap(find.text('Aceitar sugestão'));
    await tester.pumpAndSettle();

    expect(find.text('Adicionar ao repertório?'), findsOneWidget);

    // Desistir não aceita nada: acolher uma música que ninguém cadastrou
    // deixaria a sugestão acolhida apontando para o vazio.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repositorio.chamouAceitar, isFalse);
  });

  testWidgets('veio do Spotify: aceitar cadastra a faixa sem buscar de novo',
      (tester) async {
    final musicas = _MusicasFake();
    final repositorio = await _montar(
      tester,
      musicas: musicas,
      suggestion: _sugestao(spotifyUrl: 'https://open.spotify.com/track/x'),
    );

    await tester.tap(find.text('Aceitar sugestão'));
    await tester.pumpAndSettle();

    // Uma folha de confirmação, e não a busca: a faixa já foi escolhida por
    // quem sugeriu.
    expect(find.text('Adicionar ao repertório'), findsOneWidget);
    expect(find.text('Adicionar música'), findsNothing);
    expect(find.text('Isaías Saad'), findsOneWidget);

    await tester.tap(find.text('Adicionar e aceitar'));
    await tester.pumpAndSettle();

    expect(musicas.doSpotify?.title, 'Bondade de Deus');
    expect(musicas.doSpotify?.artist, 'Isaías Saad');
    expect(musicas.doSpotify?.spotifyUrl, 'https://open.spotify.com/track/x');
    // "Música nova" nasce ligada, como na tela de adicionar -- e é o líder
    // quem desliga, não uma dedução.
    expect(musicas.doSpotifyIsNew, isTrue);
    // O link de cifra que quem sugeriu mandou completa a música.
    expect(musicas.completada, {'chordsUrl': 'https://www.cifraclub.com.br/x/'});
    expect(repositorio.aceitaComSongId, 'm1');
  });

  testWidgets('link do Spotify errado: "outra versão" abre a busca direto',
      (tester) async {
    final repositorio = await _montar(
      tester,
      suggestion: _sugestao(spotifyUrl: 'https://open.spotify.com/track/x'),
    );

    await tester.tap(find.text('Aceitar sugestão'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Escolher outra versão'));
    await tester.pumpAndSettle();

    // Sem perguntar de novo "Adicionar ao repertório?": a folha já perguntou.
    expect(find.text('Adicionar ao repertório?'), findsNothing);
    expect(find.text('Adicionar música'), findsOneWidget);
    expect(repositorio.chamouAceitar, isFalse);
  });

  testWidgets('Spotify sem artista cai no cadastro pela busca', (tester) async {
    await _montar(
      tester,
      suggestion: _sugestao(
        artist: null,
        spotifyUrl: 'https://open.spotify.com/track/x',
      ),
    );

    await tester.tap(find.text('Aceitar sugestão'));
    await tester.pumpAndSettle();

    // O cadastro pelo Spotify exige o artista; sem ele, o caminho de sempre.
    expect(find.text('Adicionar ao repertório?'), findsOneWidget);
  });

  testWidgets('encerrada mostra a resposta e o caminho de volta',
      (tester) async {
    await _montar(
      tester,
      suggestion: _sugestao(
        status: 'DECLINED',
        declineReason: 'Já temos duas músicas novas neste mês.',
      ),
    );

    expect(find.text('Recusada'), findsOneWidget);
    expect(find.text('Já temos duas músicas novas neste mês.'), findsOneWidget);
    // Reabrir existe para o toque errado não virar beco sem saída.
    expect(find.text('Reabrir'), findsOneWidget);
    expect(find.text('Aceitar sugestão'), findsNothing);
  });

  testWidgets('recusa sem motivo não desenha caixa vazia', (tester) async {
    await _montar(tester, suggestion: _sugestao(status: 'DECLINED'));

    // Campo em branco é uso legítimo: às vezes o motivo certo é uma conversa
    // pessoal, e o app não é o canal.
    expect(find.text('Resposta'), findsNothing);
  });

  testWidgets('cabe no celular estreito e no tema escuro', (tester) async {
    // 320dp é o mais apertado que ainda existe em uso. Um `Row` que não coube
    // vira exceção de overflow e derruba este teste -- que é exatamente o
    // aviso que não chega de outro jeito antes do aparelho.
    await _montar(
      tester,
      suggestion: _sugestao(
        // Uma data que não vence: a de um domingo passado some com os botões.
        targetDate: '2099-09-13',
        spotifyUrl: 'https://open.spotify.com/track/x',
        youtubeUrl: 'https://youtu.be/x',
        alsoSuggestedBy: const ['Ana', 'João', 'Pedro'],
      ),
      theme: AppTheme.dark,
      size: const Size(320 * 3, 640 * 3),
    );

    expect(tester.takeException(), isNull);

    // As decisões ficam no fim da página, depois do motivo — é a ordem em que
    // a decisão acontece de verdade —, então aqui se rola até elas.
    await tester.scrollUntilVisible(
      find.text('Recusar'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Aceitar sugestão'), findsOneWidget);
    expect(find.text('Recusar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('domingo que já passou não oferece aceitar nem recusar',
      (tester) async {
    await _montar(tester, suggestion: _sugestao(targetDate: '2020-01-05'));

    await tester.scrollUntilVisible(
      find.textContaining('já passou'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Aceitar sugestão'), findsNothing);
    expect(find.text('Recusar'), findsNothing);
  });

  testWidgets('sem música no repertório, não há atalho para ela',
      (tester) async {
    await _montar(tester, suggestion: _sugestao());

    expect(find.text('Ver no repertório'), findsNothing);
  });

  testWidgets('aceita: o integrante chega à música pelo id, na equipe dela',
      (tester) async {
    await _montar(
      tester,
      suggestion: _sugestao(status: 'ACCEPTED', songId: 's1'),
      role: 'MEMBER',
      comRotas: true,
    );

    expect(find.text('Tom, cifra e letra da equipe'), findsOneWidget);

    await tester.tap(find.text('Ver no repertório'));
    await tester.pumpAndSettle();

    // A equipe da sugestão vai junto: quem serve em duas equipes não pode
    // ver a música procurada no repertório da equipe ativa.
    expect(find.text('rota /equipe/musicas/s1?equipe=t1'), findsOneWidget);

    // Voltar da música devolve a sugestão, e não a tela de baixo dela.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Ver no repertório'), findsOneWidget);
  });

  testWidgets('aceitar oferece ver a música no aviso', (tester) async {
    await _montar(
      tester,
      suggestion: _sugestao(songId: 's1'),
      comRotas: true,
    );

    await tester.tap(find.text('Aceitar sugestão'));
    await tester.pumpAndSettle();

    // A sugestão fechou; o aviso, na tela de baixo, leva à música aceita.
    expect(find.text('Aceitar sugestão'), findsNothing);
    await tester.tap(find.text('Ver música'));
    await tester.pumpAndSettle();
    expect(find.text('rota /equipe/musicas/s1?equipe=t1'), findsOneWidget);
  });

  testWidgets('quem resolveu não aparece; quem mais sugeriu, sim',
      (tester) async {
    await _montar(
      tester,
      suggestion: _sugestao(alsoSuggestedBy: const ['Ana', 'João']),
    );

    expect(
      find.text('Sugerida por Maria · Ana e João também sugeriram'),
      findsOneWidget,
    );
    // Recusa com o nome do líder do lado azeda a equipe.
    expect(find.textContaining('Simon'), findsNothing);
  });
}
