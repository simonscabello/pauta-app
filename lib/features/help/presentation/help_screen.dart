import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/open_link.dart';
import '../../auth/application/auth_controller.dart';
import '../../onboarding/presentation/tour_overlay.dart';
import '../domain/help_faq.dart';

/// A Central de Ajuda (`/perfil/ajuda`).
///
/// **Duas coisas, e só duas.** "Conhecer o Pauta" refaz o tour — que ensina
/// mostrando a tela de verdade, e por isso vem primeiro — e as perguntas
/// frequentes respondem o que o tour não cabe. Sem busca, sem categorias, sem
/// cartão por pergunta: são nove perguntas, e uma lista que abre e fecha no
/// lugar é o que menos pesa para quem tem pouca intimidade com aplicativo.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Quem lidera **alguma** equipe: a dúvida de como publicar não depende
    // de qual equipe está ativa agora.
    final lidera =
        ref.watch(authControllerProvider).teams.any((t) => t.canManage);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajuda')),
      body: SafeArea(
        top: false,
        child: AppContentWidth.reading(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.lg,
              AppSpacing.screenPadding,
              AppSpacing.xxl,
            ),
            children: [
              AppGroup(
                children: [
                  AppGroupRow(
                    icon: Icons.explore_outlined,
                    title: 'Conhecer o Pauta',
                    subtitle: 'Veja novamente como funcionam as principais '
                        'áreas do aplicativo.',
                    onTap: () => startTourManually(ref, context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              AppGroup(
                title: 'Perguntas frequentes',
                dividerIndent: AppGroup.textIndent,
                children: [
                  for (final entry in helpFaq) FaqTile(entry: entry),
                ],
              ),
              if (lidera) ...[
                const SizedBox(height: AppSpacing.xxl),
                AppGroup(
                  title: 'Para quem lidera',
                  dividerIndent: AppGroup.textIndent,
                  children: [
                    for (final entry in leaderHelpFaq) FaqTile(entry: entry),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
              // Páginas públicas do site: abrem no navegador, e são as mesmas
              // que o cadastro cita.
              AppGroup(
                title: 'Sobre o Pauta',
                children: [
                  AppGroupRow(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Política de privacidade',
                    onTap: () =>
                        openExternalLink(context, AppConfig.privacyUrl),
                  ),
                  AppGroupRow(
                    icon: Icons.gavel_rounded,
                    title: 'Termos de uso',
                    onTap: () => openExternalLink(context, AppConfig.termsUrl),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uma pergunta que abre a resposta no próprio lugar.
///
/// Abre uma de cada vez? Não: quem compara duas respostas ("sugerir" e
/// "repertório") precisa das duas abertas. Cada linha cuida de si.
class FaqTile extends StatefulWidget {
  const FaqTile({super.key, required this.entry});

  final FaqEntry entry;

  @override
  State<FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<FaqTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final motion = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : AppMotion.normal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          onTapHint: _open ? 'fechar a resposta' : 'abrir a resposta',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              hoverColor: scheme.onSurface.withValues(alpha: 0.04),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSpacing.touchTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.entry.question,
                          style: theme.textTheme.titleSmall?.copyWith(
                            // Aberta, a pergunta ganha a cor de "é aqui que
                            // você está": numa lista de nove, é o que diz de
                            // quem é a resposta embaixo.
                            color: _open ? scheme.primary : scheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: motion,
                        curve: AppMotion.standard,
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 22,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: motion,
          curve: AppMotion.standard,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.xl,
                    AppSpacing.lg,
                  ),
                  child: Text.rich(
                    faqAnswerSpans(
                      widget.entry.answer,
                      bold: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// O texto da resposta com os `**realces**` em negrito.
TextSpan faqAnswerSpans(String answer, {required TextStyle bold}) {
  final parts = answer.split('**');
  return TextSpan(
    children: [
      for (var i = 0; i < parts.length; i++)
        if (parts[i].isNotEmpty)
          TextSpan(text: parts[i], style: i.isOdd ? bold : null),
    ],
  );
}
