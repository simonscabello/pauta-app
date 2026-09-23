import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/network/api_exception.dart';
import '../../../core/responsive/adaptive_dialog.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_choice_bar.dart';
import '../../../shared/widgets/app_date_picker.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_picker_field.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/form_scaffold.dart';
import '../../../shared/widgets/unsaved_changes_guard.dart';
import '../../../shared/widgets/quarter_hour_picker.dart';
import '../../../shared/widgets/section_header.dart';
import '../../team/data/team_repository.dart';
import '../../team/domain/service_template.dart';
import '../data/event_repository.dart';
import '../domain/event_datetime.dart';
import '../domain/event_models.dart';
import '../domain/next_service_date.dart';
import 'schedule_changed_dialog.dart';

/// Um culto sendo montado no formulário.
///
/// `templateId` guarda de qual linha da grade ele veio — é o que permite, mais
/// tarde, saber quais escalas uma mudança da grade afetaria. Nulo em culto
/// avulso (Páscoa, especial).
class _ServiceDraft {
  _ServiceDraft({
    required this.label,
    required this.time,
    this.id,
    this.templateId,
  });

  /// O culto que já está gravado, quando este rascunho veio de uma escala
  /// existente. Nulo em culto novo.
  ///
  /// É o que o servidor usa para saber que mudar o horário da noite é editar
  /// aquele culto, e não trocá-lo por outro: sem o id ele recriaria a linha, e
  /// o repertório da noite iria junto.
  final String? id;

  String label;
  TimeOfDay time;
  final String? templateId;

  String get timeLabel => '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

/// Em que dia é o ensaio, em relação à escala.
enum _RehearsalDay {
  none('Sem ensaio'),
  sameDay('No dia'),
  dayBefore('Véspera'),
  other('Outro dia…');

  const _RehearsalDay(this.label);

  final String label;
}

class EventFormScreen extends ConsumerStatefulWidget {
  const EventFormScreen({super.key, this.eventId, this.initialDate});

  final String? eventId;

  /// Dia já escolhido em outra tela — hoje, o calendário de indisponibilidade
  /// e as datas em aberto da agenda. Quem chega dali já decidiu a data; repetir
  /// a escolha seria pedir duas vezes a mesma coisa, e é onde se erra o
  /// domingo.
  ///
  /// Nulo é "ninguém decidiu ainda": aí a grade da equipe decide, em
  /// [nextScheduledDate].
  final DateTime? initialDate;

