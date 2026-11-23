import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/responsive/adaptive_dialog.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/form_scaffold.dart';
import '../../../shared/widgets/open_link.dart';
import '../../../shared/domain/person_fields.dart';
import '../../../shared/widgets/unsaved_changes_guard.dart';
import '../../events/domain/setlist_duration.dart';
import '../data/song_repository.dart';
import '../domain/chord_sheet.dart';
import '../domain/hymnal_models.dart';
import '../domain/musical_keys.dart';
import '../domain/song_models.dart';
import '../domain/song_themes.dart';
import '../domain/chord_import.dart';
import 'chord_import_sheet.dart';
import 'hymnal_refs_field.dart';
import 'lyrics_reader.dart';
import 'musical_key_picker.dart';
import 'song_theme_picker.dart';

/// Edição de uma música, em duas camadas.
///
/// Em cima, **o que a equipe decide** e nenhuma API responde: em que tom ELA
/// canta, se é hino ou cântico, se é calma ou agitada. É o trabalho de toda
/// semana e abre expandido.
///
/// Embaixo, recolhido, **o que veio de fora**: artista, compositor, os quatro
/// links, o tom da gravação e a letra. Vêm do import e do enriquecimento, que
/// acertam a maioria — deixá-los à vista faria a tela parecer um formulário de
/// doze campos por preencher, quando o normal é não tocar em nenhum. Mas quando
/// o enriquecimento erra ou não acha, este é o único caminho para corrigir sem
/// mexer no banco.
class SongFormScreen extends ConsumerStatefulWidget {
  const SongFormScreen({
    super.key,
    required this.teamId,
    required this.songId,
    this.song,
  });

  final String teamId;
  final String songId;

  /// Vem por `extra` quando a navegação parte do detalhe -- evita uma segunda
  /// ida ao servidor para preencher o formulário.
  final Song? song;

  @override
  ConsumerState<SongFormScreen> createState() => _SongFormScreenState();
}

