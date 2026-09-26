import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_button_styles.dart';
import '../../../shared/widgets/app_choice_bar.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/form_scaffold.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/unsaved_changes_guard.dart';
import '../data/mcp_token_repository.dart';
import '../domain/mcp_token.dart';
import 'ai_assistants_screen.dart';
import 'mcp_connection_widgets.dart';

/// Onde a pessoa vai colar a chave: o comando do Claude Code, ou endereço e
/// cabeçalho para o resto.
enum _Client { claudeCode, otherApps }

/// Criar uma chave (`/perfil/assistentes/nova`) e, na mesma tela, mostrá-la.
///
/// **A chave inteira só existe no estado desta tela.** A API a devolve uma vez,
/// na resposta da criação; ela não vai para provider, cache, armazenamento nem
/// log, e some quando a tela sai da pilha. Por isso o resultado não é outra
/// rota: um endereço que mostrasse a chave precisaria guardá-la em algum lugar
/// para sobreviver à navegação.
///
/// Sair sem ter copiado pergunta antes — pelos três caminhos do
/// [UnsavedChangesGuard]: voltar, navegar por fora (o `onExit` da rota) e
/// recarregar ou fechar a aba na Web.
class NewAiKeyScreen extends ConsumerStatefulWidget {
  const NewAiKeyScreen({
    super.key,
    this.suggestComputer = newMcpTokenSuggestsComputer,
  });

  /// "Melhor fazer no computador" no topo do formulário: fora da Web, por
  /// padrão ([newMcpTokenSuggestsComputer]).
  final bool suggestComputer;

  @override
  ConsumerState<NewAiKeyScreen> createState() => _NewAiKeyScreenState();
}

class _NewAiKeyScreenState extends ConsumerState<NewAiKeyScreen> {
  static const _nameMaxLength = 60;

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _password = TextEditingController();

  int _days = defaultMcpTokenValidityDays;
  bool _obscure = true;
  bool _submitting = false;
  String? _passwordError;
  String? _error;

  /// A chave criada, com o valor inteiro. Só aqui.
  CreatedMcpToken? _created;

  /// Copiou a chave, o comando ou o cabeçalho — qualquer coisa que a leve
  /// inteira. O endereço sozinho não conta.
  bool _copied = false;

  /// "Concluir" ou a saída já confirmada: não perguntar de novo no caminho.
  bool _leaving = false;