  @override
  ConsumerState<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends ConsumerState<EventFormScreen>
    with UnsavedChangesTracker {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  final _colorPalette = TextEditingController();

  /// O dia da escala. Manhã e noite são o mesmo domingo, então a data é uma só
  /// e cada culto contribui apenas com o horário.
  late DateTime _date;

  List<_ServiceDraft> _services = [];
  DateTime? _rehearsalAt;

  /// Ver [RepertoireMode]. Planejado é o padrão porque é o domingo comum -- e
  /// porque é o que toda escala já gravada é.
  RepertoireMode _repertoireMode = RepertoireMode.planned;

  /// Título, local e observações começam recolhidos.
  ///
  /// **Os três juntos aparecem em menos de uma escala em dez.** O título era o
  /// primeiro campo da tela, e a primeira coisa que se lia ao criar a escala de
  /// domingo era um pedido para nomear um domingo -- que não tem nome. Em
  /// edição a seção abre sozinha quando algum deles está preenchido: escondê-lo
  /// esconderia o que já foi escrito.
  bool _extrasExpanded = false;

  /// A grade só semeia os cultos uma vez, e só numa escala nova: em edição, os
  /// horários que valem são os que já foram salvos.
  bool _seededFromTemplates = false;
  bool _populated = false;
  bool _loading = false;
  String? _error;

  /// Criou e está indo para a escalação: o botão continua travado durante a
  /// transição (ver [kArrivalTapShield]).
  bool _saindo = false;

  /// Versão da escala no momento em que esta tela a abriu. Vai junto ao salvar
  /// para o servidor recusar a gravação se outra pessoa mexeu no meio.
  DateTime? _expectedUpdatedAt;

  bool get _isEditing => widget.eventId != null;

  @override
  String unsavedSignature() => [
        _date.toIso8601String(),
        for (final s in _services) '${s.id}|${s.label}|${s.timeLabel}',
        _rehearsalAt?.toIso8601String(),
        _repertoireMode.name,
        _title.text.trim(),
        _location.text.trim(),
        _notes.text.trim(),
        _colorPalette.text.trim(),
      ].join('\n');

  @override
  void initState() {
    super.initState();
    final start = widget.initialDate ?? DateTime.now();
    _date = DateTime(start.year, start.month, start.day);
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    _colorPalette.dispose();
    super.dispose();
  }

  void _populate(Event event) {
    if (_populated) return;

    _populated = true;
    _seededFromTemplates = true;
    _expectedUpdatedAt = event.updatedAt;
    _title.text = event.title ?? '';
    _location.text = event.location ?? '';
    _notes.text = event.notes ?? '';
    _colorPalette.text = event.colorPalette ?? '';
    _repertoireMode = event.repertoireMode;
    _extrasExpanded = _title.text.isNotEmpty ||
        _location.text.isNotEmpty ||
        _notes.text.isNotEmpty;

    final timezone = _timezone(event.timezone);
    final start = eventLocalTime(event.startsAt, timezone);
    _date = DateTime(start.year, start.month, start.day);
    // `services`, e não `displayServices`: o fallback para cache antigo inventa
    // um culto usando o id DA ESCALA, e devolver esse id ao servidor faria a
    // edição ser recusada com INVALID_SERVICE. Sem culto gravado, os rascunhos
    // nascem sem id e viram cultos novos.
    final gravados = event.services;
    _services = [
      for (final service in gravados.isEmpty ? event.displayServices : gravados)
        _ServiceDraft(
          id: gravados.isEmpty ? null : service.id,
          label: service.label,
          time: TimeOfDay.fromDateTime(
            eventLocalTime(service.startsAt, timezone),
          ),
        ),
    ];
    _rehearsalAt = event.rehearsalAt == null
        ? null
        : eventLocalTime(event.rehearsalAt!, timezone);
  }

  /// Escolhe o dia e preenche os cultos a partir da grade da igreja.
  ///
  /// **A data vem da grade quando ninguém a escolheu antes.** Abrir sempre em
  /// hoje era abrir quase sempre num dia sem culto: quem cria a escala do
  /// domingo numa quarta-feira via "Não há grade para este dia da semana" e
  /// tinha de ir ao calendário consertar o palpite do app. Chegando de uma
  /// tela que já decidiu a data ([EventFormScreen.initialDate]), a grade não
  /// opina — ali a escolha já foi feita.
  void _seedFromTemplates(List<ServiceTemplate> templates, String timezone) {
    if (_seededFromTemplates) return;
    _seededFromTemplates = true;

    if (widget.initialDate == null) {
      final sugerida = nextScheduledDate(
        templates: templates,
        timezone: timezone,
        now: DateTime.now(),
      );
      // Nulo é grade vazia ou nada na janela: fica o dia de hoje, que é o que
      // esta tela sempre propôs. Nenhuma data é inventada.
      if (sugerida != null) _date = sugerida;
    }

    _services = _templatesForDate(templates, _date);
  }

  List<_ServiceDraft> _templatesForDate(
    List<ServiceTemplate> templates,
    DateTime date,
  ) {
    final matching = templates.where((t) => t.matchesDate(date)).toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return [
      for (final template in matching)
        _ServiceDraft(
          label: template.label,
          time: template.timeOfDay,
          templateId: template.id,
        ),
    ];
  }

  String _timezone(String value) => value.isEmpty ? 'America/Sao_Paulo' : value;

  /// A grade mensal do app, com os dias de culto marcados e o passado
  /// apagado. O seletor genérico do Material não mostrava a grade e aceitava
  /// criar escala num domingo que já tinha passado. Editar uma escala antiga
  /// continua possível: o dia dela fica escolhível.
  Future<void> _pickDate(List<ServiceTemplate> templates) async {
    final now = DateTime.now();
    final hoje = DateTime(now.year, now.month, now.day);
    final ativos = templates.where((t) => t.isActive).toList();
    final selected = await showAppDatePicker(
      context: context,
      title: 'Dia da escala',
      initialDate: _date,
      firstDate: _date.isBefore(hoje) ? _date : hoje,
      isMarked: ativos.isEmpty
          ? null
          : (day) => ativos.any((t) => t.matchesDate(day)),
    );
    if (selected == null || !mounted) return;

    final newDate = DateTime(selected.year, selected.month, selected.day);
    final suggestion = _templatesForDate(templates, newDate);

    // Trocar a data troca o dia da semana, e a grade do novo dia é outra. Só
    // sugerimos quando há grade para o dia -- e só quando a lista atual ainda
    // é a sugestão anterior, para não descartar horário digitado à mão.
    final replaceable = suggestion.isNotEmpty &&
        (_services.isEmpty || _services.every((s) => s.templateId != null));

    setState(() {
      // O ensaio acompanha a escala **mantendo a distância**: o da véspera
      // continua na véspera do dia novo. Antes ele caía no mesmo dia da escala
      // nova, qualquer que fosse o combinado.
      final rehearsal = _rehearsalAt;
      if (rehearsal != null) {
        final offset = DateTime(rehearsal.year, rehearsal.month, rehearsal.day)
            .difference(_date)
            .inDays;
        final day = newDate.add(Duration(days: offset));
        _rehearsalAt = DateTime(
          day.year,
          day.month,
          day.day,
          rehearsal.hour,
          rehearsal.minute,
        );
      }
      _date = newDate;
      if (replaceable) _services = suggestion;
    });
  }

  Future<void> _pickServiceTime(int index) async {
    final selected = await showQuarterHourPicker(
      context: context,
      initialTime: _services[index].time,
      title: 'Horário de ${_services[index].label}',
    );
    if (selected == null || !mounted) return;
    setState(() => _services[index].time = selected);
  }

  /// Tirar um culto da escala apaga o repertório dele junto (a FK é cascade),
  /// e isso não estava dito em lugar nenhum: era um "x" sem aviso.
  Future<void> _removeService(int index) async {
    final service = _services[index];
    final confirmed = await showConfirmDialog(
      context,
      title: 'Tirar ${service.label} desta escala?',
      message: 'O horário sai da escala. Se já houver repertório escolhido '
          'para ele, as músicas saem junto.',
      confirmLabel: 'Tirar',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _services = [..._services]..removeAt(index));
  }

  Future<void> _addService() async {
    final draft = await showAdaptiveSheet<_ServiceDraft>(
      context: context,
      maxWidth: 480,
      builder: (_) => const _ExtraServiceSheet(
        suggestions: serviceNamePresets,
      ),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _services = [..._services, draft]
        ..sort((a, b) => _minutes(a.time).compareTo(_minutes(b.time)));
    });
  }

