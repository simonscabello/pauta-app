import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/songs/data/hymnal_repository.dart';
import 'package:louvor_app/core/network/api_exception.dart';
import 'package:louvor_app/features/songs/data/song_repository.dart';
import 'package:louvor_app/features/songs/domain/chord_import.dart';
import 'package:louvor_app/features/songs/domain/song_models.dart';
import 'package:louvor_app/features/songs/presentation/musical_key_picker.dart';
import 'package:louvor_app/features/songs/presentation/song_form_screen.dart';

/// O tom na edição da música.
///
/// O que estes testes protegem: o tom se escolhe numa lista e não se digita,
/// o escolhido é o que vai para o servidor, e a anotação feita antes da lista
/// ("G (capo 2)") sobrevive a quem abriu a música só para mudar outra coisa.
class _RepositorioFake extends SongRepository {
  _RepositorioFake({this.fontes = const [], this.previa, this.erroPrevia})
      : super(Dio());

  Map<String, dynamic>? enviado;
  final List<ChordSourceInfo> fontes;
  final ChordPreview? previa;
  final ApiException? erroPrevia;
  String? linkPedido;

  @override
  Future<List<ChordSourceInfo>> chordSources(String teamId) async => fontes;

  @override
  Future<ChordPreview> previewChords(
    String teamId,
    String songId,
    String url,
  ) async {
    linkPedido = url;
    if (erroPrevia != null) throw erroPrevia!;
    return previa!;
  }

  @override
  Future<Song> update(
    String teamId,
    String songId,
    Map<String, dynamic> body,
  ) async {
    enviado = body;
    return Song.fromJson({'id': songId, 'title': body['title'] as String});
  }
}

