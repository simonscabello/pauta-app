import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../shared/widgets/app_notice.dart';
import '../storage/shared_preferences_provider.dart';
import '../theme/app_status_colors.dart';
import 'push_coordinator.dart';
import 'push_service.dart';

/// Guardado no aparelho: quem dispensou o convite não o vê de novo neste
/// navegador. Conveniência de quem olha, e não estado da conta.
const _dismissedKey = 'web_push_prompt_dismissed';

/// O convite para receber avisos **neste navegador**, na Home.
///
/// No Android o sistema pergunta sozinho depois de a Home ter conteúdo. No
/// navegador não dá: o Safari só aceita o pedido de permissão que nasce de um
/// toque, e um pedido que surge sem contexto no Chrome costuma ser bloqueado.
/// Por isso aqui é um cartão com um botão, e o pedido sai do toque.
///
/// Aparece só quando há o que fazer: navegador que sabe receber aviso, ainda
/// sem resposta à permissão, e conta com avisos ligados -- ou iPhone fora da
/// tela de início, em que o cartão explica como instalar. Some quando a
/// pessoa responde ou dispensa.
class WebPushPrompt extends ConsumerStatefulWidget {
  const WebPushPrompt({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  ConsumerState<WebPushPrompt> createState() => _WebPushPromptState();
}

class _WebPushPromptState extends ConsumerState<WebPushPrompt> {
  bool _hidden = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    // A chave chega do servidor na entrada da conta, pelo coordenador; quem
    // abre a Home antes disso (ou depois de um F5) busca aqui, para o cartão
    // não ficar escondido por uma corrida.
    final push = ref.read(pushServiceProvider);
    if (PushService.isBrowser && PushService.isSupported && !push.hasWebPushKey) {
      unawaited(_loadKey(push));
    }
  }

  Future<void> _loadKey(PushService push) async {
    try {
      push.setWebPushKey(await ref.read(authRepositoryProvider).webPushKey());
      if (mounted) setState(() {});
    } catch (_) {
      // Sem a chave o cartão não aparece -- é o mesmo que o servidor sem aviso.
    }
  }

  bool get _dismissed {
    try {
      return ref.read(sharedPreferencesProvider).getBool(_dismissedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  void _dismiss() {
    setState(() => _hidden = true);
    try {
      unawaited(ref.read(sharedPreferencesProvider).setBool(_dismissedKey, true));
    } catch (_) {
      // Sem onde guardar, o cartão volta na próxima abertura. Aceitável.
    }
  }

  Future<void> _enable() async {
    setState(() => _working = true);
    final push = ref.read(pushServiceProvider);
    final permitido = await push.requestPermission();
    if (permitido) await ref.read(pushCoordinatorProvider).registerDevice();
    if (!mounted) return;
    setState(() {
      _working = false;
      _hidden = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden || _dismissed || !PushService.isBrowser) {
      return const SizedBox.shrink();
    }
    final contaAceita =
        ref.watch(authControllerProvider).user?.pushEnabled ?? true;
    if (!contaAceita) return const SizedBox.shrink();

    final dispensar = TextButton(onPressed: _dismiss, child: const Text('Agora não'));

    if (PushService.needsInstallForPush) {
      return AppNotice(
        margin: widget.margin,
        tone: AppTone.info,
        icon: Icons.notifications_none_rounded,
        title: 'Receba os avisos no iPhone',
        message: 'Toque em Compartilhar e em "Adicionar à Tela de Início". '
            'Abrindo o Pauta por lá, ele avisa da escala e do ensaio.',
        action: dispensar,
      );
    }

    final push = ref.read(pushServiceProvider);
    if (!PushService.isSupported ||
        !push.hasWebPushKey ||
        push.isBlockedByBrowser ||
        PushService.browserPermission != 'default') {
      return const SizedBox.shrink();
    }

    return AppNotice(
      margin: widget.margin,
      tone: AppTone.primary,
      icon: Icons.notifications_active_outlined,
      title: 'Receber avisos neste navegador?',
      message: 'A escala publicada, as trocas e os lembretes do ensaio '
          'chegam aqui, mesmo com a aba fechada.',
      action: Wrap(
        spacing: 8,
        children: [
          FilledButton(
            onPressed: _working ? null : _enable,
            child: const Text('Ativar avisos'),
          ),
          dispensar,
        ],
      ),
    );
  }
}
