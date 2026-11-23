import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/shared_preferences_provider.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/cache_stamp_banner.dart';
import '../../auth/application/auth_controller.dart';
import '../../events/application/played_songs.dart';
import '../../events/data/event_repository.dart';
import '../../events/domain/event_models.dart';
import '../data/song_repository.dart';
import '../domain/chord_sheet.dart';
import '../domain/musical_keys.dart';
import '../domain/song_models.dart';
import 'reader_appearance.dart';
import '../../../shared/widgets/open_link.dart';

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

/// A velocidade da rolagem automática, guardada no aparelho como o tamanho da
/// letra. Poucos níveis, sem BPM: quem está tocando acerta no olho, com um
/// toque, e a música seguinte quase sempre pede a mesma.
class LyricsScrollSpeedController extends StateNotifier<int> {
  LyricsScrollSpeedController(this._prefs)
      : super((_prefs?.getInt(_key) ?? 1).clamp(0, levels.length - 1));

  static const _key = 'lyrics_scroll_speed';

  /// Pixels por segundo com a letra no tamanho normal; a letra maior rola
  /// proporcionalmente mais rápido, para as linhas passarem no mesmo ritmo.
  static const levels = [10.0, 18.0, 28.0, 42.0];

  final SharedPreferences? _prefs;

  /// Do mais rápido volta ao mais lento: um botão só, que cabe ao lado do
  /// tocar sem apertar nada em 320 px.
  Future<void> next() async {
    state = (state + 1) % levels.length;
    try {
      await _prefs?.setInt(_key, state);
    } catch (_) {
      // Preferência que não gravou vale só para esta sessão.
    }
  }
}

final lyricsScrollSpeedProvider =
    StateNotifierProvider<LyricsScrollSpeedController, int>((ref) {
  SharedPreferences? prefs;
  try {
    prefs = ref.watch(sharedPreferencesProvider);
  } catch (_) {
    prefs = null;
  }
  return LyricsScrollSpeedController(prefs);
});

/// A lista do leitor com a rolagem automática: tocar/pausar e a velocidade
/// numa faixa fina embaixo, junto do "Próxima" ([navigation]). Antes eles
/// flutuavam sobre a letra e o "Próxima" ocupava uma barra própria, e a cifra
/// ficava com pouco mais da metade da tela.
///
/// Pausa quando a pessoa toca ou arrasta a letra, para no fim e, quando
/// parou no fim, recomeça do topo na música seguinte ([restartKey]).
class _AutoScrollList extends ConsumerStatefulWidget {
  const _AutoScrollList({
    required this.restartKey,
    required this.children,
    this.navigation,
  });

  final Object restartKey;
  final List<Widget> children;
  final Widget? navigation;

  @override
  ConsumerState<_AutoScrollList> createState() => _AutoScrollListState();
}

