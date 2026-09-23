import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_button_styles.dart';
import '../../../shared/widgets/app_detail_header.dart';
import '../../../shared/widgets/app_facts_strip.dart';
import '../../../shared/widgets/section_header.dart';
import '../../songs/data/song_repository.dart';
import '../../songs/presentation/lyrics_reader.dart';
import '../../songs/presentation/song_resources.dart';
import '../domain/event_models.dart';

/// A música aberta de dentro da escala: tom, recado, links e letra.
///
/// Folha e não navegação para a tela do repertório por dois motivos. O tom que
/// vale aqui é o **desta escala** (o `keyOverride`, quando existe), e a tela da
/// música mostra o tom da equipe — quem abrisse de dentro da escala leria o
/// número errado. E quem abre isto está de instrumento na mão, minutos antes de
/// tocar: fechar a folha devolve a escala exatamente como estava.
///
/// **Vale para MEMBER.** É justamente quem toca que precisa da cifra; o líder
/// já tem o caminho da edição.
///
/// **A mesma linguagem da tela da música.** A folha respondia à mesma pergunta
/// com outro desenho: links em etiquetas (só os que existiam), artista em texto
/// comum, tom num cartão grande. Agora é o cabeçalho, a faixa de fatos e os
/// quatro recursos da tela da música — numa versão compacta, e com o tom
/// **desta escala** no lugar do tom da equipe.
///
/// **E daqui se chega ao repertório** ([_RepertoireLink]). Perceber que a
/// música está sem cifra é o que mais acontece nesta folha, e consertar isso
/// custava sair da escala, abrir o repertório, procurar a música e abri-la de
/// novo — quatro passos para chegar a uma tela que já se sabia qual era.
///
/// [serviceSongs] são as músicas do mesmo culto, na ordem: a letra aberta
/// daqui passa para a próxima sem voltar à escala.
Future<void> showEventSongSheet({
  required BuildContext context,
  required String teamId,
  required EventSong song,
  List<EventSong>? serviceSongs,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EventSongSheet(
      teamId: teamId,
      song: song,
      serviceSongs: serviceSongs ?? [song],
    ),
  );
}

class _EventSongSheet extends ConsumerWidget {
  const _EventSongSheet({
    required this.teamId,
    required this.song,
    required this.serviceSongs,
  });

  final List<EventSong> serviceSongs;

  /// A equipe **da escala**, e não a equipe ativa: quem participa de duas veria
  /// a letra ser procurada no repertório errado.
  final String teamId;

  final EventSong song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final temTom = song.key?.isNotEmpty ?? false;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, controller) => ListView(
        controller: controller,
        // O recuo da barra de navegação entra no fim da lista: a folha vai até
        // a borda da tela, e sem isto as últimas linhas da letra ficavam por
        // baixo dos botões do sistema -- justamente no fim da música, que é
        // onde se está olhando quando ela acaba.
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          0,
          AppSpacing.screenPadding,
          AppSpacing.xxl + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppDetailHeader(
                  title: song.title,
                  badges: [
                    if (song.isNew)
                      const AppBadge(
                        label: 'Nova',
                        tone: AppTone.info,
                        semanticsLabel:
                            'Música nova: a equipe ainda não tocou esta',
                      ),
                  ],
                  overline: song.artist,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _RepertoireLink(teamId: teamId, songId: song.songId),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // Tom, momento e número do hino: o que se procura minutos antes de
          // tocar. O tom é o **desta escala**; quando ela mudou o da equipe, o
          // de costume aparece embaixo — quem decorou "sempre em G" precisa
          // ver que hoje é diferente.
          //
          // Só o que existe: "Tom — · Momento — · Hinário —" dizia ao músico
          // três vezes que ninguém preencheu nada, e o travessão no tom
          // parecia "toque em qualquer um".
          if (temTom || song.momentText != null || song.hymnal != null)
            AppFactsStrip(
              facts: [
                if (temTom)
                  AppFact(
                    icon: Icons.piano_rounded,
                    label: song.hasCustomKey ? 'Tom nesta escala' : 'Tom',
                    value: song.key!,
                    highlight: true,
                    wrapValue: true,
                    hint: song.hasCustomKey &&
                            (song.defaultKey?.isNotEmpty ?? false)
                        ? 'equipe: ${song.defaultKey}'
                        : null,
                  ),
                if (song.momentText != null)
                  AppFact(
                    icon: Icons.flag_outlined,
                    label: 'Momento',
                    value: song.momentText!,
                    wrapValue: true,
                  ),
                if (song.hymnal != null)
                  AppFact(
                    icon: Icons.menu_book_outlined,
                    label: 'Hinário',
                    value: song.hymnal!.label,
                  ),
              ],
            ),
          if (song.note?.isNotEmpty ?? false) ...[
            const SizedBox(height: AppSpacing.md),
            _NoteBand(note: song.note!),
          ],
          const SizedBox(height: AppSpacing.lg),
          // Os quatro, sempre, como na tela da música: "está sem cifra" é
          // justamente o que a equipe precisa ver para ir atrás dela. A letra
          // guardada aparece inteira logo abaixo; o ladrilho abre o site.
          //
          // **"Letra" abre a letra guardada, no app**, como na tela da música.
          // Aqui ela abria o site (com anúncios) mesmo com o texto guardado
          // logo abaixo — o mesmo rótulo com dois comportamentos. O site
          // continua a um toque, no topo da tela da letra. Só sem letra
          // guardada o ladrilho vai direto ao link.
          SongResourceRow(
            resources: songResources(
              context,
              chordsUrl: song.chordsUrl,
              lyricsUrl: song.lyricsUrl,
              youtubeUrl: song.youtubeUrl,
              spotifyUrl: song.spotifyUrl,
              onOpenLyrics: _semLetraGuardada(ref)
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => EventLyricsScreen(
                            teamId: teamId,
                            songs: serviceSongs,
                            initialIndex: serviceSongs
                                .indexWhere((s) => s.songId == song.songId)
                                .clamp(0, serviceSongs.length - 1),
                          ),
                        ),
                      ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          // A escala não carrega a letra -- são centenas de caracteres por
          // música e ela já é a tela mais pesada. Aqui a busca é de uma música
          // só, e só quando alguém abriu esta folha.
          _Lyrics(teamId: teamId, songId: song.songId),
        ],
      ),
    );
  }
}

