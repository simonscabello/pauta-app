import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/shared_preferences_provider.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_group.dart';
import '../../team/data/team_repository.dart';
import '../domain/team_setup.dart';

/// "Primeiros passos" na Home de quem lidera uma equipe que ainda não está
/// montada. Some sozinho quando tudo está feito, e pode ser escondido antes.
///
/// O tour do primeiro acesso mostra a quem toca onde as coisas estão; quem
/// acabou de criar a equipe precisa de outra coisa -- o caminho até a primeira
/// escala --, e é isso que decide se uma igreja nova fica.
class TeamSetupCard extends ConsumerStatefulWidget {
  const TeamSetupCard({
    super.key,
    required this.teamId,
    required this.hasSchedules,
  });

  final String teamId;
  final bool hasSchedules;

  @override
  ConsumerState<TeamSetupCard> createState() => _TeamSetupCardState();
}

class _TeamSetupCardState extends ConsumerState<TeamSetupCard> {
  String get _hiddenKey => 'team_setup_hidden_${widget.teamId}';

  bool _readHidden() {
    try {
      return ref.read(sharedPreferencesProvider).getBool(_hiddenKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  void _hide() {
    try {
      ref.read(sharedPreferencesProvider).setBool(_hiddenKey, true);
    } catch (_) {
      // Sem onde guardar, o bloco volta na próxima abertura.
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_readHidden()) return const SizedBox.shrink();
    final templates =
        ref.watch(serviceTemplatesProvider(widget.teamId)).valueOrNull;
    final members = ref.watch(membersProvider(widget.teamId)).valueOrNull;
    // Sem as duas respostas o bloco espera calado: um passo "por fazer" que
    // na verdade só não carregou empurraria a Home à toa.
    if (templates == null || members == null) return const SizedBox.shrink();

    final steps = teamSetupSteps(
      templates: templates,
      members: members,
      hasSchedules: widget.hasSchedules,
    );
    final feitos = steps.where((s) => s.done).length;
    if (feitos == steps.length) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    // O espaço de cima vem daqui, e não de quem monta a Home: escondido ou
    // completo, o bloco não deixa um vão no lugar dele.
    final group = AppGroup(
      title: 'Primeiros passos · $feitos de ${steps.length}',
      trailing: TextButton(onPressed: _hide, child: const Text('Esconder')),
      children: [
        for (final step in steps)
          AppGroupRow(
            icon: step.done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            title: step.title,
            subtitle: step.done ? null : step.hint,
            showChevron: !step.done,
            trailing: step.done
                ? Icon(Icons.check_rounded, color: scheme.primary, size: 20)
                : null,
            onTap: step.done ? null : () => context.push(step.route),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: group,
    );
  }
}
