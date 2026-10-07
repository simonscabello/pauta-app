import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../application/auth_controller.dart';
import '../domain/biometric_texts.dart';
import 'login_screen.dart';
import 'splash_frame.dart';

/// O fundo do pedido de biometria, com a sessão guardada e bloqueada.
///
/// **Existe porque a tela de login parecia defeito.** O pedido de digital
/// abria por cima do formulário de e-mail e senha, e quem tinha acabado de
/// abrir o app lia aquilo como "fui deslogado". Aqui o fundo é a própria
/// splash — mesma cor, mesma marca —, então abrir o app, confirmar a digital
/// e ver a Home parece uma sequência só.
///
/// O pedido sai sozinho ao abrir. Cancelado, a tela oferece as duas saídas:
/// tentar de novo ou entrar com a senha (que continua oferecendo a biometria,
/// enquanto a sessão estiver guardada).
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  /// Começa verdadeiro: até o pedido abrir, a tela é a splash — sem botão que
  /// apareça por um instante e suma debaixo do diálogo.
  bool _unlocking = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = ref.read(authControllerProvider.notifier);
      if (!await auth.biometricsAvailable) {
        // Digitais removidas depois de ligar a biometria: não há o que pedir.
        if (mounted) context.go('/login');
        return;
      }
      if (mounted) await _unlock();
    });
  }

  Future<void> _unlock() async {
    setState(() {
      _unlocking = true;
      _error = null;
    });
    // Lido antes do `await`: quando a sessão expira, o roteador desmonta esta
    // tela antes de o resultado voltar, e `ref` de widget desmontado lança.
    final notice = ref.read(loginNoticeProvider.notifier);
    final result =
        await ref.read(authControllerProvider.notifier).unlockWithBiometrics();
    if (result == BiometricUnlock.expired) {
      // A sessão já foi descartada e o roteador está levando para o login;
      // o motivo vai junto para não parecer que o app deslogou sozinho.
      notice.state = BiometricTexts.sessionExpired;
      return;
    }
    if (!mounted) return;
    setState(() {
      _unlocking = false;
      _error = switch (result) {
        BiometricUnlock.offline => BiometricTexts.unlockOffline,
        // O Android recusou por excesso de tentativas: sem a frase, tocar em
        // "Entrar com biometria" de novo parecia não fazer nada.
        BiometricUnlock.lockedOut => BiometricTexts.unlockLockedOut,
        _ => null,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    // O mesmo frame da splash: enquanto o pedido está aberto, a tela é
    // idêntica à abertura, e a marca não se move.
    return SplashFrame(
      subtitle: _unlocking
          ? SplashFrame.defaultSubtitle
          : BiometricTexts.unlockPrompt,
      below: _unlocking
          ? const SplashProgress()
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.brandDeepViolet,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _unlock,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text(BiometricTexts.unlockButton),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => context.go('/login'),
                  child: const Text(BiometricTexts.usePassword),
                ),
              ],
            ),
    );
  }
}