extension on _EventSongSheet {
  /// A música já veio do servidor e não tem letra guardada: aí o ladrilho
  /// "Letra" vai ao site. Enquanto carrega, o palpite é que há letra — a tela
  /// da letra sabe esperar e dizer que não há.
  bool _semLetraGuardada(WidgetRef ref) {
    final full = ref
        .watch(songProvider((teamId: teamId, songId: song.songId)))
        .valueOrNull;
    return full != null && (full.lyrics?.trim().isEmpty ?? true);
  }
}

class _NoteBand extends StatelessWidget {
  const _NoteBand({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.sticky_note_2_outlined,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(note, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

/// A ponte para o repertório: a mesma música, na tela onde ela se cadastra.
///
/// **Um ícone ao lado do título**, e não um botão contornado de largura
/// inteira entre os links e a letra: ali ele pesava mais que a cifra, que é o
/// que a folha existe para abrir.
///
/// **Vai pelo id, nunca pelo nome.** A música da escala aponta para a do
/// repertório (`songId`), e procurar por título abriria a música errada nas
/// duas situações em que a equipe mais precisa dela: o repertório com duas
/// versões da mesma canção, e o título gravado com acento diferente.
///
/// A equipe é a **da escala**, e vai na consulta (`?equipe=`): quem serve em
/// duas equipes veria a música ser procurada no repertório da equipe ativa,
/// que não é a que ele está consultando.
///
/// Fecha a folha antes de navegar, e é isso que faz o botão "voltar" do
/// aparelho devolver a **escala** -- e não esta folha por cima dela.
///
/// O rótulo diz "Ver", e não "Editar": quem é MEMBER também chega aqui, e a
/// tela do repertório é que decide se mostra o lápis.
class _RepertoireLink extends StatelessWidget {
  const _RepertoireLink({required this.teamId, required this.songId});

  final String teamId;
  final String songId;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);

    // Ícone **com rótulo curto**: sozinho ele não dizia para onde levava
    // (WCAG 2.5.3), e continua pequeno o bastante para não pesar mais que a
    // cifra.
    return Tooltip(
      message: 'Ver no repertório',
      child: TextButton.icon(
        style: AppButtonStyles.compactText,
        icon: const Icon(Icons.library_music_outlined, size: 18),
        label: const Text('Repertório'),
        onPressed: () {
          navigator.pop();
          router.push('/equipe/musicas/$songId?equipe=$teamId');
        },
      ),
    );
  }
}

/// A letra guardada no banco.
///
/// Texto e não link: site de letra sai do ar, muda de endereço e não abre no
/// meio do culto com a internet da igreja.
class _Lyrics extends ConsumerWidget {
  const _Lyrics({required this.teamId, required this.songId});

  final String teamId;
  final String songId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final song = ref.watch(songProvider((teamId: teamId, songId: songId)));

    return song.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      // Falhar aqui não pode esconder o tom e a cifra, que já estão na tela e
      // vieram junto com a escala.
      error: (_, __) => Text(
        'Não foi possível carregar a letra agora.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      data: (value) {
        if (!value.hasLyrics) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Letra',
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
            ),
            SelectableText(
              value.lyrics!,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ],
        );
      },
    );
  }
}
