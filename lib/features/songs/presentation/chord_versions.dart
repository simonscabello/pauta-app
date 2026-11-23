import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_options_sheet.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/form_scaffold.dart';
import '../../../shared/widgets/unsaved_changes_guard.dart';
import '../data/song_repository.dart';
import '../domain/chord_sheet.dart';
import '../domain/musical_keys.dart';
import '../domain/song_models.dart';
import 'musical_key_picker.dart';

const _newVersion = '+nova';
const _editVersion = '+editar';

/// A folha "Versão da cifra": a original, as versões e, para quem lidera
/// ([teamId] não nulo), criar uma a partir da que está aberta ou editá-la.
///
/// Devolve a versão escolhida (nulo = original) e a música como ficou, que
/// muda quando uma versão é criada, editada ou apagada. Nulo: fechou sem
/// escolher.
Future<({String? versionId, Song song})?> showChordVersionPicker(
  BuildContext context,
  WidgetRef ref, {
  required Song song,
  required String? selectedId,
  String? teamId,
}) async {
  final selected = song.chordVersion(selectedId);
  final picked = await showAppOptionsSheet<String?>(
    context: context,
    title: 'Versão da cifra',
    selected: selected?.id,
    options: [
      const AppOption(value: null, label: 'Original'),
      for (final v in song.chordVersions)
        AppOption(
          value: v.id,
          label: v.name,
          subtitle: [
            if (v.createdByName != null) v.createdByName!,
            if (v.createdAt != null)
              DateFormat('dd/MM/yyyy').format(v.createdAt!.toLocal()),
          ].join(' · '),
        ),
      if (teamId != null) ...[
        if (selected != null)
          const AppOption(
            value: _editVersion,
            label: 'Editar esta versão',
            icon: Icons.edit_outlined,
          ),
        const AppOption(
          value: _newVersion,
          label: 'Nova versão a partir desta',
          subtitle: 'A original continua como está',
          icon: Icons.add_rounded,
        ),
      ],
    ],
  );
  if (picked == null || !context.mounted) return null;
  final choice = picked.value;
  if (choice != _newVersion && choice != _editVersion) {
    return (versionId: choice, song: song);
  }

  final editing = choice == _editVersion ? selected : null;
  final saved = await Navigator.of(context).push<Song>(
    MaterialPageRoute(
      builder: (_) => ChordVersionFormScreen(
        teamId: teamId!,
        song: song,
        version: editing,
        baseChords: selected?.chords ?? song.chords ?? '',
        baseKey: selected?.chordsKey ?? song.chordsKey,
      ),
    ),
  );
  if (saved == null) return null;
  ref.invalidate(songProvider((teamId: teamId!, songId: song.id)));
  return (
    // Editada: continua nela (ou cai na original, se foi apagada). Nova: é a
    // última da lista.
    versionId: editing != null
        ? saved.chordVersion(editing.id)?.id
        : saved.chordVersions.lastOrNull?.id,
    song: saved,
  );
}

/// Criar ou editar uma versão da cifra. A original não passa por aqui.
class ChordVersionFormScreen extends ConsumerStatefulWidget {
  const ChordVersionFormScreen({
    super.key,
    required this.teamId,
    required this.song,
    required this.baseChords,
    required this.baseKey,
    this.version,
  });

  final String teamId;
  final Song song;

  /// A versão em edição; nulo cria uma nova a partir de [baseChords].
  final ChordVersion? version;
  final String baseChords;
  final String? baseKey;

  @override
  ConsumerState<ChordVersionFormScreen> createState() =>
      _ChordVersionFormScreenState();
}

class _ChordVersionFormScreenState
    extends ConsumerState<ChordVersionFormScreen> with UnsavedChangesTracker {
  late final _name = TextEditingController(text: widget.version?.name ?? '');
  late final _chords = TextEditingController(text: widget.baseChords);
  late String? _key = normalizeMusicalKey(widget.baseKey);
  bool _saving = false;
  String? _error;

  @override
  String unsavedSignature() => [_name.text.trim(), _chords.text, _key].join('|');

  @override
  void initState() {
    super.initState();
    markUnsavedBaseline();
  }

  @override
  void dispose() {
    _name.dispose();
    _chords.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Song> Function(SongRepository repo) call) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final song = await call(ref.read(songRepositoryProvider));
      if (!mounted) return;
      markSaved();
      Navigator.of(context).pop(song);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _save() {
    final name = _name.text.trim();
    final chords = normalizeChordSheet(_chords.text);
    if (name.isEmpty || chords.trim().isEmpty) {
      setState(
        () => _error = name.isEmpty
            ? 'Dê um nome à versão, como "Correção" ou "Arranjo do ensaio".'
            : 'A versão precisa de uma cifra.',
      );
      return;
    }
    _run(
      (repo) => repo.saveChordVersion(
        widget.teamId,
        widget.song.id,
        widget.version?.id,
        {'name': name, 'chords': chords, 'chordsKey': _key},
      ),
    );
  }

  Future<void> _remove() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Apagar esta versão?',
      message: 'As escalas que usam "${widget.version!.name}" voltam à cifra '
          'original.',
      confirmLabel: 'Apagar versão',
      destructive: true,
    );
    if (!ok) return;
    await _run(
      (repo) => repo.removeChordVersion(
        widget.teamId,
        widget.song.id,
        widget.version!.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.version != null;
    return FormScaffold(
      appBar: AppBar(title: Text(editing ? 'Editar versão' : 'Nova versão')),
      subtitle: '${widget.song.title}. A cifra original continua como está.',
      isDirty: hasUnsavedChanges,
      bottomAction: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) FormErrorBanner(message: _error!),
          AppSubmitButton(
            label: 'Salvar versão',
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
      children: [
        TextField(
          controller: _name,
          enabled: !_saving,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nome da versão',
            hintText: 'Correção, Arranjo do ensaio 22/11',
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        MusicalKeyField(
          label: 'Tom da cifra',
          value: _key,
          enabled: !_saving,
          helperText: 'O tom em que os acordes foram escritos',
          onChanged: (key) => setState(() => _key = key),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _chords,
          enabled: !_saving,
          minLines: 8,
          maxLines: 20,
          maxLength: maxChordSheetLength,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Cifra',
            alignLabelWithHint: true,
            helperText: 'Acordes entre colchetes, na sílaba: [G]Santo',
            helperMaxLines: 2,
          ),
        ),
        if (editing) ...[
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _saving ? null : _remove,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Apagar versão'),
            ),
          ),
        ],
      ],
    );
  }
}
