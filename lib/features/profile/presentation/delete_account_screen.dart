import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/form_scaffold.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/presentation/login_screen.dart';
import '../../team/data/team_repository.dart';

/// O que a exclusão faria agora. `autoDispose`: a resposta muda assim que a
/// posse de uma equipe passa, e a tela precisa ver isso ao voltar.
final accountDeletionPreviewProvider =
    FutureProvider.autoDispose<AccountDeletionPreview>((ref) {
  return ref.read(authControllerProvider.notifier).deletionPreview();
});

/// Excluir a própria conta (`/perfil/dados/excluir`).
///
/// A tela diz **antes** o que some, o que fica anonimizado e o que vai junto,
/// e só então pede a senha. O dono de uma equipe em que ainda há gente com
/// conta não chega à senha: a posse precisa passar antes, e a tela leva até
/// os integrantes em vez de deixar tentar.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();

  bool _obscure = true;
  bool _deleting = false;
  String? _passwordError;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete(AccountDeletionPreview preview) async {
    if (!_formKey.currentState!.validate()) return;

    final vaiJunto = preview.teamsDeleted.map((t) => t.name).join(', ');
    final confirmed = await showConfirmDialog(
      context,
      title: 'Excluir sua conta?',
      message: preview.teamsDeleted.isEmpty
          ? 'Não há como desfazer. Para voltar a usar o Pauta, será preciso '
              'criar outra conta e ser convidado de novo.'
          : 'A equipe $vaiJunto será apagada junto, com escalas e repertório. '
              'Não há como desfazer.',
      confirmLabel: 'Excluir minha conta',
      cancelLabel: 'Manter conta',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _deleting = true;
      _passwordError = null;
      _error = null;
    });

    // Lido antes do `await`: sem a conta, o roteador leva ao login e
    // desmonta esta tela antes de a chamada voltar.
    final notice = ref.read(loginNoticeProvider.notifier);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .deleteAccount(_password.text);
      notice.state = 'Sua conta foi excluída.';
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        if (error.code == 'INVALID_PASSWORD') {
          _passwordError = error.message;
        } else {
          _error = error.message;
        }
      });
      // Alguém ganhou conta na equipe entre a prévia e agora.
      if (error.code == 'OWNER_MUST_TRANSFER') {
        ref.invalidate(accountDeletionPreviewProvider);
      }
    }
  }

  /// Leva aos integrantes da equipe que está travando, já como equipe ativa:
  /// quem é dono de duas equipes estaria olhando a outra.
  Future<void> _openMembers(TeamRef team) async {
    await ref.read(activeTeamIdProvider.notifier).select(team.teamId);
    if (mounted) context.go('/equipe');
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(accountDeletionPreviewProvider);

    return FormScaffold(
      appBar: AppBar(title: const Text('Excluir conta')),
      children: [
        const _WhatHappens(),
        const SizedBox(height: AppSpacing.xl),
        ...preview.when(
          loading: () => const [
            Center(child: CircularProgressIndicator()),
          ],
          error: (error, _) => [
            AppNotice(
              tone: AppTone.danger,
              message: error is ApiException
                  ? error.message
                  : 'Não foi possível conferir suas equipes.',
              action: TextButton(
                onPressed: () =>
                    ref.invalidate(accountDeletionPreviewProvider),
                child: const Text('Tentar de novo'),
              ),
            ),
          ],
          data: (data) => data.isBlocked
              ? [_Blocked(preview: data, onOpenMembers: _openMembers)]
              : _form(data),
        ),
      ],
    );
  }

  List<Widget> _form(AccountDeletionPreview preview) {
    final scheme = Theme.of(context).colorScheme;
    final vaiJunto = preview.teamsDeleted.map((t) => t.name).join(', ');

    return [
      if (preview.teamsDeleted.isNotEmpty) ...[
        AppNotice(
          tone: AppTone.danger,
          icon: Icons.warning_amber_rounded,
          title: 'A equipe vai junto',
          message: 'Você é a única pessoa com conta em $vaiJunto. Sem você, '
              'ninguém conseguiria administrá-la, então ela será apagada '
              'junto, com escalas, repertório e integrantes.',
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
      Form(
        key: _formKey,
        child: TextFormField(
          controller: _password,
          enabled: !_deleting,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _delete(preview),
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
          validator: (v) =>
              (v == null || v.isEmpty) ? 'Informe sua senha.' : null,
        ),
      ),
      const SizedBox(height: AppSpacing.xxl),
      if (_error != null) FormErrorBanner(message: _error!),
      FilledButton(
        onPressed: _deleting ? null : () => _delete(preview),
        style: FilledButton.styleFrom(
          backgroundColor: scheme.error,
          foregroundColor: scheme.onError,
        ),
        child: Text(_deleting ? 'Excluindo…' : 'Excluir minha conta'),
      ),
    ];
  }
}

/// O que some e o que fica, dito antes de pedir a senha. É a mesma lista da
/// página pública `excluir-conta.html`; mudou uma, mude a outra.
class _WhatHappens extends StatelessWidget {
  const _WhatHappens();

  static const _items = [
    'Sua conta, sua foto e seus dados pessoais são apagados. Os avisos param '
        'de chegar em todos os aparelhos, e os assistentes de IA que você '
        'conectou perdem o acesso.',
    'Você sai das próximas escalas. As que já aconteceram continuam na '
        'equipe, com o seu nome trocado por "Ex-integrante".',
    'Suas indisponibilidades e sugestões de música são apagadas.',
    'Não há como desfazer.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('O que acontece', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        for (final item in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: AppSpacing.sm),
                  child: Text('•'),
                ),
                Expanded(
                  child: Text(item, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Blocked extends StatelessWidget {
  const _Blocked({required this.preview, required this.onOpenMembers});

  final AccountDeletionPreview preview;
  final ValueChanged<TeamRef> onOpenMembers;

  @override
  Widget build(BuildContext context) {
    final names = preview.blockedBy.map((t) => t.name).join(', ');
    final plural = preview.blockedBy.length > 1;

    return AppNotice(
      tone: AppTone.warning,
      icon: Icons.key_rounded,
      title: 'Passe a posse antes',
      message: 'Você é dono de $names, e há outros integrantes com conta '
          '${plural ? 'nessas equipes' : 'nela'}. Abra o integrante que vai '
          'cuidar da equipe e toque em "Passar a posse". Depois, volte aqui.',
      action: TextButton(
        onPressed: () => onOpenMembers(preview.blockedBy.first),
        child: Text(
          plural
              ? 'Integrantes de ${preview.blockedBy.first.name}'
              : 'Abrir integrantes',
        ),
      ),
    );
  }
}
