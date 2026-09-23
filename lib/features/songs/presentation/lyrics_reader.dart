import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/storage/shared_preferences_provider.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_bottom_action_bar.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_states.dart';
import '../../events/domain/event_models.dart';
import '../data/song_repository.dart';
import 'song_resources.dart';

/// O tamanho da letra no modo leitura, guardado no aparelho.
///
/// Quem ensaia com o celular na estante lê de mais longe do que quem lê na
/// mão, e o corpo fixo da letra obrigava a aproximar o aparelho no meio da
/// música. Preferência do aparelho, como o tema: a mesma pessoa quer letra
/// grande no tablet do púlpito e normal no celular.
class LyricsScaleController extends StateNotifier<double> {
  LyricsScaleController(this._prefs) : super(_read(_prefs));

  static const _key = 'lyrics_scale';
  static const min = 0.85;
  static const max = 2.0;
  static const step = 0.15;

  /// Nulo sem armazenamento (testes, navegador sem `localStorage`): aí a
  /// escolha vale só para esta sessão.
  final SharedPreferences? _prefs;

  static double _read(SharedPreferences? prefs) {
    final saved = prefs?.getDouble(_key) ?? 1.0;
    return saved.clamp(min, max);
  }

  bool get canShrink => state > min + 0.001;
  bool get canGrow => state < max - 0.001;

  Future<void> shrink() => _set(state - step);
  Future<void> grow() => _set(state + step);

  Future<void> _set(double value) async {
    state = value.clamp(min, max);
    try {
      await _prefs?.setDouble(_key, state);
    } catch (_) {
      // Preferência que não gravou vale só para esta sessão.
    }
  }
}

final lyricsScaleProvider =
    StateNotifierProvider<LyricsScaleController, double>((ref) {
  SharedPreferences? prefs;
  try {
    prefs = ref.watch(sharedPreferencesProvider);
  } catch (_) {
    prefs = null;
  }
  return LyricsScaleController(prefs);
});

/// Mantém a tela ligada enquanto estiver montado.
///
/// A letra aberta é o momento em que o celular está na estante, longe da mão:
/// a tela apagando no meio da estrofe é o motivo de a equipe imprimir a letra.
/// Falhar em ligar (navegador sem a API, permissão negada) não impede nada — a
/// letra continua na tela, só sem a garantia.
class KeepScreenOn extends StatefulWidget {
  const KeepScreenOn({super.key, required this.child});

  final Widget child;

  @override
  State<KeepScreenOn> createState() => _KeepScreenOnState();
}

class _KeepScreenOnState extends State<KeepScreenOn> {
  @override
  void initState() {
    super.initState();
    _set(true);
  }

  @override
  void dispose() {
    _set(false);
    super.dispose();
  }

  Future<void> _set(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (_) {
      // Sem a API, a tela segue o tempo do aparelho.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A− e A+ na barra do topo da letra.
class LyricsFontButtons extends ConsumerWidget {
  const LyricsFontButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(lyricsScaleProvider);
    final controller = ref.read(lyricsScaleProvider.notifier);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Diminuir a letra',
          icon: const Icon(Icons.text_decrease_rounded),
          onPressed: controller.canShrink ? controller.shrink : null,
        ),
        IconButton(
          tooltip: 'Aumentar a letra',
          icon: const Icon(Icons.text_increase_rounded),
          onPressed: controller.canGrow ? controller.grow : null,
        ),
      ],
    );
  }
}

/// O texto da letra no corpo de leitura, no tamanho escolhido.
class LyricsText extends ConsumerWidget {
  const LyricsText({super.key, required this.lyrics});

  final String lyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(lyricsScaleProvider);
    final base = Theme.of(context).textTheme.bodyLarge;

    return SelectableText(
      lyrics.trim(),
      style: base?.copyWith(
        height: 1.7,
        fontSize: (base.fontSize ?? 16) * scale,
      ),
    );
  }
}

