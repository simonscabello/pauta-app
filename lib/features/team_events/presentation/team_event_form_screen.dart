import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/date/civil_date.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_picker_field.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/form_scaffold.dart';
import '../../../shared/widgets/unsaved_changes_guard.dart';
import '../../../shared/widgets/quarter_hour_picker.dart';
import '../../events/domain/event_datetime.dart';
import '../../team/data/team_repository.dart';
import '../data/team_event_repository.dart';
import '../domain/team_event.dart';

/// Marcar (ou corrigir) um evento da equipe.
///
/// **Um formulário curto de propósito.** A escala precisa de cultos, ensaio,
/// paleta e escalação; um churrasco precisa de nome, quando e onde. Cada campo
/// a mais aqui seria um campo que a liderança pula toda vez.
///
/// A hora de término é opcional e pode ser **removida** depois de posta — é a
/// única razão de o repositório ter `removeEndsAt`: no servidor, omitir
/// preserva, e sem um jeito de dizer "apague" ela ficaria presa.
class TeamEventFormScreen extends ConsumerStatefulWidget {
  const TeamEventFormScreen({super.key, this.eventId, this.initialDate});

  /// Nulo cria; preenchido edita.
  final String? eventId;

  /// O dia que a agenda tinha selecionado (`?data=AAAA-MM-DD`).
  final String? initialDate;

  bool get isEditing => eventId != null;

  @override
  ConsumerState<TeamEventFormScreen> createState() =>
      _TeamEventFormScreenState();
}

