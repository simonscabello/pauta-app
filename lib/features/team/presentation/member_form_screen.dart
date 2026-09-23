import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/date/civil_date.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/domain/person_fields.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_choice_bar.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_picker_field.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/form_scaffold.dart';
import '../../../shared/widgets/unsaved_changes_guard.dart';
import '../../../shared/widgets/position_icon.dart';
import '../../../shared/widgets/section_header.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../invites/presentation/invite_actions.dart';
import '../data/team_repository.dart';
import '../domain/team_models.dart';

/// Cadastro de membro sem exigir conta: o líder monta a equipe inteira de uma
/// vez, e cada pessoa reivindica seu cadastro depois, pelo convite.
class MemberFormScreen extends ConsumerStatefulWidget {
  const MemberFormScreen({super.key, required this.teamId, this.member});

  final String teamId;
  final Member? member;

  bool get isEditing => member != null;

  @override
  ConsumerState<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends ConsumerState<MemberFormScreen>
    with UnsavedChangesTracker {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _notes;
  late final TextEditingController _leaveReason;
  late final Set<String> _selected;

  /// `LEADER` ou `MEMBER`. Nulo enquanto não há membro (cadastro novo).
  late String? _role;

  late bool _onLeave;
  DateTime? _leaveUntil;

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.member?.displayName ?? '');
    _phone = TextEditingController(text: widget.member?.phone ?? '');
    _notes = TextEditingController(text: widget.member?.notes ?? '');
    _leaveReason = TextEditingController(text: widget.member?.leaveReason ?? '');
    _selected = {...?widget.member?.positions.map((p) => p.id)};
    _role = widget.member?.role;
    _onLeave = widget.member?.onLeave ?? false;
    _leaveUntil = widget.member?.leaveUntil;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    _leaveReason.dispose();
    super.dispose();
  }

  Future<void> _pickLeaveUntil() async {
    final hoje = today();
    final selected = await showDatePicker(
      context: context,
      locale: const Locale('pt', 'BR'),
      initialDate: _leaveUntil ?? hoje.add(const Duration(days: 30)),
      // Previsão de retorno é para a frente. Uma data no passado só produziria
      // a etiqueta de previsão vencida no instante em que fosse gravada.
      firstDate: hoje,
      lastDate: DateTime(hoje.year + 3),
      helpText: 'Previsão de retorno',
    );

    if (selected == null || !mounted) return;
    setState(() {
      _leaveUntil = DateTime(selected.year, selected.month, selected.day);
    });
  }

  @override
  String unsavedSignature() => [
        _name.text.trim(),
        _phone.text.trim(),
        _notes.text.trim(),
        _leaveReason.text.trim(),
        (_selected.toList()..sort()).join(','),
        _role,
        _onLeave,
        _leaveUntil?.toIso8601String(),
      ].join('\n');

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repository = ref.read(teamRepositoryProvider);

      Member? created;

      if (widget.isEditing) {
        await repository.updateMember(
          widget.teamId,
          widget.member!.id,
          displayName: _name.text.trim(),
          phone: _phone.text.trim(),
          notes: _notes.text.trim(),
          positionIds: _selected.toList(),
          onLeave: _onLeave,
          leaveUntil: _leaveUntil,
          leaveReason: _leaveReason.text.trim(),
          // Só quando mudou de fato. Reenviar o papel do dono daria
          // CANNOT_DEMOTE_OWNER mesmo sem ninguém ter tocado no campo.
          role: _role != widget.member!.role ? _role : null,
        );
      } else {
        created = await repository.addMember(
          widget.teamId,
          displayName: _name.text.trim(),
          phone: _phone.text.trim(),
          notes: _notes.text.trim(),
          positionIds: _selected.toList(),
        );
      }

      ref.invalidate(membersProvider(widget.teamId));
      if (!mounted) return;
      markSaved();

      final name = _name.text.trim();
      // O convite é o passo seguinte natural de cadastrar alguém, e ficava
      // escondido duas telas adiante. Oferecer aqui é o que transforma
      // "cadastrei a equipe" em "a equipe está usando o app".
      final invited = created != null && await _offerInvite(created);
      if (!mounted) return;

      context.pop(true);
      if (!invited) {
        showAppSnackBar(
          context,
          widget.isEditing
              ? 'Dados de $name atualizados.'
              : '$name entrou na equipe.',
          tone: AppTone.success,
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Pergunta, logo depois do cadastro, se o líder quer o convite na mão.
  ///
  /// Devolve `true` quando o convite foi gerado e copiado — aí a tela não
  /// mostra o aviso genérico de "entrou na equipe", que apagaria da tela o
  /// aviso de que a mensagem está pronta para colar.
  Future<bool> _offerInvite(Member member) async {
    final wants = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${member.displayName} entrou na equipe'),
        content: const Text(
          'Ainda não tem conta no app. Quer mandar um convite pelo '
          'WhatsApp?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Depois'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Convidar agora'),
          ),
        ],
      ),
    );
    if (wants != true || !mounted) return false;

    await copyIndividualInvite(
      context,
      ref,
      teamId: widget.teamId,
      membershipId: member.id,
      displayName: member.displayName,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final positions = ref.watch(positionsProvider(widget.teamId));
    markUnsavedBaseline();

    return FormScaffold(
      isDirty: hasUnsavedChanges,
      // "Integrante", como na aba Equipe: "membro" é o nome de um papel.
      appBar: AppBar(
        title: Text(
          widget.isEditing ? 'Editar integrante' : 'Adicionar integrante',
        ),
      ),
      subtitle: widget.isEditing
          ? null
          : 'A pessoa não precisa ter conta ainda. Cadastre agora e envie o '
              'convite depois.',
      // A ficha de quem já existe passa de uma tela (funções, papel,
      // afastamento): o botão fica preso embaixo.
      bottomAction: widget.isEditing
          ? AppSubmitButton(
              label: 'Salvar',
              loading: _loading,
              onPressed: _submit,
            )
          : null,
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nome'),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                enabled: !_loading,
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Informe o nome.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(
                  labelText: 'Telefone (opcional)',
                ),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                enabled: !_loading,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Observações (opcional)',
                  helperText: 'Só quem lidera vê. Ex.: "chega depois das 9h"',
                  // Em 375px a ajuda saía cortada com reticências.
                  helperMaxLines: 2,
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                maxLength: 500,
                enabled: !_loading,
              ),
              // Convidado não tem conta nem convite: falar de aniversário
              // com ele seria prometer uma tela que nunca chega.
              if (widget.isEditing && !widget.member!.isGuest)
                _PersonFacts(member: widget.member!),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const SectionHeader(
          title: 'Funções',
          subtitle: 'O que esta pessoa toca ou faz. Pode marcar mais de uma.',
        ),
        positions.when(
          loading: () => const Row(
            children: [
              AppSkeleton(width: 96, height: 40, radius: AppSpacing.radiusPill),
              SizedBox(width: AppSpacing.sm),
              AppSkeleton(width: 76, height: 40, radius: AppSpacing.radiusPill),
              SizedBox(width: AppSpacing.sm),
              AppSkeleton(width: 110, height: 40, radius: AppSpacing.radiusPill),
            ],
          ),
          // Era `Text('$e')`: o objeto de exceção do Dart impresso no meio do
          // formulário, sem nada que a pessoa pudesse fazer a respeito.
          error: (error, _) => _InlineError(
            message: error is ApiException
                ? error.message
                : 'Não foi possível carregar as funções da equipe.',
            onRetry: () => ref.invalidate(positionsProvider(widget.teamId)),
          ),
          data: (list) => _PositionGrid(
            positions: list,
            selected: _selected,
            enabled: !_loading,
            onToggle: (id, on) => setState(() {
              if (on) {
                _selected.add(id);
              } else {
                _selected.remove(id);
              }
            }),
          ),
        ),
        if (widget.isEditing) ...[
          const SizedBox(height: AppSpacing.xxl),
          _RoleField(
            member: widget.member!,
            value: _role,
            enabled: !_loading,
            // Quem está mexendo. Vem da equipe DESTA tela, e não da primeira
            // da lista: quem participa de duas veria a regra da equipe errada.
            actor: ref
                .watch(authControllerProvider)
                .teams
                .where((t) => t.teamId == widget.teamId)
                .firstOrNull,
            onChanged: (v) => setState(() => _role = v),
          ),
        ],
        if (widget.isEditing && !widget.member!.isGuest) ...[
          const SizedBox(height: AppSpacing.xxl),
          _LeaveField(
            onLeave: _onLeave,
            until: _leaveUntil,
            reason: _leaveReason,
            enabled: !_loading,
            overdue: widget.member!.leaveOverdue,
            onPickUntil: _pickLeaveUntil,
            onClearUntil: () => setState(() => _leaveUntil = null),
            onChanged: (value) => setState(() {
              _onLeave = value;
              // Desligar limpa a previsão e o motivo na tela pelo mesmo motivo
              // que o servidor os limpa: um afastamento novo, meses depois,
              // não pode nascer com o texto do anterior.
              if (!value) {
                _leaveUntil = null;
                _leaveReason.clear();
              }
            }),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        if (_error != null) FormErrorBanner(message: _error!),
        if (!widget.isEditing)
          AppSubmitButton(
            label: 'Adicionar',
            loading: _loading,
            onPressed: _submit,
          ),
      ],
    );
  }
}