Future<_RepositorioFake> _abrir(
  WidgetTester tester, {
  String? defaultKey,
  String? originalKey,
  String? chords,
  String? chordsKey,
  Map<String, dynamic>? chordsSource,
  String? chordsUrl,
  _RepositorioFake? repositorioFake,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repositorio = repositorioFake ?? _RepositorioFake();
  final song = Song.fromJson({
    'id': 's1',
    'title': 'Cristo Venceu',
    'artist': 'Novo Canto',
    'defaultKey': defaultKey,
    'chords': chords,
    'chordsKey': chordsKey,
    'chordsSource': chordsSource,
    'chordsUrl': chordsUrl,
    'originalKey': originalKey,
  });

  final router = GoRouter(
    initialLocation: '/musica/editar',
    routes: [
      GoRoute(
        path: '/musica',
        builder: (_, __) => const Scaffold(body: Text('detalhe')),
        routes: [
          GoRoute(
            path: 'editar',
            builder: (_, __) =>
                SongFormScreen(teamId: 't1', songId: 's1', song: song),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        songRepositoryProvider.overrideWithValue(repositorio),
        hymnalsProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return repositorio;
}

Future<void> _salvar(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Salvar'));
  await tester.tap(find.text('Salvar'));
  await tester.pumpAndSettle();
}

Finder _campo(String label) =>
    find.widgetWithText(MusicalKeyField, label);

void main() {
  testWidgets('salvar outro campo preserva cifra e tom sem enviar os dois',
      (tester) async {
    final repo = await _abrir(tester, chords: '[D]Canto', chordsKey: 'D');
    await _salvar(tester);
    expect(repo.enviado, isNot(contains('chords')));
    expect(repo.enviado, isNot(contains('chordsKey')));
  });

  testWidgets('colar cifra exige tom, aceita a sugestão e envia ChordPro',
      (tester) async {
    final repo = await _abrir(tester, defaultKey: 'D', originalKey: 'G');
    await tester.ensureVisible(find.text('Dados da música'));
    await tester.tap(find.text('Dados da música'));
    await tester.pumpAndSettle();
    final cifra = find.widgetWithText(TextField, 'Cifra');
    await tester.ensureVisible(cifra);
    await tester.enterText(cifra, 'D   A\nCanto');
    await _salvar(tester);
    expect(repo.enviado, isNull);
    expect(find.text('Escolha o tom em que a cifra foi escrita.'), findsOneWidget);
    final usarTom = find.text('Usar D na cifra');
    await tester.ensureVisible(usarTom);
    await tester.tap(usarTom);
    await tester.pumpAndSettle();
    await _salvar(tester);
    expect(repo.enviado, isNull);
    expect(
      find.text(
        'Diga de onde vem a cifra e confirme que a equipe pode guardá-la.',
      ),
      findsOneWidget,
    );

    final arranjo = find.text('Arranjo da equipe');
    await tester.ensureVisible(arranjo);
    await tester.tap(arranjo);
    final confirmo = find.byType(CheckboxListTile);
    await tester.ensureVisible(confirmo);
    await tester.tap(confirmo);
    await tester.pumpAndSettle();
    await _salvar(tester);
    expect(repo.enviado!['chords'], '[D]Cant[A]o');
    expect(repo.enviado!['chordsKey'], 'D');
    expect(repo.enviado!['chordsImport'], {
      'kind': 'TEXT',
      'rightsBasis': 'TEAM_ARRANGEMENT',
      'rightsNote': '',
      'authorized': true,
    });
  });

  testWidgets('ChordPro colado sugere o tom do arquivo e mostra a prévia',
      (tester) async {
    await _abrir(tester, defaultKey: 'D');
    await tester.ensureVisible(find.text('Dados da música'));
    await tester.tap(find.text('Dados da música'));
    await tester.pumpAndSettle();
    final cifra = find.widgetWithText(TextField, 'Cifra');
    await tester.ensureVisible(cifra);
    await tester.enterText(cifra, '{title: Canção}\n{key: A}\n{soc}\n[A]Canto');
    await tester.pumpAndSettle();
    expect(find.text('Usar A na cifra'), findsOneWidget);

    final ver = find.text('Ver como fica');
    await tester.ensureVisible(ver);
    await tester.tap(ver);
    await tester.pumpAndSettle();
    expect(find.text('Como a cifra vai aparecer'), findsOneWidget);
    expect(find.text('[Refrão]'), findsOneWidget);
    // O campo atrás da folha ainda tem o texto colado; a prévia, não.
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.textContaining('title'),
      ),
      findsNothing,
    );
  });

  testWidgets('cifra guardada mostra a origem e não pede declaração de novo',
      (tester) async {
    await initializeDateFormatting('pt_BR');
    final repo = await _abrir(
      tester,
      chords: '[D]Canto',
      chordsKey: 'D',
      chordsSource: {
        'kind': 'URL',
        'sourceHost': 'exemplo.com',
        'rightsBasis': 'PERMISSION',
        'importedAt': '2026-11-20T15:00:00.000Z',
        'importedByName': 'Samuel',
      },
    );
    await tester.ensureVisible(find.text('Dados da música'));
    await tester.tap(find.text('Dados da música'));
    await tester.pumpAndSettle();
    expect(
      find.text('Trazida de exemplo.com em 20/11/2026 por Samuel · '
          'Permissão do autor ou da editora'),
      findsOneWidget,
    );
    expect(find.byType(CheckboxListTile), findsNothing);
    await _salvar(tester);
    expect(repo.enviado, isNot(contains('chordsImport')));
  });

  testWidgets('apagar a cifra limpa também o tom escrito', (tester) async {
    final repo = await _abrir(tester, chords: '[D]Canto', chordsKey: 'D');
    await tester.ensureVisible(find.text('Dados da música'));
    await tester.tap(find.text('Dados da música'));
    await tester.pumpAndSettle();
    final cifra = find.widgetWithText(TextField, 'Cifra');
    await tester.ensureVisible(cifra);
    await tester.enterText(cifra, '');
    await _salvar(tester);
    expect(repo.enviado, containsPair('chords', null));
    expect(repo.enviado, containsPair('chordsKey', null));
  });

  testWidgets('o tom não tem teclado', (tester) async {
    await _abrir(tester, defaultKey: 'G');

    expect(
      find.descendant(
        of: find.byType(MusicalKeyField),
        matching: find.byType(EditableText),
      ),
      findsNothing,
    );
  });

  testWidgets('escolher um tom menor na folha e salvar', (tester) async {
    final repositorio = await _abrir(tester, defaultKey: 'G');

    await tester.tap(_campo('Nosso tom'));
    await tester.pumpAndSettle();

    // O tom atual abre marcado, na barra do modo dele.
    expect(
      tester.getSemantics(find.bySemanticsLabel('G maior')),
      matchesSemantics(isButton: true, isSelected: true, hasSelectedState: true),
    );

    await tester.tap(find.text('Menor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('F#m'));
    await tester.pumpAndSettle();

    // Tocar no tom fecha a folha: a escolha já está feita.
    expect(find.text('Menor'), findsNothing);
    expect(
      find.descendant(of: _campo('Nosso tom'), matching: find.text('F#m')),
      findsOneWidget,
    );

    await _salvar(tester);
    expect(repositorio.enviado!['defaultKey'], 'F#m');
  });

  testWidgets('anotação antiga aparece e volta intacta ao servidor',
      (tester) async {
    final repositorio = await _abrir(tester, defaultKey: 'G (capo 2)');

    expect(find.text('G (capo 2)'), findsOneWidget);
    expect(find.textContaining('Tom salvo antes da lista'), findsOneWidget);

    await _salvar(tester);
    expect(repositorio.enviado!['defaultKey'], 'G (capo 2)');
  });

  testWidgets('anotação antiga: abrir a folha e fechar sem escolher não apaga',
      (tester) async {
    final repositorio = await _abrir(tester, defaultKey: 'G (capo 2)');

    await tester.tap(_campo('Nosso tom'));
    await tester.pumpAndSettle();
    // Nada na grade corresponde à anotação.
    expect(find.bySemanticsLabel('G maior'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('G maior')),
      matchesSemantics(isButton: true, hasSelectedState: true),
    );

    await tester.tapAt(const Offset(180, 20));
    await tester.pumpAndSettle();

    await _salvar(tester);
    expect(repositorio.enviado!['defaultKey'], 'G (capo 2)');
  });

  testWidgets('tirar o tom manda vazio, que o servidor grava como nulo',
      (tester) async {
    final repositorio = await _abrir(tester, defaultKey: 'A');

    await tester.tap(_campo('Nosso tom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limpar'));
    await tester.pumpAndSettle();

    await _salvar(tester);
    expect(repositorio.enviado!['defaultKey'], '');
  });

  testWidgets('"Usar F#" copia o tom da gravação', (tester) async {
    final repositorio = await _abrir(tester, originalKey: 'F#');

    await tester.tap(find.text('Usar F#'));
    await tester.pumpAndSettle();
    expect(find.text('Usar F#'), findsNothing);

    await _salvar(tester);
    expect(repositorio.enviado!['defaultKey'], 'F#');
    expect(repositorio.enviado!['originalKey'], 'F#');
  });

  testWidgets('tom digitado em minúscula é salvo na grafia da lista',
      (tester) async {
    final repositorio = await _abrir(tester, defaultKey: 'bm');

    expect(find.textContaining('Tom salvo antes da lista'), findsNothing);

    await _salvar(tester);
    expect(repositorio.enviado!['defaultKey'], 'Bm');
  });

  group('trazer de um link', () {
    const liberado = [
      ChordSourceInfo(id: 'cifraclub', name: 'Cifra Club', mode: 'IMPORT'),
    ];
    const link = 'https://www.cifraclub.com.br/banda/cristo-venceu/';

    Future<void> abrirDados(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Dados da música'));
      await tester.tap(find.text('Dados da música'));
      await tester.pumpAndSettle();
    }

    testWidgets('sem site liberado, o botão não aparece', (tester) async {
      await _abrir(
        tester,
        repositorioFake: _RepositorioFake(
          fontes: const [
            ChordSourceInfo(
              id: 'cifraclub',
              name: 'Cifra Club',
              mode: 'LINK_ONLY',
            ),
          ],
        ),
      );
      await abrirDados(tester);
      expect(find.text('Trazer de um link'), findsNothing);
    });

    testWidgets(
        'a cifra lida vai para o campo, com o tom; salvar declara a origem',
        (tester) async {
      final repo = _RepositorioFake(
        fontes: liberado,
        previa: const ChordPreview(
          sourceName: 'Cifra Club',
          sourceUrl: link,
          sheet: 'G       D\nCristo venceu',
          key: 'G',
          capo: 2,
          warnings: ['CAPO'],
        ),
      );
      await _abrir(tester, chordsUrl: link, repositorioFake: repo);
      await abrirDados(tester);

      final trazer = find.text('Trazer de um link');
      await tester.ensureVisible(trazer);
      await tester.tap(trazer);
      await tester.pumpAndSettle();
      // O link que a música já tinha vem preenchido.
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.widgetWithText(TextField, link),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Buscar cifra'));
      await tester.pumpAndSettle();
      expect(repo.linkPedido, link);
      expect(find.textContaining('capotraste na 2ª casa'), findsOneWidget);
      expect(find.text('Tom da cifra: G · Cifra Club'), findsOneWidget);

      final usar = find.text('Usar esta cifra');
      await tester.ensureVisible(usar);
      await tester.tap(usar);
      await tester.pumpAndSettle();
      expect(find.text('Como a cifra vai aparecer'), findsNothing);
      expect(find.text('[G]Cristo v[D]enceu'), findsOneWidget);

      final arranjo = find.text('Licença da fonte');
      await tester.ensureVisible(arranjo);
      await tester.tap(arranjo);
      final confirmo = find.byType(CheckboxListTile);
      await tester.ensureVisible(confirmo);
      await tester.tap(confirmo);
      await tester.pumpAndSettle();
      await _salvar(tester);

      expect(repo.enviado!['chords'], '[G]Cristo v[D]enceu');
      expect(repo.enviado!['chordsKey'], 'G');
      expect(repo.enviado!['chordsImport'], {
        'kind': 'URL',
        'sourceUrl': link,
        'rightsBasis': 'SOURCE_LICENSE',
        'rightsNote': '',
        'authorized': true,
      });
    });

    testWidgets('site que não entrega: guardar só o link', (tester) async {
      final repo = _RepositorioFake(
        fontes: liberado,
        erroPrevia: const ApiException(
          'O Cifra Club não entregou a cifra agora.',
          code: 'SOURCE_UNAVAILABLE',
        ),
      );
      await _abrir(tester, repositorioFake: repo);
      await abrirDados(tester);

      await tester.ensureVisible(find.text('Trazer de um link'));
      await tester.tap(find.text('Trazer de um link'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Link da cifra').last,
        link,
      );
      await tester.tap(find.text('Buscar cifra'));
      await tester.pumpAndSettle();
      expect(
        find.text('O Cifra Club não entregou a cifra agora.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Guardar o link'));
      await tester.pumpAndSettle();
      await _salvar(tester);
      expect(repo.enviado!['chordsUrl'], link);
      expect(repo.enviado, isNot(contains('chords')));
    });
  });

  group('colar e abrir no site', () {
    void areaDeTransferencia(WidgetTester tester, String? texto) {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return texto == null ? null : {'text': texto};
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
    }

    Future<void> abrirDados(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Dados da música'));
      await tester.tap(find.text('Dados da música'));
      await tester.pumpAndSettle();
    }

    String campoCifra(WidgetTester tester) => tester
        .widget<TextField>(find.widgetWithText(TextField, 'Cifra'))
        .controller!
        .text;

    testWidgets('"Colar cifra" põe no campo o que foi copiado, com as colunas',
        (tester) async {
      areaDeTransferencia(tester, '\n\n      G   D\nCanto aqui\n\n');
      await _abrir(tester, defaultKey: 'G');
      await abrirDados(tester);

      final colar = find.text('Colar cifra');
      await tester.ensureVisible(colar);
      await tester.tap(colar);
      await tester.pumpAndSettle();

      expect(campoCifra(tester), '      G   D\nCanto aqui');
      expect(find.text('Ver como fica'), findsOneWidget);
      expect(find.text('De onde vem esta cifra'), findsOneWidget);
    });

    testWidgets('área de transferência vazia avisa e não apaga o campo',
        (tester) async {
      areaDeTransferencia(tester, null);
      await _abrir(tester, chords: '[D]Canto', chordsKey: 'D');
      await abrirDados(tester);

      final colar = find.text('Colar cifra');
      await tester.ensureVisible(colar);
      await tester.tap(colar);
      await tester.pump();

      expect(find.textContaining('Nada copiado ainda'), findsOneWidget);
      expect(campoCifra(tester), '[D]Canto');
    });

    testWidgets('"Abrir no Cifra Club" só com o link da cifra', (tester) async {
      await _abrir(
        tester,
        chordsUrl: 'https://www.cifraclub.com.br/banda/cristo-venceu/',
      );
      await abrirDados(tester);
      expect(find.text('Abrir no Cifra Club'), findsOneWidget);

      final link = find.widgetWithText(TextField, 'Link da cifra');
      await tester.ensureVisible(link);
      await tester.enterText(link, 'https://www.exemplo.com/cifra/');
      await tester.pump();
      expect(find.text('Abrir no site'), findsOneWidget);

      await tester.enterText(link, '');
      await tester.pump();
      expect(find.text('Abrir no site'), findsNothing);
      expect(find.text('Abrir no Cifra Club'), findsNothing);
    });
  });
}