class _TeamEventFormScreenState extends ConsumerState<TeamEventFormScreen>
    with UnsavedChangesTracker {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();

  DateTime _date = today();
  TimeOfDay _startsAt = const TimeOfDay(hour: 19, minute: 30);
  TimeOfDay? _endsAt;

  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final inicial = parseDateKey(widget.initialDate);
    if (inicial != null) _date = inicial;
    if (widget.isEditing) _carregar();
  }

  @override
  String unsavedSignature() => [
        _title.text.trim(),
        _location.text.trim(),
        _notes.text.trim(),
        _date.toIso8601String(),
        '${_startsAt.hour}:${_startsAt.minute}',
        _endsAt == null ? '' : '${_endsAt!.hour}:${_endsAt!.minute}',
      ].join('\n');

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      final evento =
          await ref.read(teamEventRepositoryProvider).find(widget.eventId!);
      if (!mounted) return;
      final inicio = eventLocalTime(evento.startsAt, evento.timezone);
      final fim = evento.endsAt == null
          ? null
          : eventLocalTime(evento.endsAt!, evento.timezone);
      setState(() {
        _title.text = evento.title;
        _location.text = evento.location ?? '';
        _notes.text = evento.notes ?? '';
        _date = DateTime(inicio.year, inicio.month, inicio.day);
        _startsAt = TimeOfDay(hour: inicio.hour, minute: inicio.minute);
        _endsAt =
            fim == null ? null : TimeOfDay(hour: fim.hour, minute: fim.minute);
        _loading = false;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => (_error = error.message, _loading = false).$1);
    }
  }

  Future<void> _escolherData() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _date,
      // Um ano para trás porque corrigir um evento passado é legítimo; três
      // para a frente porque ninguém marca churrasco em 2031.
      firstDate: DateTime(_date.year - 1),
      lastDate: DateTime(DateTime.now().year + 3, 12, 31),
      helpText: 'Data do evento',
    );
    if (escolhida != null && mounted) setState(() => _date = escolhida);
  }

  Future<void> _escolherHora({required bool inicio}) async {
    final hora = await showQuarterHourPicker(
      context: context,
      initialTime: inicio
          ? _startsAt
          : _endsAt ??
              TimeOfDay(hour: (_startsAt.hour + 2) % 24, minute: _startsAt.minute),
      title: inicio ? 'Começa às' : 'Termina às',
    );
    if (hora == null || !mounted) return;
    setState(() {
      if (inicio) {
        _startsAt = hora;
      } else {
        _endsAt = hora;
      }
    });
  }

  DateTime _toUtc(TimeOfDay hora, String timezone) {
    return tz.TZDateTime(
      tz.getLocation(timezone),
      _date.year,
      _date.month,
      _date.day,
      hora.hour,
      hora.minute,
    ).toUtc();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    final teamId = ref.read(activeTeamIdProvider);
    if (teamId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Pelo `teamProvider`, e não pelo repositório direto: a tela da equipe
      // já carregou este cadastro, e ler pelo provider aproveita a resposta em
      // cache em vez de pedir de novo só para saber o fuso.
      final team = await ref.read(teamProvider(teamId).future);
      final timezone = team.timezone.isEmpty
          ? 'America/Sao_Paulo'
          : team.timezone;
      // Evento novo no passado avisaria a equipe de algo que já aconteceu —
      // foi o que o padrão "hoje, 19:30" fez às 21h30. Editar um antigo
      // continua possível (corrigir o local de uma reunião que passou).
      if (!widget.isEditing &&
          _toUtc(_startsAt, timezone).isBefore(DateTime.now().toUtc())) {
        setState(() {
          _error = 'Esse horário já passou. Escolha outro dia ou horário '
              'para a equipe não ser avisada de algo que já aconteceu.';
          _saving = false;
        });
        return;
      }
      final repo = ref.read(teamEventRepositoryProvider);
      final inicio = _toUtc(_startsAt, timezone).toIso8601String();
      final fim = _endsAt == null ? null : _toUtc(_endsAt!, timezone);

      final TeamEvent salvo;
      if (widget.isEditing) {
        salvo = await repo.update(
          widget.eventId!,
          title: _title.text.trim(),
          startsAt: inicio,
          endsAt: fim?.toIso8601String(),
          // Sem hora de término no formulário: o servidor precisa ouvir
          // "apague", porque omitir significa "não mexe".
          removeEndsAt: _endsAt == null,
          location: _location.text.trim(),
          notes: _notes.text.trim(),
        );
      } else {
        salvo = await repo.create(
          teamId,
          title: _title.text.trim(),
          startsAt: inicio,
          endsAt: fim?.toIso8601String(),
          location: _location.text.trim(),
          notes: _notes.text.trim(),
        );
      }

      _recarregarAgenda(teamId);
      if (!mounted) return;
      markSaved();
      showAppSnackBar(
        context,
        widget.isEditing ? 'Evento atualizado.' : 'Evento marcado.',
      );
      // `pushReplacement`: quem acabou de criar quer ver o que criou, e voltar
      // ao formulário depois disso seria voltar para um rascunho já gravado.
      context.pushReplacement('/eventos/${salvo.id}');
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// A agenda lê os eventos por escopo; um evento novo pode cair em qualquer
  /// um dos dois, e a data pode ter mudado na edição.
  void _recarregarAgenda(String teamId) {
    for (final scope in ['upcoming', 'past']) {
      ref.invalidate(teamEventsProvider((teamId, scope)));
    }
    if (widget.eventId != null) {
      ref.invalidate(teamEventProvider(widget.eventId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    markUnsavedBaseline();

    return FormScaffold(
      isDirty: hasUnsavedChanges,
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Editar evento' : 'Novo evento'),
      ),
      // Sem repetir "Novo evento" no corpo: a barra já diz. A frase de apoio
      // fica só ao criar, quando ainda explica o que cabe aqui.
      subtitle: widget.isEditing
          ? null
          : 'Reunião, ensaio geral, confraternização ou outro compromisso da '
              'equipe.',
      children: [
        if (_error != null) FormErrorBanner(message: _error!),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nome do evento',
                  hintText: 'Churrasco da equipe',
                ),
                // Obrigatório, ao contrário do título da escala: "quinta, 17"
                // não diz se é reunião de liderança ou churrasco.
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Dê um nome ao evento.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              // Campos inteiros tocáveis (o campo de escolha do app): antes só
              // o texto do valor abria o seletor, e a borda e o ícone não
              // respondiam.
              AppPickerField(
                icon: Icons.event_rounded,
                label: 'Data',
                value: capitalizeWeekday(
                  '${_diaDaSemana(_date)}, ${_date.day} de ${_mes(_date)}',
                ),
                onTap: _escolherData,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppPickerField(
                icon: Icons.schedule_rounded,
                label: 'Começa às',
                value: _hhmm(_startsAt),
                onTap: () => _escolherHora(inicio: true),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppPickerField(
                icon: Icons.schedule_outlined,
                label: 'Termina às',
                // A ausência é dita, e não deixada em branco: churrasco sem
                // hora para acabar é o normal, e um campo vazio pareceria
                // esquecimento.
                value: _endsAt == null ? null : _hhmm(_endsAt!),
                placeholder: 'Sem hora definida',
                onTap: () => _escolherHora(inicio: false),
                onClear: () => setState(() => _endsAt = null),
                clearTooltip: 'Tirar a hora de término',
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _location,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Local (opcional)',
                  hintText: 'Salão da igreja',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Recado (opcional)',
                  hintText: 'Cada um leva uma coisa.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              AppSubmitButton(
                label: widget.isEditing ? 'Salvar' : 'Marcar evento',
                loading: _saving,
                onPressed: _saving ? null : _salvar,
              ),
              if (!widget.isEditing) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'A equipe recebe um aviso assim que você marcar.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String _hhmm(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

const _semana = [
  'segunda-feira',
  'terça-feira',
  'quarta-feira',
  'quinta-feira',
  'sexta-feira',
  'sábado',
  'domingo',
];

const _meses = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

String _diaDaSemana(DateTime date) => _semana[date.weekday - 1];
String _mes(DateTime date) => _meses[date.month - 1];
