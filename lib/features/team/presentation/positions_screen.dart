import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/responsive/adaptive_dialog.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_button_styles.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_notice.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../../shared/widgets/position_icon.dart';
import '../../../shared/widgets/app_primary_action.dart';
import '../data/team_repository.dart';
import '../domain/team_models.dart';

/// Rótulos e explicações das categorias.
///
/// A categoria não é enfeite: é o que sustenta as duas regras de escalação
/// (um instrumento por pessoa; quem está na técnica fica fora da banda). Por
/// isso a tela explica cada uma em vez de só listar as siglas.
const _categories = <String, ({String label, String help})>{
  'VOCAL': (label: 'Vocal', help: 'Acumula com um instrumento'),
  'INSTRUMENT': (label: 'Instrumento', help: 'Um por pessoa por escala'),
  'TECH': (label: 'Multimídia e som', help: 'Não acumula com a banda'),
  'OTHER': (label: 'Outra', help: 'Sem restrição de acúmulo'),
};

const _categoryOrder = ['VOCAL', 'INSTRUMENT', 'TECH', 'OTHER'];

class PositionsScreen extends ConsumerWidget {
  const PositionsScreen({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positions = ref.watch(allPositionsProvider(teamId));

    final nova = AppPrimaryAction(
      label: 'Nova função',
      icon: Icons.add_rounded,
      onPressed: () => _openEditor(context, ref),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Funções'),
        actions: [
          if (nova.headerAction(context) case final acao?) acao,
        ],
      ),
      floatingActionButton: nova.fab(context),
      body: SafeArea(
        top: false,
        child: AppContentWidth.reading(
          child: positions.when(
            loading: () => const AppListSkeleton(itemCount: 5),
            error: (error, _) => AppErrorState(
              message: error is ApiException
                  ? error.message
                  : 'Não foi possível carregar as funções.',
              onRetry: () => ref.invalidate(allPositionsProvider(teamId)),
            ),
            data: (list) => RefreshIndicator(
              onRefresh: () async =>
                  ref.refresh(allPositionsProvider(teamId).future),
              child: _PositionList(
                teamId: teamId,
                positions: list,
                onEdit: (p) => _openEditor(context, ref, position: p),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    Position? position,
  }) async {
    final saved = await showAdaptiveSheet<bool>(
      context: context,
      maxWidth: 480,
      builder: (_) => _PositionEditorSheet(teamId: teamId, position: position),
    );
    if (saved == true) {
      ref.invalidate(allPositionsProvider(teamId));
      ref.invalidate(positionsProvider(teamId));
    }
  }
}

class _PositionList extends StatelessWidget {
  const _PositionList({
    required this.teamId,
    required this.positions,
    required this.onEdit,
  });

  final String teamId;
  final List<Position> positions;
  final ValueChanged<Position> onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final active = positions.where((p) => p.isActive).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final inactive = positions.where((p) => !p.isActive).toList();

    final byCategory = <String, List<Position>>{};
    for (final position in active) {
      byCategory.putIfAbsent(position.category, () => []).add(position);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.lg,
        AppSpacing.screenPadding,
        AppSpacing.fabClearance,
      ),
      children: [
        Text(
          'As funções que aparecem ao escalar a equipe e ao cadastrar um '
          'integrante.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final category in _categoryOrder)
          if (byCategory[category] != null) ...[
            _CategoryHeader(category: category),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              child: Column(
                children: [
                  for (var i = 0; i < byCategory[category]!.length; i++) ...[
                    if (i > 0) Divider(color: scheme.outlineVariant, height: 1),
                    _PositionRow(
                      teamId: teamId,
                      position: byCategory[category]![i],
                      onEdit: () => onEdit(byCategory[category]![i]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        if (inactive.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          // No mesmo desenho dos cabeçalhos de categoria acima: era um
          // cabeçalho de seção, maior e mais claro, e parecia outro assunto.
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Desativadas',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  'Não aparecem ao escalar. As escalas antigas que as usaram '
                  'continuam como estão.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          AppCard(
            surface: CardSurface.sunken,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              children: [
                for (var i = 0; i < inactive.length; i++) ...[
                  if (i > 0) Divider(color: scheme.outlineVariant, height: 1),
                  _PositionRow(
                    teamId: teamId,
                    position: inactive[i],
                    onEdit: () => onEdit(inactive[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = _categories[category];

    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      child: Row(
        children: [
          Text(
            info?.label ?? category,
            // Cinza, como os cabeçalhos de grupo do resto do app.
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              info?.help ?? '',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionRow extends ConsumerWidget {
  const _PositionRow({
    required this.teamId,
    required this.position,
    required this.onEdit,
  });

  final String teamId;
  final Position position;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    // Só o ícone e o nome ficam apagados. Com a linha inteira a 60%, o
    // "Reativar" — a única ação da desativada — perdia contraste junto,
    // principalmente no tema escuro.
    Widget faded(Widget child) =>
        position.isActive ? child : Opacity(opacity: 0.6, child: child);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onEdit,
      leading: faded(
        PositionIcon(
          position.name,
          category: position.category,
          size: 18,
        ),
      ),
      title: faded(Text(position.name)),
      // Sem o "olho cortado" em toda linha: desativar é raro e mora na folha
      // de edição. Na desativada, "Reativar" continua à mão — é a única coisa
      // que se faz com ela.
      trailing: position.isActive
          ? Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
            )
          : TextButton(
              style: AppButtonStyles.compactText,
              onPressed: () => _reactivate(context, ref),
              child: const Text('Reativar'),
            ),
    );
  }

  Future<void> _reactivate(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(teamRepositoryProvider)
          .updatePosition(teamId, position.id, isActive: true);
      ref.invalidate(allPositionsProvider(teamId));
      ref.invalidate(positionsProvider(teamId));
      if (context.mounted) {
        showAppSnackBar(
          context,
          '${position.name} voltou para a lista.',
          tone: AppTone.success,
        );
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        showAppSnackBar(context, error.message, tone: AppTone.danger);
      }
    }
  }
}

class _PositionEditorSheet extends ConsumerStatefulWidget {
  const _PositionEditorSheet({required this.teamId, this.position});

  final String teamId;
  final Position? position;

  @override
  ConsumerState<_PositionEditorSheet> createState() =>
      _PositionEditorSheetState();
}

class _PositionEditorSheetState extends ConsumerState<_PositionEditorSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.position?.name ?? '');
  late String _category = widget.position?.category ?? 'INSTRUMENT';

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.position != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Informe o nome da função.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repository = ref.read(teamRepositoryProvider);
      if (_isEditing) {
        await repository.updatePosition(
          widget.teamId,
          widget.position!.id,
          name: name,
          category: _category,
        );
      } else {
        await repository.addPosition(
          widget.teamId,
          name: name,
          category: _category,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deactivate() async {
    final position = widget.position!;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Desativar ${position.name}?',
      message: 'Ela some da tela de escalar e do cadastro de integrantes. As '
          'escalas que já a usaram continuam como estão, e dá para reativar '
          'depois.',
      confirmLabel: 'Desativar',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(teamRepositoryProvider)
          .deactivatePosition(widget.teamId, position.id);
      if (!mounted) return;
      showAppSnackBar(
        context,
        '${position.name} foi desativada.',
        tone: AppTone.success,
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditing ? 'Editar função' : 'Nova função',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _name,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Sax, Cello, Backing vocal...',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Categoria', style: theme.textTheme.titleSmall),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Ela decide o que pode acumular na mesma escala.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // `RadioGroup` em vez de `groupValue`/`onChanged` em cada tile:
            // os dois foram depreciados depois do Flutter 3.32.
            RadioGroup<String>(
              groupValue: _category,
              // `onChanged` do RadioGroup não é opcional, então o bloqueio
              // durante o salvamento fica aqui dentro.
              onChanged: (value) {
                if (_saving || value == null) return;
                setState(() => _category = value);
              },
              child: Column(
                children: [
                  for (final category in _categoryOrder)
                    RadioListTile<String>(
                      value: category,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      title: Text(_categories[category]!.label),
                      subtitle: Text(_categories[category]!.help),
                    ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppNotice(
                tone: AppTone.danger,
                message: _error!,
                liveRegion: true,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppSubmitButton(
              label: 'Salvar',
              loading: _saving,
              onPressed: _save,
            ),
            if (_isEditing && widget.position!.isActive) ...[
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: _saving ? null : _deactivate,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                child: const Text('Desativar função'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