  _Client _client = _Client.claudeCode;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Função, e não campo: o guarda a consulta na hora da saída (ver
  /// [UnsavedChangesGuard.isDirty]).
  bool _secretAtRisk() => _created != null && !_copied && !_leaving;

  Future<bool> _confirmLeaveWithoutCopying(BuildContext context) {
    return showDiscardChangesDialog(
      context,
      title: 'Sair sem copiar a chave?',
      message: 'Ela não aparece de novo. Se sair sem copiar, você vai precisar '
          'revogar esta chave e criar outra.',
      // "Assim mesmo", e não "sem copiar": quem selecionou e copiou à mão
      // também passa por aqui, e a tela não tem como saber.
      leaveLabel: 'Sair assim mesmo',
      stayLabel: 'Ficar e copiar',
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _passwordError = null;
      _error = null;
    });

    // Lido antes do `await`: quem sai no meio do pedido desmonta a tela, e a
    // lista ainda precisa saber da chave nova para oferecer revogá-la.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final created = await container.read(mcpTokenRepositoryProvider).create(
            name: _name.text.trim(),
            password: _password.text,
            expiresInDays: _days,
          );
      // A lista embaixo desta tela já volta mostrando a chave nova.
      container.invalidate(mcpTokensProvider);
      if (!mounted) return;
      _password.clear();
      setState(() {
        _created = created;
        _submitting = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        if (error.code == 'INVALID_PASSWORD') {
          _passwordError = error.message;
        } else {
          _error = _messageFor(error);
        }
      });
    }
  }

  /// O 429 vem da biblioteca de limite, em inglês ("ThrottlerException: Too
  /// Many Requests"): são cinco tentativas por minuto nesta rota, porque ela
  /// confere a senha.
  static String _messageFor(ApiException error) => error.statusCode == 429
      ? 'Muitas tentativas seguidas. Espere um minuto e tente de novo.'
      : error.message;

  /// Copiar qualquer coisa que leve a chave inteira libera a saída sem
  /// pergunta.
  Future<void> _copySecret(String text, String message) async {
    final copied = await copyWithFeedback(context, text, message: message);
    if (copied && mounted && !_copied) setState(() => _copied = true);
  }

  Future<void> _finish() async {
    if (_secretAtRisk()) {
      final leave = await _confirmLeaveWithoutCopying(context);
      if (!leave || !mounted) return;
    }
    // Antes de navegar: o `onExit` da rota consulta o guarda na saída.
    _leaving = true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AiAssistantsScreen.route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final created = _created;
    return UnsavedChangesGuard(
      isDirty: _secretAtRisk,
      confirmLeave: _confirmLeaveWithoutCopying,
      child: created == null ? _form(context) : _result(context, created),
    );
  }

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final now = ref.watch(aiAssistantsClockProvider)();

    return FormScaffold(
      appBar: AppBar(title: const Text('Nova chave')),
      children: [
        if (widget.suggestComputer) ...[
          const AppNotice(
            tone: AppTone.info,
            icon: Icons.computer_rounded,
            title: 'Melhor fazer no computador',
            message: 'A chave aparece uma vez só, e é no computador que você '
                'vai colá-la. Abra o Pauta no navegador de lá, com esta '
                'mesma conta.',
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                enabled: !_submitting,
                maxLength: _nameMaxLength,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nome da chave',
                  hintText: 'Ex.: Claude no notebook',
                  helperText: 'Para reconhecer depois, na lista de chaves.',
                  counterText: '',
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Dê um nome para a chave.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.xl),
              Semantics(
                header: true,
                child: Text('Validade', style: theme.textTheme.titleSmall),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppChoiceBar<int>(
                expanded: true,
                value: _days,
                onChanged: (days) {
                  if (!_submitting) setState(() => _days = days);
                },
                options: [
                  for (final days in mcpTokenValidityOptions)
                    AppChoice(value: days, label: mcpValidityOptionLabel(days)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // Alinhada com o texto de apoio dos campos (que o Material
              // recua 4px além da folga do campo), e anunciada ao trocar de
              // prazo: é a resposta da barra logo acima.
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.lg + AppSpacing.xs,
                  right: AppSpacing.lg,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    mcpNewTokenUntilLabel(_days, now),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              TextFormField(
                controller: _password,
                enabled: !_submitting,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Sua senha',
                  helperText: 'Para confirmar que é você',
                  errorText: _passwordError,
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Mostrar senha' : 'Esconder senha',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Informe sua senha.'
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        if (_error != null) FormErrorBanner(message: _error!),
        AppSubmitButton(
          label: 'Criar chave',
          loadingLabel: 'Criando a chave',
          loading: _submitting,
          onPressed: _submit,
        ),
      ],
    );
  }

  Widget _result(BuildContext context, CreatedMcpToken created) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final secret = created.secret;
    const url = AppConfig.mcpUrl;
    final command = claudeCodeMcpCommand(url: url, secret: secret);

    return FormScaffold(
      appBar: AppBar(title: const Text('Chave criada')),
      children: [
        const AppNotice(
          tone: AppTone.warning,
          icon: Icons.warning_amber_rounded,
          title: 'Copie agora: ela só aparece esta vez',
          message: 'Depois que você sair desta tela, nem o Pauta consegue '
              'mostrá-la de novo. Se perder, é só revogar e criar outra.',
        ),
        const SizedBox(height: AppSpacing.xl),
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs),
          child: Text(
            'Chave “${created.token.name}”',
            style: theme.textTheme.labelLarge?.copyWith(color: muted),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        McpCodeBlock(
          text: secret,
          emphasis: true,
          semanticsLabel: 'Chave de acesso',
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: () => _copySecret(secret, 'Chave copiada.'),
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copiar chave'),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const SectionHeader(
          title: 'Conectar no computador',
          subtitle: 'Onde você vai usar esta chave?',
        ),
        AppChoiceBar<_Client>(
          expanded: true,
          value: _client,
          onChanged: (client) => setState(() => _client = client),
          options: const [
            AppChoice(value: _Client.claudeCode, label: 'Claude Code'),
            AppChoice(value: _Client.otherApps, label: 'Outros apps'),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_client == _Client.claudeCode) ...[
          Text(
            'Cole este comando no terminal:',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          McpCodeBlock(
            text: command,
            semanticsLabel: 'Comando do Claude Code',
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: AppButtonStyles.compactText,
              onPressed: () => _copySecret(
                command,
                'Comando copiado. É só colar no terminal.',
              ),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copiar comando'),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Depois, abra o Claude Code e pergunte: “Quais são as minhas '
            'próximas escalas?”',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ] else ...[
          Text(
            'No Cursor, no VS Code e em outros apps com MCP, adicione um '
            'servidor do tipo HTTP com estes dois valores:',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          AppGroup(
            dividerIndent: AppGroup.textIndent,
            children: [
              McpCopyRow(
                label: 'Endereço',
                value: url,
                copyTooltip: 'Copiar o endereço',
                onCopy: () => copyWithFeedback(
                  context,
                  url,
                  message: 'Endereço copiado.',
                ),
              ),
              McpCopyRow(
                label: 'Cabeçalho',
                // Encurtado na tela; o "Copiar" leva a chave inteira.
                value: mcpAuthorizationHeaderPreview(secret),
                copyTooltip: 'Copiar o cabeçalho, com a chave inteira',
                onCopy: () => _copySecret(
                  mcpAuthorizationHeader(secret),
                  'Cabeçalho copiado.',
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text(
          'O Claude no navegador e no celular e o ChatGPT ainda não aceitam '
          'chave.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: AppSpacing.xl),
        OutlinedButton(onPressed: _finish, child: const Text('Concluir')),
      ],
    );
  }
}
