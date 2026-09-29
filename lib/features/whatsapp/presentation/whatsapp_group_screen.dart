import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_notice.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/section_header.dart';
import '../data/whatsapp_repository.dart';
import '../domain/team_whatsapp.dart';

/// Gerenciar equipe › Grupo do WhatsApp: vincular o grupo do louvor para que
/// quem lidera mande a escala por ali, pelo número do Pauta.
///
/// **O grupo se prova pelo código.** Quem lidera adiciona o número do Pauta ao
/// grupo e cola o código; o servidor reconhece a mensagem e responde no grupo.
/// Não há lista de grupos para escolher: ela mostraria os grupos das outras
/// igrejas, e não provaria que quem escolheu está no grupo.
class WhatsAppGroupScreen extends ConsumerStatefulWidget {
  const WhatsAppGroupScreen({super.key, required this.teamId});

  final String teamId;

  @override
  ConsumerState<WhatsAppGroupScreen> createState() =>
      _WhatsAppGroupScreenState();
}

class _WhatsAppGroupScreenState extends ConsumerState<WhatsAppGroupScreen> {
  /// Com um código pendente, a tela pergunta de tempos em tempos se o grupo
  /// já apareceu: quem colou o código volta para cá e vê o grupo sem puxar a
  /// tela.
  Timer? _poll;
  bool _working = false;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _syncPolling(TeamWhatsApp? state) {
    final waiting = state?.linkCode != null;
    if (waiting && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 4), (_) {
        ref.invalidate(teamWhatsAppProvider(widget.teamId));
      });
    } else if (!waiting && _poll != null) {
      _poll!.cancel();
      _poll = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = teamWhatsAppProvider(widget.teamId);
    ref.listen(provider, (previous, next) {
      final before = previous?.valueOrNull;
      final after = next.valueOrNull;
      _syncPolling(after);
      // O código pendente sumiu e há grupo: foi colado e reconhecido (vale
      // para o primeiro vínculo e para "Trocar de grupo").
      final linkedNow = before?.linkCode != null &&
          after?.linkCode == null &&
          after?.group != null;
      if (linkedNow) {
        showAppSnackBar(
          context,
          'Grupo vinculado: ${after!.group!.label}.',
          tone: AppTone.success,
        );
      }
    });
    final state = ref.watch(provider);

    return Scaffold(
      appBar: AppBar(title: const Text('Grupo do WhatsApp')),
      body: SafeArea(
        top: false,
        child: AppContentWidth.reading(
          child: state.when(
            loading: () => const AppListSkeleton(itemCount: 3),
            error: (error, _) => AppErrorState(
              message: error is ApiException
                  ? error.message
                  : 'Não foi possível carregar o grupo do WhatsApp.',
              onRetry: () => ref.invalidate(provider),
            ),
            data: (whatsApp) {
              // O primeiro carregamento também decide se a tela vigia o grupo.
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _syncPolling(whatsApp));
              if (!whatsApp.available) {
                return const AppEmptyState(
                  icon: Icons.chat_outlined,
                  title: 'Envio pelo WhatsApp desligado',
                  message: 'Este servidor não está mandando escalas pelo '
                      'WhatsApp. O botão de compartilhar continua funcionando.',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(provider),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.lg,
                    AppSpacing.screenPadding,
                    AppSpacing.xxl,
                  ),
                  children: [
                    if (!whatsApp.connected) ...[
                      const AppNotice(
                        tone: AppTone.warning,
                        icon: Icons.link_off_rounded,
                        title: 'Número do Pauta desconectado',
                        message: 'Enquanto ele estiver fora, o grupo não se '
                            'vincula e a escala não sai. O botão de '
                            'compartilhar continua funcionando.',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    if (whatsApp.group != null)
                      _LinkedGroup(
                        group: whatsApp.group!,
                        busy: _working,
                        onReplace: whatsApp.linkCode == null
                            ? () => _generateCode()
                            : null,
                        onUnlink: _unlink,
                      )
                    else
                      const SectionHeader(
                        title: 'Mandar a escala para o grupo',
                        subtitle: 'Vincule o grupo do louvor uma vez. Depois, '
                            'a escala publicada vai para lá com um toque, '
                            'pelo número do Pauta.',
                      ),
                    if (whatsApp.group == null ||
                        whatsApp.linkCode != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _LinkSteps(
                        whatsApp: whatsApp,
                        busy: _working,
                        onGenerate: _generateCode,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _generateCode() async {
    setState(() => _working = true);
    try {
      await ref.read(whatsAppRepositoryProvider).createLinkCode(widget.teamId);
      ref.invalidate(teamWhatsAppProvider(widget.teamId));
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message, tone: AppTone.danger);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _unlink() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Desvincular o grupo?',
      message: 'A escala deixa de ir para este grupo pelo Pauta. O número do '
          'Pauta continua no grupo até alguém removê-lo pelo WhatsApp.',
      confirmLabel: 'Desvincular',
      cancelLabel: 'Manter',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _working = true);
    try {
      await ref.read(whatsAppRepositoryProvider).unlink(widget.teamId);
      ref.invalidate(teamWhatsAppProvider(widget.teamId));
      if (mounted) {
        showAppSnackBar(context, 'Grupo desvinculado.', tone: AppTone.success);
      }
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message, tone: AppTone.danger);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

class _LinkedGroup extends StatelessWidget {
  const _LinkedGroup({
    required this.group,
    required this.busy,
    required this.onReplace,
    required this.onUnlink,
  });

  final WhatsAppGroup group;
  final bool busy;
  final VoidCallback? onReplace;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final since = DateFormat("d 'de' MMMM", 'pt_BR').format(group.linkedAt);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.groups_rounded, color: scheme.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  group.name ?? 'Grupo vinculado',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Vinculado em $since. Na tela de uma escala publicada, '
            '"Enviar para o grupo" manda a escala para cá.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: AppSpacing.sm,
              children: [
                if (onReplace != null)
                  TextButton(
                    onPressed: busy ? null : onReplace,
                    child: const Text('Trocar de grupo'),
                  ),
                TextButton(
                  onPressed: busy ? null : onUnlink,
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  child: const Text('Desvincular'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Os dois passos: pôr o número do Pauta no grupo e colar o código lá.
class _LinkSteps extends StatelessWidget {
  const _LinkSteps({
    required this.whatsApp,
    required this.busy,
    required this.onGenerate,
  });

  final TeamWhatsApp whatsApp;
  final bool busy;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final phone = whatsApp.phoneNumber;
    final code = whatsApp.linkCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Step(
          number: 1,
          title: 'Adicione o número do Pauta ao grupo',
          message: phone == null
              ? 'O número aparece aqui quando ele estiver conectado.'
              : 'Salve ${formatWhatsAppNumber(phone)} nos contatos e '
                  'adicione ao grupo do louvor, como qualquer pessoa.',
          action: phone == null
              ? null
              : TextButton.icon(
                  onPressed: () => _copy(
                    context,
                    '+$phone',
                    'Número copiado.',
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copiar número'),
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Step(
          number: 2,
          title: 'Cole o código no grupo',
          message: code == null
              ? 'O código vale por 30 minutos. O Pauta responde no grupo '
                  'quando reconhecer.'
              : 'Mande este código no grupo. O Pauta responde lá, e esta '
                  'tela se atualiza sozinha. Vale até '
                  '${DateFormat.Hm('pt_BR').format(code.expiresAt)}.',
        ),
        const SizedBox(height: AppSpacing.md),
        if (code != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: SelectionArea(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  code.code,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: () => _copy(
              context,
              code.code,
              'Código copiado. É só colar no grupo.',
            ),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copiar código'),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: busy ? null : onGenerate,
            child: const Text('Gerar outro código'),
          ),
        ] else
          FilledButton(
            onPressed: busy || !whatsApp.connected ? null : onGenerate,
            child: const Text('Gerar código'),
          ),
      ],
    );
  }

  Future<void> _copy(BuildContext context, String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      showAppSnackBar(context, done, tone: AppTone.success);
    }
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.message,
    this.action,
  });

  final int number;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: scheme.primaryContainer,
          child: Text(
            '$number',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: scheme.onPrimaryContainer),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (action != null) action!,
            ],
          ),
        ),
      ],
    );
  }
}
