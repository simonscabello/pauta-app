import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/app_brand_mark.dart';
import '../../../shared/widgets/app_button_styles.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../auth/application/auth_controller.dart';
import '../../profile/presentation/profile_photo.dart';
import '../application/tour_controller.dart';
import '../domain/member_tour.dart';
import 'tour_target.dart';

/// O tour por cima do app inteiro.
///
/// Mora no `builder` do `MaterialApp`, **acima do Navigator**: o tour troca de
/// tela entre uma parada e outra, e uma camada que pertencesse a uma página
/// sumiria junto com ela. Por estar acima do Navigator não há `Overlay` aqui —
/// nada nesta camada usa dica (`Tooltip`) nem menu.
class OnboardingTourHost extends ConsumerWidget {
  const OnboardingTourHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Em pausa (a pessoa foi preencher "Meus dados") o tour continua ativo,
    // mas não desenha nada: a tela de lá precisa dos toques e das folhas.
    final active = ref.watch(
      tourControllerProvider.select(
        (tour) => tour.isActive && tour.phase != TourPhase.paused,
      ),
    );

    return Stack(
      children: [
        child,
        if (active) const Positioned.fill(child: _TourLayer()),
      ],
    );
  }
}

/// Quanto o destaque sobra em volta do alvo, e o arredondado dele.
const double _holePadding = 6;
const double _holeRadius = AppSpacing.radiusLg;

/// Quanto tempo esperar o alvo aparecer (a tela nova carregando) antes de
/// mostrar a explicação sem destaque. Melhor o texto no meio da tela do que
/// um escuro parado esperando algo que não vem.
const Duration _targetTimeout = Duration(seconds: 3);

class _TourLayer extends ConsumerStatefulWidget {
  const _TourLayer();

  @override
  ConsumerState<_TourLayer> createState() => _TourLayerState();
}

