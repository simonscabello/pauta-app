import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/responsive/adaptive_dialog.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../core/text/text_search.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_bottom_action_bar.dart';
import '../../../shared/widgets/app_button_styles.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_options_sheet.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/position_icon.dart';
import '../../../shared/widgets/on_leave_badge.dart';
import '../../../shared/widgets/unavailable_badge.dart';
import '../../../shared/widgets/form_scaffold.dart';
import '../../../shared/widgets/unsaved_changes_guard.dart';
import '../../events/data/event_repository.dart';
import '../../events/domain/event_models.dart';
import '../../events/presentation/schedule_changed_dialog.dart';
import '../../team/data/team_repository.dart';
import '../../team/domain/team_models.dart';
import '../../team/domain/workload_report.dart';

@visibleForTesting
List<Map<String, Object?>> buildAssignmentPayload(
  Map<String, Set<String>> selected,
  Map<(String, String), String> notes,
) {
  return <Map<String, Object?>>[
    for (final entry in selected.entries)
      for (final membershipId in entry.value)
        {
          'membershipId': membershipId,
          'positionId': entry.key,
          if (notes[(entry.key, membershipId)] case final note?) 'note': note,
        },
  ];
}

/// Como o rodízio da pessoa aparece na linha do seletor.
///
/// O líder não escala por planilha: ele lembra de quem vem à cabeça, e quem vem
/// à cabeça é quem tocou no domingo passado. Duas informações curtas ao lado do
/// nome — há quanto tempo e quantas vezes — bastam para ele reparar em quem
/// está sumindo da escala. **Não bloqueia nem sugere nada**: a decisão continua
/// sendo dele, que sabe de coisas que o app não sabe.
@visibleForTesting
String rotationSummary(
  RotationMember? rotation, {
  required int weeks,
  required DateTime now,
}) {
  final last = rotation?.lastScheduledAt;
  if (last == null) return 'Sem escala no último ano';

  final days = now.toUtc().difference(last).inDays;
  final when = switch (days) {
    <= 0 => 'Hoje',
    1 => 'Ontem',
    < 14 => 'Há $days dias',
    < 60 => 'Há ${(days / 7).round()} semanas',
    _ => 'Há ${(days / 30).round()} meses',
  };

  final count = rotation!.recentCount;
  return '$when · $count ${count == 1 ? 'escala' : 'escalas'} '
      'em $weeks semanas';
}

/// Para onde a escalação leva depois de salvar.
///
/// Nulo é "volta de onde veio" — a edição de uma escala que já existe. Nos
/// outros dois casos esta tela é o segundo passo de uma escala recém-criada, e
/// o terceiro depende do que a escala é: com repertório planejado, montar as
/// músicas; com repertório definido na hora, **não há terceiro passo**, e
/// insistir em levar até a tela de repertório é justamente o desvio que esse
/// modo existe para apagar.
///
/// Pura e exportada para poder ser testada sem montar a tela inteira: a
/// decisão é pequena, e é a que faz a diferença entre criar uma escala em dois
/// passos ou em três.
String? nextStepAfterAssignments({
  required String eventId,
  required bool isNewSchedule,
  required bool repertoireOnTheFly,
}) {
  if (!isNewSchedule) return null;
  return repertoireOnTheFly
      ? '/agenda/$eventId'
      : '/agenda/$eventId/repertorio?novo=1';
}

/// Montagem da escala.
///
/// A primeira versão listava todos os membros em checkbox dentro de cada
/// função: com 6 funções e 6 integrantes eram 36 linhas e uma rolagem enorme
/// para uma tarefa que o líder repete toda semana. Aqui cada função é uma
/// linha que mostra quem já está escalado, e a escolha acontece numa folha
/// focada em uma função de cada vez.
class AssignmentFormScreen extends ConsumerStatefulWidget {
  const AssignmentFormScreen({
    super.key,
    required this.eventId,
    this.nextIsSetlist = false,
    this.replaceMembershipId,
  });

  final String eventId;

  /// Quem precisa sair desta escala: veio do aviso "Fulano não pode". A tela
  /// abre com a pessoa destacada e "Tirar de todas as funções" à mão — trocar
  /// quem não pode levava oito passos (abrir cada função, desmarcar, e lembrar
  /// do ministrante à parte).
  final String? replaceMembershipId;

  /// Esta tela é o segundo passo de uma escala recém-criada.
  ///
  /// Muda duas coisas: o botão diz para onde leva, e salvar emenda no passo
  /// seguinte em vez de voltar. Montar a escala é escalar a equipe **e**
  /// escolher as músicas — parar no meio é o que fazia o líder ter de procurar
  /// a escala de novo na agenda para terminar.
  ///
  /// **Qual é o passo seguinte depende da escala, não desta bandeira.** Com
  /// repertório definido na hora não há lista para montar, e o caminho termina
  /// no detalhe: quem escolheu não planejar as músicas não pode ser levado à
  /// tela de planejá-las. O nome ficou por compatibilidade com a rota
  /// (`?novo=1`), que continua dizendo só "esta escala acabou de nascer".
  final bool nextIsSetlist;

  @override
  ConsumerState<AssignmentFormScreen> createState() =>
      _AssignmentFormScreenState();
}

class _AssignmentFormScreenState extends ConsumerState<AssignmentFormScreen> {
  /// positionId -> membershipIds selecionados
  final Map<String, Set<String>> _selected = {};

  /// Recado individual por (função, pessoa).
  ///
  /// A API já guardava este campo, mas o formulário remontava o payload só
  /// com os ids. Assim, abrir uma escala antiga e salvar qualquer ajuste
  /// apagava todos os recados sem aviso.
  final Map<(String, String), String> _notes = {};

  /// Quem conduz a ministração do louvor. Um por escala, não por função.
  String? _ministerId;

