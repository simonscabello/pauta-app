import 'package:flutter/material.dart';

import '../../../core/date/civil_date.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_month_grid.dart';
import '../../../shared/widgets/app_notice.dart';

/// O que o seletor devolve: o conjunto final de dias marcados (não só os
/// novos, para a tela calcular o que entrou e o que saiu) e o motivo dos dias
/// que entraram.
typedef MultiDatePick = ({Set<DateTime> dates, String? reason});

/// Motivos que se repetem. Tocar preenche o campo; escrever outro continua
/// valendo.
const unavailabilityReasons = ['Viagem', 'Trabalho', 'Saúde', 'Família'];

/// Calendário de seleção múltipla.
///
/// O Flutter só traz `showDatePicker` (um dia) e `showDateRangePicker` (um
/// intervalo contínuo). Nenhum dos dois serve aqui: quem viaja costuma perder
/// três domingos seguidos e estar presente nos dias entre eles. Este seletor
/// alterna dia a dia.
///
/// **O motivo vem na mesma folha.** Era um segundo diálogo depois de
/// confirmar os dias ("Quer dizer o motivo?", com "Pular") — um passo a mais
/// para uma pergunta opcional. Agora ele aparece embaixo do calendário assim
/// que algum dia novo é marcado.
///
/// [isServiceDay] marca os dias em que a igreja tem culto pela grade: são os
/// únicos que importam, e sem a marca a pessoa procurava o domingo certo entre
/// trinta números iguais.
///
/// [scheduledOn] descreve os dias em que a pessoa **já está escalada**
/// ("dom 4/10 (Vocal e Violão)"). Marcar um deles mostra, antes de enviar, que
/// quem lidera vai ser avisado: sem isso o retorno era só "Aviso enviado para
/// 1 dia", e a pessoa não sabia se a troca estava resolvida.
Future<MultiDatePick?> showMultiDatePicker({
  required BuildContext context,
  required Set<DateTime> initialSelection,
  bool Function(DateTime day)? isServiceDay,
  String? Function(DateTime day)? scheduledOn,
  int monthsAhead = 12,
}) {
  return showModalBottomSheet<MultiDatePick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MultiDatePickerSheet(
      initialSelection: initialSelection,
      isServiceDay: isServiceDay,
      scheduledOn: scheduledOn,
      monthsAhead: monthsAhead,
    ),
  );
}

/// O rótulo do botão diz o que vai acontecer (a regra do app para botões),
/// e não "Confirmar".
@visibleForTesting
String multiDatePickerActionLabel({required int added, required int removed}) {
  String dias(int n) => n == 1 ? '1 dia' : '$n dias';
  if (added > 0 && removed == 0) return 'Avisar ${dias(added)}';
  if (removed > 0 && added == 0) return 'Liberar ${dias(removed)}';
  if (added > 0 && removed > 0) return 'Salvar os dias';
  return 'Manter como está';
}

DateTime _dayOnly(DateTime date) => DateTime(date.year, date.month, date.day);

class _MultiDatePickerSheet extends StatefulWidget {
  const _MultiDatePickerSheet({
    required this.initialSelection,
    required this.isServiceDay,
    required this.monthsAhead,
    this.scheduledOn,
  });

  final Set<DateTime> initialSelection;
  final bool Function(DateTime day)? isServiceDay;
  final String? Function(DateTime day)? scheduledOn;
  final int monthsAhead;

  @override
  State<_MultiDatePickerSheet> createState() => _MultiDatePickerSheetState();
}

class _MultiDatePickerSheetState extends State<_MultiDatePickerSheet> {
  late final Set<DateTime> _selected = {...widget.initialSelection};
  late final DateTime _today = _dayOnly(DateTime.now());
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _hasNewDays =>
      _selected.any((day) => !widget.initialSelection.contains(day));

  /// Os dias novos em que a pessoa já está na escala, já descritos.
  List<String> get _newScheduledDays {
    final describe = widget.scheduledOn;
    if (describe == null) return const [];
    final novos = _selected
        .where((day) => !widget.initialSelection.contains(day))
        .toList()
      ..sort();
    return [
      for (final day in novos)
        if (describe(day) case final phrase?) phrase,
    ];
  }

