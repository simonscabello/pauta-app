import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/form_scaffold.dart';
import '../../auth/application/auth_controller.dart';
import '../data/team_repository.dart';

class CreateTeamScreen extends ConsumerStatefulWidget {
  const CreateTeamScreen({super.key});

  @override
  ConsumerState<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _CreateTeamScreenState extends ConsumerState<CreateTeamScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Depois de criar, **sai daqui**. A tela não navegava: recarregava a sessão
  /// e ficava parada com o formulário de pé, e quem achou que nada tinha
  /// acontecido tocou de novo — três equipes com o mesmo nome em produção.
  Future<void> _submit() async {
    // Botão e campo já se travam no carregamento; isto é a trava do próprio
    // `_submit`, para não depender de os dois continuarem assim.
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final team =
          await ref.read(teamRepositoryProvider).create(name: _name.text.trim());
      // Recarrega a sessao para a nova equipe entrar no estado de auth.
      await ref.read(authControllerProvider.notifier).reloadTeams();
      // Quem já servia em outra equipe cairia nela, e não na que acabou de
      // criar.
      await ref.read(activeTeamIdProvider.notifier).select(team.id);
      if (!mounted) return;
      context.go('/inicio');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      // O nome da ação na barra, e não repetido no corpo.
      appBar: AppBar(title: const Text('Criar equipe')),
      subtitle: 'Você será o dono da equipe e poderá cadastrar os integrantes '
          'em seguida.',
      children: [
        Form(
          key: _formKey,
          child: TextFormField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Nome da equipe',
              hintText: 'Ministério de Louvor',
            ),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            enabled: !_loading,
            onFieldSubmitted: (_) => _submit(),
            validator: (v) => (v == null || v.trim().length < 2)
                ? 'Informe o nome da equipe.'
                : null,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (_error != null) FormErrorBanner(message: _error!),
        AppSubmitButton(
          label: 'Criar equipe',
          loading: _loading,
          loadingLabel: 'Criando a equipe',
          onPressed: _submit,
        ),
      ],
    );
  }
}
