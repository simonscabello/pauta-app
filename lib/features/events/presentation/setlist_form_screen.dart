import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/responsive/adaptive_dialog.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_bottom_action_bar.dart';
import '../../../shared/widgets/app_button_styles.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_choice_bar.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/form_scaffold.dart';
import '../../../shared/widgets/unsaved_changes_guard.dart';
import '../../songs/data/song_repository.dart';
import '../../songs/domain/moment_suggestion.dart';
import '../../songs/domain/song_history.dart';
import '../../songs/domain/song_models.dart';
import '../../songs/domain/song_sections.dart';
import '../../songs/domain/song_themes.dart';
import '../../songs/presentation/add_song_screen.dart';
import '../../songs/presentation/musical_key_picker.dart';
import '../../songs/presentation/song_theme_picker.dart';
import '../../suggestions/presentation/event_suggestions_band.dart';
import '../data/event_repository.dart';
import '../domain/event_datetime.dart';
import '../domain/event_models.dart';
import '../domain/service_moments.dart';

/// Monta o repertório da escala, **um repertório por culto**: escolhe do
/// repertório da equipe, arrasta para ordenar, e ajusta o tom quando aquele
/// culto pede diferente.
///
/// A ordem é o conteúdo, não enfeite: é a sequência que a equipe vai tocar, e é
/// assim que ela sai no texto do WhatsApp.
///
/// A mesma música pode entrar de manhã e à noite — são duas linhas, e à noite
/// pode ser outro tom e outro recado. Arrastar só reordena dentro do próprio
/// culto: mover entre cultos é tirar de um e pôr no outro, que é o que a
/// pessoa faz de qualquer forma quando muda de ideia.
class SetlistFormScreen extends ConsumerStatefulWidget {
  const SetlistFormScreen({
    super.key,
    required this.teamId,
    required this.eventId,
    this.event,
    this.isNewSchedule = false,
  });

  final String teamId;
  final String eventId;
  final Event? event;

  /// Último passo de uma escala recém-criada (criar → escalar → músicas).
  ///
  /// Salvar termina no detalhe da escala, e não voltando: os dois passos
  /// anteriores já saíram da pilha, e voltar cairia na agenda sem nunca mostrar
  /// a escala que a pessoa acabou de montar.
  final bool isNewSchedule;

  @override
  ConsumerState<SetlistFormScreen> createState() => _SetlistFormScreenState();
}

class _SetlistFormScreenState extends ConsumerState<SetlistFormScreen> {
  /// serviceId -> músicas daquele culto, na ordem.
  final Map<String, List<EventSong>> _porCulto = {};
  List<EventService> _cultos = const [];

  bool _populated = false;
  bool _saving = false;
  String? _error;

  /// Ver [kArrivalTapShield]: a tela chega pelo botão da escalação, que fica
  /// exatamente onde está o "Salvar" daqui.
  final DateTime _abertaEm = DateTime.now();

  /// Já salvou e está saindo: o botão fica travado durante a transição, em vez
  /// de voltar a aceitar toque por alguns quadros.
  bool _saindo = false;

  /// O repertório como foi aberto (ou salvo por último). É contra ele que a
  /// guarda de "Sair sem salvar?" compara.
  String _salvo = '';

  void _populate(Event event) {
    _populated = true;
    _cultos = event.displayServices;
    for (final grupo in event.songsByService) {
      _porCulto[grupo.service.id] = [...grupo.songs];
    }
    _salvo = _assinatura();
  }

  /// Tudo o que salvar mandaria: a ordem, a música e os ajustes de cada linha.
  String _assinatura() => [
        for (final culto in _cultos)
          for (final s in _lista(culto.id))
            '${culto.id}|${s.songId}|${s.keyOverride}|${s.note}|'
                '${s.moment}|${s.momentLabel}',
      ].join('\n');

  bool _alterado() => _populated && _assinatura() != _salvo;

  List<EventSong> _lista(String serviceId) =>
      _porCulto.putIfAbsent(serviceId, () => []);

  int get _total =>
      _porCulto.values.fold(0, (soma, musicas) => soma + musicas.length);