  bool _seeded = false;
  bool _saving = false;
  String? _error;

  /// Ver [kArrivalTapShield]: vindo de "Criar escala", o botão daqui está no
  /// mesmo lugar do de lá.
  final DateTime _abertaEm = DateTime.now();

  /// Já salvou e está indo para o passo seguinte: o botão fica travado.
  bool _saindo = false;

  /// Versão da escala no momento em que esta tela a abriu. Vai junto ao salvar
  /// para o servidor recusar a gravação se outra pessoa mexeu no meio.
  DateTime? _expectedUpdatedAt;

  void _seedFromEvent(Event event) {
    if (_seeded) return;
    _seeded = true;
    _expectedUpdatedAt = event.updatedAt;
    for (final group in event.assignments) {
      _selected[group.positionId] = {
        for (final member in group.members) member.membershipId,
      };
      for (final member in group.members) {
        final note = member.note?.trim();
        if (note != null && note.isNotEmpty) {
          _notes[(group.positionId, member.membershipId)] = note;
        }
      }
    }
    _ministerId = event.minister?.membershipId;
    _salvo = _assinatura();
  }

  /// A escalação como foi aberta (ou salva por último), para a guarda de
  /// "Sair sem salvar?".
  String _salvo = '';

  /// Tudo o que salvar mandaria, em ordem estável: quem está em cada função,
  /// os recados e o ministrante.
  String _assinatura() {
    final funcoes = _selected.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => '${e.key}:${(e.value.toList()..sort()).join(',')}')
        .toList()
      ..sort();
    final recados = _notes.entries
        .where((e) => e.value.trim().isNotEmpty)
        .map((e) => '${e.key.$1}/${e.key.$2}=${e.value.trim()}')
        .toList()
      ..sort();
    return '${funcoes.join(';')}|${recados.join(';')}|$_ministerId';
  }

  bool _alterado() => _seeded && _assinatura() != _salvo;

  /// Tira a pessoa de todas as funções e do ministério, de uma vez.
  void _tirarDeTudo(String membershipId) {
    setState(() {
      for (final ids in _selected.values) {
        ids.remove(membershipId);
      }
      _notes.removeWhere((key, _) => key.$2 == membershipId);
      if (_ministerId == membershipId) _ministerId = null;
    });
  }

  /// "Falta escolher: quem ministra, Vocal e Violão." — o que a pessoa que
  /// saiu deixou vago, pela escala como estava ao abrir.
  String _vagas(Event event, String membershipId) {
    final vagas = [
      if (event.minister?.membershipId == membershipId && _ministerId == null)
        'quem ministra',
      for (final group in event.assignments)
        if (group.members.any((m) => m.membershipId == membershipId))
          group.positionName,
    ];
    if (vagas.isEmpty) return '';
    final lista = vagas.length == 1
        ? vagas.single
        : '${vagas.sublist(0, vagas.length - 1).join(', ')} e ${vagas.last}';
    return 'Falta escolher: $lista.';
  }

  /// O aviso de quem precisa sair, no topo da escalação.
  Widget? _substituirNotice(Event event) {
    final id = widget.replaceMembershipId;
    if (id == null) return null;

    final pessoa = event.warnings.unavailableAssigned
            .where((u) => u.membershipId == id)
            .firstOrNull ??
        event.unavailable.where((u) => u.membershipId == id).firstOrNull;
    final nome = pessoa?.displayName ??
        event.assignments
            .expand((g) => g.members)
            .where((m) => m.membershipId == id)
            .firstOrNull
            ?.displayName;
    if (nome == null) return null;

    final aindaEsta =
        _assignedIds.contains(id) || _ministerId == id;
    // O que ela fazia, lido da escala como estava ao abrir: depois de tirar,
    // é justamente essa lista que diz o que falta preencher.
    final fazia = event.rolesPhraseFor(id);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppNotice(
        tone: aindaEsta ? AppTone.danger : AppTone.success,
        icon: aindaEsta ? Icons.event_busy_rounded : Icons.check_circle_rounded,
        title: aindaEsta
            ? '$nome avisou que não pode neste dia'
            : '$nome saiu da escala',
        message: aindaEsta
            ? [
                if (fazia != null) '$nome $fazia.',
                if (pessoa?.reason?.isNotEmpty ?? false)
                  'Motivo: ${pessoa!.reason}.',
              ].join(' ')
            : 'Escolha quem entra no lugar e salve. ${_vagas(event, id)}',
        action: aindaEsta
            ? FilledButton.tonalIcon(
                style: AppButtonStyles.compact,
                onPressed: () => _tirarDeTudo(id),
                icon: const Icon(Icons.person_remove_alt_1_rounded, size: 18),
                label: const Text('Tirar de todas as funções'),
              )
            : null,
      ),
    );
  }

  /// Todos os escalados, sem repetir quem acumula duas funções.
  Set<String> get _assignedIds => _selected.values.expand((ids) => ids).toSet();

  /// O ministrante precisa continuar escalado; se saiu, o campo se limpa.
  void _dropMinisterIfUnassigned() {
    if (_ministerId != null && !_assignedIds.contains(_ministerId)) {
      _ministerId = null;
    }
  }

  /// Pessoas distintas: quem acumula duas funções conta uma vez.
  int get _distinctPeople =>
      _selected.values.expand((ids) => ids).toSet().length;

  /// Por que esta pessoa não pode entrar nesta função, dado o resto da escala.
  ///
  /// Duas regras do culto (as mesmas validadas no backend):
  ///  - ninguém toca dois instrumentos; vocal acumula com um instrumento
  ///  - quem está na multimídia ou no som fica fora da banda
  ///
  /// Bloquear na tela evita o líder montar a escala inteira e só descobrir o
  /// problema ao salvar.
  String? _blockedReason(
    Member member,
    Position target,
    List<Position> positions,
  ) {
    final byId = {for (final p in positions) p.id: p};
    final current = <Position>[
      for (final entry in _selected.entries)
        if (entry.key != target.id && entry.value.contains(member.id))
          if (byId[entry.key] != null) byId[entry.key]!,
    ];

    if (target.isInstrument) {
      final other = current.where((p) => p.isInstrument).firstOrNull;
      if (other != null) return 'Já está em ${other.name}';
      final tech = current.where((p) => p.isTech).firstOrNull;
      if (tech != null) return 'Está em ${tech.name}';
    }

    if (target.isVocal) {
      final tech = current.where((p) => p.isTech).firstOrNull;
      if (tech != null) return 'Está em ${tech.name}';
    }

    if (target.isTech) {
      final band =
          current.where((p) => p.isVocal || p.isInstrument).firstOrNull;
      if (band != null) return 'Está em ${band.name}';
    }

    return null;
  }

  int get _filledPositions =>
      _selected.values.where((ids) => ids.isNotEmpty).length;

  /// [force] repete a gravação sem a trava de versão: é o "salvar assim mesmo"
  /// de quem viu o aviso de que a escala mudou e decidiu sobrescrever.
  Future<void> _save({bool force = false}) async {
    if (widget.nextIsSetlist &&
        DateTime.now().difference(_abertaEm) < kArrivalTapShield) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final payload = buildAssignmentPayload(_selected, _notes);

    try {
      final updated =
          await ref.read(eventRepositoryProvider).replaceAssignments(
                widget.eventId,
                payload,
                ministerMembershipId: _ministerId,
                expectedUpdatedAt: force ? null : _expectedUpdatedAt,
              );
      ref.invalidate(eventProvider(widget.eventId));
      // A agenda também mostra a escalação (o chip "VOCÊ" e a contagem de
      // escalados). Sem invalidar a lista, o cartão continuava com o número
      // de antes de salvar, contradizendo a tela de detalhe.
      ref.invalidate(eventsProvider((updated.teamId, 'upcoming')));
      ref.invalidate(eventsProvider((updated.teamId, 'past')));
      if (!mounted) return;
      _salvo = _assinatura();

      // Avisos depois de salvar, não bloqueios antes: a escala é do líder.
      final warnings = <String>[];

      final unavailable = updated.warnings.unavailableAssigned;
      if (unavailable.isNotEmpty) {
        final names = unavailable.map((u) => u.displayName).toSet().join(', ');
        warnings.add('$names marcou que não pode neste dia.');
      }

      final conflicts = updated.warnings.sameDayConflicts;
      if (conflicts.isNotEmpty) {
        final names = conflicts.map((c) => c.displayName).toSet().join(', ');
        warnings.add('$names também está em outra escala no mesmo dia.');
      }

      final proximoPasso = nextStepAfterAssignments(
        eventId: widget.eventId,
        isNewSchedule: widget.nextIsSetlist,
        repertoireOnTheFly: updated.isRepertoireOnTheFly,
      );
      // A escala nova acaba aqui quando o repertório é definido na hora: não
      // há lista para montar, e mandar a pessoa para uma tela de repertório
      // que ela decidiu não usar é justamente o passo que este modo existe
      // para tirar do caminho.
      final terminaAqui = widget.nextIsSetlist && updated.isRepertoireOnTheFly;

      // Salvar sem avisos também precisa responder. Antes, a tela simplesmente
      // fechava: dava para não ter certeza se o toque tinha pegado, e o líder
      // reabria a escala para conferir.
      showAppSnackBar(
        context,
        switch ((warnings.isEmpty, terminaAqui)) {
          (false, _) => 'Escala salva. ${warnings.join(' ')}',
          // Mesma frase do fim do caminho com repertório planejado: o que
          // muda é onde ele termina, não o que a pessoa conquistou.
          (true, true) =>
            'Rascunho salvo. A equipe só vê a escala depois que você tocar '
                'em "Publicar".',
          (true, false) => 'Escala salva.',
        },
        tone: warnings.isEmpty ? AppTone.success : AppTone.warning,
      );

      // `pushReplacement` e não `push`: a escalação já foi salva, e voltar para
      // ela do repertório só ofereceria salvá-la de novo. O que fica embaixo é
      // o detalhe da escala, que é onde o repertório desemboca ao terminar.
      _saindo = true;
      if (proximoPasso != null) {
        context.pushReplacement(proximoPasso);
        return;
      }
      context.pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == scheduleChangedCode) {
        await _resolveConflict(error.message);
        return;
      }
      setState(() => _error = error.message);
    } finally {
      if (mounted && !_saindo) setState(() => _saving = false);
    }
  }

  /// Sobrescrever é escolha da pessoa; conferir é o caminho oferecido primeiro.
  /// Ao voltar, o detalhe recarrega e mostra a escala como ela está agora.
  Future<void> _resolveConflict(String message) async {
    final overwrite = await showScheduleChangedDialog(context, message);
    if (!mounted) return;

    if (overwrite) {
      await _save(force: true);
      return;
    }
    ref.invalidate(eventProvider(widget.eventId));
    // Escolheu ver a versão do outro: o que estava aqui foi deixado de lado
    // por decisão, e perguntar "sair sem salvar?" agora seria contradizê-la.
    _salvo = _assinatura();
    if (mounted) context.pop();
  }

  Future<void> _openPicker({
    required Position position,
    required List<Member> members,
    required List<Position> positions,
    required Set<String> unavailableIds,
    required String teamId,
    required Map<String, RotationMember>? rotation,
  }) async {
    // No celular sobe do rodapé; no monitor abre no centro. O conteúdo é o
    // mesmo widget nos dois casos.
    await showAdaptiveSheet<void>(
      context: context,
      maxWidth: 560,
      builder: (sheetContext) => _MemberPickerSheet(
        position: position,
        members: members,
        rotation: rotation,
        unavailableIds: unavailableIds,
        blockedReason: (member) => _blockedReason(member, position, positions),
        onAddGuest: (name) => _addGuest(teamId, name),
        initialSelection: _selected[position.id] ?? const <String>{},
        noteFor: (member) => _notes[(position.id, member.id)],
        // O recado mora na folha, ao lado da pessoa marcada: era um botão de
        // ~24px dentro da pílula, na tela, ao lado de outro para remover.
        onEditNote: (member) => _editNote(position: position, member: member),
        onChanged: (next) => setState(() {
          _selected[position.id] = next;
          _dropMinisterIfUnassigned();
        }),
      ),
    );
  }

  Future<void> _editNote({
    required Position position,
    required Member member,
  }) async {
    final key = (position.id, member.id);
    final result = await showAdaptiveSheet<String>(
      context: context,
      maxWidth: 480,
      builder: (_) => _NoteSheet(
        memberName: member.displayName,
        positionName: position.name,
        initial: _notes[key] ?? '',
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      if (result.isEmpty) {
        _notes.remove(key);
      } else {
        _notes[key] = result;
      }
    });
  }

  Future<Member?> _addGuest(String teamId, String name) async {
    try {
      final guest = await ref.read(addGuestProvider)(teamId, name);
      ref.invalidate(schedulableMembersProvider(teamId));
      return guest;
    } on ApiException catch (error) {
      if (mounted) {
        showAppSnackBar(context, error.message, tone: AppTone.danger);
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return UnsavedChangesGuard(
      isDirty: _alterado,
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final eventAsync = ref.watch(eventProvider(widget.eventId));

    return eventAsync.when(
      loading: () => const Scaffold(body: AppLoading()),
      error: (_, __) => Scaffold(
        appBar: AppBar(title: const Text('Escalar')),
        body: AppErrorState(
          message: 'Não foi possível carregar a escala.',
          onRetry: () => ref.invalidate(eventProvider(widget.eventId)),
        ),
      ),
      data: (cached) {
        final event = cached.data;
        _seedFromEvent(event);
        final membersAsync =
            ref.watch(schedulableMembersProvider(event.teamId));
        final positionsAsync = ref.watch(positionsProvider(event.teamId));

        return membersAsync.when(
          loading: () => const Scaffold(body: AppLoading()),
          error: (_, __) => Scaffold(
            appBar: AppBar(title: const Text('Escalar')),
            body: const AppErrorState(
              message: 'Não foi possível carregar a equipe.',
            ),
          ),
          data: (members) => positionsAsync.when(
            loading: () => const Scaffold(body: AppLoading()),
            error: (_, __) => Scaffold(
              appBar: AppBar(title: const Text('Escalar')),
              body: const AppErrorState(
                message: 'Não foi possível carregar as funções.',
              ),
            ),
            data: (positions) => _buildForm(context, event, members, positions),
          ),
        );
      },
    );
  }

  Widget _buildForm(
    BuildContext context,
    Event event,
    List<Member> members,
    List<Position> positions,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) => _form(
        context,
        event,
        members,
        positions,
        constraints.maxWidth,
      ),
    );
  }

  Widget _form(
    BuildContext context,
    Event event,
    List<Member> members,
    List<Position> positions,
    double available,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final activePositions = positions.where((p) => p.isActive).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    // Quem avisou que não pode no dia desta escala. Não bloqueia escalar —
    // sinaliza, porque o líder às vezes já combinou uma troca por fora.
    final unavailableIds = {
      for (final person in event.unavailable) person.membershipId,
    };
    // Observado aqui, e não dentro da folha: quando o líder toca na função a
    // resposta já chegou, e a linha não nasce depois que ele começou a ler.
    final rotation =
        ref.watch(rotationProvider(event.teamId)).valueOrNull?.members;

    void openPicker(Position position) => _openPicker(
          position: position,
          members: members,
          positions: activePositions,
          unavailableIds: unavailableIds,
          teamId: event.teamId,
          rotation: rotation,
        );

    final minister = _MinisterRow(
      members: members,
      assignedIds: _assignedIds,
      ministerId: _ministerId,
      enabled: !_saving,
      onChanged: (id) => setState(() => _ministerId = id),
    );

    final summary = _SummaryText(
      people: _distinctPeople,
      filled: _filledPositions,
      total: activePositions.length,
    );

    final saveButton = AppSubmitButton(
      // Sem repertório a montar, o botão não pode prometer músicas: aqui ele é
      // o último passo da criação, e é isso que precisa dizer.
      label: switch ((widget.nextIsSetlist, event.isRepertoireOnTheFly)) {
        (true, false) => 'Salvar e escolher músicas',
        (true, true) => 'Salvar e ver a escala',
        (false, _) => 'Salvar escala',
      },
      loading: _saving,
      onPressed: _save,
    );

    // No monitor, montar a escala deixa de ser uma rolagem: as funções à
    // esquerda, como uma tabela de uma superfície só, e à direita o que
    // responde "acabou?" — o resumo, o ministrante e o botão, parados enquanto
    // a lista rola. A escolha de quem entra continua sendo a **mesma** folha
    // do celular; ela só aparece como diálogo (ver `showAdaptiveSheet`).
    //
    // 940 é a largura **disponível para esta tela** (janela menos a barra
    // lateral), não a da janela: num monitor de 1024px com a barra aberta
    // sobram 756px, e ali as duas colunas espremeriam a tabela de funções.
    if (available >= 940) {
      return Scaffold(
        appBar: AppBar(title: const Text('Escalar equipe')),
        body: SafeArea(
          top: false,
          child: AppContentWidth.wide(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.dateAndTitle, style: theme.textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.lg),
                  if (_substituirNotice(event) case final aviso?) aviso,
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.xl,
                            ),
                            children: [
                              _PositionsTable(
                                positions: activePositions,
                                members: members,
                                selected: _selected,
                                notes: _notes,
                                unavailableIds: unavailableIds,
                                onOpen: openPicker,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xl),
                        SizedBox(
                          width: 320,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.xl,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                summary,
                                if (_error != null) ...[
                                  const SizedBox(height: AppSpacing.lg),
                                  FormErrorBanner(message: _error!),
                                ],
                                const SizedBox(height: AppSpacing.lg),
                                AppCard(child: minister),
                                const SizedBox(height: AppSpacing.lg),
                                saveButton,
                              ],
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
        ),
      );
    }

    // No celular, **uma superfície para a escala inteira**: uma linha por
    // função e o ministrante no fim, como a tabela do monitor. Eram um cartão
    // com borda por função — oito funções davam quase mil pixels de caixas —,
    // e o resumo num bloco colorido no topo, que saía da tela justamente
    // enquanto se escalava. Agora o resumo mora na barra de baixo, ao lado do
    // botão, e fica à vista a tarefa inteira.
    return Scaffold(
      appBar: AppBar(title: const Text('Escalar equipe')),
      body: AppContentWidth.wide(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.md,
            AppSpacing.screenPadding,
            AppSpacing.xxl,
          ),
          children: [
            Text(event.dateAndTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            if (_substituirNotice(event) case final aviso?) aviso,
            if (_error != null) FormErrorBanner(message: _error!),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // **Ministrante no topo.** Era a última linha, depois de Som
                  // e de "Direção do culto" — a responsabilidade maior da
                  // escala escondida no fim, ao lado de um nome parecido. A
                  // escolha continua sendo entre quem já está escalado: a
                  // linha diz isso enquanto a equipe está vazia.
                  minister,
                  Divider(
                    height: 1,
                    indent: AppSpacing.lg,
                    color: scheme.outlineVariant,
                  ),
                  for (final position in activePositions) ...[
                    _PositionListRow(
                      position: position,
                      members: members,
                      selected: _selected[position.id] ?? const <String>{},
                      notes: {
                        for (final membershipId
                            in _selected[position.id] ?? const <String>{})
                          if (_notes[(position.id, membershipId)]
                              case final note?)
                            membershipId: note,
                      },
                      unavailableIds: unavailableIds,
                      onTap: () => openPicker(position),
                    ),
                    if (position != activePositions.last)
                      Divider(
                        height: 1,
                        indent: AppSpacing.lg,
                        color: scheme.outlineVariant,
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomActionBar(
        leading: summary,
        action: saveButton,
      ),
    );
  }
}

/// As funções como uma tabela de uma superfície só — a versão de monitor da
/// pilha de cartões.
///
/// **Uma superfície, não uma por função.** Oito cartões com borda própria numa
/// coluna de 700px é o mural de fichas soltas que o `AppGroup` já resolveu no
/// resto do app; aqui a mesma ideia dá também o alinhamento das colunas, que é
/// o que faz a lista ser lida por coluna ("quais funções estão vazias?") em vez
/// de item por item.
class _PositionsTable extends StatelessWidget {
  const _PositionsTable({
    required this.positions,
    required this.members,
    required this.selected,
    required this.notes,
    required this.unavailableIds,
    required this.onOpen,
  });

  final List<Position> positions;
  final List<Member> members;
  final Map<String, Set<String>> selected;
  final Map<(String, String), String> notes;
  final Set<String> unavailableIds;
  final ValueChanged<Position> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: scheme.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 200,
                  child: Text('Função', style: AppTypography.eyebrow(context)),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Text(
                    'Quem está escalado',
                    style: AppTypography.eyebrow(context),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < positions.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
            _PositionRow(
              position: positions[i],
              members: members,
              selected: selected[positions[i].id] ?? const <String>{},
              notes: {
                for (final membershipId
                    in selected[positions[i].id] ?? const <String>{})
                  if (notes[(positions[i].id, membershipId)] case final note?)
                    membershipId: note,
              },
              unavailableIds: unavailableIds,
              onOpen: () => onOpen(positions[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// Uma função como linha da tabela: nome à esquerda, escalados no meio, a ação
/// à direita — sempre no mesmo lugar, para o clique não ter de ser procurado.
class _PositionRow extends StatelessWidget {
  const _PositionRow({
    required this.position,
    required this.members,
    required this.selected,
    required this.notes,
    required this.unavailableIds,
    required this.onOpen,
  });

  final Position position;
  final List<Member> members;
  final Set<String> selected;
  final Map<String, String> notes;
  final Set<String> unavailableIds;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chosen =
        members.where((m) => selected.contains(m.id)).toList(growable: false);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 200,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: PositionIcon(
                    position.name,
                    category: position.category,
                    size: 16,
                    color: chosen.isEmpty
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    position.name,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: chosen.isEmpty
                ? Text(
                    'Ninguém escalado',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final member in chosen)
                        _SelectedChip(
                          member: member,
                          // Escalar fora do cadastro é permitido (regra 18); o
                          // chip sinaliza, não impede.
                          outsideRegistration:
                              !member.positions.any((p) => p.id == position.id),
                          unavailable: unavailableIds.contains(member.id),
                          note: notes[member.id],
                        ),
                    ],
                  ),
          ),
          const SizedBox(width: AppSpacing.lg),
          // Botão com palavra, e não só um ícone: é a ação da linha, e "+"
          // sozinho num monitor não diz se acrescenta pessoa ou função.
          TextButton.icon(
            onPressed: onOpen,
            icon: Icon(
              chosen.isEmpty ? Icons.add_rounded : Icons.edit_outlined,
              size: 18,
            ),
            label: Text(chosen.isEmpty ? 'Escolher' : 'Alterar'),
          ),
        ],
      ),
    );
  }
}

/// Responde "quanto falta?" sem o líder ter de rolar a lista inteira.
///
/// Texto, e não bloco colorido: mora na barra de baixo, ao lado do botão de
/// salvar, que é onde o olho está quando a tarefa termina.
class _SummaryText extends StatelessWidget {
  const _SummaryText({
    required this.people,
    required this.filled,
    required this.total,
  });

  final int people;
  final int filled;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      people == 0
          ? 'Nenhuma função preenchida ainda'
          : '$filled de $total ${total == 1 ? 'função' : 'funções'} · '
              '$people ${people == 1 ? 'pessoa' : 'pessoas'}',
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontFeatures: AppTypography.tabular,
      ),
    );
  }
}

