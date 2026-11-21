import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_notice.dart';
import '../data/song_repository.dart';
import '../domain/chord_import.dart';
import '../domain/chord_sheet.dart';
import '../domain/musical_keys.dart';
import 'lyrics_reader.dart';

/// Trazer a cifra de um link: cola o link, vê a cifra lida e decide usar.
///
/// **Não salva nada.** "Usar esta cifra" só preenche o formulário, onde a
/// pessoa corrige o que precisar e declara de onde a cifra veio. Quando o site
/// não entrega a cifra, a saída é guardar o link.
class ChordImportSheet extends ConsumerStatefulWidget {
  const ChordImportSheet({
    super.key,
    required this.teamId,
    required this.songId,
    required this.sources,
    this.initialUrl = '',
  });

  final String teamId;
  final String songId;
  final List<ChordSourceInfo> sources;
  final String initialUrl;

  @override
  ConsumerState<ChordImportSheet> createState() => _ChordImportSheetState();
}

class _ChordImportSheetState extends ConsumerState<ChordImportSheet> {
  late final _url = TextEditingController(text: widget.initialUrl);
  bool _loading = false;
  ChordPreview? _preview;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final url = _url.text.trim();
    if (url.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _preview = null;
    });
    try {
      final preview = await ref
          .read(songRepositoryProvider)
          .previewChords(widget.teamId, widget.songId, url);
      if (mounted) setState(() => _preview = preview);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _warningText(String warning, ChordPreview preview) =>
      switch (warning) {
        'OTHER_SONG' => 'Esta página parece ser de outra música: '
            '"${preview.title ?? 'sem título'}"'
            '${preview.artist == null ? '' : ', de ${preview.artist}'}.',
        'CAPO' => 'A cifra é para capotraste na ${preview.capo}ª casa: os '
            'acordes são o desenho no braço.',
        'TABLATURE_REMOVED' => 'A tablatura da página ficou de fora.',
        _ => warning,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;
    final key = normalizeMusicalKey(preview?.key);
    final names = [
      for (final source in widget.sources)
        if (source.canImport) source.name,
    ].join(', ');

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          0,
          AppSpacing.screenPadding,
          AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Trazer a cifra de um link',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _url,
                enabled: !_loading,
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _fetch(),
                decoration: InputDecoration(
                  labelText: 'Link da cifra',
                  helperText: 'Funciona com: $names',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // Um botão cheio por vez: buscar, ou usar o que veio.
              if (preview == null)
                FilledButton(
                  onPressed: _loading ? null : _fetch,
                  child: Text(_loading ? 'Buscando…' : 'Buscar cifra'),
                )
              else
                OutlinedButton(
                  onPressed: _loading ? null : _fetch,
                  child: const Text('Buscar de novo'),
                ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                AppNotice(
                  tone: AppTone.warning,
                  message: _error!,
                  liveRegion: true,
                  action: TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop<ChordImportResult>(
                      (preview: null, keepLink: _url.text.trim()),
                    ),
                    child: const Text('Guardar o link'),
                  ),
                ),
              ],
              if (preview != null) ...[
                const SizedBox(height: AppSpacing.lg),
                for (final warning in preview.warnings)
                  AppNotice(
                    tone: warning == 'OTHER_SONG'
                        ? AppTone.warning
                        : AppTone.info,
                    message: _warningText(warning, preview),
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  ),
                if (key != null)
                  Text(
                    'Tom da cifra: $key · ${preview.sourceName}',
                    style: theme.textTheme.titleSmall,
                  ),
                const SizedBox(height: AppSpacing.md),
                ChordSheetView(
                  chords: normalizeChordSheet(preview.sheet),
                  sourceKey: key,
                  targetKey: key,
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop<ChordImportResult>(
                    (preview: preview, keepLink: null),
                  ),
                  child: const Text('Usar esta cifra'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