class _AutoScrollListState extends ConsumerState<_AutoScrollList>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  bool _ended = false;

  bool get _playing => _ticker.isActive;

  void _start() {
    _ended = false;
    _last = Duration.zero;
    _ticker.start();
  }

  void _stop({bool ended = false}) {
    if (!_playing) return;
    _ticker.stop();
    setState(() => _ended = ended);
  }

  void _tick(Duration elapsed) {
    // Teto no passo: voltar de outro app não dá um salto pelo tempo fora.
    final seconds = math.min((elapsed - _last).inMicroseconds / 1e6, 0.1);
    _last = elapsed;
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent) return _stop(ended: true);
    final speed = LyricsScrollSpeedController
            .levels[ref.read(lyricsScrollSpeedProvider)] *
        ref.read(lyricsScaleProvider);
    _scroll.jumpTo(
      math.min(position.pixels + speed * seconds, position.maxScrollExtent),
    );
  }

  @override
  void didUpdateWidget(_AutoScrollList old) {
    super.didUpdateWidget(old);
    // A lista nova já nasce no topo (a chave dela muda junto).
    if (old.restartKey != widget.restartKey && _ended) _start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final speed = ref.watch(lyricsScrollSpeedProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: Listener(
            onPointerDown: (_) => _stop(),
            onPointerSignal: (_) => _stop(),
            child: ListView(
              key: ValueKey(widget.restartKey),
              controller: _scroll,
              // Margem menor que a das outras telas: cada coluna a mais é uma
              // linha de cifra que deixa de quebrar em duas.
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              children: widget.children,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(child: widget.navigation ?? const SizedBox.shrink()),
                Tooltip(
                  message: 'Velocidade da rolagem',
                  child: TextButton.icon(
                    onPressed:
                        ref.read(lyricsScrollSpeedProvider.notifier).next,
                    icon: const Icon(Icons.speed_rounded),
                    label: Text(
                      '${speed + 1}',
                      semanticsLabel: 'Velocidade da rolagem: ${speed + 1} de '
                          '${LyricsScrollSpeedController.levels.length}',
                    ),
                  ),
                ),
                IconButton.filled(
                  tooltip: _playing ? 'Pausar a rolagem' : 'Rolar sozinho',
                  onPressed: () => _playing ? _stop() : setState(_start),
                  icon: Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

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

/// A− e A+ da folha de aparência, com o tamanho atual entre eles.
class LyricsFontButtons extends ConsumerWidget {
  const LyricsFontButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(lyricsScaleProvider);
    final controller = ref.read(lyricsScaleProvider.notifier);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          tooltip: 'Diminuir a letra',
          icon: const Icon(Icons.text_decrease_rounded),
          onPressed: controller.canShrink ? controller.shrink : null,
        ),
        SizedBox(
          width: 64,
          child: Text(
            '${(scale * 100).round()}%',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton.outlined(
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
        height: 1.5,
        fontSize: (base.fontSize ?? 16) * scale,
      ),
    );
  }
}

/// O destino só passa a ser o tom escrito quando a pessoa move o controle.
String? _readerTarget(String? initialKey, String? writtenKey, int? steps) {
  final initial = normalizeMusicalKey(initialKey);
  if (steps == null) return initial;
  final base = initial ?? normalizeMusicalKey(writtenKey);
  return base == null ? null : shiftMusicalKey(base, steps);
}

/// Uma barra só: o tom (na cifra), a aparência e o site. O tom e o A−/A+
/// tinham uma segunda barra embaixo desta; o tamanho da letra, que se acerta
/// uma vez e fica guardado, foi para a folha de aparência.
AppBar _readerAppBar(
  BuildContext context, {
  required String title,
  required bool chordMode,
  required String? url,
  required String? currentKey,
  required ValueChanged<int>? onStep,
}) {
  return AppBar(
    title: Text(title),
    actions: [
      if (chordMode) _KeyStepper(currentKey: currentKey, onStep: onStep),
      IconButton(
        tooltip: 'Aparência da leitura',
        icon: const Icon(Icons.palette_outlined),
        onPressed: () => showReaderAppearanceSheet(
          context,
          fontButtons: const LyricsFontButtons(),
        ),
      ),
      if (url?.trim().isNotEmpty ?? false)
        IconButton(
          tooltip: 'Abrir no site',
          icon: const Icon(Icons.open_in_new_rounded),
          onPressed: () => openExternalLink(context, url!),
        ),
    ],
  );
}

class _KeyStepper extends StatelessWidget {
  const _KeyStepper({required this.currentKey, required this.onStep});

  final String? currentKey;
  final ValueChanged<int>? onStep;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Baixar meio tom',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove),
          onPressed: onStep == null ? null : () => onStep!(-1),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 28),
          child: Text(
            currentKey ?? '—',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
            semanticsLabel: currentKey == null
                ? 'Tom desconhecido'
                : musicalKeySpokenLabel(currentKey!),
          ),
        ),
        IconButton(
          tooltip: 'Subir meio tom',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add),
          onPressed: onStep == null ? null : () => onStep!(1),
        ),
      ],
    );
  }
}

