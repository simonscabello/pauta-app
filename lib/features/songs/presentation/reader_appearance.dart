import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/responsive/adaptive_dialog.dart';
import '../../../core/storage/shared_preferences_provider.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

/// O fundo do leitor de letra e cifra. Cada um tem o texto, o cinza dos
/// rótulos e uma variante de cada cor de acorde com contraste ≥ 4,5 sobre ele
/// (`test/reader_appearance_test.dart`): quem toca lê de longe, na estante.
class ReaderPalette {
  const ReaderPalette(
    this.id,
    this.label, {
    required this.brightness,
    required this.background,
    required this.text,
    required this.muted,
  });

  final String id;
  final String label;
  final Brightness brightness;
  final Color background;
  final Color text;
  final Color muted;

  static const dark = ReaderPalette(
    'dark',
    'Escuro',
    brightness: Brightness.dark,
    background: Color(0xFF121212),
    text: Color(0xFFF2F2F2),
    muted: Color(0xFFA8A8A8),
  );
  static const light = ReaderPalette(
    'light',
    'Claro',
    brightness: Brightness.light,
    background: Color(0xFFFFFFFF),
    text: Color(0xFF141414),
    muted: Color(0xFF5C5C5C),
  );
  static const paper = ReaderPalette(
    'paper',
    'Papel',
    brightness: Brightness.light,
    background: Color(0xFFF4EBD5),
    text: Color(0xFF2A2118),
    muted: Color(0xFF65584A),
  );
  static const black = ReaderPalette(
    'black',
    'Preto',
    brightness: Brightness.dark,
    background: Color(0xFF000000),
    text: Color(0xFFFFFFFF),
    muted: Color(0xFFBDBDBD),
  );

  static const all = [dark, light, paper, black];
}

/// A cor dos acordes, com um tom para fundo escuro e outro para fundo claro.
class ChordColor {
  const ChordColor(this.id, this.label, this.onDark, this.onLight);

  final String id;
  final String label;
  final Color onDark;
  final Color onLight;

  Color on(Brightness brightness) =>
      brightness == Brightness.dark ? onDark : onLight;

  static const all = [
    // O laranja do Pauta Admin: o que a equipe pediu para os acordes.
    ChordColor('orange', 'Laranja', Color(0xFFF2A65A), Color(0xFFA84300)),
    ChordColor('yellow', 'Amarelo', Color(0xFFFFD43B), Color(0xFF7A5A00)),
    ChordColor('blue', 'Azul', Color(0xFF6CB8FF), Color(0xFF0B5BAA)),
    ChordColor('green', 'Verde', Color(0xFF5FD38D), Color(0xFF1D7039)),
    ChordColor('pink', 'Rosa', Color(0xFFFF85BA), Color(0xFFA8215A)),
  ];
}

/// Fundo e cor dos acordes do leitor, guardados no aparelho como o tamanho da
/// letra. `palette == null` acompanha o tema do app (escuro ou claro).
typedef ReaderAppearance = ({ReaderPalette? palette, ChordColor chordColor});

class ReaderAppearanceController extends StateNotifier<ReaderAppearance> {
  ReaderAppearanceController(this._prefs) : super(_read(_prefs));

  static const _paletteKey = 'reader_palette';
  static const _chordKey = 'reader_chord_color';

  final SharedPreferences? _prefs;

  static ReaderAppearance _read(SharedPreferences? prefs) {
    final palette = prefs?.getString(_paletteKey);
    final chord = prefs?.getString(_chordKey);
    return (
      palette: ReaderPalette.all.where((p) => p.id == palette).firstOrNull,
      chordColor: ChordColor.all.firstWhere(
        (c) => c.id == chord,
        orElse: () => ChordColor.all.first,
      ),
    );
  }

