import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/form_scaffold.dart';
import '../application/auth_controller.dart';
import '../data/auth_repository.dart';
import 'forgot_password_sheet.dart';

/// "Esqueci minha senha", em duas etapas na mesma tela: o e-mail, e depois o
/// código que chegou nele com a senha nova. Salvar já entra no app -- quem
/// tira a pessoa daqui é o redirect do router, como no login.
///
/// O caminho antigo continua como saída: quem lidera cria uma senha
/// temporária (`showForgotPasswordSheet`). Ele abre sozinho quando o servidor
/// está sem e-mail configurado.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  /// O que estava digitado no login. Vai por `extra`, e não pela URL: na Web
  /// o endereço fica no histórico do navegador.
  final String initialEmail;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailForm = GlobalKey<FormState>();
  final _resetForm = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail.trim());
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  /// O e-mail para o qual o código foi pedido. Nulo na primeira etapa.
  String? _sentTo;
  int _expiresInMinutes = 15;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _requestCode({bool resend = false}) async {
    if (!resend && !_emailForm.currentState!.validate()) return;
    final email = resend ? _sentTo! : _email.text.trim();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final minutes =
          await ref.read(authRepositoryProvider).requestPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _sentTo = email;
        _expiresInMinutes = minutes;
      });
      if (resend) {
        showAppSnackBar(
          context,
          'Se o e-mail estiver certo, um código novo chega em instantes.',
          tone: AppTone.success,
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'PASSWORD_RESET_UNAVAILABLE') {
        await showForgotPasswordSheet(context, email: email);
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    if (!_resetForm.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).resetPassword(
            email: _sentTo!,
            code: _code.text.replaceAll(RegExp(r'\s'), ''),
            newPassword: _password.text,
          );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeEmail() {
    setState(() {
      _sentTo = null;
      _error = null;
      _code.clear();
    });
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sentTo = _sentTo;
    return FormScaffold(
      appBar: AppBar(
        title: const Text('Esqueci minha senha'),
        leading: BackButton(onPressed: _back),
      ),
      subtitle: sentTo == null
          ? 'Informe o e-mail da sua conta. Vamos mandar um código para você '
              'criar uma senha nova.'
          : 'Enviamos um código para $sentTo. Ele vale $_expiresInMinutes '
              'minutos. Se não aparecer, confira a caixa de spam.',
      children: sentTo == null ? _emailStep() : _resetStep(),
    );
  }

  List<Widget> _emailStep() {
    return [
      Form(
        key: _emailForm,
        child: TextFormField(
          controller: _email,
          decoration: const InputDecoration(labelText: 'E-mail'),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          enabled: !_loading,
          onFieldSubmitted: (_) => _requestCode(),
          validator: (v) => (v == null || !v.contains('@'))
              ? 'Informe um e-mail válido.'
              : null,
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      if (_error != null) FormErrorBanner(message: _error!),
      AppSubmitButton(
        label: 'Enviar código',
        loadingLabel: 'Enviando',
        loading: _loading,
        onPressed: _requestCode,
      ),
      const SizedBox(height: AppSpacing.sm),
      _askLeaderButton(),
    ];
  }

  List<Widget> _resetStep() {
    return [
      AutofillGroup(
        child: Form(
          key: _resetForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _code,
                decoration: const InputDecoration(labelText: 'Código'),
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                textInputAction: TextInputAction.next,
                enabled: !_loading,
                validator: (v) => (v == null || v.length != 6)
                    ? 'O código tem 6 números.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _password,
                decoration: InputDecoration(
                  labelText: 'Nova senha',
                  helperText: 'Ao menos 8 caracteres',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Mostrar senha' : 'Ocultar senha',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                enabled: !_loading,
                validator: (v) => (v == null || v.length < 8)
                    ? 'A senha precisa ter ao menos 8 caracteres.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _confirm,
                decoration:
                    const InputDecoration(labelText: 'Confirme a nova senha'),
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                enabled: !_loading,
                onFieldSubmitted: (_) => _reset(),
                validator: (v) =>
                    v != _password.text ? 'As senhas não conferem.' : null,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      if (_error != null) FormErrorBanner(message: _error!),
      AppSubmitButton(
        label: 'Salvar e entrar',
        loading: _loading,
        onPressed: _reset,
      ),
      const SizedBox(height: AppSpacing.sm),
      TextButton(
        onPressed: _loading ? null : () => _requestCode(resend: true),
        child: const Text('Enviar outro código'),
      ),
      TextButton(
        onPressed: _loading ? null : _changeEmail,
        child: const Text('Usar outro e-mail'),
      ),
      _askLeaderButton(),
    ];
  }

  /// Sem acesso ao e-mail, ou ele não chega: o recado para quem lidera.
  Widget _askLeaderButton() {
    return TextButton(
      onPressed: _loading
          ? null
          : () => showForgotPasswordSheet(
                context,
                email: _sentTo ?? _email.text.trim(),
              ),
      child: const Text('Sem acesso ao e-mail? Peça a quem lidera'),
    );
  }
}