  static int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;

  /// Em que dia é o ensaio, em relação à escala.
  _RehearsalDay get _rehearsalDay {
    final rehearsal = _rehearsalAt;
    if (rehearsal == null) return _RehearsalDay.none;
    final offset = DateTime(rehearsal.year, rehearsal.month, rehearsal.day)
        .difference(_date)
        .inDays;
    return switch (offset) {
      0 => _RehearsalDay.sameDay,
      -1 => _RehearsalDay.dayBefore,
      _ => _RehearsalDay.other,
    };
  }

  /// O ensaio é quase sempre no dia ou na véspera, e o formulário pedia um
  /// calendário e depois um relógio para dizer isso. Agora é um chip e a hora.
  Future<void> _chooseRehearsal(_RehearsalDay day) async {
    switch (day) {
      case _RehearsalDay.none:
        setState(() => _rehearsalAt = null);
      case _RehearsalDay.sameDay:
      case _RehearsalDay.dayBefore:
        final base = day == _RehearsalDay.sameDay
            ? _date
            : _date.subtract(const Duration(days: 1));
        final time = await showQuarterHourPicker(
          context: context,
          initialTime: _rehearsalAt == null
              ? const TimeOfDay(hour: 19, minute: 0)
              : TimeOfDay.fromDateTime(_rehearsalAt!),
          title: 'Horário do ensaio',
        );
        if (time == null || !mounted) return;
        setState(() {
          _rehearsalAt = DateTime(
            base.year,
            base.month,
            base.day,
            time.hour,
            time.minute,
          );
        });
      case _RehearsalDay.other:
        await _pickRehearsal();
    }
  }