  void _toggle(DateTime day) {
    setState(() {
      if (!_selected.remove(day)) {
        _selected.add(day);
      }
    });
  }

  void _confirm() {
    final reason = _reason.text.trim();
    final MultiDatePick pick = (
      dates: _selected,
      reason: _hasNewDays && reason.isNotEmpty ? reason : null,
    );
    Navigator.of(context).pop(pick);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        child: SizedBox(
          height: (media.size.height - media.viewInsets.bottom) * 0.85,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dias em que não posso',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Toque nos dias. Podem ser vários, sem precisar '
                            'ser seguidos.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (widget.isServiceDay != null) ...[
                          const SizedBox(width: AppSpacing.md),
                          const AppDayLegendChip(),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'Dia de culto',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const _WeekdayHeader(),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  itemCount: widget.monthsAhead + 1,
                  itemBuilder: (context, index) {
                    final month = DateTime(_today.year, _today.month + index);
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.sm,
                              AppSpacing.lg,
                              AppSpacing.sm,
                              AppSpacing.sm,
                            ),
                            child: Text(
                              monthYearLabel(month),
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          AppMonthGrid(
                            month: month,
                            today: _today,
                            showWeekdays: false,
                            keyPrefix: 'indisponivel-',
                            onTap: _toggle,
                            describe: (day) {
                              final service =
                                  widget.isServiceDay?.call(day) ?? false;
                              final marcado = _selected.contains(day);
                              return AppMonthDay(
                                selected: marcado,
                                icon: marcado ? Icons.close_rounded : null,
                                marks: service ? 1 : 0,
                                // Dia passado não é marcável: o backend recusa
                                // e não haveria o que avisar sobre uma escala
                                // que já aconteceu.
                                enabled: !day.isBefore(_today),
                                detail: [
                                  if (marcado) 'marcado como "não posso"',
                                  if (service) 'dia de culto',
                                ].join(', ').ifEmptyNull,
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              if (_newScheduledDays.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    0,
                  ),
                  child: AppNotice(
                    tone: AppTone.warning,
                    liveRegion: true,
                    message: _newScheduledDays.length == 1
                        ? 'Você já está na escala de '
                            '${_newScheduledDays.single}. Quem lidera vai ser '
                            'avisado para achar alguém no seu lugar.'
                        : 'Você já está na escala de '
                            '${_newScheduledDays.join(' e de ')}. Quem lidera '
                            'vai ser avisado para achar alguém no seu lugar.',
                  ),
                ),
              if (_hasNewDays)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    0,
                  ),
                  child: UnavailabilityReasonField(controller: _reason),
                ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selected.isEmpty
                            ? 'Nenhum dia marcado'
                            : '${_selected.length} '
                                '${_selected.length == 1 ? 'dia marcado' : 'dias marcados'}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    FilledButton(
                      onPressed: _confirm,
                      child: Text(
                        multiDatePickerActionLabel(
                          added: _selected
                              .difference(widget.initialSelection)
                              .length,
                          removed: widget.initialSelection
                              .difference(_selected)
                              .length,
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

/// O motivo, opcional: chips para os que se repetem e o campo para o resto.
///
/// Exposto porque a correção do motivo de um dia já marcado usa a mesma peça.
class UnavailabilityReasonField extends StatelessWidget {
  const UnavailabilityReasonField({
    super.key,
    required this.controller,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final reason in unavailabilityReasons)
                ChoiceChip(
                  label: Text(reason),
                  selected: controller.text.trim() == reason,
                  // Tocar no escolhido limpa: é como se volta atrás sem um
                  // chip "nenhum".
                  onSelected: (on) => controller.text = on ? reason : '',
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: controller,
            autofocus: autofocus,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Motivo (opcional)',
              hintText: 'Viagem, trabalho...',
              // Dito onde se escreve: o motivo pode ser "cirurgia", e quem
              // escreve precisa saber que o resto da equipe não lê.
              helperText: 'Só quem lidera a equipe vê o motivo.',
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Semana começando no domingo, como no calendário brasileiro.
    const labels = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          for (final label in labels)
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