/// Quem conduz a ministração do louvor nesta escala — uma linha da mesma
/// superfície das funções.
///
/// Um por escala, e não por função: é a pessoa que lê os versículos, fala
/// antes das músicas e delega. Ela também está escalada em alguma função, mas
/// o papel não pertence à função — por isso a linha é própria.
///
/// Era um bloco com estilo seu (pílulas sem avatar) no pé da tela. Agora é uma
/// linha como as outras, e a escolha abre a lista de escalados.
class _MinisterRow extends StatelessWidget {
  const _MinisterRow({
    required this.members,
    required this.assignedIds,
    required this.ministerId,
    required this.enabled,
    required this.onChanged,
  });

  final List<Member> members;
  final Set<String> assignedIds;
  final String? ministerId;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final assigned = members
        .where((member) => assignedIds.contains(member.id))
        .toList(growable: false)
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final current =
        assigned.where((member) => member.id == ministerId).firstOrNull;

    // O subtítulo diz o que a função é quando ainda não há ninguém: ao lado
    // de "Direção do culto", na lista de funções, as duas se confundiam para
    // quem é novo.
    return AppGroupRow(
      icon: Icons.record_voice_over_rounded,
      title: 'Ministrante',
      subtitle: assigned.isEmpty
          ? 'Quem conduz o louvor. Escale a equipe primeiro'
          : current?.displayName ??
              'Quem conduz o louvor (não é a direção do culto)',
      onTap: !enabled || assigned.isEmpty
          ? null
          : () async {
              final escolha = await showAppOptionsSheet<String?>(
                context: context,
                title: 'Quem ministra',
                subtitle: 'Entre quem já está escalado.',
                selected: ministerId,
                options: [
                  // Às vezes ainda não se sabe quem vai ministrar, e isso não
                  // pode travar a escala.
                  const AppOption(value: null, label: 'Ainda não definido'),
                  for (final member in assigned)
                    AppOption(value: member.id, label: member.displayName),
                ],
              );
              if (escolha != null) onChanged(escolha.value);
            },
    );
  }
}