  Future<void> _pickRehearsal() async {
    final current = _rehearsalAt ?? _date;
    final date = await showDatePicker(
      context: context,
      locale: const Locale('pt', 'BR'),
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;

    final time = await showQuarterHourPicker(
      context: context,
      initialTime: _rehearsalAt == null
          ? const TimeOfDay(hour: 19, minute: 0)
          : TimeOfDay.fromDateTime(current),
      title: 'Horário do ensaio',
    );
    if (time == null || !mounted) return;

    setState(() {
      _rehearsalAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  /// "19:00" no dia da escala; "sáb 19:00" em outro dia — o mesmo formato do
  /// detalhe da escala. Longe da semana da escala, a data vai junto.
  String _rehearsalLabel(DateTime rehearsal) {
    final hora = DateFormat('HH:mm', 'pt_BR').format(rehearsal);
    final dia =
        DateFormat('EEE', 'pt_BR').format(rehearsal).replaceAll('.', '');
    return switch (_rehearsalDay) {
      _RehearsalDay.sameDay => hora,
      _RehearsalDay.dayBefore => '$dia $hora',
      _ => '$dia ${DateFormat('d/M', 'pt_BR').format(rehearsal)} $hora',
    };
  }

  DateTime _toUtc(DateTime dateTime, String timezone) {
    final location = tz.getLocation(timezone);
    return tz.TZDateTime(
      location,
      dateTime.year,
      dateTime.month,
      dateTime.day,
      dateTime.hour,
      dateTime.minute,
    ).toUtc();
  }

  List<Map<String, String?>> _servicePayload(String timezone) {
    return [
      for (final service in _services)
        {
          // Só nos cultos que já existiam: é o que diz ao servidor "edite este"
          // em vez de "troque por um novo".
          if (service.id != null) 'id': service.id,
          'label': service.label,
          'startsAt': _toUtc(
            DateTime(
              _date.year,
              _date.month,
              _date.day,
              service.time.hour,
              service.time.minute,
            ),
            timezone,
          ).toIso8601String(),
          if (service.templateId != null) 'templateId': service.templateId,
        },
    ];
  }

  Future<String> _createTimezone(String teamId) async {
    final team = await ref.read(teamRepositoryProvider).find(teamId);
    return _timezone(team.timezone);
  }

  /// [force] repete a gravação sem a trava de versão: é o "salvar assim mesmo"
  /// de quem viu o aviso de que a escala mudou e decidiu sobrescrever.
  Future<void> _submit({bool force = false}) async {
    if (!_formKey.currentState!.validate()) return;

    if (_services.isEmpty) {
      setState(() => _error = 'Escolha pelo menos um culto para esta escala.');
      return;
    }

    final activeTeamId = ref.read(activeTeamIdProvider);
    if (!_isEditing && activeTeamId == null) {
      setState(() => _error = 'Nenhuma equipe ativa foi encontrada.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cached = _isEditing
          ? await ref.read(eventRepositoryProvider).find(widget.eventId!)
          : null;
      final event = cached?.data;
      final timezone = event == null
          ? await _createTimezone(activeTeamId!)
          : _timezone(event.timezone);

      final services = _servicePayload(timezone);
      final rehearsalAt = _rehearsalAt == null
          ? null
          : _toUtc(_rehearsalAt!, timezone).toIso8601String();
      final repository = ref.read(eventRepositoryProvider);

      if (event != null) {
        await repository.update(
          event.id,
          title: _title.text.trim(),
          services: services,
          rehearsalAt: rehearsalAt,
          removeRehearsalAt: _rehearsalAt == null,
          location: _location.text.trim(),
          notes: _notes.text.trim(),
          colorPalette: _colorPalette.text.trim(),
          repertoireMode: _repertoireMode,
          expectedUpdatedAt: force ? null : _expectedUpdatedAt,
        );
        ref.invalidate(eventsProvider((event.teamId, 'upcoming')));
        ref.invalidate(eventsProvider((event.teamId, 'past')));
        ref.invalidate(eventProvider(event.id));
      } else {
        final createdEvent = await repository.create(
          activeTeamId!,
          title: _title.text.trim(),
          services: services,
          rehearsalAt: rehearsalAt,
          location: _location.text.trim(),
          notes: _notes.text.trim(),
          colorPalette: _colorPalette.text.trim(),
          repertoireMode: _repertoireMode,
        );
        ref.invalidate(eventsProvider((createdEvent.teamId, 'upcoming')));
        ref.invalidate(eventsProvider((createdEvent.teamId, 'past')));
        ref.invalidate(eventProvider(createdEvent.id));

        if (!mounted) return;
        markSaved();
        _saindo = true;
        // Criar a escala não é o fim da tarefa: ela nasce sem ninguém escalado
        // e sem repertório. Em vez de devolver o líder à agenda -- de onde ele
        // teria de achar a escala nova e abrir dois menus --, a criação emenda
        // direto na escalação e, dali, no repertório.
        //
        // **`?novo=1` diz só "esta escala acabou de nascer".** Se o passo
        // seguinte é o repertório ou o detalhe da escala, quem decide é a
        // escalação, olhando o modo que foi gravado agora: com repertório
        // definido na hora não há lista para montar.
        //
        // **Uma chamada de navegação por passo.** A tentativa anterior fazia
        // `go` (para montar agenda → detalhe) e `push` da escalação por cima,
        // no mesmo frame: em go_router as duas disparam análises assíncronas, e
        // o `push` toma como base a configuração de ANTES do `go`. A pilha
        // saía indeterminada e o passo seguinte não avançava. `pushReplacement`
        // troca este formulário -- que já cumpriu seu papel -- pela escalação,
        // e cada etapa faz o mesmo com a próxima.
        context.pushReplacement(
          '/agenda/${createdEvent.id}/escalar?novo=1',
        );
        return;
      }

      if (!mounted) return;
      markSaved();
      context.pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == scheduleChangedCode) {
        await _resolveConflict(error.message);
        return;
      }
      setState(() => _error = error.message);
    } finally {
      if (mounted && !_saindo) setState(() => _loading = false);
    }
  }

  /// Sobrescrever é escolha da pessoa; conferir é o caminho oferecido primeiro.
  /// Ao voltar, o detalhe recarrega e mostra a escala como ela está agora.
  Future<void> _resolveConflict(String message) async {
    final overwrite = await showScheduleChangedDialog(context, message);
    if (!mounted) return;

    if (overwrite) {
      await _submit(force: true);
      return;
    }
    ref.invalidate(eventProvider(widget.eventId!));
    if (!mounted) return;
    markSaved();
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final eventAsync =
        _isEditing ? ref.watch(eventProvider(widget.eventId!)) : null;

    if (eventAsync != null && eventAsync.isLoading) {
      return const Scaffold(body: AppLoading());
    }

    if (eventAsync != null && eventAsync.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Culto')),
        body: AppErrorState(
          message: 'Não foi possível carregar a escala.',
          onRetry: () => ref.invalidate(eventProvider(widget.eventId!)),
        ),
      );
    }

    final event = eventAsync?.valueOrNull?.data;
    if (event != null) _populate(event);

    final teamId = ref.watch(activeTeamIdProvider);
    final templatesAsync = teamId == null
        ? const AsyncValue<List<ServiceTemplate>>.data([])
        : ref.watch(serviceTemplatesProvider(teamId));
    final templates = templatesAsync.valueOrNull ?? const <ServiceTemplate>[];

    // O fuso da equipe decide que dia é "hoje" ao propor a data. Observado
    // aqui, e não buscado na hora de semear, porque semear acontece durante o
    // `build` -- e porque a agenda já mantém esta resposta em cache.
    final teamAsync = teamId == null ? null : ref.watch(teamProvider(teamId));

    // A grade só entra em escala nova; em edição valem os horários salvos.
    //
    // A espera é pelas **duas** respostas: semear com o fuso padrão enquanto a
    // equipe carrega proporia o dia errado para uma igreja em outro fuso, e
    // depois nada corrigiria -- a semeadura acontece uma vez só. Equipe que
    // falhou não trava a tela: aí vale o fuso padrão, que é o de quase todas.
    final teamSettled =
        teamAsync == null || teamAsync.hasValue || teamAsync.hasError;
    if (!_isEditing && templatesAsync.hasValue && teamSettled) {
      _seedFromTemplates(
        templates,
        _timezone(teamAsync?.valueOrNull?.timezone ?? ''),
      );
    }

    // A fotografia do "como estava" só depois de o formulário ficar pronto:
    // antes disso a grade ainda vai trocar a data e os cultos sozinha, e isso
    // não é alteração de ninguém.
    if (_isEditing ? _populated : _seededFromTemplates) markUnsavedBaseline();

    return FormScaffold(
      isDirty: hasUnsavedChanges,
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar escala' : 'Nova escala'),
      ),
      // O botão fica preso embaixo: com "Informações adicionais" aberta o
      // formulário rola mais de uma tela, e "Criar escala" ficava longe.
      bottomAction: AppSubmitButton(
        label: _isEditing ? 'Salvar' : 'Criar escala',
        loading: _loading,
        onPressed: _submit,
      ),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPickerField(
                label: 'Dia',
                icon: Icons.calendar_today_outlined,
                // O ano só quando não é o atual, como no resto do app.
                value: capitalizeWeekday(
                  DateFormat(
                    _date.year == DateTime.now().year
                        ? "EEEE, d 'de' MMMM"
                        : "EEEE, d 'de' MMMM 'de' y",
                    'pt_BR',
                  ).format(_date),
                ),
                enabled: !_loading,
                onTap: () => _pickDate(templates),
              ),
              const SizedBox(height: AppSpacing.xl),
              _ServicesSection(
                services: _services,
                templates: templates,
                date: _date,
                loadingTemplates: templatesAsync.isLoading,
                enabled: !_loading,
                onPickTime: _pickServiceTime,
                onRemove: _removeService,
                onAdd: _addService,
              ),
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(
                title: 'Ensaio',
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
              ),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final day in _RehearsalDay.values)
                    ChoiceChip(
                      label: Text(day.label),
                      selected: _rehearsalDay == day,
                      onSelected:
                          _loading ? null : (_) => _chooseRehearsal(day),
                    ),
                ],
              ),
              if (_rehearsalAt != null) ...[
                const SizedBox(height: AppSpacing.md),
                AppPickerField(
                  label: 'Horário do ensaio',
                  icon: Icons.schedule_outlined,
                  value: _rehearsalLabel(_rehearsalAt!),
                  enabled: !_loading,
                  onTap: () => _chooseRehearsal(_rehearsalDay),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              _RepertoireModeSection(
                mode: _repertoireMode,
                enabled: !_loading,
                onChanged: (mode) => setState(() => _repertoireMode = mode),
              ),
              const SizedBox(height: AppSpacing.xl),
              // Fica na tela principal, e não com o título: é combinado da
              // equipe para aquele dia ("todos de preto"), e quem monta a
              // escala precisa vê-lo sem procurar.
              TextFormField(
                controller: _colorPalette,
                enabled: !_loading,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Paleta de roupas (opcional)',
                  hintText: 'Preto e dourado',
                  helperText: 'A combinação de cores que a equipe vai vestir.',
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _AdditionalInfoSection(
                expanded: _extrasExpanded,
                onToggle: () =>
                    setState(() => _extrasExpanded = !_extrasExpanded),
                filled: [
                  if (_title.text.trim().isNotEmpty) 'Título',
                  if (_location.text.trim().isNotEmpty) 'Local',
                  if (_notes.text.trim().isNotEmpty) 'Observações',
                ],
                children: [
                  // Opcional e sem validação: o domingo comum não precisa de
                  // nome, e exigir um produzia "Domingo" ao lado de um selo que
                  // já dizia DOM 9 AGO. Só culto especial tem o que nomear.
                  TextFormField(
                    controller: _title,
                    enabled: !_loading,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    // O resumo recolhido conta quais campos têm algo dentro;
                    // sem isto ele só mudaria no próximo `setState` de outra
                    // coisa.
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Título (opcional)',
                      hintText: 'Páscoa, Ceia, Batismo...',
                      helperText: 'Deixe vazio no culto comum.',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _location,
                    enabled: !_loading,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                    decoration:
                        const InputDecoration(labelText: 'Local (opcional)'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _notes,
                    enabled: !_loading,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 3,
                    maxLines: 5,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Observações (opcional)',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.xl),
          FormErrorBanner(message: _error!),
        ],
      ],
    );
  }
}

/// Como o repertório desta escala vai ser decidido.
///
/// **Da escala, e não de cada culto**: no domingo de manhã e noite quem
/// ministra é a mesma pessoa e o jeito de trabalhar é um só.
///
/// A linha de apoio muda com a escolha porque é ela que diz a consequência --
/// escolher "na hora" desliga toda a cobrança de repertório desta escala, e
/// isso precisa estar dito onde se escolhe, não descoberto depois.
class _RepertoireModeSection extends StatelessWidget {
  const _RepertoireModeSection({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final RepertoireMode mode;
  final bool enabled;
  final ValueChanged<RepertoireMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Músicas',
          subtitle: switch (mode) {
            RepertoireMode.planned =>
              'As músicas são escolhidas antes e vão junto na escala.',
            RepertoireMode.onTheFly =>
              'Quem ministra escolhe no culto. A escala não vai cobrar '
                  'repertório nem avisar que faltam músicas.',
          },
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        ),
        AppChoiceBar<RepertoireMode>(
          value: mode,
          options: const [
            AppChoice(
              value: RepertoireMode.planned,
              label: 'Planejado',
              icon: Icons.queue_music_rounded,
            ),
            AppChoice(
              value: RepertoireMode.onTheFly,
              label: 'Na hora',
              icon: Icons.bolt_rounded,
            ),
          ],
          onChanged: (value) {
            if (!enabled) return;
            onChanged(value);
          },
        ),
      ],
    );
  }
}

/// Título, local e observações — recolhidos até alguém precisar deles.
///
/// Os três são opcionais e raros, e ocupavam um terço da tela de criação: o
/// título abria o formulário pedindo nome para um domingo que não tem nome.
/// Recolhidos, a escala comum cabe numa tela — dia, cultos, repertório — e
/// quem tem uma Páscoa para nomear continua a um toque de distância.
///
/// **O resumo diz o que está guardado dentro.** Uma seção fechada que não
/// mostra sinal do que contém é uma seção que ninguém abre — e aí o local que
/// alguém escreveu semana passada some da vista de quem edita.
class _AdditionalInfoSection extends StatelessWidget {
  const _AdditionalInfoSection({
    required this.expanded,
    required this.onToggle,
    required this.filled,
    required this.children,
  });

  final bool expanded;
  final VoidCallback onToggle;

  /// Os nomes dos campos que já têm conteúdo: "Título", "Local", "Observações".
  final List<String> filled;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final resumo =
        filled.isEmpty ? 'Título, local e observações' : filled.join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Informações adicionais',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            resumo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: AppMotion.fast,
                      curve: AppMotion.standard,
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
        ],
      ),
    );
  }
}

