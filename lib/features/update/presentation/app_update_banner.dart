import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_notice.dart';
import '../data/version_repository.dart';

/// Aviso de versão nova, no topo da Home e da Agenda.
///
/// É um [AppNotice] como os outros avisos do app. [margin] é de quem chama: a
/// Home o põe fora da lista (com a margem da página), a Agenda dentro dela
/// (que já tem a margem) — com a margem fixa de antes, na Agenda ele ficava
/// 40px recuado em relação ao calendário.
class AppUpdateBanner extends ConsumerWidget {
  const AppUpdateBanner({
    super.key,
    this.margin = const EdgeInsets.only(bottom: AppSpacing.md),
  });

  final EdgeInsetsGeometry margin;

  Future<void> _download(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    final opened = uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      showAppSnackBar(
        context,
        'Não foi possível abrir o download do APK.',
        tone: AppTone.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (AppConfig.isPlayStore) return const SizedBox.shrink();
    final update = ref.watch(appUpdateProvider).valueOrNull;
    if (update == null || !update.updateAvailable) {
      return const SizedBox.shrink();
    }

    final url = update.apkUrl;

    return AppNotice(
      margin: margin,
      tone: AppTone.primary,
      icon: Icons.system_update_rounded,
      message: url == null
          ? 'Versão ${update.latestVersion} disponível. Peça o APK atualizado '
              'ao líder.'
          : 'Versão ${update.latestVersion} disponível.',
      action: url == null
          ? null
          : TextButton(
              onPressed: () => _download(context, url),
              child: const Text('Atualizar'),
            ),
    );
  }
}