/// Uma função como linha: ícone, nome, quem está escalado. A linha inteira
/// abre a folha de escolha.
class _PositionListRow extends StatelessWidget {
  const _PositionListRow({
    required this.position,
    required this.members,
    required this.selected,
    required this.notes,
    required this.unavailableIds,
    required this.onTap,
  });

  final Position position;
  final List<Member> members;
  final Set<String> selected;
  final Map<String, String> notes;
  final Set<String> unavailableIds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chosen =
        members.where((m) => selected.contains(m.id)).toList(growable: false);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 22,
                child: PositionIcon(
                  position.name,
                  category: position.category,
                  size: 17,
                  color: chosen.isEmpty
                      ? scheme.onSurfaceVariant
                      : scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(position.name, style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  if (chosen.isEmpty)
                    Text(
                      'Ninguém escalado',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final member in chosen)
                          _SelectedChip(
                            member: member,
                            // Escalar fora do cadastro é permitido (regra 18);
                            // o chip sinaliza, não impede.
                            outsideRegistration: !member.positions
                                .any((p) => p.id == position.id),
                            unavailable: unavailableIds.contains(member.id),
                            note: notes[member.id],
                          ),
                      ],
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Icon(
                chosen.isEmpty ? Icons.add_rounded : Icons.edit_outlined,
                size: 20,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uma pessoa escalada: avatar, nome e, quando há, o sinal do que merece
/// atenção.
///
/// **Sem botões dentro.** A pílula tinha cinco peças — avatar, nome, estado,
/// um botão de recado e outro de remover, os dois com ~24px — e errar entre os
/// dois era tirar alguém da escala querendo deixar um recado. Recado e
/// remover moram na folha de escolha, com alvo de 48dp.
class _SelectedChip extends StatelessWidget {
  const _SelectedChip({
    required this.member,
    required this.outsideRegistration,
    required this.unavailable,
    required this.note,
  });

  final Member member;
  final bool outsideRegistration;
  final bool unavailable;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = AppStatusColors.of(context);

    // Âmbar para "fora do cadastro", vermelho para "avisou que não pode": o
    // azul da marca é a cor do que está certo.
    final tone = unavailable
        ? AppTone.danger
        : outsideRegistration
            ? AppTone.warning
            : AppTone.neutral;
    final palette = status.resolve(tone, scheme);

    final hint = [
      member.displayName,
      if (unavailable) 'avisou que não pode neste dia',
      if (!unavailable && outsideRegistration)
        'não tem esta função no cadastro',
      if (note != null) 'recado: $note',
    ].join(', ');

    return Semantics(
      label: hint,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(3, 3, AppSpacing.sm, 3),
        decoration: BoxDecoration(
          color: palette.container,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppAvatar(
              name: member.displayName,
              imageUrl: member.avatarUrl,
              radius: 11,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                member.displayName,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: palette.onContainer,
                ),
              ),
            ),
            if (unavailable) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.event_busy_rounded,
                size: 15,
                color: palette.onContainer,
              ),
            ] else if (outsideRegistration) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: palette.onContainer,
              ),
            ],
            if (note != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.sticky_note_2_rounded,
                size: 14,
                color: palette.onContainer,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// O recado de uma pessoa nesta escala ("trazer o violão reserva").
class _NoteSheet extends StatefulWidget {
  const _NoteSheet({
    required this.memberName,
    required this.positionName,
    required this.initial,
  });

  final String memberName;
  final String positionName;
  final String initial;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Recado para ${widget.memberName}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.positionName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Recado individual',
                hintText: 'Ex.: trazer o violão reserva',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_controller.text.trim()),
              child: const Text('Salvar recado'),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Folha de escolha, focada em uma função por vez.
class _MemberPickerSheet extends StatefulWidget {
  const _MemberPickerSheet({
    required this.position,
    required this.members,
    required this.rotation,
    required this.unavailableIds,
    required this.blockedReason,
    required this.onAddGuest,
    required this.initialSelection,
    required this.noteFor,
    required this.onEditNote,
    required this.onChanged,
  });

  final Position position;
  final List<Member> members;

  /// O recado de uma pessoa nesta função, se houver.
  final String? Function(Member member) noteFor;
  final Future<void> Function(Member member) onEditNote;

  /// Nulo enquanto o relatório de rodízio não chegou.
  final Map<String, RotationMember>? rotation;
  final Set<String> unavailableIds;

  /// Nulo = pode escalar. Texto = motivo do bloqueio, exibido na linha.
  final String? Function(Member) blockedReason;
  final Future<Member?> Function(String displayName) onAddGuest;
  final Set<String> initialSelection;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  late Set<String> _working = {...widget.initialSelection};

  /// "Outros membros" começa recolhido: na maioria das semanas o líder escala
  /// quem já tem a função cadastrada, e repetir a equipe inteira em cada
  /// função era o que transformava a tela num paredão.
  ///
  /// **Exceto quando ninguém tem a função.** Aí a folha abria só com "Outros
  /// integrantes (9) — Mostrar", e o primeiro toque era sempre o mesmo.
  late bool _showOthers = !widget.members.any(
    (m) => m.positions.any((p) => p.id == widget.position.id),
  );
  bool _addingGuest = false;

  /// A busca pelo nome, a partir de [_searchFrom] pessoas: numa equipe de 40,
  /// achar alguém rolando a lista é o que mais demora na escalação.
  String _search = '';
  static const _searchFrom = 12;

  /// Cadastra o convidado e já o deixa marcado nesta função — quem abre esse
  /// fluxo está com a função vazia na mão.
  Future<void> _promptGuest() async {
    final name = await showAdaptiveSheet<String>(
      context: context,
      maxWidth: 480,
      builder: (_) => const _GuestSheet(),
    );

    if (name == null || name.length < 2 || !mounted) return;

    setState(() => _addingGuest = true);
    final guest = await widget.onAddGuest(name);
    if (!mounted) return;

    setState(() {
      _addingGuest = false;
      if (guest != null) {
        _working = {..._working, guest.id};
        _extraGuests = [..._extraGuests, guest];
      }
    });
    if (guest != null) widget.onChanged(_working);
  }

  /// Convidados criados aqui dentro: a lista recebida por parâmetro só é
  /// recarregada quando a folha fecha.
  List<Member> _extraGuests = [];

  /// O convidado fica de fora: ele não faz parte da equipe, e "sem escala no
  /// último ano" ao lado do nome de quem foi chamado só para o dia diria algo
  /// que não é sobre ele.
  String? _rotationOf(Member member) {
    final report = widget.rotation;
    if (report == null || member.isGuest) return null;
    return rotationSummary(
      report[member.id],
      weeks: rotationWeeks,
      now: DateTime.now(),
    );
  }

  Future<void> _editNote(Member member) async {
    await widget.onEditNote(member);
    // O recado vive na tela de baixo; a folha só precisa redesenhar o ícone.
    if (mounted) setState(() {});
  }

  void _toggle(String membershipId) {
    setState(() {
      _working = {..._working};
      if (!_working.remove(membershipId)) {
        _working.add(membershipId);
      }
    });
    widget.onChanged(_working);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final everyone = [...widget.members, ..._extraGuests];
    final termo = normalizeForSearch(_search.trim());
    final all = termo.isEmpty
        ? everyone
        : everyone
            .where((m) => normalizeForSearch(m.displayName).contains(termo))
            .toList();
    final registered = all
        .where((m) => m.positions.any((p) => p.id == widget.position.id))
        .toList();
    final others = all
        .where((m) => !m.positions.any((p) => p.id == widget.position.id))
        .toList();

    // Quem foi escalado fora do cadastro continua visível mesmo com a seção
    // recolhida -- senão a pessoa sumiria da folha logo após ser marcada.
    // Com busca, a lista abre inteira: quem digitou um nome quer vê-lo.
    final othersToShow = _showOthers || termo.isNotEmpty
        ? others
        : others.where((m) => _working.contains(m.id)).toList();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  PositionIcon(
                    widget.position.name,
                    category: widget.position.category,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      widget.position.name,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    '${_working.length} '
                    'escolhido${_working.length == 1 ? '' : 's'}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (everyone.length >= _searchFrom)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Buscar pelo nome',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                ),
              ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                // shrinkWrap para a folha ter a altura do conteúdo: com uma
                // função de poucos membros ela abria ocupando 3/4 da tela,
                // quase tudo vazio. O ConstrainedBox acima segue limitando.
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                children: [
                  if (registered.isEmpty && others.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Text(
                        termo.isEmpty
                            ? 'Nenhum integrante cadastrado na equipe.'
                            : 'Ninguém com esse nome na equipe.',
                      ),
                    ),
                  if (registered.isNotEmpty) ...[
                    _SheetLabel('Com esta função', count: registered.length),
                    for (final member in registered)
                      _PickerTile(
                        member: member,
                        checked: _working.contains(member.id),
                        rotation: _rotationOf(member),
                        unavailable: widget.unavailableIds.contains(member.id),
                        blockedReason: widget.blockedReason(member),
                        note: widget.noteFor(member),
                        onEditNote: () => _editNote(member),
                        onTap: () => _toggle(member.id),
                      ),
                  ],
                  if (others.isNotEmpty) ...[
                    _SheetLabel(
                      'Outros integrantes',
                      count: others.length,
                      trailing: TextButton(
                        onPressed: () =>
                            setState(() => _showOthers = !_showOthers),
                        child: Text(_showOthers ? 'Ocultar' : 'Mostrar'),
                      ),
                    ),
                    for (final member in othersToShow)
                      _PickerTile(
                        member: member,
                        checked: _working.contains(member.id),
                        rotation: _rotationOf(member),
                        outsideRegistration: true,
                        unavailable: widget.unavailableIds.contains(member.id),
                        blockedReason: widget.blockedReason(member),
                        note: widget.noteFor(member),
                        onEditNote: () => _editNote(member),
                        onTap: () => _toggle(member.id),
                      ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                children: [
                  // O momento em que se descobre que falta alguém é este:
                  // montando a escala e sem ninguém para a função.
                  TextButton.icon(
                    onPressed: _addingGuest ? null : _promptGuest,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('Convidar alguém de fora'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Concluir'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text, {required this.count, this.trailing});

  final String text;
  final int count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        trailing == null ? AppSpacing.xl : AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$text ($count)',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.member,
    required this.checked,
    required this.onTap,
    this.rotation,
    this.outsideRegistration = false,
    this.unavailable = false,
    this.blockedReason,
    this.note,
    this.onEditNote,
  });

  final Member member;
  final bool checked;
  final VoidCallback onTap;

  /// O recado desta pessoa na função. O botão só aparece com ela marcada.
  final String? note;
  final VoidCallback? onEditNote;

  /// "Há 3 semanas · 2 escalas em 8 semanas". Nulo = nada a mostrar.
  final String? rotation;
  final bool outsideRegistration;

  /// A pessoa avisou que não pode no dia desta escala.
  final bool unavailable;

  /// Combinação proibida (dois instrumentos, ou técnica junto com banda).
  /// Diferente de "indisponível": aqui não há escolha, a regra impede.
  final String? blockedReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final blocked = blockedReason != null && !checked;

    // A linha inteira é **um** controle: sem `MergeSemantics` o leitor de tela
    // lia o nome e a caixa de seleção como dois itens separados, e o estado
    // ficava longe de quem ele descreve.
    return MergeSemantics(
      child: InkWell(
        onTap: blocked ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              // O esmaecido cobre só a identificação da pessoa. Antes ele
              // envolvia a linha toda a 45%, **inclusive o motivo do bloqueio**
              // -- justamente a frase que explica por que aquele nome não pode
              // ser marcado, apagada até quase sumir.
              Opacity(
                opacity: blocked ? 0.5 : 1,
                child: AppAvatar(
                  name: member.displayName,
                  imageUrl: member.avatarUrl,
                  radius: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Opacity(
                      opacity: blocked ? 0.5 : 1,
                      child: Text(
                        member.displayName,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    // As etiquetas descem para a linha de apoio: na mesma linha
                    // do nome, duas delas espremiam o nome num celular
                    // estreito. Nenhuma impede escalar — o líder às vezes já
                    // acertou uma troca por fora do app.
                    if (unavailable || member.onLeave || member.isGuest)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            if (unavailable) const UnavailableBadge(),
                            if (member.onLeave) const OnLeaveBadge(),
                            if (member.isGuest) const _GuestBadge(),
                          ],
                        ),
                      ),
                    if (blocked)
                      Text(
                        blockedReason!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else if (outsideRegistration && checked)
                      // Âmbar, não azul: é uma ressalva, e o azul é a cor do
                      // que está certo no app inteiro.
                      Text(
                        'Fora do cadastro desta função',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppStatusColors.of(context).warning.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    // Cinza, e não uma cor de estado: é contexto para a
                    // decisão do líder, não alarme. Escalar de novo quem tocou
                    // ontem continua sendo legítimo.
                    else if (rotation != null)
                      Text(
                        rotation!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (checked && onEditNote != null)
                IconButton(
                  tooltip: note == null ? 'Adicionar recado' : 'Editar recado',
                  onPressed: onEditNote,
                  icon: Icon(
                    note == null
                        ? Icons.edit_note_rounded
                        : Icons.sticky_note_2_rounded,
                    color: note == null ? scheme.onSurfaceVariant : scheme.primary,
                  ),
                ),
              Checkbox(
                value: checked,
                onChanged: blocked ? null : (_) => onTap(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Marca quem é de fora — na escala compartilhada isso muda o que se espera
/// da pessoa (não tem o app, não vê avisos).
class _GuestBadge extends StatelessWidget {
  const _GuestBadge();

  @override
  Widget build(BuildContext context) {
    return const AppBadge(
      label: 'Convidado',
      tone: AppTone.info,
      semanticsLabel: 'Convidado de fora: não tem conta no app e recebe a '
          'escala pelo texto compartilhado',
    );
  }
}

/// Chamar alguém de fora para esta escala.
class _GuestSheet extends StatefulWidget {
  const _GuestSheet();

  @override
  State<_GuestSheet> createState() => _GuestSheetState();
}

class _GuestSheetState extends State<_GuestSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Convidar alguém de fora', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Músico convidado não tem conta no app. Ele entra na escala e '
              'recebe os detalhes pelo texto compartilhado.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome'),
              onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_controller.text.trim()),
              child: const Text('Adicionar'),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