/// Os cultos desta escala.
///
/// Vêm marcados a partir da grade da igreja: escolhida a data, os cultos
/// daquele dia da semana já estão aqui. Dá para desmarcar (domingo sem culto
/// de manhã acontece) e acrescentar um avulso (Páscoa, especial).
class _ServicesSection extends StatelessWidget {
  const _ServicesSection({
    required this.services,
    required this.templates,
    required this.date,
    required this.loadingTemplates,
    required this.enabled,
    required this.onPickTime,
    required this.onRemove,
    required this.onAdd,
  });

  final List<_ServiceDraft> services;
  final List<ServiceTemplate> templates;
  final DateTime date;
  final bool loadingTemplates;
  final bool enabled;
  final ValueChanged<int> onPickTime;
  final ValueChanged<int> onRemove;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasGradeForDay = templates.any((t) => t.matchesDate(date));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Enquanto a grade carrega não se afirma nada sobre ela: "Não há grade
        // para este dia" aparecia por um instante e logo dava lugar ao culto
        // que existia, como se a tela tivesse mudado de ideia.
        SectionHeader(
          title: 'Cultos',
          subtitle: loadingTemplates
              ? null
              : hasGradeForDay
                  ? 'Vieram da grade da igreja. Remova o que não vai ter.'
                  : 'Não há grade para este dia da semana. Adicione o horário.',
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        ),
        if (loadingTemplates)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          )
        else if (services.isEmpty)
          AppCard(
            surface: CardSurface.sunken,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'Nenhum culto nesta escala.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          // Uma superfície para os cultos, e não uma caixa com borda para
          // cada um: são as linhas de uma lista só.
          AppCard(
            child: Column(
              children: [
                for (var i = 0; i < services.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: AppSpacing.lg,
                      color: scheme.outlineVariant,
                    ),
                  _ServiceRow(
                    service: services[i],
                    enabled: enabled,
                    onPickTime: () => onPickTime(i),
                    onRemove: () => onRemove(i),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: enabled ? onAdd : null,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Adicionar culto'),
          ),
        ),
      ],
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.service,
    required this.enabled,
    required this.onPickTime,
    required this.onRemove,
  });

  final _ServiceDraft service;
  final bool enabled;
  final VoidCallback onPickTime;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(Icons.church_rounded, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              service.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          TextButton(
            onPressed: enabled ? onPickTime : null,
            child: Text(service.timeLabel),
          ),
          IconButton(
            tooltip: 'Remover culto',
            onPressed: enabled ? onRemove : null,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Culto fora da grade: Páscoa, vigília, culto especial.
///
/// O nome vem sugerido em chips — os nomes da grade e os especiais que se
/// repetem —, e o campo continua aceitando qualquer outro.
class _ExtraServiceSheet extends StatefulWidget {
  const _ExtraServiceSheet({required this.suggestions});

  final List<String> suggestions;

  @override
  State<_ExtraServiceSheet> createState() => _ExtraServiceSheetState();
}

class _ExtraServiceSheetState extends State<_ExtraServiceSheet> {
  final _label = TextEditingController();
  TimeOfDay _time = const TimeOfDay(hour: 19, minute: 0);
  String? _error;

  @override
  void dispose() {
    _label.dispose();
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
            Text('Adicionar culto', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Para um culto que não está na grade da igreja.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ListenableBuilder(
              listenable: _label,
              builder: (context, _) => Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final name in widget.suggestions)
                    ChoiceChip(
                      label: Text(name),
                      selected: _label.text.trim() == name,
                      onSelected: (_) => _label.text = name,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _label,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Vigília, Especial...',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPickerField(
              label: 'Horário',
              icon: Icons.schedule_outlined,
              value: '${_time.hour.toString().padLeft(2, '0')}:'
                  '${_time.minute.toString().padLeft(2, '0')}',
              onTap: () async {
                final picked = await showQuarterHourPicker(
                  context: context,
                  initialTime: _time,
                  title: 'Horário do culto',
                );
                if (picked != null) setState(() => _time = picked);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: () {
                final label = _label.text.trim();
                if (label.isEmpty) {
                  setState(() => _error = 'Informe o nome do culto.');
                  return;
                }
                Navigator.of(context).pop(
                  _ServiceDraft(label: label, time: _time),
                );
              },
              child: const Text('Adicionar'),
            ),
          ],
        ),
      ),
    );
  }
}
