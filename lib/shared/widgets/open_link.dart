import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_status_colors.dart';
import 'app_feedback.dart';

/// Abre um endereço fora do app (navegador ou o app do serviço). Falhou, avisa
/// em vez de não fazer nada: um toque sem resposta parece botão quebrado.
Future<void> openExternalLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url.trim());
  final ok =
      uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    showAppSnackBar(
      context,
      'Não foi possível abrir o link.',
      tone: AppTone.danger,
    );
  }
}
