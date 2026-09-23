import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/responsive/adaptive_dialog.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_bottom_action_bar.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/form_scaffold.dart';
import '../data/song_repository.dart';
import '../domain/song_models.dart';
import 'song_theme_picker.dart';

/// Completa a música recém-criada com os links que a sugestão trouxe.
///
/// **Só o que ficou vazio.** O catálogo traz cifra e letra de verdade, e o
/// enriquecimento do Spotify vai ao CifraClub: sobrescrever com o link que
/// alguém colou no celular trocaria o melhor pelo aproximado. E o que
/// chegou como "letra ou cifra" — um campo só na sugestão, porque perguntar
/// qual dos dois é cobrar uma classificação que não muda nada para quem
/// sugere — cai na coluna que o próprio endereço denuncia.
///
/// Um PATCH a mais, e não campos no POST, porque as portas de cadastro têm
/// corpos diferentes: aqui a regra é uma só para todas — inclusive o aceite
/// direto da sugestão que já veio do Spotify.
Future<Song> applySuggestedLinks(
  SongRepository repository,
  String teamId,
  Song song, {
  String? lyricsUrl,
  String? youtubeUrl,
  String? spotifyUrl,
}) async {
  final colado = lyricsUrl?.trim() ?? '';
  final letraOuCifra = colado.isEmpty ? null : colado;
  final ehCifra = letraOuCifra != null && _pareceCifra(letraOuCifra);

  final patch = <String, dynamic>{
    if (ehCifra && (song.chordsUrl ?? '').isEmpty) 'chordsUrl': letraOuCifra,
    if (letraOuCifra != null && !ehCifra && (song.lyricsUrl ?? '').isEmpty)
      'lyricsUrl': letraOuCifra,
    if ((youtubeUrl ?? '').isNotEmpty && (song.youtubeUrl ?? '').isEmpty)
      'youtubeUrl': youtubeUrl!.trim(),
    if ((spotifyUrl ?? '').isNotEmpty && (song.spotifyUrl ?? '').isEmpty)
      'spotifyUrl': spotifyUrl!.trim(),
  };
  if (patch.isEmpty) return song;

  try {
    return await repository.update(teamId, song.id, patch);
  } on ApiException {
    // A música já existe, e é isso que o líder veio fazer. Um link recusado
    // (endereço torto digitado por quem sugeriu) não pode desfazer o
    // cadastro nem virar erro numa tela que deu certo — ele se completa na
    // edição.
    return song;
  }
}

/// Site de cifra ou site de letra. Heurística curta de propósito: errar aqui
/// põe o link na outra coluna da mesma tela, e o líder corrige num toque.
bool _pareceCifra(String url) {
  final endereco = url.toLowerCase();
  return endereco.contains('cifraclub') ||
      endereco.contains('cifras') ||
      endereco.contains('cifra');
}

/// Adicionar música: uma caixa de busca, duas fontes.
///
/// Primeiro o que outras equipes já cadastraram — é instantâneo, não gasta
/// chamada externa e **vem com letra**, que é o que nenhuma API entrega.
/// Depois o Spotify, para o que ninguém tem ainda.
///
/// A pessoa escolhe: título sozinho é ambíguo ("Aleluia" existe em cinco
/// versões) e casar automaticamente erraria calado.
class AddSongScreen extends ConsumerStatefulWidget {
  const AddSongScreen({
    super.key,
    required this.teamId,
    this.onCreated,
    this.initialSearch,
    this.initialArtist,
    this.initialLyricsUrl,
    this.initialYoutubeUrl,
    this.initialSpotifyUrl,
  });

  final String teamId;

  /// O que já se sabe do nome da música.
  ///
  /// Preenchido quando esta tela é aberta a partir de uma sugestão da equipe:
  /// o nome já foi digitado uma vez por quem sugeriu, e obrigar o líder a
  /// digitá-lo de novo seria trabalho repetido. A busca dispara sozinha.
  final String? initialSearch;

