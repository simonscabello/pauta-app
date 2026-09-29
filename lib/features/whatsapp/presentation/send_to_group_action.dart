import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../events/domain/event_models.dart';
import '../../events/domain/schedule_share_text.dart';
import '../data/whatsapp_repository.dart';
import '../domain/team_whatsapp.dart';

/// "Enviar para o grupo": a escala publicada vai para o grupo do WhatsApp da
/// equipe pelo número do Pauta.
///
/// **O texto é o mesmo do botão de compartilhar** (`buildScheduleShareText`):
/// o grupo recebe exatamente o que quem lidera colaria à mão. Pergunta antes
/// porque a mensagem chega na hora para a equipe inteira, e não tem volta.
Future<void> sendScheduleToGroup(
  BuildContext context,
  WidgetRef ref,
  Event event,
  WhatsAppGroup group,
) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Enviar para o grupo?',
    message: 'A escala vai agora para "${group.label}", pelo número do '
        'Pauta, com o mesmo texto do compartilhar.',
    confirmLabel: 'Enviar para o grupo',
  );
  if (!confirmed || !context.mounted) return;

  try {
    final name = await ref
        .read(whatsAppRepositoryProvider)
        .sendSchedule(event.id, buildScheduleShareText(event));
    if (context.mounted) {
      showAppSnackBar(
        context,
        'Escala enviada para ${name ?? group.label}.',
        tone: AppTone.success,
      );
    }
  } on ApiException catch (e) {
    if (context.mounted) {
      showAppSnackBar(context, e.message, tone: AppTone.danger);
    }
  }
}