  Future<void> _save() async {
    if (DateTime.now().difference(_abertaEm) < kArrivalTapShield) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // Na ordem dos cultos: o servidor normaliza a posição dentro de cada um,
      // então o que precisa chegar certo é a sequência de cada lista.
      final todas = [
        for (final culto in _cultos) ..._lista(culto.id),
      ];
      await ref.read(eventRepositoryProvider).replaceSongs(
            widget.eventId,
            todas,
          );

      ref.invalidate(eventProvider(widget.eventId));
      if (!mounted) return;
      _salvo = _assinatura();
      _saindo = true;

      if (widget.isNewSchedule) {
        context.pushReplacement('/agenda/${widget.eventId}');
        // A escala nova é rascunho: "pronta" e "compartilhe" faziam o líder
        // procurar um ícone que só existe depois de publicar — ou mandar ao
        // grupo algo que a equipe ainda não enxerga. O botão "Publicar" fica
        // logo acima deste aviso, na barra de baixo do detalhe.
        showAppSnackBar(
          context,
          'Rascunho salvo. A equipe só vê a escala depois que você '
              'tocar em "Publicar".',
          tone: AppTone.success,
        );
        return;
      }
      context.pop();
      showAppSnackBar(context, 'Repertório salvo.', tone: AppTone.success);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted && !_saindo) setState(() => _saving = false);
    }
  }

  Future<void> _addSongs(EventService culto) async {
    final escolha = await showModalBottomSheet<_PickerResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SongPicker(
        teamId: widget.teamId,
        eventId: widget.eventId,
        culto: culto,
        // Já escaladas **neste culto** não aparecem: repetir a mesma música no
        // mesmo culto é erro e o servidor recusaria. No outro culto ela
        // continua disponível, que é o caso comum de manhã e noite.
        jaEscolhidas: _lista(culto.id).map((s) => s.songId).toSet(),
        mostrarTodosOsCultos: _cultos.length > 1,
      ),
    );

    if (escolha == null || !mounted) return;

    if (escolha.cadastrarNova) {
      final nova = await _cadastrarMusica();
      if (nova != null && mounted) {
        setState(() => _lista(culto.id).add(_novoItem(culto, nova)));
      }
      // Volta ao seletor: quem abriu para escolher músicas raramente queria
      // cadastrar só uma e ir embora.
      if (mounted) await _addSongs(culto);
      return;
    }

    setState(() {
      for (final song in escolha.songs) {
        _lista(culto.id).add(_novoItem(culto, song, moment: escolha.moment));
      }
    });
  }

  /// Cadastro completo (catálogo de outras equipes + Spotify) sem sair da
  /// escala em montagem.
  ///
  /// `Navigator.push` sobre esta tela, e não `context.push` do go_router: a
  /// escala continua viva embaixo, com o que já foi escolhido, e volta intacta
  /// quando a música é criada ou o cadastro é abandonado.
  Future<Song?> _cadastrarMusica() {
    return Navigator.of(context).push<Song>(
      MaterialPageRoute(
        builder: (rota) => AddSongScreen(
          teamId: widget.teamId,
          onCreated: (song) => Navigator.of(rota).pop(song),
        ),
      ),
    );
  }

  /// Põe no culto uma música vinda da faixa de sugestões.
  ///
  /// **Isto não aceita a sugestão**, de propósito: o líder pode estar
  /// experimentando, e a escala ainda é rascunho. Quem diz que a sugestão foi
  /// aceita é o botão "Aceitar", ali do lado — deduzir o aceite de "a música
  /// entrou" é a mesma armadilha do `isNew`.
  Future<void> _adicionarSugerida(String songId, EventService culto) async {
    try {
      // Busca a música inteira: a sugestão só carrega título e artista, e o
      // item da escala precisa do tom da equipe e dos links -- os mesmos que o
      // seletor põe quando a escolha vem de lá.
      final song = await ref
          .read(songRepositoryProvider)
          .find(widget.teamId, songId);
      if (!mounted) return;
      setState(() => _lista(culto.id).add(_novoItem(culto, song)));
    } on ApiException catch (error) {
      if (mounted) {
        showAppSnackBar(context, error.message, tone: AppTone.danger);
      }
    }
  }

  /// De onde o culto vazio pode copiar: o primeiro outro culto que já tem
  /// música. Nulo quando não há nada a copiar.
  EventService? _fonteDeCopia(EventService culto) {
    if (_lista(culto.id).isNotEmpty) return null;
    for (final outro in _cultos) {
      if (outro.id != culto.id && _lista(outro.id).isNotEmpty) return outro;
    }
    return null;
  }

  /// Manhã e noite costumam ter o mesmo repertório, e o culto vazio só
  /// oferecia "Escolher músicas" — tudo escolhido de novo, e tom e momento
  /// acertados de novo, música por música. A cópia leva a ordem, o momento e
  /// o tom desta escala; o recado fica, porque costuma ser do culto
  /// ("intro só no violão" de manhã não vale para a banda da noite).
  void _copiar({required EventService de, required EventService para}) {
    final origem = _lista(de.id);
    setState(() {
      _lista(para.id).addAll([
        for (final s in origem)
          EventSong(
            songId: s.songId,
            serviceId: para.id,
            title: s.title,
            artist: s.artist,
            key: s.key,
            keyOverride: s.keyOverride,
            defaultKey: s.defaultKey,
            isNew: s.isNew,
            moment: s.moment,
            momentLabel: s.momentLabel,
            hymnals: s.hymnals,
            chordsUrl: s.chordsUrl,
            lyricsUrl: s.lyricsUrl,
            youtubeUrl: s.youtubeUrl,
            spotifyUrl: s.spotifyUrl,
          ),
      ]);
    });
    showAppSnackBar(
      context,
      origem.length == 1
          ? '1 música copiada de ${de.label}, com momento e tom.'
          : '${origem.length} músicas copiadas de ${de.label}, com momento e '
              'tom.',
      tone: AppTone.success,
    );
  }

  EventSong _novoItem(EventService culto, Song song, {String? moment}) =>
      EventSong(
        songId: song.id,
        serviceId: culto.id,
        title: song.title,
        artist: song.artist,
        key: song.defaultKey,
        defaultKey: song.defaultKey,
        // Do cadastro: é o que faz "314 CC" aparecer na linha antes mesmo de
        // salvar, sem uma volta ao servidor.
        hymnals: song.hymnals,
        // O momento só vem quando o líder o escolheu no seletor — aí é decisão
        // dele, tomada ali. Sem escolha, a música entra sem momento: preencher
        // por dedução poria na escala uma decisão que ninguém tomou.
        moment: moment,
        chordsUrl: song.chordsUrl,
        lyricsUrl: song.lyricsUrl,
        youtubeUrl: song.youtubeUrl,
        spotifyUrl: song.spotifyUrl,
      );

  Future<void> _editItem(String serviceId, int index) async {
    final song = _lista(serviceId)[index];
    // O que o histórico já sabe dos momentos desta música: ajuda a escolher,
    // e não escolhe.
    final historico = ref
        .read(songHistoryProvider(widget.teamId))
        .valueOrNull?[song.songId];

    // "Música nova" não está aqui: é a marca que mais se mexe e a que menos
    // precisa de formulário. Ela mora no chip da própria linha, a um toque.
    final ajuste = await showAdaptiveSheet<_SongSettings>(
      context: context,
      maxWidth: 520,
      builder: (_) => _SongSettingsDialog(
        song: song,
        usualMoments: historico == null
            ? null
            : usualMomentsPhrase(historico.moments),
      ),
    );

    if (ajuste == null) return;

    setState(() {
      _lista(serviceId)[index] = EventSong(
        songId: song.songId,
        serviceId: song.serviceId,
        title: song.title,
        artist: song.artist,
        key: ajuste.keyOverride ?? song.defaultKey,
        keyOverride: ajuste.keyOverride,
        defaultKey: song.defaultKey,
        note: ajuste.note,
        isNew: song.isNew,
        moment: ajuste.moment,
        momentLabel: ajuste.momentLabel,
        hymnals: song.hymnals,
        chordsUrl: song.chordsUrl,
        lyricsUrl: song.lyricsUrl,
        youtubeUrl: song.youtubeUrl,
        spotifyUrl: song.spotifyUrl,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return UnsavedChangesGuard(
      isDirty: _alterado,
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    // O histórico das músicas começa a carregar ao abrir a montagem, e não ao
    // abrir o seletor: quando o líder toca em "Escolher músicas", as linhas já
    // nascem dizendo "Cantada há 12 dias". Observá-lo aqui também o mantém
    // vivo entre uma abertura do seletor e a seguinte.
    ref.watch(songHistoryProvider(widget.teamId));

    // O provider devolve o invólucro de cache; aqui só interessa a escala.
    final event = widget.event ??
        ref.watch(eventProvider(widget.eventId)).valueOrNull?.data;

    if (event == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Músicas da escala')),
        body: const AppLoading(),
      );
    }

    if (!_populated) _populate(event);

    final timezone =
        event.timezone.isEmpty ? 'America/Sao_Paulo' : event.timezone;

    return Scaffold(
      // "Salvar" saiu da barra do topo e virou o botão de baixo, do tamanho da
      // tela — igual ao da escalação, que é o passo imediatamente anterior no
      // mesmo fluxo. Como link de texto no canto superior ele tinha o peso de
      // uma ação secundária, ficava longe do polegar e desaparecia atrás do
      // teclado ao editar o tom de uma música.
      // "Músicas da escala", e não "Repertório da escala": no app, Repertório
      // é o acervo da equipe (a barra lateral, a aba), e "montar o
      // repertório" soava, para quem é novo, como cadastrar músicas.
      appBar: AppBar(title: const Text('Músicas da escala')),
      bottomNavigationBar: AppBottomActionBar(
        action: AppSubmitButton(
          label: widget.isNewSchedule
              ? 'Salvar e ver a escala'
              : 'Salvar músicas',
          loading: _saving,
          onPressed: _save,
        ),
      ),
      body: SafeArea(
        top: false,
        child: AppContentWidth.reading(
          child: Column(
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.md,
                    AppSpacing.screenPadding,
                    0,
                  ),
                  child: FormErrorBanner(message: _error!),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.md,
                    AppSpacing.screenPadding,
                    AppSpacing.xxl,
                  ),
                  children: [
                    // A data no topo, como na escalação: a montagem é de um
                    // domingo, e sem ela nada na tela dizia qual.
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: Text(
                        event.dateAndTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    // As sugestões da equipe para ESTE domingo, antes de tudo.
                    // É a razão de a funcionalidade existir: o líder monta o
                    // repertório vendo o que a equipe pediu, em vez de
                    // lembrar do que passou no grupo do WhatsApp.
                    EventSuggestionsBand(
                      teamId: widget.teamId,
                      eventId: widget.eventId,
                      services: _cultos,
                      setlistIsEmpty: _total == 0,
                      servicesWithSong: (songId) => {
                        for (final culto in _cultos)
                          if (_lista(culto.id).any((s) => s.songId == songId))
                            culto.id,
                      },
                      onAddToService: _adicionarSugerida,
                    ),
                    if (_total == 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                        child: Text(
                          _cultos.length > 1
                              ? 'Cada culto tem as próprias músicas. A ordem '
                                  'aqui é a ordem que vocês vão tocar.'
                              : 'Escolha do repertório da equipe. A ordem aqui '
                                  'é a ordem que vocês vão tocar.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                    for (final culto in _cultos)
                      _ServiceSetlist(
                        culto: culto,
                        timezone: timezone,
                        songs: _lista(culto.id),
                        saving: _saving,
                        copyFrom: _fonteDeCopia(culto),
                        onCopy: (fonte) => _copiar(de: fonte, para: culto),
                        onAdd: () => _addSongs(culto),
                        onEdit: (index) => _editItem(culto.id, index),
                        onRemove: (index) =>
                            setState(() => _lista(culto.id).removeAt(index)),
                        onReorder: (oldIndex, newIndex) => setState(() {
                          final lista = _lista(culto.id);
                          lista.insert(newIndex, lista.removeAt(oldIndex));
                        }),
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

/// O repertório de um culto: cabeçalho, lista arrastável e o botão de
/// acrescentar.
///
/// O cabeçalho aparece mesmo quando a escala tem um culto só. Some a dúvida de
/// "para qual culto estou escolhendo" antes de ela existir, e o botão de
/// acrescentar já nasce dizendo a que culto pertence.
class _ServiceSetlist extends StatelessWidget {
  const _ServiceSetlist({
    required this.culto,
    required this.timezone,
    required this.songs,
    required this.saving,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
    required this.onReorder,
    this.copyFrom,
    this.onCopy,
  });

  final EventService culto;
  final String timezone;
  final List<EventSong> songs;
  final bool saving;

  /// O outro culto de onde dá para copiar, quando este está vazio.
  final EventService? copyFrom;
  final ValueChanged<EventService>? onCopy;
  final VoidCallback onAdd;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.church_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${culto.label} ${formatEventTime(culto.startsAt, timezone)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (songs.isNotEmpty)
                Text(
                  songs.length == 1 ? '1 música' : '${songs.length} músicas',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (songs.isEmpty)
            AppCard(
              surface: CardSurface.sunken,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nenhuma música neste culto ainda.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (copyFrom case final fonte? when onCopy != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.tonalIcon(
                      style: AppButtonStyles.compact,
                      onPressed: saving ? null : () => onCopy!(fonte),
                      icon: const Icon(Icons.copy_all_rounded, size: 18),
                      label: Text('Copiar de ${fonte.label}'),
                    ),
                  ],
                ],
              ),
            )
          else
            // **Um cartão por culto, e as músicas como linhas dele** — como no
            // detalhe da escala. Cada música era um cartão com borda: a mesma
            // lista desenhada de dois jeitos em duas telas vizinhas.
            AppCard(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                // A rolagem é da tela: cada culto é um pedaço dela, e não um
                // painel que rola por dentro.
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: songs.length,
                // `onReorderItem` e não `onReorder`: ele já entrega o índice
                // de destino corrigido para o item removido, e compensar à mão
                // aqui erraria por um ao arrastar para baixo.
                onReorderItem: onReorder,
                // A linha arrastada ganha a superfície do cartão: fora dele,
                // no meio do arraste, ela ficaria transparente sobre a página.
                proxyDecorator: (child, _, __) => Material(
                  color: scheme.surfaceContainerLowest,
                  elevation: 4,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  child: child,
                ),
                itemBuilder: (context, index) => Column(
                  // A chave precisa distinguir a linha, e não só a música: a
                  // mesma canção pode estar nos dois cultos.
                  key: ValueKey('${culto.id}:${songs[index].songId}'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (index > 0)
                      Divider(
                        height: 1,
                        indent: AppSpacing.lg,
                        color: scheme.outlineVariant,
                      ),
                    _SetlistTile(
                      song: songs[index],
                      position: index + 1,
                      index: index,
                      onEdit: () => onEdit(index),
                      onRemove: () => onRemove(index),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: saving ? null : onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                songs.isEmpty
                    ? 'Escolher músicas'
                    : 'Acrescentar em ${culto.label}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Os ajustes ainda vazios de uma música da escala, na ordem da folha.
List<String> _faltando(EventSong song, bool hasKey) => [
      if (!hasKey) 'tom',
      if (song.moment == null) 'momento',
      if (song.note == null || song.note!.isEmpty) 'recado',
    ];

class _SetlistTile extends StatelessWidget {
  const _SetlistTile({
    required this.song,
    required this.position,
    required this.index,
    required this.onEdit,
    required this.onRemove,
  });

  final EventSong song;
  final int position;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final hasKey = song.key != null && song.key!.isNotEmpty;
    final details = [
      if (song.hymnal != null) song.hymnal!.label,
      if (song.momentText != null) song.momentText!,
      if (song.artist != null && song.artist!.isNotEmpty) song.artist!,
    ].join(' · ');

    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$position',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontFeatures: AppTypography.tabular,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A etiqueta é só leitura, aqui e em toda parte: quem
                  // responde "a equipe já tocou esta?" é o histórico, não quem
                  // monta. Aparece nesta tela porque quem escolhe o repertório
                  // precisa ver quanta novidade está pedindo para um domingo.
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (song.isNew) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const AppBadge(label: 'Nova', tone: AppTone.info),
                      ],
                    ],
                  ),
                  // "314 CC · Dízimos e Ofertas". O hinário abre a linha
                  // porque é o que identifica a música ("ninguém pede Pão da
                  // Vida, pede 142"), e o que não existe simplesmente não
                  // aparece -- nenhum "—" de campo vazio.
                  if (details.isNotEmpty)
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (song.note != null && song.note!.isNotEmpty)
                    Text(
                      song.note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  // **O que falta ajustar, escrito na linha.** A linha abria
                  // tom, momento e recado ao toque, sem nenhum sinal disso: quem
                  // não descobria deixava o tom vazio, e o músico lia "Tom —".
                  // Cada marcador some quando o valor existe — aí é o próprio
                  // valor que aparece.
                  if (_faltando(song, hasKey) case final faltam
                      when faltam.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        faltam.map((f) => '+ $f').join('  ·  '),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // O tom à direita, como no detalhe da escala: violeta quando esta
            // escala mudou o tom da equipe. Pintar a linha de apoio inteira de
            // violeta fazia o hinário e o artista parecerem a alteração.
            if (hasKey) ...[
              const SizedBox(width: AppSpacing.sm),
              AppBadge(
                label: song.key!,
                tone: song.hasCustomKey ? AppTone.primary : AppTone.neutral,
                semanticsLabel: song.hasCustomKey
                    ? 'Tom desta escala: ${song.key}'
                    : 'Tom: ${song.key}',
              ),
            ],
            IconButton(
              tooltip: 'Tirar do culto',
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: onRemove,
            ),
            // A alça é explícita porque `buildDefaultDragHandles` está
            // desligado: com a lista dentro da rolagem da tela, a alça
            // automática disputava o gesto de rolar.
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Icon(
                  Icons.drag_handle_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// O que a folha de ajustes devolve. Campos nulos são o campo apagado, e não
/// "não mexi": a folha mostra o estado inteiro e devolve o estado inteiro.
class _SongSettings {
  const _SongSettings({
    this.keyOverride,
    this.note,
    this.moment,
    this.momentLabel,
  });

  final String? keyOverride;
  final String? note;
  final String? moment;
  final String? momentLabel;
}

/// Tom, momento do culto e recado desta música **nesta escala**.
///
/// Os três são da linha da escala, e não do cadastro: a mesma canção sobe um
/// tom quando quem canta muda, é oferta num domingo e abertura no outro, e o
/// recado ("entra só o teclado") vale para aquele culto.
///
/// **O momento começa em "sem momento", e não em "Momento de Louvor".** A
/// maioria das músicas de uma escala não tem momento nomeado; escolher um por
/// quem não escolheu poria na escala publicada uma decisão de ninguém.
class _SongSettingsDialog extends StatefulWidget {
  const _SongSettingsDialog({required this.song, this.usualMoments});

  final EventSong song;

  /// "Momento de Louvor (7 vezes) · Abertura (2 vezes)", do histórico das
  /// escalas. Só informa: nenhum chip vem marcado por causa disso.
  final String? usualMoments;

  @override
  State<_SongSettingsDialog> createState() => _SongSettingsDialogState();
}

class _SongSettingsDialogState extends State<_SongSettingsDialog> {
  /// Nulo é "vale o tom da equipe". Um tom anotado antes da lista volta como
  /// está, como na edição da música.
  late String? _keyOverride = (widget.song.keyOverride ?? '').trim().isEmpty
      ? null
      : widget.song.keyOverride!.trim();
  late final TextEditingController _note = TextEditingController(
    text: widget.song.note ?? '',
  );
  late final TextEditingController _momentLabel = TextEditingController(
    text: widget.song.momentLabel ?? '',
  );

  late String? _moment = widget.song.moment;

  @override
  void dispose() {
    _note.dispose();
    _momentLabel.dispose();
    super.dispose();
  }

  void _aplicar() {
    final recado = _note.text.trim();
    final rotulo = _momentLabel.text.trim();

    Navigator.pop(
      context,
      _SongSettings(
        keyOverride: _keyOverride,
        note: recado.isEmpty ? null : recado,
        moment: _moment,
        // Só em "Outro", como no servidor: guardar "Santa Ceia" preso a
        // "Abertura" deixaria o nome de uma escolha desfeita na linha.
        momentLabel: _moment == otherServiceMoment && rotulo.isNotEmpty
            ? rotulo
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Text(
                widget.song.title,
                style: theme.textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            MusicalKeyField(
              label: 'Tom neste culto',
              value: _keyOverride,
              helperText: widget.song.defaultKey != null
                  ? 'Sem escolher, fica ${widget.song.defaultKey}'
                  : null,
              onChanged: (key) => setState(() => _keyOverride = key),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Momento do culto (opcional)',
              style: theme.textTheme.titleSmall,
            ),
            if (widget.usualMoments != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Já entrou em: ${widget.usualMoments}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final entry in serviceMoments.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _moment == entry.key,
                    // Tocar no que já está marcado limpa: é como se volta
                    // atrás sem um chip "nenhum" ocupando a primeira posição.
                    onSelected: (marcado) => setState(
                      () => _moment = marcado ? entry.key : null,
                    ),
                  ),
              ],
            ),
            if (_moment == otherServiceMoment) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _momentLabel,
                textCapitalization: TextCapitalization.words,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Qual momento',
                  hintText: 'Ex.: Santa Ceia',
                  // O contador de 40 seria a única coisa numerada da folha,
                  // para um campo de duas palavras.
                  counterText: '',
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Recado',
                hintText: 'Ex.: entra só o teclado',
              ),
            ),
          ],
                ),
              ),
            ),
            // Os botões ficam fora da rolagem: com o teclado aberto no
            // recado, "Aplicar" não pode sumir embaixo dele.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(onPressed: _aplicar, child: const Text('Aplicar')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// O que o seletor devolve: as músicas marcadas, ou o pedido de cadastrar uma
/// que ainda não existe no repertório.
class _PickerResult {
  const _PickerResult.songs(this.songs, {this.moment}) : cadastrarNova = false;
  const _PickerResult.cadastrar()
      : songs = const [],
        cadastrarNova = true,
        moment = null;

  final List<Song> songs;
  final bool cadastrarNova;

  /// O momento escolhido no seletor, que as músicas marcadas levam. Nulo = o
  /// líder não escolheu, e elas entram sem momento.
  final String? moment;
}

/// A letra ou a faixa de números que abre um trecho da lista.
///
/// Discreto de propósito: letra pequena em maiúscula, na cor do texto de apoio,
/// e um fio que corre até a borda. Sem fundo tingido e sem barra — o marcador
/// existe para o olho saber onde está enquanto rola, não para ser lido. Uma
/// faixa colorida a cada dez linhas seria mais visível que as próprias músicas.
class _SectionMarker extends StatelessWidget {
  const _SectionMarker({required this.label, required this.first});

  final String label;

  /// O primeiro não leva folga acima: ele encosta na barra de filtros.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        first ? AppSpacing.sm : AppSpacing.lg,
        AppSpacing.screenPadding,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Divider(height: 1, color: scheme.outlineVariant),
          ),
        ],
      ),
    );
  }
}

/// O vazio do seletor, que agora depende também da aba.
///
/// Dizer "o repertório está vazio" enquanto a pessoa está em "Hinos" com 581
/// hinos cadastrados seria mentira: o que está vazio é a aba.
class _PickerEmpty extends StatelessWidget {
  const _PickerEmpty({
    required this.filter,
    required this.searching,
    required this.themes,
    required this.onCadastrar,
    required this.onClearThemes,
    this.otherTabs = const {},
    this.onOpenTab,
  });

  final SongFilter filter;
  final bool searching;

  /// Com busca: as outras abas que têm resultado, e quantos.
  final Map<SongFilter, int> otherTabs;
  final ValueChanged<SongFilter>? onOpenTab;
  final Set<String> themes;
  final VoidCallback onCadastrar;
  final VoidCallback onClearThemes;

  @override
  Widget build(BuildContext context) {
    if (searching) {
      // A música pode estar na aba ao lado: o hino procurado em Cânticos
      // "não existia", e a saída oferecida era cadastrá-lo de novo.
      if (otherTabs.isNotEmpty && onOpenTab != null) {
        final (aba, quantas) = (otherTabs.keys.first, otherTabs.values.first);
        final nome = switch (aba) {
          SongFilter.hinos => 'Hinos',
          SongFilter.novas => 'Novas',
          SongFilter.canticos => 'Cânticos',
          SongFilter.arquivadas => 'Arquivadas',
        };
        return AppEmptyState(
          icon: Icons.search_rounded,
          title: 'Nada nesta aba',
          message: quantas == 1
              ? 'Há 1 música com esse nome em $nome.'
              : 'Há $quantas músicas com esse nome em $nome.',
          actionLabel: 'Ver em $nome',
          onAction: () => onOpenTab!(aba),
        );
      }
      return AppEmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nenhuma música com esse nome',
        message: 'Não está em nenhuma aba. Dá para cadastrar agora.',
        actionLabel: 'Cadastrar música',
        onAction: onCadastrar,
      );
    }

    if (themes.isNotEmpty) {
      return AppEmptyState(
        icon: Icons.sell_outlined,
        title: 'Nada com esses temas',
        message: switch (filter) {
          SongFilter.canticos =>
            'Nenhum cântico classificado assim. Se for hino, toque em Hinos.',
          SongFilter.hinos =>
            'Nenhum hino classificado assim. Se for cântico, toque em Cânticos.',
          SongFilter.novas =>
            'Nenhuma música em aprendizado com esses temas.',
          SongFilter.arquivadas =>
            'Nenhuma música arquivada com esses temas.',
        },
        actionLabel: 'Limpar temas',
        onAction: onClearThemes,
      );
    }

    final (String title, String message) = switch (filter) {
      SongFilter.hinos => (
          'Nenhum hino para adicionar',
          'Ou a equipe ainda não tem hinos cadastrados, ou todos já estão '
              'neste culto.',
        ),
      SongFilter.novas => (
          'Nenhuma música em aprendizado',
          'As músicas marcadas como novas aparecem aqui. Procure em Cânticos '
              'ou em Hinos.',
        ),
      SongFilter.canticos => (
          'Nada para adicionar',
          'Ou o repertório está vazio, ou todos os cânticos já estão neste '
              'culto.',
        ),
      // O seletor da escala não abre o arquivo: a música é arquivada
      // justamente para deixar de aparecer aqui.
      SongFilter.arquivadas => (
          'Nada para adicionar',
          'As músicas arquivadas ficam fora do repertório da escala.',
        ),
    };

    return AppEmptyState(
      icon: Icons.library_music_outlined,
      title: title,
      message: message,
      actionLabel: 'Cadastrar música',
      onAction: onCadastrar,
    );
  }
}

/// A segunda linha de uma música no seletor: o que o histórico diz dela.
///
/// `Cantada há 12 dias · 3 vezes em 6 meses · Gratidão, Entrega`
///
/// - **a última vez** abre a linha, e vem tingida quando é recente — o aviso
///   discreto de que pô-la de novo vira repetição. Avisa, e não impede;
/// - **quantas vezes** só a partir de duas, porque "1 vez" repetiria a frase
///   anterior;
/// - **até dois temas**, que é o que cabe numa linha e o que ajuda a escolher.
///
/// O tom da equipe já está na primeira linha. A música nunca cantada e sem
/// tema não ganha segunda linha nenhuma: são centenas de hinos importados, e
/// "nunca cantada" em cada um seria ruído.
@visibleForTesting
({String? lastPlayed, bool recent, String? rest}) songPickerHistory(
  Song song,
  SongHistory? history,
  DateTime now,
) {
  final rest = [
    if (recentCountPhrase(history?.last6Months ?? 0) case final vezes?) vezes,
    if (song.themes.isNotEmpty)
      song.themes.take(2).map(songThemeLabel).join(', '),
  ];
  return (
    lastPlayed: lastPlayedPhrase(history?.lastPlayedAt, now),
    recent: isRecentlyPlayed(history?.lastPlayedAt, now),
    rest: rest.isEmpty ? null : rest.join(' · '),
  );
}

/// Os momentos que o seletor oferece. "Outro" fica de fora: ele pede um nome
/// escrito à mão, e isso continua na folha de ajustes da música.
final _pickerMoments = [
  for (final entry in serviceMoments.entries)
    if (entry.key != otherServiceMoment) entry,
];

/// Quantas "Sugestões do Pauta" aparecem. Poucas: são um atalho no topo da
/// lista, e o repertório inteiro continua logo abaixo.
const _maxMomentSuggestions = 3;

/// Um marcador de trecho que não vem de `buildSongSections`.
class _MarkerItem {
  const _MarkerItem(this.label);

  final String label;
}

/// Escolha múltipla do repertório da equipe, para um culto.
class _SongPicker extends ConsumerStatefulWidget {
  const _SongPicker({
    required this.teamId,
    required this.eventId,
    required this.culto,
    required this.jaEscolhidas,
    required this.mostrarTodosOsCultos,
  });

  final String teamId;

  /// A escala em montagem: é a data dela que decide o que as sugestões deixam
  /// de fora (a música do domingo anterior, a do seguinte).
  final String eventId;
  final EventService culto;
  final Set<String> jaEscolhidas;

  /// Com mais de um culto, o seletor diz para qual deles está escolhendo.
  final bool mostrarTodosOsCultos;

  @override
  ConsumerState<_SongPicker> createState() => _SongPickerState();
}

class _SongPickerState extends ConsumerState<_SongPicker> {
  /// Por id, e não pelo objeto: a mesma música pode aparecer duas vezes na
  /// lista — nas sugestões e no trecho dela —, como dois objetos diferentes.
  /// Marcar uma precisa marcar a outra, e nunca entrar duas vezes no culto.
  final _selecionadas = <String, Song>{};
  String _search = '';

  /// Mesmo filtro do Repertório, e começando em "Cânticos" pelo mesmo motivo.
  ///
  /// **Este seletor não mostrava hino nenhum.** Ele construía a `SongQuery` sem
  /// `filter`, e o padrão dela é `canticos` — que exclui hinos de propósito.
  /// Resultado: 581 dos 861 títulos da igreja eram inalcançáveis na hora de
  /// montar a escala, e a única saída era cadastrar de novo uma música que já
  /// existia.
  SongFilter _filter = SongFilter.canticos;
  Set<String> _themes = {};

  /// O momento do culto para o qual o líder está escolhendo. Opcional: sem
  /// ele, o seletor é o de sempre. Com ele, aparecem as "Sugestões do Pauta"
  /// e as músicas marcadas entram já com esse momento — porque foi o líder
  /// quem disse, aqui.
  String? _moment;

  Widget _tile(Song song, {Widget? details}) {
    final marcada = _selecionadas.containsKey(song.id);

    return CheckboxListTile(
      value: marcada,
      isThreeLine: details != null,
      controlAffinity: ListTileControlAffinity.leading,
      // O tom à direita, como em toda lista de música do app.
      secondary: song.defaultKey == null
          ? null
          : AppBadge(
              label: song.defaultKey!,
              tone: AppTone.primary,
              semanticsLabel: 'Tom da equipe: ${song.defaultKey}',
            ),
      title: Text(song.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            [
              // No hino o número abre a linha: é assim que a igreja pede
              // ("142", não "Pão da Vida"). Com a sigla junto, porque a mesma
              // igreja canta de mais de um livro.
              if (song.hymnal != null) song.hymnal!.label,
              song.subtitle,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (details != null) details,
        ],
      ),
      onChanged: (_) => setState(() {
        if (marcada) {
          _selecionadas.remove(song.id);
        } else {
          _selecionadas[song.id] = song;
        }
      }),
    );
  }

  Widget? _historyLine(Song song, SongHistory? history, DateTime now) {
    final linha = songPickerHistory(song, history, now);
    if (linha.lastPlayed == null && linha.rest == null) return null;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Text.rich(
      TextSpan(
        children: [
          if (linha.lastPlayed != null)
            TextSpan(
              text: linha.lastPlayed,
              // Âmbar é o papel de atenção do app: "cuidado com a repetição",
              // sem o susto do vermelho.
              style: linha.recent
                  ? TextStyle(
                      color: scheme.tertiary,
                      fontWeight: FontWeight.w600,
                    )
                  : null,
            ),
          if (linha.lastPlayed != null && linha.rest != null)
            const TextSpan(text: ' · '),
          if (linha.rest != null) TextSpan(text: linha.rest),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );
  }

  Widget? _reasonsLine(MomentSuggestion suggestion, DateTime now) {
    final linha = suggestionReasonsLine(suggestion.reasons, now);
    if (linha.isEmpty) return null;

    final theme = Theme.of(context);
    return Text(
      linha,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final searching = _search.trim().isNotEmpty;

    final query = SongQuery(
      teamId: widget.teamId,
      search: _search,
      filter: _filter,
      themes: _themes,
    );
    final songs = ref.watch(songsProvider(query));
    final contagens = searching ? ref.watch(songTabCountsProvider(query)) : null;

    // Uma chamada para a lista inteira (ver `songHistoryProvider`). Sem ela, as
    // linhas só não ganham a segunda frase: a escolha continua possível.
    final history = ref.watch(songHistoryProvider(widget.teamId)).valueOrNull ??
        const <String, SongHistory>{};

    // Só com momento escolhido e sem busca: quem digita um nome já sabe o que
    // quer, e as sugestões no topo empurrariam o resultado para baixo.
    final moment = _moment;
    final sugestoes = moment == null || searching
        ? const <MomentSuggestion>[]
        : [
            for (final sugestao in ref
                    .watch(
                      momentSuggestionsProvider(
                        (eventId: widget.eventId, moment: moment),
                      ),
                    )
                    .valueOrNull ??
                const <MomentSuggestion>[])
              if (!widget.jaEscolhidas.contains(sugestao.song.id)) sugestao,
          ].take(_maxMomentSuggestions).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (_, controller) => Column(
        children: [
          if (widget.mostrarTodosOsCultos)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                0,
                AppSpacing.screenPadding,
                AppSpacing.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Escolhendo para ${widget.culto.label}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _search = v),
              decoration: const InputDecoration(
                hintText: 'Buscar no repertório',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // **O momento à vista, e não atrás de um ícone de filtro.** Ele não
          // é filtro: escolher "Momento de Louvor" traz as Sugestões do Pauta
          // para o topo e faz as músicas marcadas entrarem já com o momento —
          // a ferramenta mais útil da montagem, que quase ninguém achava num
          // diálogo empilhado sobre a folha. Opcional, e nenhum vem marcado.
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
              ),
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Text(
                      'Para qual momento?',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                for (final entry in _pickerMoments)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: _moment == entry.key,
                      // Tocar no marcado desmarca, como na folha de ajustes.
                      onSelected: (marcado) => setState(
                        () => _moment = marcado ? entry.key : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Abas e temas numa linha só. Com busca, cada aba diz quantas
          // músicas tem — "Hinos (3)" — para ninguém concluir que o hino não
          // existe por estar olhando Cânticos.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              0,
              AppSpacing.screenPadding - AppSpacing.sm,
              0,
            ),
            child: Row(
              children: [
                // As mesmas três abas do Repertório, na mesma ordem: quem monta
                // a escala é quem cadastra as músicas, e o acervo é o mesmo.
                Flexible(
                  child: AppChoiceBar<SongFilter>(
                    value: _filter,
                    onChanged: (value) => setState(() => _filter = value),
                    options: [
                      AppChoice(
                        value: SongFilter.canticos,
                        label: songTabLabel(
                          'Cânticos',
                          contagens?[SongFilter.canticos],
                        ),
                      ),
                      AppChoice(
                        value: SongFilter.hinos,
                        label: songTabLabel(
                          'Hinos',
                          contagens?[SongFilter.hinos],
                        ),
                      ),
                      AppChoice(
                        value: SongFilter.novas,
                        label: songTabLabel(
                          'Novas',
                          contagens?[SongFilter.novas],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SongThemeFilterButton(
                  selected: _themes,
                  onChanged: (themes) => setState(() => _themes = themes),
                ),
              ],
            ),
          ),
          if (_themes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            SongThemeFilterBar(
              selected: _themes,
              showTrigger: false,
              onChanged: (themes) => setState(() => _themes = themes),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: songs.when(
              loading: () => const AppLoading(),
              error: (error, _) => AppErrorState(
                message: error is ApiException
                    ? error.message
                    : 'Não foi possível carregar o repertório.',
              ),
              data: (list) {
                final disponiveis = list
                    .where((s) => !widget.jaEscolhidas.contains(s.id))
                    .toList();

                if (disponiveis.isEmpty && sugestoes.isEmpty) {
                  return _PickerEmpty(
                    filter: _filter,
                    searching: searching,
                    otherTabs: {
                      for (final entry
                          in (contagens ?? const <SongFilter, int>{}).entries)
                        if (entry.key != _filter && entry.value > 0)
                          entry.key: entry.value,
                    },
                    onOpenTab: (tab) => setState(() => _filter = tab),
                    themes: _themes,
                    onCadastrar: () => Navigator.pop(
                      context,
                      const _PickerResult.cadastrar(),
                    ),
                    onClearThemes: () => setState(() => _themes = {}),
                  );
                }

                final entries = buildSongSections(
                  disponiveis,
                  filter: _filter,
                  searching: searching,
                );

                // As sugestões são itens da mesma lista, e não um bloco fixo
                // acima dela: rolam junto, e a lista continua construindo só o
                // que aparece.
                final items = <Object>[
                  if (sugestoes.isNotEmpty) ...[
                    const _MarkerItem('Sugestões do Pauta'),
                    ...sugestoes,
                    // Sem marcador próprio no começo do trecho seguinte, as
                    // sugestões se confundiriam com o resto da lista.
                    if (entries.isNotEmpty && entries.first is! SongSectionHeader)
                      const _MarkerItem('Repertório'),
                  ],
                  ...entries,
                ];

                return ListView.builder(
                  controller: controller,
                  // O marcador de seção é item da lista, não cabeçalho fixo:
                  // assim o `ListView` continua construindo só o que aparece,
                  // que com 581 hinos é o que mantém a rolagem leve.
                  itemCount: items.length,
                  itemBuilder: (_, index) {
                    final item = items[index];
                    return switch (item) {
                      _MarkerItem(:final label) =>
                        _SectionMarker(label: label, first: index == 0),
                      SongSectionHeader(:final label) =>
                        _SectionMarker(label: label, first: index == 0),
                      MomentSuggestion() => _tile(
                          item.song,
                          details: _reasonsLine(item, now),
                        ),
                      SongSectionItem(:final song) => _tile(
                          song,
                          details: _historyLine(song, history[song.id], now),
                        ),
                      _ => const SizedBox.shrink(),
                    };
                  },
                );
              },
            ),
          ),
          // `SafeArea` no rodapé: a folha ocupa a tela inteira e o `Padding`
          // sozinho não sabia da barra de navegação do Android — "Cadastrar" e
          // "Adicionar" ficavam **por baixo** dos botões do sistema, cortados
          // ao meio. `SafeArea` usa `padding`, que já desconta o teclado: com
          // ele aberto o recuo vai a zero, porque aí é o teclado que cobre a
          // barra e somar os dois empurraria os botões para o meio da tela.
          // **As escolhidas pelo nome**, e não só "Adicionar 3": marcar em
          // Cânticos, trocar para Hinos e marcar mais deixava as primeiras
          // fora de vista, sem jeito de conferir nem de desmarcar.
          if (_selecionadas.isNotEmpty) ...[
            const Divider(height: 1),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                  vertical: AppSpacing.xs,
                ),
                children: [
                  for (final song in _selecionadas.values)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: InputChip(
                        label: Text(song.title),
                        onDeleted: () =>
                            setState(() => _selecionadas.remove(song.id)),
                        deleteIcon: const Icon(Icons.close_rounded, size: 16),
                        deleteButtonTooltipMessage: 'Desmarcar ${song.title}',
                      ),
                    ),
                ],
              ),
            ),
          ],
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: Row(
                children: [
                // Sem `Expanded`: o botão fica com a largura do próprio texto.
                // Dividir a linha em frações espremia "Cadastrar" em um terço
                // da tela e quebrava a palavra no meio ("Cadast / rar").
                //
                // Sempre visível, e não só na lista vazia: quem já sabe que a
                // música não está cadastrada não deveria ter de procurar por
                // ela primeiro para descobrir o caminho.
                  TextButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      const _PickerResult.cadastrar(),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Cadastrar', softWrap: false),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // O que sobra vai para a ação principal.
                  Expanded(
                    child: FilledButton(
                      onPressed: _selecionadas.isEmpty
                          ? null
                          : () => Navigator.pop(
                                context,
                                _PickerResult.songs(
                                  _selecionadas.values.toList(),
                                  moment: _moment,
                                ),
                              ),
                      // Sem o momento no rótulo: num celular ele cortava o
                      // botão ao meio ("Adicionar 1 · Dízimos e…"), e o chip
                      // marcado logo acima já diz em que momento elas entram.
                      child: Text(
                        _selecionadas.isEmpty
                            ? 'Escolha as músicas'
                            : 'Adicionar ${_selecionadas.length}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