/// O título da música e uma linha de detalhes, no lugar do título grande com
/// divisória: o leitor é para tocar, e o que importa é a primeira estrofe
/// aparecer sem rolar.
List<Widget> _readerHeader(BuildContext context, String title, String details) {
  final theme = Theme.of(context);
  return [
    Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    if (details.isNotEmpty)
      Text(
        details,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    const SizedBox(height: AppSpacing.md),
  ];
}

/// O leitor com o fundo que a pessoa escolheu (ou o escuro/claro do app).
class _ReaderThemed extends ConsumerWidget {
  const _ReaderThemed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = ref.watch(readerAppearanceProvider).palette;
    // "Do app": o leitor fica com o fundo de sempre; só os acordes mudam.
    if (chosen == null) return child;
    return Theme(data: readerTheme(chosen), child: child);
  }
}

final _noLyrics = RegExp(r'^[\s|()x\d]*$');

class ChordSheetView extends ConsumerWidget {
  const ChordSheetView({
    super.key,
    required this.chords,
    required this.sourceKey,
    required this.targetKey,
    this.chordsUrl,
  });

  final String? chords;
  final String? sourceKey;
  final String? targetKey;
  final String? chordsUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(lyricsScaleProvider);
    final appearance = ref.watch(readerAppearanceProvider);
    final chordColor = appearance.chordColor;
    // O grau é do tom que está na tela; sem tom conhecido, ficam as notas.
    final degreeKey = appearance.degrees ? targetKey ?? sourceKey : null;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = theme.textTheme.bodyLarge!;
    // Entrelinha curta: o acorde fica colado à sílaba dele, e cada par
    // acorde/letra ocupa menos altura — menos rolagem durante a música.
    final lyricsStyle = base.copyWith(
      fontSize: base.fontSize! * scale,
      height: 1.3,
      color: scheme.onSurface,
    );
    final chordStyle = lyricsStyle.copyWith(
      color: chordColor.on(theme.brightness),
      fontWeight: FontWeight.w800,
      height: 1.15,
    );

    if (chords?.trim().isEmpty ?? true) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('A cifra desta música ainda não foi guardada no Pauta.'),
          if (chordsUrl?.trim().isNotEmpty ?? false)
            TextButton(
              onPressed: () => openExternalLink(context, chordsUrl!),
              child: const Text('Abrir no site'),
            ),
        ],
      );
    }
    // A arrumação também na leitura: corrige a cifra já guardada sem passar
    // pelo formulário (acorde em linha própria, "Aº", caractere invisível).
    final sheet =
        transposeChordSheet(normalizeChordSheet(chords!), sourceKey, targetKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Uma linha discreta, e não um cartão: o tom já está na barra.
        if (normalizeMusicalKey(sourceKey) == null ||
            normalizeMusicalKey(targetKey) == null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              sourceKey?.trim().isNotEmpty == true
                  ? 'A cifra está como foi escrita, em $sourceKey.'
                  : 'O tom em que a cifra foi escrita não foi informado.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final line in parseChordSheet(sheet))
          _chordLine(
            [
              for (final s in line)
                (
                  chord:
                      s.chord == null ? null : chordDegree(s.chord!, degreeKey),
                  text: s.text,
                ),
            ],
            lyricsStyle,
            chordStyle,
            scheme.onSurfaceVariant,
          ),
      ],
    );
  }

  Widget _chordLine(
    List<ChordSegment> line,
    TextStyle lyricsStyle,
    TextStyle chordStyle,
    Color labelColor,
  ) {
    final text = line.map((s) => s.text).join();
    Widget lyricText(String value) => Text(
          value,
          style: isChordSectionLabel(value)
              ? lyricsStyle.copyWith(color: labelColor)
              : lyricsStyle,
        );
    if (!line.any((s) => s.chord != null)) return lyricText(text);

    // Intro, solo, "Intro: D A | Bm x2": sem letra embaixo, tudo numa linha só.
    // Verso com o acorde só no fim ("Em santidade servirei [F#m]") é verso:
    // antes do primeiro acorde, só rótulo ou nada.
    final lead = line.first.chord == null ? line.first.text.trim() : '';
    final instrumental = (_noLyrics.hasMatch(lead) ||
            isChordSectionLabel(lead) ||
            (lead.startsWith('(') && lead.endsWith(')'))) &&
        line
            .where((s) => s.chord != null)
            .every((s) => _noLyrics.hasMatch(s.text));
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: instrumental
          ? line.expand((s) => [s.chord, s.text.trim()]).nonNulls.join(' ')
          : text,
      child: Wrap(
        spacing: instrumental ? AppSpacing.sm : 0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final s in line)
            if (!instrumental)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A folga impede "A4 A" no fim da linha de virar "A4A".
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: Text(s.chord ?? ' ', style: chordStyle),
                  ),
                  lyricText(s.text),
                ],
              )
            else ...[
              if (s.chord != null) Text(s.chord!, style: chordStyle),
              if (s.text.trim().isNotEmpty)
                Text(
                  s.text.trim(),
                  style: lyricsStyle.copyWith(color: labelColor),
                ),
            ],
        ],
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
    this.chordMode = false,
    this.eventId,
  });

  /// A equipe **da escala**, para buscar a letra no repertório certo.
  final String teamId;

  /// A escala, para o tom ao vivo: na cifra, o leitor confere o tom de tempo
  /// em tempo, e quem lidera grava o tom que acertou no ensaio.
  final String? eventId;

  /// As músicas do culto, na ordem da escala.
  final List<EventSong> songs;
  final int initialIndex;
  final bool chordMode;

  @override
  ConsumerState<EventLyricsScreen> createState() => _EventLyricsScreenState();
}

