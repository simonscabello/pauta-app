import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/contact_actions.dart';
import '../data/team_repository.dart';
import '../domain/team_models.dart';

/// Redefinir a senha de um integrante — o "esqueci minha senha" deste app.
///
/// **Não existe recuperação por e-mail**, e enquanto não existir é assim que
/// alguém volta para dentro: fala com quem lidera, recebe uma senha temporária
/// e o app exige a troca no primeiro acesso.
///
/// **Até onde vai a derrubada de sessão.** O servidor revoga os refresh tokens
/// na hora, então nenhum aparelho renova a sessão e a senha antiga não entra
/// mais em lugar nenhum. O que *não* morre na hora é o access token que já
/// estava na mão: ele é um JWT verificado sem ir ao banco, e vale até expirar
/// (uma hora). Um app aberto continua respondendo nessa janela — o texto do
/// diálogo diz isso em vez de prometer o que não acontece.
///
/// Quem pode: `OWNER` e `LEADER`, com uma exceção que o servidor impõe — um
/// líder **não** redefine a senha do dono (403 `CANNOT_RESET_OWNER_PASSWORD`).
/// A rota devolve a senha a quem chamou, então poder chamá-la seria poder
/// entrar na conta do dono.
Future<void> resetMemberPassword(
  BuildContext context,
  WidgetRef ref, {
  required String teamId,
  required Member member,
}) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Redefinir a senha de ${member.displayName}?',
    // "Conectados à conta", sem afirmar que existe algum: quem lidera não
    // precisa saber se a pessoa usa assistente de IA.
    message: 'Vamos gerar uma senha temporária para você passar para '
        '${member.displayName}. A senha atual deixa de funcionar, os '
        'assistentes de IA conectados à conta perdem o acesso, e no próximo '
        'acesso o app pede uma nova.',
    confirmLabel: 'Redefinir',
  );
  if (!confirmed || !context.mounted) return;

  final String senha;
  try {
    senha = await ref
        .read(teamRepositoryProvider)
        .resetMemberPassword(teamId, member.id);
  } on ApiException catch (e) {
    if (context.mounted) {
      showAppSnackBar(context, e.message, tone: AppTone.danger);
    }
    return;
  }

  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    // Fechar tocando fora perderia a senha sem querer, e ela não aparece de
    // novo: só o botão fecha.
    barrierDismissible: false,
    builder: (dialogContext) => _TemporaryPasswordDialog(
      member: member,
      password: senha,
    ),
  );
}

class _TemporaryPasswordDialog extends StatelessWidget {
  const _TemporaryPasswordDialog({
    required this.member,
    required this.password,
  });

  final Member member;
  final String password;

  String get _message =>
      'Sua senha da Pauta foi redefinida.\n\nSenha temporária: $password\n\n'
      'Entre com ela e o app vai pedir para você escolher uma senha nova.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final phone = member.phoneDigits;

    return AlertDialog(
      title: const Text('Senha temporária'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Passe esta senha para ${member.displayName}. Ela só aparece '
            'agora: depois de fechar, não dá para ver de novo.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: SelectableText(
              password,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                // Monoespaçada: a senha tem base64url, onde l/1 e O/0 se
                // parecem. Quem for ditar por telefone precisa distingui-los.
                fontFamily: 'monospace',
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
      actionsOverflowButtonSpacing: AppSpacing.sm,
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: password));
            if (context.mounted) {
              showAppSnackBar(
                context,
                'Senha copiada.',
                tone: AppTone.success,
              );
            }
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copiar'),
        ),
        // Só quando há número: um botão de WhatsApp que abre uma conversa com
        // ninguém é pior que botão nenhum.
        if (phone != null)
          TextButton.icon(
            onPressed: () => openWhatsApp(context, phone, message: _message),
            icon: const Icon(Icons.chat_rounded, size: 18),
            label: const Text('WhatsApp'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
