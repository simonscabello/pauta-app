import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/date/civil_date.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_choice_bar.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/app_pressable.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/app_primary_action.dart';
import '../../auth/application/auth_controller.dart';
import '../../songs/presentation/song_resources.dart';
import '../data/suggestion_repository.dart';
import '../domain/song_suggestion.dart';
import 'suggest_song_sheet.dart';
import 'suggestion_detail_screen.dart';

/// As sugestões da equipe.
///
/// **A lista é índice; o detalhe é onde se decide.** Nenhum botão aqui: decidir
/// de raspão numa lista é decidir sem ler o motivo.
///
/// **Agrupada por destino.** A pergunta de quem lidera é "o que pediram para
/// este domingo?", e a data vinha numa etiqueta repetida em cada cartão — um
/// cartão por sugestão, com borda própria. Agora a data é o título do grupo
/// ("Domingo, 21 de setembro", "Para o repertório") e as sugestões são linhas
/// de uma superfície só.
class SuggestionsScreen extends ConsumerStatefulWidget {
  const SuggestionsScreen({super.key, required this.teamId});

  final String teamId;

  @override
  ConsumerState<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends ConsumerState<SuggestionsScreen> {
  SuggestionScope _scope = SuggestionScope.open;

  @override
  Widget build(BuildContext context) {
    final query = (teamId: widget.teamId, scope: _scope);
    final suggestions = ref.watch(suggestionsProvider(query));
    final team = ref
        .watch(authControllerProvider)
        .teams
        .where((t) => t.teamId == widget.teamId)
        .firstOrNull;

    final sugerir = AppPrimaryAction(
      label: 'Sugerir',
      icon: Icons.add_rounded,
      onPressed: () => showSuggestSongSheet(context, teamId: widget.teamId),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sugestões da equipe'),
        actions: [
          if (sugerir.headerAction(context) case final acao?) acao,
        ],
      ),
      floatingActionButton: sugerir.fab(context),
      body: SafeArea(
        top: false,
        child: AppContentWidth.reading(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.md,
                  AppSpacing.screenPadding,
                  AppSpacing.md,
                ),
                child: AppChoiceBar<SuggestionScope>(
                  value: _scope,
                  onChanged: (value) => setState(() => _scope = value),
                  options: const [
                    AppChoice(
                      value: SuggestionScope.open,
                      label: 'Abertas',
                    ),
                    AppChoice(
                      value: SuggestionScope.closed,
                      label: 'Encerradas',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: suggestions.when(
                  loading: () => const AppLoading(),
                  error: (error, _) => AppErrorState(
                    message: error is ApiException
                        ? error.message
                        : 'Não foi possível carregar as sugestões.',
                    onRetry: () => ref.invalidate(suggestionsProvider(query)),
                  ),
                  data: (list) {
                    if (list.isEmpty) return _vazio();
                    final grupos = groupSuggestionsByTarget(
                      list,
                      newestFirst: _scope == SuggestionScope.closed,
                    );

                    return RefreshIndicator(
                      onRefresh: () async =>
                          ref.refresh(suggestionsProvider(query).future),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.screenPadding,
                          AppSpacing.sm,
                          AppSpacing.screenPadding,
                          AppSpacing.fabClearance,
                        ),
                        children: [
                          for (var i = 0; i < grupos.length; i++) ...[
                            if (i > 0) const SizedBox(height: AppSpacing.xl),
                            AppGroup(
                              title: grupos[i].title,
                              dividerIndent: AppGroup.textIndent,
                              children: [
                                for (final item in grupos[i].items)
                                  SuggestionRow(
                                    suggestion: item,
                                    teamId: widget.teamId,
                                    isMine: item.createdBy.membershipId ==
                                        team?.membershipId,
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vazio() {
    if (_scope == SuggestionScope.closed) {
      return const AppEmptyState(
        icon: Icons.inbox_rounded,
        title: 'Nada encerrado ainda',
        message: 'As sugestões respondidas e as de domingos que já passaram '
            'aparecem aqui.',
      );
    }
    // Sem botão próprio: o flutuante "Sugerir" já está na tela, e dois
    // botões para a mesma ação fazem a pessoa procurar a diferença.
    return const AppEmptyState(
      icon: Icons.lightbulb_outline_rounded,
      title: 'Nenhuma sugestão por enquanto',
      message: 'Qualquer pessoa da equipe pode sugerir uma música para o '
          'repertório ou para um domingo. Toque em "Sugerir".',
    );
  }
}

/// Um grupo da lista: o destino e as sugestões dele.
typedef SuggestionGroup = ({String title, List<SongSuggestion> items});

/// Agrupa as sugestões pelo destino: uma data por grupo, e "Para o repertório"
/// por último.
///
/// Nas abertas, a data mais próxima primeiro — é o domingo que o líder está
/// montando. Nas encerradas, a mais recente primeiro. Dentro de cada grupo, a
/// ordem que o servidor mandou.
List<SuggestionGroup> groupSuggestionsByTarget(
  List<SongSuggestion> suggestions, {
  bool newestFirst = false,
  DateTime? now,
}) {
  final porData = <DateTime, List<SongSuggestion>>{};
  final repertorio = <SongSuggestion>[];

  for (final item in suggestions) {
    final data = item.targetDate;
    if (data == null) {
      repertorio.add(item);
    } else {
      final dia = DateTime(data.year, data.month, data.day);
      porData.putIfAbsent(dia, () => []).add(item);
    }
  }

  final crescente = porData.keys.toList()..sort();
  final datas = newestFirst ? crescente.reversed.toList() : crescente;
  final anoAtual = (now ?? DateTime.now()).year;

  return [
    for (final data in datas)
      (
        title: suggestionTargetLabel(data, currentYear: anoAtual),
        items: porData[data]!
      ),
    if (repertorio.isNotEmpty) (title: 'Para o repertório', items: repertorio),
  ];
}

/// "Domingo, 21 de setembro" (com o ano quando não é o atual).
String suggestionTargetLabel(DateTime date, {required int currentYear}) {
  final pattern = date.year == currentYear
      ? "EEEE, d 'de' MMMM"
      : "EEEE, d 'de' MMMM 'de' y";
  final texto = DateFormat(pattern, 'pt_BR').format(date);
  return texto.isEmpty ? texto : texto[0].toUpperCase() + texto.substring(1);
}

/// Uma sugestão como linha: título, motivo cortado, quem pediu.
///
/// Sem data: o grupo em que ela está já diz para quando. Sem botão: o toque
/// abre o detalhe, onde se lê o motivo inteiro antes de decidir.
class SuggestionRow extends StatelessWidget {
  const SuggestionRow({
    super.key,
    required this.suggestion,
    required this.teamId,
    required this.isMine,
  });

  final SongSuggestion suggestion;
  final String teamId;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = suggestion;

    return AppPressable(
      onTap: () => openSuggestionDetail(
        context,
        teamId: teamId,
        suggestion: s,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (s.artist ?? '').isEmpty
                        ? s.title
                        : '${s.title} · ${s.artist}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.reason,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      AppAvatar(
                        name: s.createdBy.displayName,
                        imageUrl: s.createdBy.avatarUrl,
                        radius: 9,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          _assinatura(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      SuggestionMaterialDots(materials: s.materials),
                      if (s.status.isResolved || s.isExpiredOn(today())) ...[
                        const SizedBox(width: AppSpacing.xs),
                        _selo(),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selo() => switch (suggestion.status) {
        SuggestionStatus.accepted => const AppBadge(
            label: 'Aceita',
            tone: AppTone.success,
            icon: Icons.check_circle_outline_rounded,
          ),
        SuggestionStatus.declined => const AppBadge(
            label: 'Recusada',
            tone: AppTone.neutral,
          ),
        // Só chega aqui a que venceu sem resposta (ver `isExpiredOn`).
        SuggestionStatus.pending => const AppBadge(
            label: 'Sem resposta',
            tone: AppTone.neutral,
          ),
      };

  String _assinatura() {
    final quem = isMine ? 'Você' : suggestion.createdBy.displayName;
    final outros = suggestion.alsoSuggestedBy;
    if (outros.isEmpty) return quem;
    // "+1", e não "+1 pessoa": ao lado dos materiais e do selo, a palavra
    // saía cortada ("Maria · +1 pess…") num celular de 375px. O nome de quem
    // mais sugeriu está no detalhe.
    return '$quem +${outros.length}';
  }
}

/// Quais materiais a sugestão trouxe, em ícones miúdos — os mesmos ícones de
/// recurso das músicas.
///
/// Só os que existem: link que ninguém mandou não vira ícone apagado, seria
/// promessa falsa.
class SuggestionMaterialDots extends StatelessWidget {
  const SuggestionMaterialDots({super.key, required this.materials});

  final List<SuggestionMaterial> materials;

  @override
  Widget build(BuildContext context) {
    if (materials.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final material in materials)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Tooltip(
              message: material.label,
              child: Icon(
                suggestionMaterialIcon(material.kind),
                size: 14,
                color: scheme.onSurfaceVariant,
                semanticLabel: material.label,
              ),
            ),
          ),
      ],
    );
  }
}

IconData suggestionMaterialIcon(SuggestionMaterialKind kind) => switch (kind) {
      SuggestionMaterialKind.lyrics => SongResourceIcons.lyrics,
      SuggestionMaterialKind.spotify => SongResourceIcons.spotify,
      SuggestionMaterialKind.youtube => SongResourceIcons.youtube,
    };