class _EventLyricsScreenState extends ConsumerState<EventLyricsScreen> {
  int? _steps;
  Timer? _poll;
  bool _checking = false;
  bool _savingKey = false;

  /// Os tons que o servidor devolveu desde que a tela abriu, por
  /// `culto:música`. Ausente = vale o que veio com a escala.
  final _liveKeys = <String, String?>{};

  static String _slot(EventSong song) => '${song.serviceId}:${song.songId}';

  String? _keyOf(EventSong song) =>
      _liveKeys.containsKey(_slot(song)) ? _liveKeys[_slot(song)] : song.key;

  void _move(int delta) => setState(() {
        _index += delta;
        _steps = null;
      });

  late int _index = widget.initialIndex.clamp(0, widget.songs.length - 1);

  @override
  void initState() {
    super.initState();
    // Só na cifra: é nela que o tom muda o que se toca. Cinco segundos é o
    // atraso de um aviso falado; a rota tem limite próprio na API.
    if (widget.chordMode && widget.eventId != null) {
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _checkKeys());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _checkKeys() async {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    // Fora da tela (outro app, aba escondida) não pergunta.
    if (_checking ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    _checking = true;
    try {
      final keys =
          await ref.read(eventRepositoryProvider).songKeys(widget.eventId!);
      if (!mounted) return;
      final atual = widget.songs[_index];
      final before = _keyOf(atual);
      setState(() {
        for (final song in widget.songs) {
          if (keys.containsKey(_slot(song))) {
            _liveKeys[_slot(song)] = keys[_slot(song)];
          }
        }
        // O tom combinado mudou: a transposição pessoal deixa de valer.
        if (_keyOf(atual) != before) _steps = null;
      });
      final now = _keyOf(atual);
      if (now != before && now != null) {
        showAppSnackBar(context, 'Tom mudou para $now.');
      }
    } catch (_) {
      // Sem rede no ensaio: o leitor segue com o tom que já tem.
    } finally {
      _checking = false;
    }
  }

  /// Grava o tom que quem lidera acertou no −/+ como o tom desta música
  /// nesta escala. Não avisa ninguém no celular: os leitores abertos mudam
  /// sozinhos, e quem abrir depois já abre no tom novo.
  Future<void> _useForAll(EventSong song, String key) async {
    setState(() => _savingKey = true);
    try {
      await ref
          .read(eventRepositoryProvider)
          .setSongKey(widget.eventId!, song, key);
      if (!mounted) return;
      setState(() {
        _liveKeys[_slot(song)] = key;
        _steps = null;
      });
      ref.invalidate(eventProvider(widget.eventId!));
      showAppSnackBar(
        context,
        'Tom $key para todos nesta escala.',
        tone: AppTone.success,
      );
    } on ApiException catch (error) {
      if (mounted) {
        showAppSnackBar(context, error.message, tone: AppTone.danger);
      }
    } finally {
      if (mounted) setState(() => _savingKey = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeepScreenOn(
      child: _ReaderThemed(child: Builder(builder: _buildScreen)),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final atual = widget.songs[_index];
    final atualKey = _keyOf(atual);
    final full = ref.watch(
      songProvider((teamId: widget.teamId, songId: atual.songId)),
    );
    final anterior = _index > 0 ? widget.songs[_index - 1] : null;
    final proxima =
        _index < widget.songs.length - 1 ? widget.songs[_index + 1] : null;

    // Anterior só com o ícone; o "Próxima" diz qual é, que é o que se
    // procura no meio do culto.
    final navigation = widget.songs.length < 2
        ? null
        : Row(
            children: [
              IconButton(
                tooltip:
                    anterior == null ? null : 'Anterior: ${anterior.title}',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: anterior == null ? null : () => _move(-1),
              ),
              if (proxima != null)
                Flexible(
                  child: TextButton.icon(
                    onPressed: () => _move(1),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.chevron_right_rounded),
                    label: Text(
                      'Próxima: ${proxima.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          );

    final title = widget.chordMode ? 'Cifra' : 'Letra';
    final song = full.valueOrNull?.data;
    final cachedAt = full.valueOrNull?.cachedAt;
    final sourceKey = normalizeMusicalKey(song?.chordsKey);
    final target = _readerTarget(atualKey, sourceKey, _steps);
    // Papel da equipe DA ESCALA, não da equipe ativa (armadilha 10).
    final canManage = widget.chordMode &&
        widget.eventId != null &&
        (ref
                .watch(authControllerProvider)
                .teams
                .where((t) => t.teamId == widget.teamId)
                .firstOrNull
                ?.canManage ??
            false);
    final offerKey = canManage &&
            _steps != null &&
            target != null &&
            target != normalizeMusicalKey(atualKey)
        ? target
        : null;
    final detalhes = [
      if (widget.songs.length > 1) '${_index + 1} de ${widget.songs.length}',
      if (atual.hymnal != null) atual.hymnal!.label,
      if (!widget.chordMode && (atualKey?.isNotEmpty ?? false)) 'Tom $atualKey',
      if (atual.momentText != null) atual.momentText!,
    ].join(' · ');

    return Scaffold(
      appBar: _readerAppBar(
        context,
        title: title,
        chordMode: widget.chordMode,
        url: widget.chordMode
            ? (song?.hasChords == false
                ? null
                : song?.chordsUrl ?? atual.chordsUrl)
            : atual.lyricsUrl,
        currentKey: sourceKey == null ? null : target ?? sourceKey,
        onStep: sourceKey != null && song!.hasChords
            ? (step) => setState(() => _steps = (_steps ?? 0) + step)
            : null,
      ),
      body: SafeArea(
        top: false,
        child: AppContentWidth.reading(
          child: Column(
            children: [
              if (cachedAt != null) CacheStampBanner(cachedAt: cachedAt),
              if (offerKey != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    heightFactor: 1,
                    child: TextButton.icon(
                      onPressed:
                          _savingKey ? null : () => _useForAll(atual, offerKey),
                      icon: const Icon(Icons.groups_outlined),
                      label: Text('Usar $offerKey para todos'),
                    ),
                  ),
                ),
              Expanded(
                child: _AutoScrollList(
                  restartKey: atual.songId,
                  navigation: navigation,
                  children: [
                    ..._readerHeader(context, atual.title, detalhes),
                    if (atual.note?.isNotEmpty ?? false) ...[
                      Text(
                        atual.note!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    full.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        child: AppLoading(),
                      ),
                      error: (_, __) => AppErrorState(
                        message:
                            'Não foi possível carregar a ${title.toLowerCase()}.',
                        onRetry: () => ref.invalidate(
                          songProvider(
                            (teamId: widget.teamId, songId: atual.songId),
                          ),
                        ),
                      ),
                      data: (cached) => widget.chordMode
                          ? ChordSheetView(
                              chords: cached.data.chords,
                              sourceKey: cached.data.chordsKey,
                              targetKey: target,
                              chordsUrl:
                                  cached.data.chordsUrl ?? atual.chordsUrl,
                            )
                          : cached.data.hasLyrics
                              ? LyricsText(lyrics: cached.data.lyrics!)
                              : Text(
                                  'A letra desta música ainda não foi guardada no '
                                  'Pauta.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                    ),
                    // No fim da música, e não no "Próxima": passar as cifras
                    // no ensaio não pode riscar o repertório do culto.
                    if (widget.eventId != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        heightFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.lg),
                          child: Consumer(
                            builder: (context, ref, _) {
                              ref.watch(playedSongsProvider);
                              final played =
                                  ref.read(playedSongsProvider.notifier);
                              final isPlayed =
                                  played.isPlayed(widget.eventId!, atual);
                              return TextButton.icon(
                                onPressed: () =>
                                    played.toggle(widget.eventId!, atual),
                                icon: Icon(
                                  isPlayed
                                      ? Icons.check_circle_rounded
                                      : Icons.check_circle_outline_rounded,
                                ),
                                label: Text(
                                  isPlayed
                                      ? 'Tocada. Desmarcar'
                                      : 'Marcar como tocada',
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A letra inteira, sem nada em volta.
///
/// É a tela de quem está ensaiando com o celular na estante: título para
/// saber que é a música certa, e o texto em corpo maior. O link do site da
/// letra, quando existe, fica no topo — a letra guardada é a preferida, mas o
/// link continua sendo um recurso da música.
class SongLyricsScreen extends StatefulWidget {
  const SongLyricsScreen({
    super.key,
    required this.song,
    this.chordMode = false,
    this.cachedAt,
  });

  final Song song;
  final bool chordMode;

  /// Quando a música veio do aparelho, sem rede.
  final DateTime? cachedAt;

  @override
  State<SongLyricsScreen> createState() => _SongLyricsScreenState();
}

class _SongLyricsScreenState extends State<SongLyricsScreen> {
  int? _steps;

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final url = widget.chordMode ? song.chordsUrl : song.lyricsUrl;
    final sourceKey = normalizeMusicalKey(song.chordsKey);
    final target = _readerTarget(song.defaultKey, sourceKey, _steps);

    return KeepScreenOn(
      child: _ReaderThemed(
        child: Builder(
          builder: (context) => Scaffold(
            appBar: _readerAppBar(
              context,
              title: widget.chordMode ? 'Cifra' : 'Letra',
              chordMode: widget.chordMode,
              url: widget.chordMode && !song.hasChords ? null : url,
              currentKey: sourceKey == null ? null : target ?? sourceKey,
              onStep: sourceKey != null && song.hasChords
                  ? (step) => setState(() => _steps = (_steps ?? 0) + step)
                  : null,
            ),
            body: SafeArea(
              top: false,
              child: AppContentWidth.reading(
                child: Column(
                  children: [
                    if (widget.cachedAt != null)
                      CacheStampBanner(cachedAt: widget.cachedAt!),
                    Expanded(
                      child: _AutoScrollList(
                        restartKey: song.id,
                        children: [
                          ..._readerHeader(
                            context,
                            song.displayTitle,
                            song.subtitle,
                          ),
                          if (widget.chordMode)
                            ChordSheetView(
                              chords: song.chords,
                              sourceKey: song.chordsKey,
                              targetKey: target,
                              chordsUrl: song.chordsUrl,
                            )
                          else
                            LyricsText(lyrics: song.lyrics ?? ''),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
