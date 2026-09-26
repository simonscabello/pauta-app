import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/form_scaffold.dart';
import '../application/auth_controller.dart';

/// Troca de senha, nos dois caminhos que existem:
///
/// - `forced` (rota /trocar-senha): depois que o líder redefine a senha do
///   membro (regra 27). Enquanto a troca não acontece, o backend bloqueia as
///   demais rotas e o redirect do router prende o app aqui -- por isso não há
///   como voltar, só "Sair".
/// - voluntária (rota /perfil/senha): o próprio usuário decide trocar. Tem
///   AppBar, volta para o perfil e não oferece sair.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key, this.forced = true});

  final bool forced;

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );

      // No caminho obrigatorio quem tira o usuario daqui e o redirect do
      // router, assim que o estado deixa de ser mustChangePassword.
      if (!widget.forced && mounted) {
        context.pop();
        showAppSnackBar(
          context,
          'Senha alterada. Os outros aparelhos e os assistentes de IA foram '
          'desconectados.',
          tone: AppTone.success,
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      appBar: widget.forced
          ? null
          : AppBar(title: const Text('Alterar senha')),
      showBrand: widget.forced,
      // Com barra, o título já está nela. Na troca obrigatória não há barra,
      // e o título é quem explica a tela.
      title: widget.forced ? 'Defina uma nova senha' : null,
      subtitle: widget.forced
          ? 'Sua senha foi redefinida pelo líder da equipe. Escolha uma nova '
              'para continuar.'
          // As chaves dos assistentes de IA caem junto
          // (`revokeAllCredentialsForUser`): quem descobriu a senha pode ter
          // aberto uma.
          : 'Trocar a senha desconecta o app nos outros aparelhos e os '
              'assistentes de IA que você conectou.',
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _current,
                decoration: InputDecoration(
                  labelText: widget.forced
                      ? 'Senha atual (a que você recebeu)'
                      : 'Senha atual',
                ),
                obscureText: true,
                textInputAction: TextInputAction.next,
                enabled: !_loading,
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Informe a senha atual.' : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _next,
                decoration: const InputDecoration(
                  labelText: 'Nova senha',
                  helperText: 'Ao menos 8 caracteres',
                ),
                obscureText: true,
                textInputAction: TextInputAction.next,
                enabled: !_loading,
                validator: (v) => (v == null || v.length < 8)
                    ? 'A senha precisa ter ao menos 8 caracteres.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _confirm,
                decoration: const InputDecoration(
                  labelText: 'Confirme a nova senha',
                ),
                obscureText: true,
                textInputAction: TextInputAction.done,
                enabled: !_loading,
                onFieldSubmitted: (_) => _submit(),
                validator: (v) =>
                    v != _next.text ? 'As senhas não conferem.' : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (_error != null) FormErrorBanner(message: _error!),
        AppSubmitButton(
          label: widget.forced ? 'Salvar e continuar' : 'Salvar',
          loading: _loading,
          onPressed: _submit,
        ),
        if (widget.forced) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _loading
                ? null
                : () => ref.read(authControllerProvider.notifier).logout(),
            child: const Text('Sair'),
          ),
        ],
      ],
    );
  }
}
