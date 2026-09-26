import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../data/mcp_token_repository.dart';
import '../domain/mcp_token.dart';
import 'mcp_connection_widgets.dart';

/// Perfil › Segurança › Assistentes de IA (`/perfil/assistentes`).
///
/// As chaves com que Claude Code, Cursor e VS Code consultam o Pauta pelo
/// `/mcp`, **só para leitura**. A chave é da pessoa, não da equipe: qualquer
/// um com conta cria a sua, e o que ela lê segue o papel de quem a criou.
///
/// Sem chave, a tela explica antes de oferecer: o que o assistente pode e o
/// que não pode fazer. Com chave, vira a lista — com o que ajuda a reconhecer
/// cada uma (nome, final, último uso) e o prazo, que avisa em âmbar na última
/// semana.
class AiAssistantsScreen extends ConsumerWidget {
  const AiAssistantsScreen({super.key});

  static const route = '/perfil/assistentes';
  static const newKeyRoute = '$route/nova';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(mcpTokensProvider);
    final now = ref.watch(aiAssistantsClockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('Assistentes de IA')),
      // Sem a barra inferior nesta rota, ninguém consome o recuo dos botões de
      // navegação do Android.
      body: SafeArea(
        top: false,
        child: AppContentWidth.reading(
          child: tokens.when(
            loading: () => const AppListSkeleton(itemCount: 3),
            error: (error, _) => AppErrorState(
              message: error is ApiException
                  ? error.message
                  : 'Não foi possível carregar as suas chaves.',
              onRetry: () => ref.invalidate(mcpTokensProvider),
            ),
            data: (list) => RefreshIndicator(
              // Espera a lista nova, e a falha aparece no lugar da lista, com
              // "Tentar de novo" — e não como erro solto do gesto.
              onRefresh: () => ref
                  .refresh(mcpTokensProvider.future)
                  .then<void>((_) {}, onError: (Object _) {}),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.xl,
                  AppSpacing.screenPadding,
                  AppSpacing.xxl,
                ),
                children: list.isEmpty
                    ? _firstVisit(context)
                    : _keys(context, list, now),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Sem nenhuma chave: o que é, o que pode e o que não pode, e só então o
  /// botão.
  List<Widget> _firstVisit(BuildContext context) {
    final theme = Theme.of(context);

    return [
      Text(
        'Com uma chave, um assistente de IA como o Claude consulta o Pauta '
        'por você: suas escalas, o repertório e a agenda da equipe.',
        style: theme.textTheme.bodyLarge,
      ),
      const SizedBox(height: AppSpacing.xl),
      const _WhatItCanDo(),
      const SizedBox(height: AppSpacing.lg),
      AppEmptyState(
        icon: Icons.key_rounded,
        title: 'Nenhuma chave ainda',
        message: 'Crie uma chave e cole no assistente do seu computador, como '
            'o Claude Code, o Cursor ou o VS Code.',
        actionLabel: 'Criar chave',
        onAction: () => context.push(newKeyRoute),
      ),
      Text(
        'O Claude no navegador e no celular e o ChatGPT ainda não aceitam '
        'chave. Por enquanto, só assistentes que rodam no computador.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  List<Widget> _keys(
    BuildContext context,
    List<McpToken> tokens,
    DateTime now,
  ) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final active = activeMcpTokenCount(tokens, now);
    final canCreate = active < maxActiveMcpTokens;

    return [
      Text(
        'Cada chave deixa um assistente de IA consultar o Pauta por você. Ele '
        'lê o que você vê no app e não muda nada.',
        style: theme.textTheme.bodyMedium?.copyWith(color: muted),
      ),
      const SizedBox(height: AppSpacing.xl),
      AppGroup(
        title: 'Suas chaves',
        // Com teto: em 320px e fonte grande, título e contagem não cabem numa
        // linha, e a contagem quebra em duas em vez de espremer o título.
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(
            mcpActiveCountLabel(active),
            textAlign: TextAlign.end,
            style: theme.textTheme.labelMedium?.copyWith(color: muted),
          ),
        ),
        children: [
          for (final token in sortMcpTokens(tokens, now))
            _KeyRow(key: ValueKey(token.id), token: token, now: now),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: canCreate ? () => context.push(newKeyRoute) : null,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Criar outra chave'),
        ),
      ),
      // O botão apagado diz por quê, em vez de deixar a pessoa adivinhar —
      // e de deixar tentar só para receber o 409 depois da senha.
      if (!canCreate)
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.md),
          child: Text(
            'Você chegou a $maxActiveMcpTokens chaves ativas. Revogue uma '
            'para criar outra.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      const SizedBox(height: AppSpacing.xl),
      AppGroup(
        title: 'Como conectar',
        children: [
          McpCopyRow(
            icon: Icons.dns_outlined,
            label: 'Endereço do servidor',
            value: AppConfig.mcpUrl,
            copyTooltip: 'Copiar o endereço do servidor',
            onCopy: () => copyWithFeedback(
              context,
              AppConfig.mcpUrl,
              message: 'Endereço copiado.',
            ),
          ),
          AppGroupRow(
            icon: Icons.help_outline_rounded,
            title: 'Passo a passo',
            subtitle: 'Claude Code, Cursor e VS Code, na Ajuda',
            onTap: () => context.push('/perfil/ajuda'),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      Padding(
        padding: const EdgeInsets.only(left: AppSpacing.xs),
        child: Text(
          'Trocar a senha revoga todas as chaves de uma vez.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ),
    ];
  }
}

/// O que a chave deixa e o que não deixa fazer, antes da primeira.
class _WhatItCanDo extends StatelessWidget {
  const _WhatItCanDo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'O que o assistente pode fazer',
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const _Capability(allowed: true, text: 'Ler o que você já vê no app'),
          const _Capability(
            allowed: true,
            text: 'Para quem lidera, ler também os relatórios de '
                'participação e de repertório',
          ),
          const _Capability(
            allowed: false,
            text: 'Criar, mudar ou apagar qualquer coisa',
          ),
          const _Capability(
            allowed: false,
            text: 'Ver e-mail, telefone ou ano de nascimento de alguém',
          ),
        ],
      ),
    );
  }
}

class _Capability extends StatelessWidget {
  const _Capability({required this.allowed, required this.text});

  final bool allowed;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final success = AppStatusColors.of(context).success;

    // O ícone diz "pode" e "não pode" para quem vê; o leitor de tela ouve a
    // palavra, que o traço e o xis sozinhos não dizem.
    return Semantics(
      container: true,
      label: '${allowed ? 'Pode' : 'Não pode'}: $text',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              allowed ? Icons.check_rounded : Icons.close_rounded,
              size: 20,
              color: allowed ? success.foreground : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

enum _KeyAction { revoke, remove }

/// Uma chave como linha: nome, final e último uso, prazo, e o ⋮.
///
/// Não é um `AppGroupRow` porque a segunda linha mistura texto corrido com o
/// final da chave em fonte monoespaçada, e o selo vem por baixo; as medidas são
/// as mesmas.
class _KeyRow extends StatefulWidget {
  const _KeyRow({super.key, required this.token, required this.now});

  final McpToken token;
  final DateTime now;

  @override
  State<_KeyRow> createState() => _KeyRowState();
}

class _KeyRowState extends State<_KeyRow> {
  bool _busy = false;

  McpToken get _token => widget.token;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final state = mcpTokenState(_token, widget.now);
    final expired = state == McpTokenState.expired;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.key_outlined,
              size: 22,
              // A vencida recua: continua na lista para ser reconhecida, mas
              // não disputa atenção com as que funcionam.
              color: expired ? muted.withValues(alpha: 0.6) : muted,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _token.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: expired ? muted : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Termina em '),
                      TextSpan(
                        text: _token.ending,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      TextSpan(text: ' · ${mcpUsageLabel(_token, widget.now)}'),
                    ],
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                ..._deadline(state),
              ],
            ),
          ),
          SizedBox(
            width: AppSpacing.touchTarget,
            height: AppSpacing.touchTarget,
            child: _busy
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : PopupMenuButton<_KeyAction>(
                    tooltip: 'Mais opções de ${_token.name}',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (action) {
                      if (action == _KeyAction.revoke) {
                        _revoke();
                      } else {
                        _remove();
                      }
                    },
                    itemBuilder: (_) => [
                      // A vencida não dá acesso a ninguém: não há o que
                      // revogar, só o que tirar da vista.
                      if (expired)
                        const PopupMenuItem(
                          value: _KeyAction.remove,
                          child: Text('Remover da lista'),
                        )
                      else
                        const PopupMenuItem(
                          value: _KeyAction.revoke,
                          child: Text('Revogar chave'),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _deadline(McpTokenState state) {
    final theme = Theme.of(context);

    switch (state) {
      case McpTokenState.active:
        return [
          Text(
            mcpValidUntilLabel(_token, widget.now),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ];
      case McpTokenState.expiring:
        final label = mcpExpiringLabel(mcpTokenDaysLeft(_token, widget.now));
        return [
          const SizedBox(height: 6),
          AppBadge(
            icon: Icons.schedule_rounded,
            label: label,
            tone: AppTone.warning,
            semanticsLabel: 'Atenção: ${label.toLowerCase()}',
          ),
        ];
      case McpTokenState.expired:
        return const [
          SizedBox(height: 6),
          AppBadge(label: 'Vencida'),
        ];
    }
  }

  /// Revogar pergunta antes: o assistente perde o acesso na hora, e não há
  /// como desfazer.
  Future<void> _revoke() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Revogar “${_token.name}”?',
      message: 'O assistente que usa esta chave perde o acesso na hora. Não '
          'dá para desfazer: se precisar de novo, crie outra chave.',
      confirmLabel: 'Revogar',
      cancelLabel: 'Voltar',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _delete(done: 'Chave revogada.');
  }

  /// A vencida sai sem pergunta: ela já não abre nada, e tirá-la da lista não
  /// perde coisa alguma.
  Future<void> _remove() => _delete(done: 'Chave removida da lista.');

  Future<void> _delete({required String done}) async {
    setState(() => _busy = true);
    // Lido antes do `await`: sair da tela no meio do pedido desmonta a linha.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await container.read(mcpTokenRepositoryProvider).revoke(_token.id);
      container.invalidate(mcpTokensProvider);
      if (mounted) showAppSnackBar(context, done, tone: AppTone.success);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppSnackBar(context, e.message, tone: AppTone.danger);
    }
  }
}
