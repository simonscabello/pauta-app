import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/form_scaffold.dart';
import '../../../shared/widgets/unsaved_changes_guard.dart';
import '../data/song_repository.dart';
import '../domain/hymnal_models.dart';
import '../domain/musical_keys.dart';
import '../domain/song_models.dart';
import '../domain/song_themes.dart';
import 'hymnal_refs_field.dart';
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
  final _artist = TextEditingController();
  final _composer = TextEditingController();
  final _lyrics = TextEditingController();
  final _lyricsUrl = TextEditingController();
  final _chordsUrl = TextEditingController();
  final _youtubeUrl = TextEditingController();
  final _spotifyUrl = TextEditingController();

  /// Nulo é "sem tom". Pode ser anotação de antes da lista ("G (capo 2)"):
  /// ela volta ao servidor intacta enquanto ninguém escolher outro tom.
  String? _defaultKey;
  String? _originalKey;
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
      _artist,
      _composer,
      _lyrics,
      _lyricsUrl,
      _chordsUrl,
      _youtubeUrl,
      _spotifyUrl,
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
    _themes = {...song.themes};
    _hymnals = [...song.hymnals];
    _isNew = song.isNew;
    _artist.text = song.artist ?? '';
    _composer.text = song.composer ?? '';
    _originalKey = _keyOrNull(song.originalKey);
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
          _artist,
          _composer,
          _lyrics,
          _lyricsUrl,
          _chordsUrl,
          _youtubeUrl,
          _spotifyUrl,
        ])
          c.text.trim(),
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
          // A letra só vai quando mudou. São até 20 mil caracteres, e
          // reenviá-los a cada ajuste de tom é peso puro na rede da igreja.
          if (_lyrics.text != (song.lyrics ?? '')) 'lyrics': _lyrics.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    final song = widget.song ??
        ref
            .watch(
              songProvider((teamId: widget.teamId, songId: widget.songId)),
            )
            .valueOrNull;

    if (song == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Editar música')),
        body: const AppLoading(),
      );
    }

    if (!_populated) _populate(song);
    markUnsavedBaseline();
    final recordingKey = normalizeMusicalKey(song.originalKey);

    return FormScaffold(
      isDirty: hasUnsavedChanges,
      // Sem o nome da música no corpo: ele já é o primeiro campo, logo
      // abaixo, e repeti-lo em título grande empurrava o formulário para
      // baixo com a mesma palavra duas vezes.
      appBar: AppBar(title: const Text('Editar música')),
      // Preso embaixo: com "Dados da música" aberto (quatro links e a letra),
      // o botão ficava duas telas abaixo de onde a pessoa mexeu.
      bottomAction: AppSubmitButton(
        label: 'Salvar',
        loading: _saving,
        onPressed: () => _save(song),
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
        _ChipField(
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
          lyrics: _lyrics,
          lyricsUrl: _lyricsUrl,
          chordsUrl: _chordsUrl,
          youtubeUrl: _youtubeUrl,
          spotifyUrl: _spotifyUrl,
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.xl),
          FormErrorBanner(message: _error!),
        ],
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
  final TextEditingController lyrics;
  final TextEditingController lyricsUrl;
  final TextEditingController chordsUrl;
  final TextEditingController youtubeUrl;
  final TextEditingController spotifyUrl;

  String get _resumo {
    final tem = [
      if (chordsUrl.text.trim().isNotEmpty) 'cifra',
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
                        expanded
                            ? 'Preenchidos automaticamente. Corrija se algo '
                                'veio errado.'
                            : _resumo,
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