class _TourLayerState extends ConsumerState<_TourLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _focusNode = FocusNode(debugLabel: 'tour');

  /// Onde o destaque está desenhado. Ele anda até o alvo medido em vez de
  /// saltar, para deslizar de uma parada para a outra na mesma tela.
  Rect? _shown;

  DateTime _waitingSince = DateTime.now();
  bool _gaveUp = false;
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    // No teclado inteiro, e não num `Focus` da camada: com o foco no botão,
    // as setas eram consumidas para andar entre botões e nunca chegavam aqui.
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _goToStep(ref.read(tourControllerProvider));
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _ticker.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Leva o app até a tela da parada e recomeça a procura pelo alvo.
  void _goToStep(TourState tour) {
    _gaveUp = false;
    _scrolled = false;
    _waitingSince = DateTime.now();

    final route = tour.step?.route;
    if (route == null) return;
    final router = ref.read(routerProvider);
    final here = router.routerDelegate.currentConfiguration.uri.path;
    // `go`, e não `push`: o tour troca de aba, e empilhar deixaria a barra
    // inferior apontando para um lugar e a tela mostrando outro.
    if (here != route) router.go(route);
  }

  /// A cada quadro: onde o alvo está agora. A tela rola, carrega, gira — medir
  /// sempre é o que mantém o destaque em cima da coisa certa.
  void _onTick(Duration _) {
    final tour = ref.read(tourControllerProvider);
    final targetId = tour.step?.target;
    Rect? measured;

    if (targetId != null && !_gaveUp) {
      measured = _measure(targetId);
      if (measured == null &&
          DateTime.now().difference(_waitingSince) > _targetTimeout) {
        setState(() => _gaveUp = true);
        return;
      }
    }

    final previous = _shown;
    Rect? next = measured;
    if (measured != null &&
        previous != null &&
        !MediaQuery.of(context).disableAnimations) {
      next = Rect.lerp(previous, measured, 0.25)!;
      if (_close(next, measured)) next = measured;
    }

    final changed = next == null || previous == null
        ? next != previous
        : !_close(next, previous);
    if (changed) setState(() => _shown = next);
  }

  static bool _close(Rect a, Rect b) =>
      (a.left - b.left).abs() < 0.5 &&
      (a.top - b.top).abs() < 0.5 &&
      (a.right - b.right).abs() < 0.5 &&
      (a.bottom - b.bottom).abs() < 0.5;

  Rect? _measure(String id) {
    final targetContext = TourTarget.contextOf(id);
    final box = targetContext?.findRenderObject();
    final layer = context.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        layer is! RenderBox ||
        !layer.hasSize) {
      return null;
    }

    // Uma vez por parada: rola a tela até o alvo, com folga em cima para o
    // cartão caber embaixo dele.
    if (!_scrolled) {
      _scrolled = true;
      Scrollable.ensureVisible(
        targetContext!,
        alignment: 0.15,
        duration: MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : AppMotion.slow,
        curve: AppMotion.standard,
      );
    }

    final origin = layer.globalToLocal(box.localToGlobal(Offset.zero));
    return (origin & box.size).inflate(_holePadding);
  }

  // Nos três finais, o aviso e o roteador vêm **antes** de encerrar: ao
  // encerrar o tour esta camada sai da árvore, e depois disso não há mais
  // `context` para mostrar nada. O aviso sobrevive à troca de tela porque
  // quem o guarda é o `ScaffoldMessenger`, acima das páginas.

  Future<void> _skip() async {
    final tour = ref.read(tourControllerProvider);
    final router = ref.read(routerProvider);
    if (!tour.manual) _showHelpHint();
    final origin = await ref.read(tourControllerProvider.notifier).skip();
    if (origin != null &&
        router.routerDelegate.currentConfiguration.uri.path != origin) {
      router.go(origin);
    }
  }

  /// Quem pulou precisa saber onde achar depois — senão o "depois" vira
  /// "nunca".
  void _showHelpHint() {
    showAppSnackBar(
      context,
      'Tudo bem! Quando quiser, é só abrir Perfil › Ajuda.',
    );
  }

  Future<void> _finish() async {
    final router = ref.read(routerProvider);
    await ref.read(tourControllerProvider.notifier).finish();
    if (router.routerDelegate.currentConfiguration.uri.path != '/inicio') {
      router.go('/inicio');
    }
  }

  /// Teclado de quem usa a versão Web: setas andam, Esc pula.
  bool _onHardwareKey(KeyEvent event) =>
      mounted && _onKey(event) == KeyEventResult.handled;

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final tour = ref.read(tourControllerProvider);
    final controller = ref.read(tourControllerProvider.notifier);
    final key = event.logicalKey;

    // Esc nas boas-vindas não faz nada: o primeiro acesso passa pelo tour.
    if (key == LogicalKeyboardKey.escape) {
      if (tour.phase == TourPhase.touring) {
        _skip();
      } else if (tour.phase == TourPhase.profile) {
        controller.continueFromProfile();
      }
      return KeyEventResult.handled;
    }
    if (tour.phase == TourPhase.touring ||
        tour.phase == TourPhase.profile ||
        tour.phase == TourPhase.finished) {
      if (key == LogicalKeyboardKey.arrowRight &&
          tour.phase == TourPhase.touring) {
        controller.next();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        controller.back();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TourState>(tourControllerProvider, (previous, next) {
      final changedStep = next.phase == TourPhase.touring &&
          (previous?.phase != TourPhase.touring ||
              previous?.index != next.index ||
              !identical(previous?.steps, next.steps));
      if (changedStep) _goToStep(next);
    });

    final tour = ref.watch(tourControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scrim = Colors.black.withValues(alpha: dark ? 0.72 : 0.62);
    final step = tour.step;
    final waitingTarget = step?.target != null && _shown == null && !_gaveUp;

    final Widget card = switch (tour.phase) {
      TourPhase.idle => const SizedBox.shrink(),
      TourPhase.welcome => _WelcomeCard(
          onStart: () => ref.read(tourControllerProvider.notifier).start(),
        ),
      TourPhase.preparing || TourPhase.paused => const SizedBox.shrink(),
      // Esperando a tela nova montar o alvo: um indicador, e não o escuro
      // vazio — três segundos de tela preta parecem app travado.
      TourPhase.touring => waitingTarget
          ? const _WaitingIndicator()
          : _StepCard(
              key: ValueKey(tour.index),
              step: step!,
              index: tour.index,
              total: tour.steps.length,
              onNext: ref.read(tourControllerProvider.notifier).next,
              onBack: tour.isFirst
                  ? null
                  : ref.read(tourControllerProvider.notifier).back,
              onSkip: _skip,
            ),
      TourPhase.profile => _ProfileCard(
          onEditData: ref.read(tourControllerProvider.notifier).editProfileData,
          onContinue:
              ref.read(tourControllerProvider.notifier).continueFromProfile,
          onBack: ref.read(tourControllerProvider.notifier).back,
        ),
      TourPhase.finished => _FinishedCard(
          onStart: _finish,
          onBack: ref.read(tourControllerProvider.notifier).back,
        ),
    };

    final hole = tour.phase == TourPhase.touring ? _shown : null;

    return Focus(
      focusNode: _focusNode,
      child: BlockSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: AppMotion.normal,
            builder: (context, opacity, child) =>
                Opacity(opacity: opacity, child: child),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // O escuro engole os toques: durante o tour, o app embaixo é
                // para ver, não para usar — um toque solto levaria a pessoa
                // para fora do caminho sem jeito de voltar.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: CustomPaint(
                    painter: _ScrimPainter(
                      hole: hole,
                      color: scrim,
                      ring: dark ? scheme.primary : Colors.white,
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: CustomSingleChildLayout(
                      delegate: _CardLayout(
                        hole: hole,
                        insets: MediaQuery.paddingOf(context),
                      ),
                      child: AnimatedSwitcher(
                        duration: AppMotion.normal,
                        child: card,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Escurece tudo menos o alvo, e contorna o alvo com um fio claro.
class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.hole, required this.color, required this.ring});

  final Rect? hole;
  final Color color;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final hole = this.hole;
    if (hole == null) {
      canvas.drawPath(full, Paint()..color = color);
      return;
    }
    final rrect =
        RRect.fromRectAndRadius(hole, const Radius.circular(_holeRadius));
    // Par-ímpar, e não `Path.combine(difference, ...)`: no Flutter Web a
    // diferença saía sem o furo — o alvo ficava escurecido como o resto, só
    // com o contorno em volta. O retângulo com o furo dentro, preenchido por
    // par-ímpar, dá o mesmo desenho em todos os renderizadores.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(rrect),
      Paint()..color = color,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole || old.color != color || old.ring != ring;
}

/// Põe o cartão onde ele não cobre o alvo: embaixo se couber, em cima se não,
/// e no pé da tela quando o alvo ocupa quase tudo. Sem alvo, no meio.
class _CardLayout extends SingleChildLayoutDelegate {
  _CardLayout({required this.hole, required this.insets});

  /// Em coordenadas da camada inteira; este layout está dentro do recuo da
  /// área segura e da margem, e desconta os dois.
  final Rect? hole;
  final EdgeInsets insets;

  static const double _gap = AppSpacing.md;
  static const double _maxWidth = 420;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = math.min(constraints.maxWidth, _maxWidth);
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    final hole = this.hole;
    if (hole == null) {
      return Offset(
        (size.width - child.width) / 2,
        (size.height - child.height) / 2,
      );
    }

    // Do sistema da camada para o deste layout.
    final shift =
        Offset(insets.left + AppSpacing.lg, insets.top + AppSpacing.lg);
    final local = hole.shift(-shift);

    final below = size.height - local.bottom - _gap;
    final above = local.top - _gap;
    final double top;
    if (child.height <= below) {
      top = local.bottom + _gap;
    } else if (child.height <= above) {
      top = local.top - _gap - child.height;
    } else {
      top = size.height - child.height;
    }

    final left = (local.center.dx - child.width / 2)
        .clamp(0.0, math.max(0.0, size.width - child.width))
        .toDouble();
    return Offset(
      left,
      top.clamp(0.0, math.max(0.0, size.height - child.height)).toDouble(),
    );
  }

  @override
  bool shouldRelayout(_CardLayout old) =>
      old.hole != hole || old.insets != insets;
}

/// A superfície dos três cartões do tour.
class _TourCard extends StatelessWidget {
  const _TourCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: AppElevation.overlay(scheme),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: SingleChildScrollView(child: child),
    );
  }
}

/// As boas-vindas do primeiro acesso.
///
/// **Sem "Agora não".** Com ele, quase todo mundo dizia não e nunca mais via o
/// tour — que é curto justamente para caber no primeiro acesso. Quem quiser
/// sair no meio tem o "Pular" de cada parada.
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Boas-vindas ao Pauta',
      child: _TourCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.sm),
            const Align(
              alignment: Alignment.centerLeft,
              child: AppBrandMark(size: 48),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Boas-vindas ao Pauta 👋',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Aqui você encontra tudo o que precisa para participar da sua '
              'equipe de louvor.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Veja suas escalas, prepare as músicas, informe sua '
              'disponibilidade, acompanhe os compromissos e participe da vida '
              'da equipe.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              autofocus: true,
              onPressed: onStart,
              child: const Text('Conhecer o Pauta'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    super.key,
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final TourStep step;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final last = index == total - 1;

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      liveRegion: true,
      explicitChildNodes: true,
      label: '${step.title}. Passo ${index + 1} de $total',
      child: _TourCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${index + 1} DE $total',
                    style: AppTypography.eyebrow(context).copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
                TextButton(
                  style: AppButtonStyles.compactText,
                  onPressed: onSkip,
                  child: const Text('Pular'),
                ),
              ],
            ),
            Text(step.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              step.body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                if (onBack != null)
                  TextButton(
                    style: AppButtonStyles.compactText,
                    onPressed: onBack,
                    child: const Text('Voltar'),
                  ),
                const Spacer(),
                FilledButton(
                  style: AppButtonStyles.compact,
                  autofocus: true,
                  onPressed: onNext,
                  child: Text(last ? 'Concluir' : 'Próximo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Esperando a tela da parada montar o alvo.
class _WaitingIndicator extends StatelessWidget {
  const _WaitingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Center(
      heightFactor: 1,
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
      ),
    );
  }
}

/// "Complete seu perfil": a foto e os dados, antes do final.
///
/// **A foto é escolhida aqui mesmo**: o seletor de imagem é do sistema, e não
/// uma tela do app — abre por cima de tudo, inclusive desta camada. Os dados
/// não: a data de nascimento abre um calendário, que precisa do Navigator
/// embaixo do escuro. Por isso "Preencher agora" pausa o tour, abre "Meus
/// dados" e o tour volta sozinho quando a pessoa sai de lá.
///
/// O telefone não está aqui: ele é da equipe, e quem o cadastra é a liderança.
class _ProfileCard extends ConsumerStatefulWidget {
  const _ProfileCard({
    required this.onEditData,
    required this.onContinue,
    required this.onBack,
  });

  final VoidCallback onEditData;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  bool _busy = false;
  String? _error;

  /// A câmera só no aplicativo: no navegador o seletor de arquivo do próprio
  /// celular já oferece a câmera.
  static bool get _offersCamera =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _choose(ImageSource source) async {
    setState(() => _error = null);
    try {
      final picked = await pickAvatarImage(source);
      if (picked == null || !mounted) return;
      setState(() => _busy = true);
      await uploadAvatarImage(ref, picked);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível usar esta imagem.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final success = AppStatusColors.of(context).success;
    final user = ref.watch(authControllerProvider).user;
    if (user == null) return const SizedBox.shrink();

    final hasPhoto = user.avatarUrl != null;
    final hasData = user.birthDate != null;

    Widget done(String text) => Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 20,
              color: success.foreground,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          ],
        );

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Complete seu perfil',
      child: _TourCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Text('Complete seu perfil', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Com a sua foto, a equipe te reconhece na escala. A data de '
              'nascimento faz a equipe lembrar do seu aniversário — ela vê só '
              'o dia e o mês.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    AppAvatar(
                      name: user.name,
                      imageUrl: user.avatarUrl,
                      radius: 28,
                    ),
                    if (_busy)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: hasPhoto && !_busy
                      ? done('Foto cadastrada')
                      : Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            FilledButton.tonal(
                              style: AppButtonStyles.compact,
                              onPressed: _busy
                                  ? null
                                  : () => _choose(ImageSource.gallery),
                              child: const Text('Escolher foto'),
                            ),
                            if (_offersCamera)
                              TextButton(
                                style: AppButtonStyles.compactText,
                                onPressed: _busy
                                    ? null
                                    : () => _choose(ImageSource.camera),
                                child: const Text('Tirar foto'),
                              ),
                          ],
                        ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (hasData)
              done('Data de nascimento cadastrada')
            else
              // Texto e botão empilhados: lado a lado não cabem num celular
              // estreito, e o botão cortado é o que se toca errado.
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Data de nascimento e gênero',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  FilledButton.tonal(
                    style: AppButtonStyles.compact,
                    onPressed: _busy ? null : widget.onEditData,
                    child: const Text('Preencher agora'),
                  ),
                ],
              ),
            const SizedBox(height: AppSpacing.xl),
            // Empilhados, como no "Tudo pronto!": "Deixar para depois" e
            // "Voltar" lado a lado não cabem em 320px.
            FilledButton(
              autofocus: true,
              onPressed: _busy ? null : widget.onContinue,
              child: Text(
                hasPhoto || hasData ? 'Continuar' : 'Deixar para depois',
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(onPressed: widget.onBack, child: const Text('Voltar')),
          ],
        ),
      ),
    );
  }
}

class _FinishedCard extends StatelessWidget {
  const _FinishedCard({required this.onStart, required this.onBack});

  final VoidCallback onStart;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final success = AppStatusColors.of(context).success;

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Tudo pronto',
      child: _TourCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Icon(
                Icons.check_circle_rounded,
                size: 40,
                color: success.foreground,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Tudo pronto! 🎵', style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Agora você já sabe onde encontrar suas escalas, preparar as '
              'músicas, informar sua disponibilidade e acompanhar sua equipe.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Se precisar, a Ajuda fica no Perfil.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              autofocus: true,
              onPressed: onStart,
              child: const Text('Começar'),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(onPressed: onBack, child: const Text('Voltar')),
          ],
        ),
      ),
    );
  }
}

/// Abre o tour dos integrantes a pedido (Ajuda → Conhecer o Pauta).
///
/// Não passa pelas boas-vindas — quem tocou em "Conhecer o Pauta" já disse
/// que quer — e não grava nada no servidor.
void startTourManually(WidgetRef ref, BuildContext context) {
  ref.read(tourControllerProvider.notifier).start(
        manual: true,
        origin: GoRouterState.of(context).uri.path,
      );
}