class _SongFormScreenState extends ConsumerState<SongFormScreen>
    with UnsavedChangesTracker {
  final _title = TextEditingController();
  final _duration = TextEditingController();
  final _artist = TextEditingController();
  final _composer = TextEditingController();
  final _chords = TextEditingController();
  final _lyrics = TextEditingController();
  final _lyricsUrl = TextEditingController();
  final _chordsUrl = TextEditingController();
  final _youtubeUrl = TextEditingController();
  final _spotifyUrl = TextEditingController();
  final _rightsNote = TextEditingController();

  /// Nulo é "sem tom". Pode ser anotação de antes da lista ("G (capo 2)"):
  /// ela volta ao servidor intacta enquanto ninguém escolher outro tom.
  String? _defaultKey;
  String? _originalKey;
  String? _chordsKey;

  /// A declaração da cifra nova. Fora da assinatura de alterações: sozinha,
  /// sem cifra nova, não há o que salvar.
  String? _rightsBasis;
  bool _rightsAuthorized = false;

  /// O link de onde "Trazer de um link" leu a cifra que está no campo. Vai na
  /// declaração como `URL`; sem ele, a cifra foi colada.
  String? _importedFrom;
  String? _kind;
  String? _pace;
  Set<String> _themes = {};
  List<HymnalRef> _hymnals = const [];
  bool _isNew = false;
  bool _populated = false;
  bool _saving = false;
  String? _error;

  /// Só abre quando alguém pede. Ver o grupo fechado é a informação de que
  /// aquilo já está resolvido.
  bool _showExternal = false;

  @override
  void dispose() {
    for (final controller in [
      _title,
      _duration,
      _artist,
      _composer,
      _lyrics,
      _chords,
      _lyricsUrl,
      _chordsUrl,
      _youtubeUrl,
      _spotifyUrl,
      _rightsNote,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _populate(Song song) {
    _populated = true;
    _title.text = song.title;
    _defaultKey = _keyOrNull(song.defaultKey);
    _kind = song.kind;
    _pace = song.pace;
    if (song.durationSeconds case final seconds?) {
      _duration.text = formatDuration(seconds);
    }
    _themes = {...song.themes};
    _hymnals = [...song.hymnals];
    _isNew = song.isNew;
    _artist.text = song.artist ?? '';
    _composer.text = song.composer ?? '';
    _originalKey = _keyOrNull(song.originalKey);
    _chords.text = song.chords ?? '';
    _chordsKey = _keyOrNull(song.chordsKey);
    _lyrics.text = song.lyrics ?? '';
    _lyricsUrl.text = song.lyricsUrl ?? '';
    _chordsUrl.text = song.chordsUrl ?? '';
    _youtubeUrl.text = song.youtubeUrl ?? '';
    _spotifyUrl.text = song.spotifyUrl ?? '';
  }

  @override
  String unsavedSignature() => [
        for (final c in [
          _title,
          _duration,
          _artist,
          _composer,
          _lyrics,
          _lyricsUrl,
          _chordsUrl,
          _youtubeUrl,
          _spotifyUrl,
        ])
          c.text.trim(),
        _chords.text,
        _chordsKey,
        _defaultKey,
        _originalKey,
        _kind,
        _pace,
        (_themes.toList()..sort()).join(','),
        [for (final h in _hymnals) '${h.hymnalId}:${h.number}:${h.isPrimary}']
            .join(','),
        _isNew,
      ].join('\n');

  /// A grafia da lista quando dá (`g` vira `G`); o texto como está quando não
  /// dá; nulo quando não há nada.
  static String? _keyOrNull(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    return normalizeMusicalKey(value) ?? value;
  }

  Future<void> _save(Song song) async {
    final title = _title.text.trim();
    if (title.length < 2) {
      setState(() => _error = 'Informe o nome da música.');
      return;
    }

    final duration = _duration.text.trim();
    int? durationSeconds;
    if (duration.isNotEmpty) {
      final match = RegExp(r'^(\d{1,2}):([0-5]\d)$').firstMatch(duration);
      if (match == null) {
        setState(() => _error = 'Informe a duração em m:ss, por exemplo 4:30.');
        return;
      }
      durationSeconds = int.parse(match[1]!) * 60 + int.parse(match[2]!);
      if (durationSeconds < 10 || durationSeconds > 3600) {
        setState(() => _error = 'Informe uma duração entre 0:10 e 60:00.');
        return;
      }
    }

    final raw = _chords.text;
    final savedChords = song.hasChords ? song.chords : null;
    final chords = raw.trim().isEmpty
        ? null
        : raw == savedChords
            ? savedChords
            : normalizeChordSheet(raw);
    final chordsKey = chords == null && savedChords != null ? null : _chordsKey;
    final missingKey = normalizeMusicalKey(chordsKey) == null;
    if (chords != null &&
        (missingKey || chords.runes.length > maxChordSheetLength)) {
      setState(() {
        _showExternal = true;
        _error = missingKey
            ? 'Escolha o tom em que a cifra foi escrita.'
            : 'A cifra pode ter até 30 mil caracteres depois da conversão.';
      });
      return;
    }
    final newChords = chords != null && chords != savedChords;
    if (newChords && (_rightsBasis == null || !_rightsAuthorized)) {
      setState(() {
        _showExternal = true;
        _error =
            'Diga de onde vem a cifra e confirme que a equipe pode guardá-la.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(songRepositoryProvider).update(
        widget.teamId,
        widget.songId,
        {
          'title': title,
          // String vazia vira null no backend: o campo volta a "não decidido".
          'defaultKey': _defaultKey ?? '',
          'kind': _kind,
          'pace': _pace,
          'durationSeconds': durationSeconds,
          // Sempre enviado, inclusive vazio: `[]` é o que limpa a
          // classificação, e omitir o campo significaria "não mexi nele" — a
          // pessoa que tirou a última etiqueta não conseguiria salvar isso.
          'themes': _themes.toList(),
          'isNew': _isNew,
          // Sempre enviada, inclusive vazia: `[]` é o que apaga a última
          // referência, e omitir o campo significaria "não mexi nele" — quem
          // tirou o hinário errado não conseguiria salvar isso.
          'hymnals': [for (final ref in _hymnals) ref.toJson()],
          'artist': _artist.text.trim(),
          'composer': _composer.text.trim(),
          'originalKey': _originalKey ?? '',
          'lyricsUrl': _lyricsUrl.text.trim(),
          'chordsUrl': _chordsUrl.text.trim(),
          'youtubeUrl': _youtubeUrl.text.trim(),
          'spotifyUrl': _spotifyUrl.text.trim(),
          // Os textos longos só vão quando mudam.
          if (chords != savedChords) 'chords': chords,
          if (newChords)
            'chordsImport': {
              'kind': _importedFrom == null ? 'TEXT' : 'URL',
              if (_importedFrom != null) 'sourceUrl': _importedFrom,
              'rightsBasis': _rightsBasis,
              'rightsNote': _rightsNote.text.trim(),
              'authorized': true,
            },
          if (chordsKey != song.chordsKey) 'chordsKey': chordsKey,
          if (_lyrics.text != (song.lyrics ?? ''))
            'lyrics': _lyrics.text.trim(),
        },
      );

      ref.invalidate(
        songProvider((teamId: widget.teamId, songId: widget.songId)),
      );
      // A família inteira, e não a consulta sem filtro.
      //
      // A lista que ficou embaixo desta tela tem os filtros que a pessoa
      // deixou ligados — uma aba, uma busca, temas marcados —, e é ELA que
      // precisa se refazer. Invalidar só `SongQuery(teamId)` acertava uma
      // consulta que ninguém estava olhando: a tela continuava com o valor
      // antigo até alguém puxar para atualizar, e com o filtro por tema isso
      // fica pior, porque a música pode ter acabado de sair (ou entrar) no
      // critério que está na tela.
      ref.invalidate(songCatalogProvider);
      // Desmarcar "nova" aqui tira a música do cartão "Estamos aprendendo",
      // e a Home continua viva embaixo desta pilha.
      ref.invalidate(learningSongsProvider(widget.teamId));
      if (mounted) {
        markSaved();
        context.pop();
        showAppSnackBar(context, '"$title" foi salva.', tone: AppTone.success);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Cola a cifra que a pessoa copiou no site. É o caminho da cifra que o
  /// Pauta não traz sozinho: quem abre a página é o navegador dela.
  Future<void> _pasteChords() async {
    String? copied;
    var unreadable = false;
    try {
      copied = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (_) {
      // O navegador pode negar a leitura; colar no campo continua valendo.
      unreadable = true;
    }
    if (!mounted) return;
    // Só as linhas vazias do começo saem: o espaço antes do primeiro acorde
    // é a coluna dele.
    final text =
        (copied ?? '').replaceFirst(RegExp(r'^(?:[ \t]*\r?\n)+'), '').trimRight();
    if (text.trim().isEmpty) {
      showAppSnackBar(
        context,
        unreadable
            ? 'Não foi possível ler o que você copiou. Toque no campo Cifra e '
                'cole por lá.'
            : 'Nada copiado ainda. Copie a cifra no site e toque em "Colar '
                'cifra" de novo.',
      );
      return;
    }
    setState(() {
      _chords.text = text;
      _importedFrom = null;
      _error = null;
    });
  }

  /// Lê a cifra de um link e põe no campo, sem salvar: a pessoa confere,
  /// corrige e declara de onde ela veio antes de "Salvar".
  Future<void> _importChords(List<ChordSourceInfo> sources) async {
    final result = await showAdaptiveSheet<ChordImportResult>(
      context: context,
      builder: (_) => ChordImportSheet(
        teamId: widget.teamId,
        songId: widget.songId,
        sources: sources,
        initialUrl: _chordsUrl.text.trim(),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _error = null;
      if (result.preview case final preview?) {
        _chords.text = normalizeChordSheet(preview.sheet);
        _chordsKey = normalizeMusicalKey(preview.key) ?? _chordsKey;
        _importedFrom = preview.sourceUrl;
        if (_chordsUrl.text.trim().isEmpty) _chordsUrl.text = preview.sourceUrl;
        // Cifra nova, declaração nova.
        _rightsBasis = null;
        _rightsAuthorized = false;
      } else if (result.keepLink case final link? when link.isNotEmpty) {
        _chordsUrl.text = link;
      }
    });
  }

  /// A cifra como vai aparecer para a equipe, antes de salvar.
  void _previewChords() {
    final key = _chordsKey ?? chordSheetKey(_chords.text);
    final sheet = normalizeChordSheet(_chords.text);
    showAdaptiveSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            0,
            AppSpacing.screenPadding,
            AppSpacing.xl,
          ),
          // Largura cheia: sem ela a folha encolhe até a linha mais longa.
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Como a cifra vai aparecer',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                ChordSheetView(chords: sheet, sourceKey: key, targetKey: key),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song ??
        ref
            .watch(
              songProvider((teamId: widget.teamId, songId: widget.songId)),
            )
            .valueOrNull
            ?.data;

    if (song == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Editar música')),
        body: const AppLoading(),
      );
    }

    if (!_populated) _populate(song);
    markUnsavedBaseline();
    final recordingKey = normalizeMusicalKey(song.originalKey);
    final hasChordsText = _chords.text.trim().isNotEmpty;
    final chordsChanged =
        hasChordsText && _chords.text != (song.hasChords ? song.chords : null);
    final origin = song.hasChords ? song.chordsSource : null;
    final chordSources =
        ref.watch(chordSourcesProvider(widget.teamId)).valueOrNull ?? const [];

    return FormScaffold(
      isDirty: hasUnsavedChanges,
      // Sem o nome da música no corpo: ele já é o primeiro campo, logo
      // abaixo, e repeti-lo em título grande empurrava o formulário para
      // baixo com a mesma palavra duas vezes.
      appBar: AppBar(title: const Text('Editar música')),
      // Preso embaixo: com "Dados da música" aberto (quatro links e a letra),
      // o botão ficava duas telas abaixo de onde a pessoa mexeu.
      bottomAction: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) FormErrorBanner(message: _error!),
          AppSubmitButton(
            label: 'Salvar',
            loading: _saving,
            onPressed: () => _save(song),
          ),
        ],
      ),
      children: [
        TextField(
          controller: _title,
          enabled: !_saving,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nome da música'),
        ),
        const SizedBox(height: AppSpacing.lg),
        MusicalKeyField(
          label: 'Nosso tom',
          value: _defaultKey,
          enabled: !_saving,
          helperText: song.originalKey != null
              ? 'A gravação está em ${song.originalKey}'
              : null,
          onChanged: (key) => setState(() => _defaultKey = key),
        ),
        // Só oferece o que a lista aceita: copiar uma anotação livre do tom da
        // gravação traria de volta o texto livre por outra porta.
        if (_defaultKey == null && recordingKey != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              avatar: const Icon(Icons.content_copy_rounded, size: 16),
              label: Text('Usar $recordingKey'),
              onPressed: _saving
                  ? null
                  : () => setState(() => _defaultKey = recordingKey),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        _ChipField(
          label: 'Tipo',
          value: _kind,
          options: const {'HYMN': 'Hino', 'SONG': 'Cântico'},
          onChanged: _saving ? null : (v) => setState(() => _kind = v),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _ChipField(
                label: 'Andamento',
                value: _pace,
                options: const {
                  'CALM': 'Calma',
                  'MODERATE': 'Moderada',
                  'UPBEAT': 'Agitada',
                },
                hint: song.bpm != null ? 'A gravação tem ${song.bpm} bpm' : null,
                onChanged: _saving ? null : (v) => setState(() => _pace = v),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: TextField(
                controller: _duration,
                enabled: !_saving,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(
                  labelText: 'Duração',
                  hintText: '4:30',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _ThemeField(
          themes: _themes,
          enabled: !_saving,
          onChanged: (themes) => setState(() => _themes = themes),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Os hinários ficam nesta camada, e não no grupo recolhido: o número
        // do hino é como a igreja chama a música, e a seção some sozinha
        // quando não há nenhuma referência — é um botão, não um campo vazio.
        HymnalRefsField(
          refs: _hymnals,
          enabled: !_saving,
          onChanged: (refs) => setState(() => _hymnals = refs),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Onde a novidade termina.
        //
        // É este o interruptor que fecha o ciclo: liga no cadastro, desliga
        // aqui quando a equipe domina e a igreja já canta junto. Nenhuma conta
        // do app sabe esse momento — tocar uma vez não encerra nada, e o
        // cadastro só diz quando a MÚSICA entrou no app, não quando a EQUIPE a
        // aprendeu. Fica junto de tom, tipo e andamento porque é da mesma
        // natureza: o que a equipe sabe e nenhuma API responde.
        SwitchListTile(
          value: _isNew,
          onChanged: _saving ? null : (v) => setState(() => _isNew = v),
          contentPadding: EdgeInsets.zero,
          title: const Text('Música nova'),
        ),
        const SizedBox(height: AppSpacing.xl),
        _ExternalFields(
          expanded: _showExternal,
          enabled: !_saving,
          onToggle: () => setState(() => _showExternal = !_showExternal),
          artist: _artist,
          composer: _composer,
          originalKey: _originalKey,
          onOriginalKeyChanged: (key) => setState(() => _originalKey = key),
          chords: _chords,
          chordsKey: _chordsKey,
          // O tom que o próprio arquivo declara vem antes dos da música.
          suggestedKey: chordSheetKey(_chords.text) ??
              normalizeMusicalKey(_defaultKey) ??
              normalizeMusicalKey(_originalKey),
          onPreviewChords: hasChordsText ? _previewChords : null,
          onPasteChords: _pasteChords,
          // Só quando algum site está liberado: um botão que sempre responde
          // "não dá" não é caminho.
          onImportChords: chordSources.any((source) => source.canImport)
              ? () => _importChords(chordSources)
              : null,
          chordsFooter: chordsChanged
              ? _ChordsDeclaration(
                  basis: _rightsBasis,
                  authorized: _rightsAuthorized,
                  note: _rightsNote,
                  enabled: !_saving,
                  onBasisChanged: (basis) => setState(() {
                    _rightsBasis = basis;
                    _error = null;
                  }),
                  onAuthorizedChanged: (value) => setState(() {
                    _rightsAuthorized = value;
                    _error = null;
                  }),
                )
              : origin == null
                  ? null
                  : _ChordsOrigin(source: origin),
          onChordsKeyChanged: (key) => setState(() {
            _chordsKey = key;
            _error = null;
          }),
          onChordsChanged: (_) => setState(() => _error = null),
          lyrics: _lyrics,
          lyricsUrl: _lyricsUrl,
          chordsUrl: _chordsUrl,
          youtubeUrl: _youtubeUrl,
          spotifyUrl: _spotifyUrl,
        ),
      ],
    );
  }
}

/// O grupo recolhido: o que o import e o enriquecimento preencheram.
///
/// Fechado, resume o que já está lá ("cifra, letra, YouTube") em vez de só
/// dizer "mais campos": quem abre a tela para conferir um link descobre a
/// resposta sem precisar abrir nada.
class _ExternalFields extends StatelessWidget {
  const _ExternalFields({
    required this.expanded,
    required this.enabled,
    required this.onToggle,
    required this.artist,
    required this.composer,
    required this.originalKey,
    required this.onOriginalKeyChanged,
    required this.chords,
    required this.chordsKey,
    required this.suggestedKey,
    required this.onChordsKeyChanged,
    required this.onChordsChanged,
    required this.onPreviewChords,
    required this.onPasteChords,
    required this.onImportChords,
    required this.chordsFooter,
    required this.lyrics,
    required this.lyricsUrl,
    required this.chordsUrl,
    required this.youtubeUrl,
    required this.spotifyUrl,
  });

  final bool expanded;
  final bool enabled;
  final VoidCallback onToggle;
  final TextEditingController artist;
  final TextEditingController composer;
  final String? originalKey;
  final ValueChanged<String?> onOriginalKeyChanged;
  final TextEditingController chords;
  final String? chordsKey;
  final String? suggestedKey;
  final ValueChanged<String?> onChordsKeyChanged;
  final ValueChanged<String> onChordsChanged;
  final VoidCallback? onPreviewChords;
  final VoidCallback onPasteChords;
  final VoidCallback? onImportChords;

  /// A declaração da cifra nova, ou a origem da que já está guardada.
  final Widget? chordsFooter;
  final TextEditingController lyrics;
  final TextEditingController lyricsUrl;
  final TextEditingController chordsUrl;
  final TextEditingController youtubeUrl;
  final TextEditingController spotifyUrl;

  String get _resumo {
    final tem = [
      if (chords.text.trim().isNotEmpty) 'cifra no Pauta',
      if (chordsUrl.text.trim().isNotEmpty) 'link da cifra',
      if (lyricsUrl.text.trim().isNotEmpty || lyrics.text.trim().isNotEmpty)
        'letra',
      if (youtubeUrl.text.trim().isNotEmpty) 'YouTube',
      if (spotifyUrl.text.trim().isNotEmpty) 'Spotify',
    ];
    if (tem.isEmpty) return 'Nada preenchido ainda';
    return 'Tem ${tem.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: scheme.outlineVariant, height: 1),
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dados da música',
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        expanded ? 'Créditos, letra, cifra e links' : _resumo,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: artist,
            enabled: enabled,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Artista'),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: composer,
            enabled: enabled,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Compositor'),
          ),
          const SizedBox(height: AppSpacing.lg),
          MusicalKeyField(
            label: 'Tom da gravação',
            value: originalKey,
            enabled: enabled,
            helperText: 'O tom da versão original',
            onChanged: onOriginalKeyChanged,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: chords,
            enabled: enabled,
            onChanged: onChordsChanged,
            minLines: 4,
            maxLines: 12,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Cifra',
              alignLabelWithHint: true,
              helperText:
                  'Cole a cifra com os acordes em cima da letra, ou em ChordPro.',
              helperMaxLines: 2,
            ),
          ),
          // "Abrir no site" acompanha o link da cifra, que fica mais abaixo.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: chordsUrl,
            builder: (context, link, _) {
              final site = link.text.trim();
              return Wrap(
                spacing: AppSpacing.sm,
                children: [
                  if (site.isNotEmpty)
                    TextButton.icon(
                      onPressed: enabled
                          ? () => openExternalLink(context, site)
                          : null,
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: Text(
                        Uri.tryParse(site)?.host.contains('cifraclub') ?? false
                            ? 'Abrir no Cifra Club'
                            : 'Abrir no site',
                      ),
                    ),
                  TextButton.icon(
                    onPressed: enabled ? onPasteChords : null,
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('Colar cifra'),
                  ),
                  if (onImportChords != null)
                    TextButton.icon(
                      onPressed: enabled ? onImportChords : null,
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('Trazer de um link'),
                    ),
                  if (onPreviewChords != null)
                    TextButton.icon(
                      onPressed: enabled ? onPreviewChords : null,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Ver como fica'),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          MusicalKeyField(
            label: 'Tom da cifra',
            value: chordsKey,
            enabled: enabled,
            helperText: 'O tom em que os acordes foram escritos',
            onChanged: onChordsKeyChanged,
          ),
          if (chordsKey == null && suggestedKey != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ActionChip(
              label: Text('Usar $suggestedKey na cifra'),
              onPressed:
                  enabled ? () => onChordsKeyChanged(suggestedKey) : null,
            ),
          ],
          if (chordsFooter != null) ...[
            const SizedBox(height: AppSpacing.lg),
            chordsFooter!,
          ],
          const SizedBox(height: AppSpacing.lg),
          _LinkField(
            controller: chordsUrl,
            enabled: enabled,
            label: 'Link da cifra',
            icon: Icons.music_note_rounded,
          ),
          const SizedBox(height: AppSpacing.lg),
          _LinkField(
            controller: lyricsUrl,
            enabled: enabled,
            label: 'Link da letra',
            icon: Icons.article_outlined,
          ),
          const SizedBox(height: AppSpacing.lg),
          _LinkField(
            controller: youtubeUrl,
            enabled: enabled,
            label: 'Link do YouTube',
            icon: Icons.play_circle_outline_rounded,
          ),
          const SizedBox(height: AppSpacing.lg),
          _LinkField(
            controller: spotifyUrl,
            enabled: enabled,
            label: 'Link do Spotify',
            icon: Icons.headphones_rounded,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: lyrics,
            enabled: enabled,
            maxLines: 12,
            minLines: 4,
            decoration: const InputDecoration(
              labelText: 'Letra',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ],
    );
  }
}

/// A cifra nova diz de onde veio. O Pauta guarda o que a pessoa declarou; não
/// confere licença nenhuma.
class _ChordsDeclaration extends StatelessWidget {
  const _ChordsDeclaration({
    required this.basis,
    required this.authorized,
    required this.note,
    required this.enabled,
    required this.onBasisChanged,
    required this.onAuthorizedChanged,
  });

  final String? basis;
  final bool authorized;
  final TextEditingController note;
  final bool enabled;
  final ValueChanged<String?> onBasisChanged;
  final ValueChanged<bool> onAuthorizedChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChipField(
          label: 'De onde vem esta cifra',
          value: basis,
          options: chordRightsBasisLabels,
          onChanged: enabled ? onBasisChanged : null,
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: note,
          enabled: enabled,
          maxLength: 300,
          decoration: const InputDecoration(
            labelText: 'Detalhes (opcional)',
            helperText: 'De onde veio, quem autorizou',
          ),
        ),
        CheckboxListTile(
          value: authorized,
          onChanged: enabled ? (v) => onAuthorizedChanged(v ?? false) : null,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Confirmo que a equipe tem autorização para guardar esta cifra '
            'no Pauta.',
          ),
        ),
      ],
    );
  }
}

/// "Guardada em 20/11/2026 por Samuel · Arranjo da equipe".
String chordsOriginText(ChordsSource source) {
  final where = source.kind == 'URL' && source.sourceHost != null
      ? 'Trazida de ${source.sourceHost}'
      : 'Guardada';
  final basis =
      chordRightsBasisLabels[source.rightsBasis] ?? source.rightsBasis;
  return '$where em ${formatFullDate(source.importedAt.toLocal())} por '
      '${source.importedByName} · $basis';
}

class _ChordsOrigin extends StatelessWidget {
  const _ChordsOrigin({required this.source});

  final ChordsSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      chordsOriginText(source),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Campo de link. Teclado de URL e sem autocorreção — o corretor do celular
/// transformava "cifraclub" em outra palavra ao colar endereço.
class _LinkField extends StatelessWidget {
  const _LinkField({
    required this.controller,
    required this.enabled,
    required this.label,
    required this.icon,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.url,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        hintText: 'https://',
      ),
    );
  }
}

/// Escolha única em chips, com opção de desmarcar. Tocar no que já está
/// selecionado limpa: é como se volta atrás sem um botão "nenhum".
class _ChipField extends StatelessWidget {
  const _ChipField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? value;
  final Map<String, String> options;
  final String? hint;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        if (hint != null)
          Text(
            hint!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final entry in options.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: value == entry.key,
                onSelected: onChanged == null
                    ? null
                    : (selected) => onChanged!(selected ? entry.key : null),
              ),
          ],
        ),
      ],
    );
  }
}

/// Os temas da música, na camada de cima do formulário.
///
/// Fica junto de tom, tipo e andamento — e não no grupo recolhido — porque é
/// da mesma natureza: **leitura da letra, feita por gente**. Nenhum serviço
/// externo classifica canção, e o que o script de classificação escreveu é um
/// palpite que esta tela existe para corrigir.
///
/// A lista completa não cabe no formulário: 82 etiquetas empurrariam o botão de
/// salvar para dois palmos abaixo da dobra. Aqui ficam só as escolhidas, e o
/// resto mora no seletor, que é onde há espaço para buscar.
class _ThemeField extends StatelessWidget {
  const _ThemeField({
    required this.themes,
    required this.enabled,
    required this.onChanged,
  });

  final Set<String> themes;
  final bool enabled;
  final ValueChanged<Set<String>> onChanged;

  Future<void> _open(BuildContext context) async {
    final escolha = await showSongThemePicker(context, selected: themes);
    if (escolha != null) onChanged(escolha);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Temas', style: theme.textTheme.titleSmall),
        Text(
          'Ajudam a encontrar a música na hora de montar o culto.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final tema in themes)
              InputChip(
                label: Text(songThemeLabel(tema)),
                selected: true,
                showCheckmark: false,
                onDeleted:
                    enabled ? () => onChanged({...themes}..remove(tema)) : null,
                deleteIcon: const Icon(Icons.close_rounded, size: 16),
                deleteButtonTooltipMessage: 'Tirar ${songThemeLabel(tema)}',
                onSelected: enabled ? (_) => _open(context) : null,
              ),
            // Sempre no fim da lista, e com rótulo diferente quando ainda não
            // há nenhum: "Escolher temas" convida, "Adicionar" acrescenta.
            ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 18),
              label: Text(themes.isEmpty ? 'Escolher temas' : 'Adicionar'),
              onPressed: enabled ? () => _open(context) : null,
            ),
          ],
        ),
      ],
    );
  }
}
