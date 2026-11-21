import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:louvor_app/core/storage/read_cache.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:louvor_app/features/events/presentation/event_song_sheet.dart';
import 'package:louvor_app/features/songs/data/song_repository.dart';
import 'package:louvor_app/features/songs/domain/song_models.dart';

/// O caminho da música da escala até o repertório.
///
/// Perceber que a música está sem cifra é o que mais acontece na folha aberta
/// de dentro da escala. Consertar isso custava sair da escala, abrir o
/// repertório, procurar a música e abri-la de novo — quatro passos até uma tela
/// que já se sabia qual era.
///
/// Duas coisas se protegem aqui: o caminho vai pelo **id** (procurar pelo nome
/// abriria a música errada num repertório com duas versões da mesma canção) e
/// leva a **equipe da escala**, que não é necessariamente a equipe ativa de
/// quem serve em duas.
void main() {
  testWidgets('leva ao repertório pelo id da música e pela equipe da escala',
      (tester) async {
    final rota = await _abrirEToqueNoAtalho(tester);

    expect(rota, '/equipe/musicas/mus-1?equipe=t-da-escala');
  });

  testWidgets('a folha fecha antes de navegar, e o voltar devolve a escala',
      (tester) async {
    await _abrirEToqueNoAtalho(tester);

    // A folha não pode continuar empilhada embaixo: voltar do repertório
    // levaria de volta a ela, e não à escala que estava sendo consultada.
    expect(find.text('Meu Deus, meu Rei'), findsNothing);
    expect(find.text('repertório de mus-1'), findsOneWidget);

    final context = tester.element(find.text('repertório de mus-1'));
    GoRouter.of(context).pop();
    await tester.pumpAndSettle();

    expect(find.text('a escala'), findsOneWidget);
  });

  testWidgets('Cifra na folha abre o leitor no tom da escala', (tester) async {
    await _abrirFolha(tester, chords: '[G/B]Canto');
    expect(find.text('Canto'), findsNothing);
    await tester.tap(find.text('Cifra'));
    await tester.pumpAndSettle();
    expect(find.text('D/F#'), findsOneWidget);
  });

  testWidgets('MEMBER também tem o caminho, e ele diz "Ver"', (tester) async {
    await _abrirFolha(tester);

    // "Editar no repertório" prometeria a quem é MEMBER uma edição que a tela
    // do repertório não oferece.
    expect(find.byTooltip('Ver no repertório'), findsOneWidget);
    expect(find.textContaining('Editar'), findsNothing);
    expect(find.byTooltip('Editar no repertório'), findsNothing);
  });
}

const _song = EventSong(
  songId: 'mus-1',
  serviceId: 's1',
  title: 'Meu Deus, meu Rei',
  key: 'G',
);

Future<String?> _abrirEToqueNoAtalho(WidgetTester tester) async {
  final rotas = await _abrirFolha(tester);

  await tester.tap(find.byTooltip('Ver no repertório'));
  await tester.pumpAndSettle();

  return rotas.last;
}

Future<List<String>> _abrirFolha(WidgetTester tester, {String? chords}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final rotas = <String>[];

  final router = GoRouter(
    initialLocation: '/agenda/e1',
    routes: [
      GoRoute(
        path: '/agenda/:id',
        builder: (_, __) => const _EscalaFalsa(),
      ),
      GoRoute(
        path: '/equipe/musicas/:songId',
        builder: (_, state) {
          rotas.add(state.uri.toString());
          return Scaffold(
            body: Text('repertório de ${state.pathParameters['songId']}'),
          );
        },
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // A letra é buscada só quando alguém abre a folha; aqui ela vem sem
        // letra, que é justamente o caso em que o atalho existe.
        songProvider.overrideWith(
          (ref, args) async => CachedValue(
            fromCache: false,
            data: Song.fromJson({
              'id': args.songId,
              'teamId': args.teamId,
              'chords': chords,
              'chordsKey': chords == null ? null : 'C',
              'title': 'Meu Deus, meu Rei',
            }),
          ),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('abrir a música'));
  await tester.pumpAndSettle();

  return rotas;
}

/// A escala por baixo da folha, reduzida ao que importa: o botão que abre a
/// música e um texto para conferir que o "voltar" chegou aqui.
class _EscalaFalsa extends StatelessWidget {
  const _EscalaFalsa();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('a escala'),
            TextButton(
              onPressed: () => showEventSongSheet(
                context: context,
                // A equipe **da escala**, e não a ativa.
                teamId: 't-da-escala',
                song: _song,
              ),
              child: const Text('abrir a música'),
            ),
          ],
        ),
      ),
    );
  }
}
