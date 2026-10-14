import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/platform/web_bridge.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_options_sheet.dart';
import '../../../shared/widgets/open_link.dart';
import '../domain/event_models.dart';
import '../domain/schedule_calendar.dart';

/// "Adicionar ao calendário": a escala na agenda do celular, para o próprio
/// calendário lembrar do culto e do ensaio -- inclusive onde o Pauta não
/// consegue avisar (o iPhone pelo navegador).
///
/// Duas portas, porque nenhuma serve a todo mundo: o Google Agenda abre pelo
/// endereço e já vem preenchido; o arquivo .ics é o que a agenda do iPhone, o
/// Outlook e a maioria dos calendários do Android importam.
Future<void> addScheduleToCalendar(BuildContext context, Event event) async {
  final escolha = await showAppOptionsSheet<String>(
    context: context,
    title: 'Adicionar ao calendário',
    subtitle: event.rehearsalAt == null
        ? 'Os horários desta escala entram na sua agenda.'
        : 'Os horários desta escala e o ensaio entram na sua agenda.',
    selected: '',
    options: const [
      AppOption(
        value: 'google',
        label: 'Google Agenda',
        subtitle: 'Abre o Google Agenda já preenchido',
        icon: Icons.event_rounded,
      ),
      AppOption(
        value: 'arquivo',
        label: 'Outro calendário',
        subtitle: 'iPhone, Outlook e outros: um arquivo para abrir na agenda',
        icon: Icons.file_download_outlined,
      ),
    ],
  );
  if (escolha == null || !context.mounted) return;

  switch (escolha.value) {
    case 'google':
      await openExternalLink(context, googleCalendarUrl(event));
    case 'arquivo':
      await _shareIcs(context, event);
  }
}

Future<void> _shareIcs(BuildContext context, Event event) async {
  final nome = scheduleIcsFileName(event);
  final conteudo = buildScheduleIcs(event);
  // No navegador, baixar; o Safari do iPhone abre o arquivo direto na agenda.
  if (WebBridge.download(nome, 'text/calendar', conteudo)) return;
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            utf8.encode(conteudo),
            mimeType: 'text/calendar',
            name: nome,
          ),
        ],
        fileNameOverrides: [nome],
      ),
    );
  } catch (_) {
    if (context.mounted) {
      showAppSnackBar(
        context,
        'Não foi possível abrir o arquivo por aqui. Tente o Google Agenda.',
        tone: AppTone.danger,
      );
    }
  }
}
