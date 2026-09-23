import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/form_scaffold.dart';
import '../application/auth_controller.dart';
import '../domain/auth_models.dart';
import 'forgot_password_sheet.dart';

/// Um aviso para a próxima abertura do login — hoje, só "sua sessão expirou",
/// vindo da `UnlockScreen`. Quem o põe já foi desmontado quando o login abre,
/// por isso ele mora num provider e não num parâmetro de rota.
final loginNoticeProvider = StateProvider<String?>((ref) => null);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  String? _error;
  bool _biometricAvailable = false;
  bool _unlocking = false;

  @override
  void initState() {
    super.initState();
    // O pedido automático de biometria saiu daqui para a `UnlockScreen`: quem
    // chega ao login com a sessão bloqueada escolheu a senha, e abrir a
    // digital de novo por cima seria desfazer a escolha.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final available =
          await ref.read(authControllerProvider.notifier).biometricsAvailable;
      if (!mounted) return;
      setState(() => _biometricAvailable = available);
    });
  }

  Future<void> _unlock() async {
    if (_unlocking) return;
    ref.read(loginNoticeProvider.notifier).state = null;
    setState(() {
      _unlocking = true;
      _error = null;
    });
    final result =
        await ref.read(authControllerProvider.notifier).unlockWithBiometrics();
    if (mounted) {
      setState(() {
        _unlocking = false;
        _error = switch (result) {
          BiometricUnlock.success => null,
          BiometricUnlock.cancelled => null,
          BiometricUnlock.offline =>
            'Não foi possível conectar ao servidor. Tente de novo ou entre com e-mail e senha.',
          BiometricUnlock.expired =>
            'Sua sessão expirou. Entre com seu e-mail e senha.',
        };
      });
    }
  }

  Future<void> _offerBiometrics(AuthUser user) async {
    final auth = ref.read(authControllerProvider.notifier);
    TextInput.finishAutofillContext(shouldSave: true);
    if (!await auth.shouldOfferBiometrics(user) || !mounted) return;
    await auth.markBiometricOffer(user);
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Entrar mais rápido da próxima vez?'),
        content: const Text(
          'Use a biometria do seu aparelho para acessar o Pauta sem precisar digitar sua senha.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Usar biometria'),
          ),
        ],
      ),
    );
    if (accepted == true) await auth.enableBiometricsFor(user);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    ref.read(loginNoticeProvider.notifier).state = null;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).login(
            email: _email.text.trim(),
            password: _password.text,
            onAuthenticated: _offerBiometrics,
          );
      // A navegacao e feita pelo redirect do router ao mudar o estado de auth.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error ?? ref.watch(loginNoticeProvider);
    return FormScaffold(
      showBrand: true,
      title: 'Que bom te ver por aqui!',
      subtitle: 'Escala, agenda e repertório da sua equipe em um lugar só.',
      children: [
        AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'E-mail'),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  textInputAction: TextInputAction.next,
                  enabled: !_loading,
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Informe um e-mail válido.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _password,
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    suffixIcon: IconButton(
                      // Sem `tooltip` o leitor de tela anunciava só "botão": não
                      // dizia o que ele faz nem em que estado a senha está.
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
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  enabled: !_loading,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Informe sua senha.' : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (error != null) FormErrorBanner(message: error),
        AppSubmitButton(
          label: 'Entrar',
          loading: _loading,
          loadingLabel: 'Entrando',
          onPressed: _submit,
        ),
        // Logo abaixo do "Entrar", que é onde se percebe o esquecimento.
        TextButton(
          onPressed: _loading
              ? null
              : () => showForgotPasswordSheet(context, email: _email.text),
          child: const Text('Esqueci minha senha'),
        ),
        if (_biometricAvailable &&
            ref.watch(authControllerProvider).status == AuthStatus.locked)
          TextButton.icon(
            onPressed: _unlocking ? null : _unlock,
            icon: const Icon(Icons.fingerprint, size: 19),
            label: const Text('Entrar com biometria'),
          ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: _loading ? null : () => context.go('/cadastro'),
          child: const Text('Não tenho conta. Criar agora'),
        ),
        const SizedBox(height: AppSpacing.xl),
        TextButton.icon(
          onPressed: () => context.push('/diagnostico'),
          icon: const Icon(Icons.wifi_tethering, size: 18),
          label: const Text('Problemas para conectar?'),
        ),
      ],
    );
  }
}