  /// O resto do que a sugestão trouxe.
  ///
  /// Quem sugeriu já mandou artista e links — o servidor até **exige** o link
  /// da letra ou da cifra de música que não está no repertório. Pedir tudo de
  /// novo ao líder é o tipo de trabalho repetido que faz a sugestão ficar para
  /// depois e nunca ser respondida.
  ///
  /// Vale nas três portas de cadastro: o que o catálogo ou o Spotify já
  /// trouxerem manda, e estes preenchem só o que ficou vazio (ver
  /// [applySuggestedLinks]).
  final String? initialArtist;
  final String? initialLyricsUrl;
  final String? initialYoutubeUrl;
  final String? initialSpotifyUrl;

  /// O que fazer com a música recém-criada.
  ///
  /// Nulo no caminho normal (`Equipe → Repertório → Nova`): abre a música
  /// criada, que é o que se quer ao cadastrar por cadastrar. Preenchido quando
  /// esta tela é aberta de dentro da montagem de uma escala, onde ir para o
  /// detalhe da música abandonaria a escala pela metade -- ali a música volta
  /// para quem pediu e entra direto no culto.
  final ValueChanged<Song>? onCreated;

  @override
  ConsumerState<AddSongScreen> createState() => _AddSongScreenState();
}

class _AddSongScreenState extends ConsumerState<AddSongScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  List<CatalogCandidate> _catalog = [];
  List<ExternalCandidate> _external = [];
  bool _searching = false;
  bool _adding = false;
  bool _searched = false;
  String? _error;

  /// Se a equipe vai **aprender** esta música.
  ///
  /// Nasce ligado: quem abre esta tela quase sempre está atrás de uma canção
  /// que a equipe ainda não canta — é essa a razão de procurar. Quem está
  /// cadastrando o acervo antigo desliga uma vez e a escolha vale para as
  /// próximas desta sessão, que é como o cadastro em lote acontece.
  bool _isNew = true;

  /// Os temas que vão junto com a música escolhida.
  ///
  /// Como o `_isNew`: valem para a próxima que for adicionada e continuam
  /// valendo para as seguintes desta sessão. Quem está cadastrando o repertório
  /// de Natal adiciona seis músicas seguidas com o mesmo tema, e remarcar a
  /// cada uma seria trabalho repetido sem razão.
  ///
  /// Numa música vinda do catálogo eles **se somam** aos que a outra equipe já
  /// tinha classificado; numa vinda do Spotify são os únicos que existem, já
  /// que nenhum serviço externo lê letra.
  Set<String> _themes = {};

  @override
  void initState() {
    super.initState();
    final inicial = widget.initialSearch?.trim() ?? '';
    if (inicial.length >= 2) {
      _controller.text = inicial;
      // Sem esperar o debounce: o termo não foi digitado agora, já está certo.
      WidgetsBinding.instance.addPostFrameCallback((_) => _search(inicial));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _catalog = [];
        _external = [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(value));
  }

  Future<void> _search(String term) async {
    setState(() {
      _searching = true;
      _error = null;
    });

    final repository = ref.read(songRepositoryProvider);

    try {
      // As duas juntas: uma é local e a outra sai para o Spotify, e esperar
      // em fila dobraria o tempo à toa.
      final results = await Future.wait([
        repository.catalog(widget.teamId, term),
        repository.searchExternal(widget.teamId, term),
      ]);

      if (!mounted) return;
      setState(() {
        _catalog = results[0] as List<CatalogCandidate>;
        _external = results[1] as List<ExternalCandidate>;
        _searched = true;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(Future<Song> Function() create) async {
    setState(() {
      _adding = true;
      _error = null;
    });

    try {
      var song = await create();
      song = await applySuggestedLinks(
        ref.read(songRepositoryProvider),
        widget.teamId,
        song,
        lyricsUrl: widget.initialLyricsUrl,
        youtubeUrl: widget.initialYoutubeUrl,
        spotifyUrl: widget.initialSpotifyUrl,
      );
      if (!mounted) return;

      // A lista do repertório precisa enxergar a música nova: quem volta para
      // ela (ou para o seletor da escala) procuraria por algo que a resposta
      // em cache não tem. A família inteira, porque a lista de trás está com
      // os filtros que a pessoa deixou ligados.
      ref.invalidate(songCatalogProvider);
      // A música nasce marcada como nova com frequência, e o cartão da Home
      // precisa enxergá-la.
      ref.invalidate(learningSongsProvider(widget.teamId));

      showAppSnackBar(
        context,
        '"${song.title}" entrou no repertório.',
        tone: AppTone.success,
      );

      final onCreated = widget.onCreated;
      if (onCreated != null) {
        onCreated(song);
        return;
      }
      context.pushReplacement('/equipe/musicas/${song.id}');
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// Porta de saída quando a música não existe nem no catálogo nem no
  /// Spotify. O backend sempre aceitou cadastro manual, mas a interface só
  /// expunha as duas buscas — numa equipe nova, sem catálogo e sem credenciais
  /// do Spotify, era impossível cadastrar a primeira música.
  Future<void> _addManual() async {
    final draft = await showAdaptiveSheet<_ManualSongDraft>(
      context: context,
      maxWidth: 480,
      builder: (_) => _ManualSongSheet(
        initialTitle: _controller.text.trim(),
        initialArtist: widget.initialArtist,
      ),
    );
    if (draft == null || !mounted) return;

    final repository = ref.read(songRepositoryProvider);
    await _add(
      () => repository.create(
        widget.teamId,
        {
          'title': draft.title,
          if (draft.artist != null) 'artist': draft.artist,
          'isNew': _isNew,
          if (_themes.isNotEmpty) 'themes': _themes.toList(),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.read(songRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar música')),
      // "Música nova" e os temas valem para a música que for escolhida, e por
      // isso moram no rodapé: acima dos resultados eles vinham antes da
      // própria busca — a primeira coisa da tela era um interruptor sobre uma
      // música que ainda não existia. No rodapé ficam parados (a tela não
      // pula enquanto se digita) e à mão na hora de escolher.
      bottomNavigationBar: _adding
          ? null
          : AppBottomActionBar(
              // Material transparente: a barra tem cor própria, e sem um
              // Material entre ela e o interruptor o respingo do toque não
              // aparece.
              action: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      value: _isNew,
                      onChanged: (v) => setState(() => _isNew = v),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Entra como música nova'),
                    ),
                    SongThemeStrip(
                      themes: _themes,
                      onChanged: (themes) => setState(() => _themes = themes),
                    ),
                  ],
                ),
              ),
            ),
      body: SafeArea(
        top: false,
        child: AppContentWidth.reading(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                child: TextField(
                  controller: _controller,
                  onChanged: _onChanged,
                  autofocus: true,
                  enabled: !_adding,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Nome da música e artista',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPadding,
                  ),
                  child: FormErrorBanner(message: _error!),
                ),
              Expanded(
                child: _adding
                    ? const AppLoading(
                        message: 'Procurando a cifra, a letra e o tom.\n'
                            'Pode levar alguns segundos.',
                      )
                    : _Results(
                        catalog: _catalog,
                        external: _external,
                        searched: _searched,
                        onManual: _addManual,
                        onPickCatalog: (c) => _add(
                          () => repository.copyFromCatalog(
                            widget.teamId,
                            c.sourceSongId,
                            isNew: _isNew,
                            themes: _themes,
                          ),
                        ),
                        onPickExternal: (c) => _add(
                          () => repository.createFromExternal(
                            widget.teamId,
                            c,
                            isNew: _isNew,
                            themes: _themes,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.catalog,
    required this.external,
    required this.searched,
    required this.onManual,
    required this.onPickCatalog,
    required this.onPickExternal,
  });

  final List<CatalogCandidate> catalog;
  final List<ExternalCandidate> external;
  final bool searched;
  final VoidCallback onManual;
  final ValueChanged<CatalogCandidate> onPickCatalog;
  final ValueChanged<ExternalCandidate> onPickExternal;

  @override
  Widget build(BuildContext context) {
    if (!searched) {
      return const AppEmptyState(
        icon: Icons.search_rounded,
        title: 'Procure a música',
        message: 'Digite o nome e, se souber, o artista. Buscamos no que '
            'outras equipes já cadastraram e no Spotify.',
      );
    }

    if (catalog.isEmpty && external.isEmpty) {
      return AppEmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nada encontrado',
        message: 'Tente escrever o artista junto ou cadastre esta versão '
            'manualmente.',
        actionLabel: 'Cadastrar manualmente',
        onAction: onManual,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        0,
        AppSpacing.screenPadding,
        AppSpacing.xxl,
      ),
      children: [
        // Linhas agrupadas, como a lista do repertório: cada resultado era um
        // cartão com borda, e dezesseis cartões são uma pilha de caixinhas.
        if (catalog.isNotEmpty) ...[
          AppGroup(
            title: 'Já cadastrada por outra equipe',
            subtitle: 'Vem completa, inclusive a letra',
            dividerIndent: AppGroup.iconIndent,
            children: [
              for (final item in catalog)
                _CatalogTile(item: item, onTap: () => onPickCatalog(item)),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        if (external.isNotEmpty)
          AppGroup(
            title: 'Spotify',
            // O que o cadastro faz de verdade: cifra e letra vêm do
            // CifraClub/Letras, o vídeo do YouTube. O tom **de vocês** nenhum
            // serviço sabe — o da gravação entra só como referência.
            subtitle: 'Ao adicionar, buscamos a cifra, a letra e o vídeo. O '
                'tom de vocês fica para a edição.',
            dividerIndent: AppGroup.iconIndent,
            children: [
              for (final item in external)
                _ExternalTile(item: item, onTap: () => onPickExternal(item)),
            ],
          ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onManual,
            icon: const Icon(Icons.edit_note_rounded, size: 18),
            label: const Text('Não achou? Cadastrar manualmente'),
          ),
        ),
      ],
    );
  }
}

class _ManualSongDraft {
  const _ManualSongDraft({required this.title, this.artist});

  final String title;
  final String? artist;
}

/// Cadastro mínimo. O restante continua na edição em duas camadas: aqui só se
/// pede o que identifica a música, para não transformar a saída de emergência
/// da busca num formulário de doze campos.
class _ManualSongSheet extends StatefulWidget {
  const _ManualSongSheet({required this.initialTitle, this.initialArtist});

  final String initialTitle;

  /// Vem da sugestão que se está acolhendo, quando há uma.
  final String? initialArtist;

  @override
  State<_ManualSongSheet> createState() => _ManualSongSheetState();
}

class _ManualSongSheetState extends State<_ManualSongSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title =
      TextEditingController(text: widget.initialTitle);
  late final TextEditingController _artist =
      TextEditingController(text: widget.initialArtist ?? '');

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final artist = _artist.text.trim();
    Navigator.of(context).pop(
      _ManualSongDraft(
        title: _title.text.trim(),
        artist: artist.isEmpty ? null : artist,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Cadastrar manualmente',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Informe só o que identifica a música. Tom, letra e links '
                'podem ser completados depois.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _title,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Nome da música'),
                validator: (value) => value == null || value.trim().length < 2
                    ? 'Informe o nome da música.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _artist,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Artista (opcional)',
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppSubmitButton(
                label: 'Cadastrar',
                loading: false,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({required this.item, required this.onTap});

  final CatalogCandidate item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final traz = [
      if (item.hasLyrics) 'letra',
      if (item.hasChords) 'cifra',
      if (item.originalKey != null) 'tom ${item.originalKey}',
      if (item.hasYoutube) 'YouTube',
      if (item.hasSpotify) 'Spotify',
    ];

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(Icons.library_add_check_outlined, color: scheme.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: theme.textTheme.titleSmall),
                  Text(
                    item.artist ?? 'Sem artista',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (traz.isNotEmpty)
                    Text(
                      'Traz ${traz.join(', ')}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.add_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _ExternalTile extends StatelessWidget {
  const _ExternalTile({required this.item, required this.onTap});

  final ExternalCandidate item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(Icons.headphones_rounded, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    [item.artist, if (item.year != null) item.year!]
                        .where((e) => e.isNotEmpty)
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.add_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