/// Nascimento e gênero, **em leitura**.
///
/// Eles moram na conta da pessoa, e é ela quem os preenche em Perfil → Meus
/// dados. Aqui aparecem por dois motivos: quem lidera precisa ver o que já
/// existe, e a ausência precisa ter explicação. Sem esta caixa, um aniversário
/// em branco no meio de um formulário editável parece um campo que o líder
/// esqueceu de preencher — e ele passaria a tarde procurando onde se preenche.
class _PersonFacts extends StatelessWidget {
  const _PersonFacts({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final linhas = <String>[
      if (member.birthDate != null)
        '${formatBirthday(member.birthDate!)} · ${ageOn(member.birthDate!, today())} anos',
      if (member.gender != null) member.gender!.label,
    ];

    final String texto;
    if (linhas.isNotEmpty) {
      texto = linhas.join('  ·  ');
    } else if (!member.hasAccount) {
      texto = 'Aparece quando ${member.displayName} criar a conta e preencher.';
    } else {
      texto = 'Ainda não preencheu. Só a própria pessoa pode informar.';
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.cake_outlined,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nascimento e gênero',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    texto,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: linhas.isEmpty ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Afastamento temporário: licença, viagem longa, estudo fora.
///
/// **Liga e desliga à mão, e a data não desliga nada.** Quem sabe que a pessoa
/// voltou é quem lidera, não o calendário: voltar antes do previsto é comum, e
/// um retorno automático na data recolocaria na escala alguém que ninguém
/// conferiu. Por isso a previsão é informação, e quando ela vence a tela cobra
/// a decisão em vez de tomá-la.
///
/// Não é o mesmo que remover: a pessoa continua na equipe, no histórico e nos
/// relatórios. E não é o mesmo que indisponibilidade, que é a própria pessoa
/// marcando dias soltos — aqui é a liderança dizendo que ela está fora por um
/// tempo.
class _LeaveField extends StatelessWidget {
  const _LeaveField({
    required this.onLeave,
    required this.until,
    required this.reason,
    required this.enabled,
    required this.overdue,
    required this.onChanged,
    required this.onPickUntil,
    required this.onClearUntil,
  });

  final bool onLeave;
  final DateTime? until;
  final TextEditingController reason;
  final bool enabled;
  final bool overdue;
  final ValueChanged<bool> onChanged;
  final VoidCallback onPickUntil;
  final VoidCallback onClearUntil;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Afastamento',
          subtitle: 'Continua na equipe e no histórico, mas a etiqueta aparece '
              'na hora de escalar.',
          padding: EdgeInsets.only(bottom: AppSpacing.md),
        ),
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
          ),
          tileColor: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          title: const Text('Em afastamento'),
          value: onLeave,
          onChanged: enabled ? onChanged : null,
        ),
        if (onLeave) ...[
          if (overdue) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                const AppBadge(
                  label: 'Previsão vencida',
                  tone: AppTone.warning,
                  icon: Icons.schedule_rounded,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'A data já passou. Desligue o afastamento ou marque outra.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppPickerField(
            label: 'Previsão de retorno (opcional)',
            icon: Icons.event_rounded,
            value: until != null ? formatFullDate(until!) : null,
            placeholder: 'Sem data definida',
            helperText: 'Só para lembrar. O afastamento não termina sozinho.',
            enabled: enabled,
            onTap: onPickUntil,
            onClear: onClearUntil,
            clearTooltip: 'Remover previsão',
          ),
          const SizedBox(height: AppSpacing.lg),
          TextFormField(
            controller: reason,
            enabled: enabled,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Motivo (opcional)',
              hintText: 'Licença, intercâmbio, saúde...',
            ),
          ),
        ],
      ],
    );
  }
}

