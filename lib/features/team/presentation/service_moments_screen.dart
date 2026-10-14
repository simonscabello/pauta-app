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
import '../../../shared/widgets/app_primary_action.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/app_submit_button.dart';
import '../../events/domain/service_moments.dart';
import '../data/team_repository.dart';

/// Os momentos do culto da equipe: os que a folha de ajustes da música e o
/// seletor oferecem, na ordem em que acontecem.
///
/// A equipe nasce com os seis de fábrica e pode renomear, reordenar e excluir
/// qualquer um, e cadastrar os dela — o culto especial, a liturgia que mudou,
/// que antes eram um "Outro" escrito à mão a cada escala. Excluir só tira das
/// escolhas: as escalas que já usam o momento continuam com o nome dele, e
/// "Restaurar" o traz de volta.
class ServiceMomentsScreen extends ConsumerWidget {
  const ServiceMomentsScreen({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moments = ref.watch(allServiceMomentsProvider(teamId));

    final novo = AppPrimaryAction(
      label: 'Novo momento',
      icon: Icons.add_rounded,
      onPressed: () => _openEditor(context, ref),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Momentos do culto'),
        actions: [
          if (novo.headerAction(context) case final acao?) acao,
        ],
      ),
      floatingActionButton: novo.fab(context),
      body: SafeArea(
        top: false,
        child: AppContentWidth.reading(
          child: moments.when(
            loading: () => const AppListSkeleton(itemCount: 6),
            error: (error, _) => AppErrorState(
              message: error is ApiException
                  ? error.message
                  : 'Não foi possível carregar os momentos do culto.',
              onRetry: () => ref.invalidate(allServiceMomentsProvider(teamId)),
            ),
            data: (list) => _MomentList(
              teamId: teamId,
              moments: list,
              onEdit: (m) => _openEditor(context, ref, moment: m),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    TeamMoment? moment,
  }) async {
    final saved = await showAdaptiveSheet<bool>(
      context: context,
      maxWidth: 480,
      builder: (_) => _MomentEditorSheet(teamId: teamId, moment: moment),
    );
    if (saved == true) invalidateServiceMoments(ref, teamId);
  }
}

/// Depois de mexer na lista: a tela de gestão e as escolhas da escala.
void invalidateServiceMoments(WidgetRef ref, String teamId) {
  ref.invalidate(allServiceMomentsProvider(teamId));
  ref.invalidate(serviceMomentsProvider(teamId));
}

class _MomentList extends ConsumerStatefulWidget {
  const _MomentList({
    required this.teamId,
    required this.moments,
    required this.onEdit,
  });

  final String teamId;
  final List<TeamMoment> moments;
  final ValueChanged<TeamMoment> onEdit;

  @override
  ConsumerState<_MomentList> createState() => _MomentListState();
}

class _MomentListState extends ConsumerState<_MomentList> {
  /// A ordem na tela enquanto o servidor confirma: arrastar e ver a linha
  /// voltar ao lugar até a resposta chegar pareceria que não funcionou.
  late List<TeamMoment> _ativos = _ativosDe(widget.moments);

  static List<TeamMoment> _ativosDe(List<TeamMoment> moments) =>
      [for (final m in moments) if (m.isActive) m];

  @override
  void didUpdateWidget(covariant _MomentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moments != widget.moments) {
      _ativos = _ativosDe(widget.moments);
    }
  }

  /// `newIndex` já vem descontado da linha que saiu (`onReorderItem`).
  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (newIndex == oldIndex) return;
    final antes = _ativos;
    final nova = [..._ativos];
    nova.insert(newIndex, nova.removeAt(oldIndex));
    setState(() => _ativos = nova);
    try {
      await ref.read(teamRepositoryProvider).reorderServiceMoments(
            widget.teamId,
            [for (final m in nova) m.id],
          );
      invalidateServiceMoments(ref, widget.teamId);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _ativos = antes);
      showAppSnackBar(context, error.message, tone: AppTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final excluidos = [
      for (final m in widget.moments)
        if (!m.isActive) m,
    ];

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.lg,
        AppSpacing.screenPadding,
        AppSpacing.fabClearance,
      ),
      // A alça de arrastar fica à direita, e é só ela que arrasta: com a linha
      // inteira arrastável, tocar para renomear viraria arrastar sem querer.
      buildDefaultDragHandles: false,
      header: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Text(
          'Os momentos que aparecem ao montar as músicas da escala, na ordem do '
          'culto. Arraste para reordenar; toque para renomear ou excluir.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
      footer: excluidos.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Excluídos',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Não aparecem nas escolhas. As escalas que já os usam '
                    'continuam com o nome.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    surface: CardSurface.sunken,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Column(
                      children: [
                        for (final (i, m) in excluidos.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          _ExcludedRow(teamId: widget.teamId, moment: m),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
      itemCount: _ativos.length,
      onReorderItem: _reorder,
      itemBuilder: (context, index) {
        final m = _ativos[index];
        return Material(
          key: ValueKey(m.id),
          color: scheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: index == 0 ? const Radius.circular(16) : Radius.zero,
              bottom: index == _ativos.length - 1
                  ? const Radius.circular(16)
                  : Radius.zero,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (index > 0)
                const Divider(height: 1, indent: AppSpacing.lg),
              ListTile(
                contentPadding: const EdgeInsets.only(
                  left: AppSpacing.lg,
                  right: AppSpacing.xs,
                ),
                onTap: () => widget.onEdit(m),
                title: Text(m.name),
                trailing: ReorderableDragStartListener(
                  index: index,
                  child: Semantics(
                    label: 'Arrastar para reordenar ${m.name}',
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExcludedRow extends ConsumerWidget {
  const _ExcludedRow({required this.teamId, required this.moment});

  final String teamId;
  final TeamMoment moment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Opacity(opacity: 0.6, child: Text(moment.name)),
      trailing: TextButton(
        style: AppButtonStyles.compactText,
        onPressed: () => _restore(context, ref),
        child: const Text('Restaurar'),
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(teamRepositoryProvider)
          .updateServiceMoment(teamId, moment.id, isActive: true);
      invalidateServiceMoments(ref, teamId);
      if (context.mounted) {
        showAppSnackBar(
          context,
          '${moment.name} voltou para a lista.',
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

class _MomentEditorSheet extends ConsumerStatefulWidget {
  const _MomentEditorSheet({required this.teamId, this.moment});

  final String teamId;
  final TeamMoment? moment;

  @override
  ConsumerState<_MomentEditorSheet> createState() => _MomentEditorSheetState();
}

class _MomentEditorSheetState extends ConsumerState<_MomentEditorSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.moment?.name ?? '');

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.moment != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Informe o nome do momento.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repository = ref.read(teamRepositoryProvider);
      if (_isEditing) {
        await repository.updateServiceMoment(
          widget.teamId,
          widget.moment!.id,
          name: name,
        );
      } else {
        await repository.addServiceMoment(widget.teamId, name);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final moment = widget.moment!;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Excluir ${moment.name}?',
      message: 'Ele sai das escolhas ao montar as músicas da escala. As escalas '
          'que já o usam continuam com o nome, e dá para restaurar depois.',
      confirmLabel: 'Excluir',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(teamRepositoryProvider)
          .deleteServiceMoment(widget.teamId, moment.id);
      if (!mounted) return;
      showAppSnackBar(
        context,
        '${moment.name} foi excluído.',
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
    final moment = widget.moment;

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
              _isEditing ? 'Editar momento' : 'Novo momento',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _name,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.words,
              maxLength: 40,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: 'Nome',
                hintText: 'Santa Ceia, Apelo, Batismo...',
                // Renomear muda o nome em todas as escalas que já o usam —
                // vale dizer antes.
                helperText: moment != null
                    ? 'O novo nome vale também nas escalas que já o usam.'
                    : null,
                counterText: '',
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
            if (moment != null && moment.isActive) ...[
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: _saving ? null : _delete,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                child: const Text('Excluir momento'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