/// A letra das músicas de um culto, **uma depois da outra**.
///
/// Aberta pela folha da música da escala. O botão "Letra" dali abria o site
/// (com anúncios) mesmo com a letra guardada logo abaixo; agora abre esta
/// tela, que é a letra no app com o tom **desta escala** no topo, o tamanho
/// ajustável e o "Próxima" levando à música seguinte do culto — é o que se
/// faz no ensaio, e antes exigia voltar à escala e abrir outra folha.
class EventLyricsScreen extends ConsumerStatefulWidget {
  const EventLyricsScreen({
    super.key,
    required this.teamId,
    required this.songs,
    required this.initialIndex,
  });

  /// A equipe **da escala**, para buscar a letra no repertório certo.
  final String teamId;

  /// As músicas do culto, na ordem da escala.
  final List<EventSong> songs;
  final int initialIndex;

  @override
  ConsumerState<EventLyricsScreen> createState() => _EventLyricsScreenState();
}

class _EventLyricsScreenState extends ConsumerState<EventLyricsScreen> {
  late int _index = widget.initialIndex.clamp(0, widget.songs.length - 1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final atual = widget.songs[_index];
    final full = ref.watch(
      songProvider((teamId: widget.teamId, songId: atual.songId)),
    );
    final anterior = _index > 0 ? widget.songs[_index - 1] : null;
    final proxima =
        _index < widget.songs.length - 1 ? widget.songs[_index + 1] : null;

    final detalhes = [
      if (atual.hymnal != null) atual.hymnal!.label,
      if (atual.key?.isNotEmpty ?? false) 'Tom ${atual.key}',
      if (atual.momentText != null) atual.momentText!,
    ].join(' · ');

    return KeepScreenOn(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.songs.length > 1
                ? 'Letra · ${_index + 1} de ${widget.songs.length}'
                : 'Letra',
          ),
          actions: [
            const LyricsFontButtons(),
            if (atual.lyricsUrl?.trim().isNotEmpty ?? false)
              IconButton(
                tooltip: 'Abrir no site',
                icon: const Icon(Icons.open_in_new_rounded),
                onPressed: () => openResourceLink(context, atual.lyricsUrl!),
              ),
          ],
        ),
        bottomNavigationBar: widget.songs.length < 2
            ? null
            : AppBottomActionBar(
                action: Row(
                  children: [
                    if (anterior != null)
                      TextButton.icon(
                        onPressed: () => setState(() => _index--),
                        icon: const Icon(Icons.chevron_left_rounded),
                        label: const Text('Anterior'),
                      ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: proxima == null
                            ? null
                            : FilledButton.icon(
                                onPressed: () => setState(() => _index++),
                                iconAlignment: IconAlignment.end,
                                icon: const Icon(Icons.chevron_right_rounded),
                                label: Text(
                                  'Próxima: ${proxima.title}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
        body: SafeArea(
          top: false,
          child: AppContentWidth.reading(
            child: ListView(
              key: ValueKey(atual.songId),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.lg,
                AppSpacing.screenPadding,
                AppSpacing.xxl,
              ),
              children: [
                Text(atual.title, style: theme.textTheme.headlineMedium),
                if (detalhes.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    detalhes,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ],
                if (atual.note?.isNotEmpty ?? false) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    atual.note!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Divider(height: 1, color: scheme.outlineVariant),
                const SizedBox(height: AppSpacing.lg),
                full.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: AppLoading(),
                  ),
                  error: (_, __) => AppErrorState(
                    message: 'Não foi possível carregar a letra.',
                    onRetry: () => ref.invalidate(
                      songProvider(
                        (teamId: widget.teamId, songId: atual.songId),
                      ),
                    ),
                  ),
                  data: (song) => (song.lyrics?.trim().isNotEmpty ?? false)
                      ? LyricsText(lyrics: song.lyrics!)
                      : Text(
                          'A letra desta música ainda não foi guardada no '
                          'Pauta.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