/// Falha de um pedaço da tela, sem derrubar o resto do formulário.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppStatusColors.of(context).danger;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.container,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: palette.onContainer,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.onContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: palette.onContainer),
            child: const Text('Tentar de novo'),
          ),
        ],
      ),
    );
  }
}

/// Papel na equipe: membro ou líder.
///
/// Líder faz tudo o que o dono faz — cria e edita escalas, escala a equipe,
/// convida, mexe no repertório, nas funções, na grade de cultos e nos dados da
/// equipe. É o caminho para quem lidera junto.
///
/// Três casos o servidor recusa, e a tela explica em vez de deixar tentar:
/// o dono (o papel dele não se altera), você mesmo (ninguém se promove) e o
/// convidado (não é integrante da equipe).
class _RoleField extends StatelessWidget {
  const _RoleField({
    required this.member,
    required this.value,
    required this.enabled,
    required this.actor,
    required this.onChanged,
  });

  final Member member;
  final String? value;
  final bool enabled;

  /// A participação de quem está editando, nesta equipe.
  final TeamSummary? actor;

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final bloqueio = switch (member) {
      _ when member.isOwner =>
        'Quem criou a equipe é sempre o dono, e isso não se transfere por aqui.',
      _ when member.isGuest =>
        'Convidado toca numa ocasião e não é integrante da equipe.',
      _ when actor != null && actor!.membershipId == member.id =>
        'Ninguém muda o próprio papel. Peça a quem criou a equipe.',
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Papel na equipe',
          padding: EdgeInsets.only(bottom: AppSpacing.sm),
        ),
        if (bloqueio != null)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  member.isOwner
                      ? Icons.workspace_premium_rounded
                      : Icons.lock_outline_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.roleLabel, style: theme.textTheme.bodyLarge),
                      Text(bloqueio, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          )
        else ...[
          // Uma barra de escolha, e não duas caixas grandes com borda, ícone e
          // descrição: é uma escolha entre duas palavras. A explicação do que
          // foi escolhido fica numa linha embaixo.
          AppChoiceBar<String>(
            expanded: true,
            value: value ?? 'MEMBER',
            onChanged: (role) {
              if (enabled) onChanged(role);
            },
            options: const [
              AppChoice(
                value: 'MEMBER',
                label: 'Membro',
                icon: Icons.person_outline_rounded,
              ),
              AppChoice(
                value: 'LEADER',
                label: 'Líder',
                icon: Icons.shield_outlined,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value == 'LEADER'
                ? 'Monta escalas, convida pessoas e cuida da equipe — tudo o '
                    'que você faz.'
                : 'Vê as escalas e onde está escalado.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _PositionGrid extends StatelessWidget {
  const _PositionGrid({
    required this.positions,
    required this.selected,
    required this.enabled,
    required this.onToggle,
  });

  final List<Position> positions;
  final Set<String> selected;
  final bool enabled;
  final void Function(String positionId, bool on) onToggle;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    for (var i = 0; i < positions.length; i += 2) {
      final left = positions[i];
      final right = i + 1 < positions.length ? positions[i + 1] : null;

      rows.add(
        Padding(
          padding: EdgeInsets.only(
            bottom: i + 2 < positions.length ? AppSpacing.sm : 0,
          ),
          // IntrinsicHeight + stretch: as duas celulas da linha ficam com a
          // mesma altura. Sem o IntrinsicHeight, o stretch pede altura
          // infinita (o formulario rola) e a grade inteira some.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildTile(left)),
                const SizedBox(width: AppSpacing.sm),
                // Numero impar de funcoes: a ultima ocupa so a coluna da
                // esquerda, em vez de esticar e ficar diferente das outras.
                Expanded(
                  child: right == null
                      ? const SizedBox.shrink()
                      : _buildTile(right),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(children: rows);
  }

  Widget _buildTile(Position position) {
    return _PositionTile(
      position: position,
      selected: selected.contains(position.id),
      enabled: enabled,
      onTap: () => onToggle(position.id, !selected.contains(position.id)),
    );
  }
}

class _PositionTile extends StatelessWidget {
  const _PositionTile({
    required this.position,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Position position;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground =
        selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                // `outline` e não `outlineVariant`: este cartão é selecionável,
                // e a borda é a única coisa que diz onde ele começa e se está
                // marcado. Isso pede os 3:1 do WCAG 1.4.11 — com o fio
                // decorativo, quem enxerga pouco não achava a borda do que
                // ainda não tinha escolhido.
                color: selected ? scheme.primary : scheme.outline,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                PositionIcon(
                  position.name,
                  category: position.category,
                  size: 17,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    position.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: scheme.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
