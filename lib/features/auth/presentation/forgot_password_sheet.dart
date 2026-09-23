import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/responsive/adaptive_dialog.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/share_action.dart';

/// O recado pronto para pedir uma senha nova a quem lidera.
@visibleForTesting
String forgotPasswordMessage(String email) {
  final conta = email.trim().isEmpty ? '' : ' Meu e-mail no Pauta é $email.';
  return 'Oi! Esqueci minha senha do Pauta. Você consegue criar uma senha '
      'temporária para mim? É em Equipe, no meu nome, em "Redefinir '
      'senha".$conta';
}

/// "Esqueci minha senha", no login.
///
/// **Não há e-mail de recuperação no Pauta**: quem cria uma senha temporária é
/// quem lidera a equipe, pelo menu do integrante (`Redefinir senha`). O
/// caminho existia, mas o login não dizia nada sobre ele — oferecia só "Criar
/// agora" e "Problemas para conectar?", e quem tem pouca familiaridade
/// desistia ou criava uma segunda conta. A folha diz o caminho e já entrega o
/// recado escrito, para mandar pelo WhatsApp.
Future<void> showForgotPasswordSheet(
  BuildContext context, {
  String email = '',
}) {
  return showAdaptiveSheet<void>(
    context: context,
    maxWidth: 480,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final scheme = theme.colorScheme;
      final message = forgotPasswordMessage(email);

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Esqueci minha senha', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Quem lidera a sua equipe cria uma senha temporária para você '
                'em poucos segundos. Depois de entrar com ela, o Pauta pede '
                'para você escolher uma nova.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Mande este recado', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                surface: CardSurface.sunken,
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: SelectableText(
                  message,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: () => shareText(
                  sheetContext,
                  message,
                  copiedMessage: 'Recado copiado. É só colar no WhatsApp.',
                ),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Enviar o recado'),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: message));
                  if (sheetContext.mounted) {
                    showAppSnackBar(
                      sheetContext,
                      'Recado copiado.',
                      tone: AppTone.success,
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copiar o recado'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
