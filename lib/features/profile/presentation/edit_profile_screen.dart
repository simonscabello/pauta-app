import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/date/civil_date.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/domain/person_fields.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_options_sheet.dart';
import '../../../shared/widgets/app_picker_field.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/form_scaffold.dart';
import '../../../shared/widgets/unsaved_changes_guard.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_repository.dart';

/// Meus dados: nome, e-mail, nascimento e gênero. A senha tem tela própria
/// porque exige a atual.
///
/// **Nascimento e gênero são da pessoa, e por isso ficam aqui e não na ficha
/// da equipe.** A consequência está assumida: quem foi cadastrado pelo líder e
/// ainda não criou conta não tem aniversário, e o líder não preenche por ele —
/// a lista da equipe diz isso com todas as letras, em vez de mostrar um campo
/// vazio que parece descuido.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen>
    with UnsavedChangesTracker {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();

  DateTime? _birthDate;
  Gender? _gender;

  bool _populated = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final hoje = today();
    final selected = await showDatePicker(
      context: context,
      locale: const Locale('pt', 'BR'),
      // Sem data cadastrada o calendário abre trinta anos atrás, e não hoje:
      // quem vai preencher a própria data de nascimento teria de voltar mês a
      // mês, e a grade de anos fica a um toque de qualquer jeito.
      initialDate: _birthDate ?? DateTime(hoje.year - 30, hoje.month, hoje.day),
      firstDate: DateTime(1900),
      lastDate: hoje,
      helpText: 'Data de nascimento',
      initialDatePickerMode: DatePickerMode.year,
    );

    if (selected == null || !mounted) return;
    setState(() {
      _birthDate = DateTime(selected.year, selected.month, selected.day);
    });
  }

  @override
  String unsavedSignature() => [
        _name.text.trim(),
        _email.text.trim().toLowerCase(),
        _dateOrNull(_birthDate),
        _gender?.name,
      ].join('\n');

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final user = ref.read(authControllerProvider).user;
    if (user == null) return;

    final name = _name.text.trim();
    final email = _email.text.trim().toLowerCase();

    final birthChanged = _dateOrNull(_birthDate) != _dateOrNull(user.birthDate);
    final genderChanged = _gender != user.gender;

    if (name == user.name &&
        email == user.email &&
        !birthChanged &&
        !genderChanged) {
      context.pop();
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).updateProfile(
            name: name == user.name ? null : name,
            email: email == user.email ? null : email,
            // Envelopado: apagar a data é uma intenção, e um `null` solto
            // seria indistinguível de "não mexi neste campo".
            birthDate: birthChanged ? Patch(_birthDate) : null,
            gender: genderChanged ? Patch(_gender) : null,
          );

      if (!mounted) return;
      markSaved();
      context.pop();
      showAppSnackBar(context, 'Dados atualizados.', tone: AppTone.success);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _dateOrNull(DateTime? date) => date == null ? null : dateKey(date);

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;

    if (user == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    if (!_populated) {
      _populated = true;
      _name.text = user.name;
      _email.text = user.email;
      _birthDate = user.birthDate;
      _gender = user.gender;
    }
    markUnsavedBaseline();

    return FormScaffold(
      isDirty: hasUnsavedChanges,
      appBar: AppBar(title: const Text('Meus dados')),
      subtitle: 'Seu nome aparece para a equipe, e o e-mail é o que você '
          'usa para entrar.',
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Nome'),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Informe seu nome.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _email,
                enabled: !_saving,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  helperText: 'Você passa a entrar no app com ele',
                ),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  final valid = value.contains('@') &&
                      value.contains('.') &&
                      !value.endsWith('@');
                  return valid ? null : 'Informe um e-mail válido.';
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              _BirthDateField(
                value: _birthDate,
                enabled: !_saving,
                onPick: _pickBirthDate,
                onClear: () => setState(() => _birthDate = null),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Um campo de seleção, e não uma barra: quatro opções numa barra
              // que não divide a largura rolavam de lado num celular de 360px,
              // e "Outro" ficava fora da tela.
              AppPickerField(
                label: 'Gênero',
                value: _gender?.label ?? 'Não informar',
                enabled: !_saving,
                onTap: () async {
                  final escolha = await showAppOptionsSheet<Gender?>(
                    context: context,
                    title: 'Gênero',
                    selected: _gender,
                    options: [
                      const AppOption(value: null, label: 'Não informar'),
                      for (final gender in Gender.values)
                        AppOption(value: gender, label: gender.label),
                    ],
                  );
                  if (escolha != null) setState(() => _gender = escolha.value);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        if (_error != null) FormErrorBanner(message: _error!),
        AppSubmitButton(
          label: 'Salvar',
          loading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// A data como campo de formulário, e não como linha de configuração: ela está
/// entre o e-mail e o gênero, e trocar de linguagem visual no meio de um
/// formulário faz a pessoa procurar onde toca.
class _BirthDateField extends StatelessWidget {
  const _BirthDateField({
    required this.value,
    required this.enabled,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? value;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final preenchida = value != null;

    return AppPickerField(
      label: 'Data de nascimento',
      value: preenchida
          ? '${formatFullDate(value!)} · ${ageOn(value!, today())} anos'
          : null,
      placeholder: 'Escolher',
      // Sem ícone, como Nome, E-mail e Gênero: só este tinha, e o texto dele
      // começava mais à direita que o dos outros campos.
      enabled: enabled,
      helperText: preenchida
          ? 'A equipe vê o dia e o mês, não o ano'
          : 'Opcional. Assim a equipe lembra do seu aniversário',
      onTap: onPick,
      onClear: onClear,
      clearTooltip: 'Remover data',
    );
  }
}