  Future<void> setPalette(ReaderPalette? palette) async {
    state = (palette: palette, chordColor: state.chordColor);
    try {
      if (palette == null) {
        await _prefs?.remove(_paletteKey);
      } else {
        await _prefs?.setString(_paletteKey, palette.id);
      }
    } catch (_) {
      // Preferência que não gravou vale só para esta sessão.
    }
  }

  Future<void> setChordColor(ChordColor color) async {
    state = (palette: state.palette, chordColor: color);
    try {
      await _prefs?.setString(_chordKey, color.id);
    } catch (_) {
      // Preferência que não gravou vale só para esta sessão.
    }
  }
}

final readerAppearanceProvider =
    StateNotifierProvider<ReaderAppearanceController, ReaderAppearance>((ref) {
  SharedPreferences? prefs;
  try {
    prefs = ref.watch(sharedPreferencesProvider);
  } catch (_) {
    prefs = null;
  }
  return ReaderAppearanceController(prefs);
});

/// O fundo escolhido, ou o escuro/claro que acompanha o tema do app.
ReaderPalette resolveReaderPalette(
  BuildContext context,
  ReaderPalette? chosen,
) =>
    chosen ??
    (Theme.of(context).brightness == Brightness.dark
        ? ReaderPalette.dark
        : ReaderPalette.light);

/// O tema do app com as cores do leitor: as barras e o texto acompanham o fundo.
ThemeData readerTheme(ReaderPalette palette) {
  final base =
      palette.brightness == Brightness.dark ? AppTheme.dark : AppTheme.light;
  final scheme = base.colorScheme.copyWith(
    surface: palette.background,
    onSurface: palette.text,
    onSurfaceVariant: palette.muted,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.background,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: palette.background,
      foregroundColor: palette.text,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

/// Tamanho da letra, fundo e cor dos acordes, numa folha só.
Future<void> showReaderAppearanceSheet(
  BuildContext context, {
  required Widget fontButtons,
}) {
  return showAdaptiveSheet<void>(
    context: context,
    builder: (_) => _ReaderAppearanceSheet(fontButtons: fontButtons),
  );
}

class _ReaderAppearanceSheet extends ConsumerWidget {
  const _ReaderAppearanceSheet({required this.fontButtons});

  final Widget fontButtons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(readerAppearanceProvider);
    final controller = ref.read(readerAppearanceProvider.notifier);
    final theme = Theme.of(context);
    final palette = resolveReaderPalette(context, appearance.palette);

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.lg,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          0,
          AppSpacing.screenPadding,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aparência da leitura', style: theme.textTheme.titleLarge),
            heading('Tamanho da letra'),
            fontButtons,
            heading('Fundo'),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                ChoiceChip(
                  label: const Text('Do app'),
                  selected: appearance.palette == null,
                  onSelected: (_) => controller.setPalette(null),
                ),
                for (final p in ReaderPalette.all)
                  ChoiceChip(
                    avatar: _Swatch(fill: p.background, ink: p.text),
                    label: Text(p.label),
                    selected: appearance.palette?.id == p.id,
                    onSelected: (_) => controller.setPalette(p),
                  ),
              ],
            ),
            heading('Cor dos acordes'),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final c in ChordColor.all)
                  ChoiceChip(
                    avatar: _Swatch(
                      fill: palette.background,
                      ink: c.on(palette.brightness),
                    ),
                    label: Text(c.label),
                    selected: appearance.chordColor.id == c.id,
                    onSelected: (_) => controller.setChordColor(c),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _Preview(palette: palette, chordColor: appearance.chordColor),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.fill, required this.ink});

  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.palette, required this.chordColor});

  final ReaderPalette palette;
  final ChordColor chordColor;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge!;
    return ExcludeSemantics(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'G            D/F#',
              style: style.copyWith(
                color: chordColor.on(palette.brightness),
                fontWeight: FontWeight.bold,
                height: 1.15,
              ),
            ),
            Text(
              'Assim fica a cifra',
              style: style.copyWith(color: palette.text, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}
