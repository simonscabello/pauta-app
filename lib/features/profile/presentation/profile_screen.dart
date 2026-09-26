import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/push/push_coordinator.dart';
import '../../../core/push/push_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_colors.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../shared/widgets/app_badge.dart';
import '../../../shared/widgets/app_choice_bar.dart';
import '../../../shared/widgets/app_content_width.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_group.dart';
import '../../../shared/widgets/greeting_header.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/team_picker.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/biometric_service.dart';
import '../../auth/domain/auth_models.dart';
import '../../team/data/team_repository.dart';
import '../../onboarding/domain/member_tour.dart';
import '../../onboarding/presentation/tour_target.dart';
import 'profile_photo.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (user == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AppContentWidth.reading(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              0,
              0,
              0,
              AppSpacing.screenPadding,
            ),
            children: [
              // O título grande das outras abas ([TabHeader]), sem a linha da
              // equipe: o Perfil é da pessoa, e a equipe é uma linha abaixo.
              const TabHeader(title: 'Perfil'),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // O nome sobe para o tamanho de manchete. É a única coisa nesta
                    // tela que identifica de quem ela é, e estava no mesmo corpo dos
                    // títulos de bloco logo abaixo.
                    Row(
                      children: [
                        const ProfilePhoto(radius: 34),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.name,
                                style: theme.textTheme.headlineSmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user.email,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    // "Minha disponibilidade" abre a tela e saiu de "Equipe". Não é
                    // uma configuração: é a única coisa que um integrante **faz**
                    // neste app além de ler a escala, e estava enterrada abaixo de
                    // "Meus dados" e "Alterar senha" — dois itens que se mexe uma
                    // vez na vida.
                    AppGroup(
                      title: 'Minha participação',
                      children: [
                        AppGroupRow(
                          icon: Icons.event_busy_outlined,
                          title: 'Minha disponibilidade',
                          subtitle: 'Os dias em que você não pode ser escalado',
                          onTap: () => context.push('/disponibilidade'),
                        ),
                        _TeamRow(teams: auth.teams),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.xxl),
                    AppGroup(
                      title: 'Conta',
                      children: [
                        AppGroupRow(
                          icon: Icons.badge_outlined,
                          title: 'Meus dados',
                          // A foto se troca tocando no avatar aqui em cima, que já
                          // tem o selo de câmera. Repeti-la dentro de "Meus dados"
                          // daria dois caminhos para o mesmo gesto.
                          subtitle: 'Nome, e-mail e data de nascimento',
                          onTap: () => context.push('/perfil/dados'),
                        ),
                        // Condicional aqui, e nao so dentro da linha: o grupo
                        // desenha o divisor antes de cada filho, mesmo vazio.
                        if (PushService.isSupported)
                          const _PushNotificationsRow(),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.xxl),
                    AppGroup(
                      title: 'Segurança',
                      children: [
                        AppGroupRow(
                          icon: Icons.lock_outline_rounded,
                          title: 'Alterar senha',
                          subtitle: 'Você precisa da senha atual',
                          onTap: () => context.push('/perfil/senha'),
                        ),
                        if (ref
                                .watch(biometricsAvailableProvider)
                                .valueOrNull ==
                            true)
                          const _BiometricRow(),
                        // Em Segurança, e não em Conta: o que se faz aqui é
                        // abrir e fechar portas para um programa de fora.
                        AppGroupRow(
                          icon: Icons.smart_toy_outlined,
                          title: 'Assistentes de IA',
                          subtitle: 'Claude e outros, só para consulta',
                          onTap: () => context.push('/perfil/assistentes'),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.xxl),
                    const SectionHeader(
                      title: 'Aparência',
                      subtitle: 'Vale só neste aparelho.',
                      padding: EdgeInsets.only(
                        left: AppSpacing.xs,
                        bottom: AppSpacing.md,
                      ),
                    ),
                    const _ThemeModeCard(),

                    const SizedBox(height: AppSpacing.xxl),
                    // Sair e diagnóstico viraram linhas de um grupo, no fim da tela.
                    // Como botão vermelho de largura inteira, "Sair" era o elemento
                    // mais pesado do Perfil — e ele é a coisa que menos se faz ali. O
                    // vermelho fica no texto, que basta para avisar o que é.
                    AppGroup(
                      dividerIndent: AppGroup.iconIndent,
                      children: [
                        // Junto do diagnóstico, no fim: é para quando algo
                        // não está claro, e não uma coisa do dia a dia.
                        AppGroupRow(
                          icon: Icons.help_outline_rounded,
                          title: 'Ajuda',
                          subtitle: 'Conhecer o Pauta e perguntas frequentes',
                          onTap: () => context.push('/perfil/ajuda'),
                        ),
                        AppGroupRow(
                          icon: Icons.wifi_tethering_rounded,
                          title: 'Diagnóstico de conexão',
                          onTap: () => context.push('/diagnostico'),
                        ),
                        AppGroupRow(
                          icon: Icons.logout_rounded,
                          title: 'Sair da conta',
                          tone: AppTone.danger,
                          showChevron: false,
                          onTap: () => _confirmLogout(context, ref),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sair passou a perguntar.
  ///
  /// Era um toque só, num botão que fica logo abaixo de "Tema" — e voltar custa
  /// digitar e-mail e senha, que é justamente o que quem usa o app no meio do
  /// culto não vai querer fazer. A pergunta também lembra que a sessão é do
  /// aparelho, não da equipe.
  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sair da conta?',
      message: 'Para voltar você vai precisar do e-mail e da senha. As escalas '
          'da equipe continuam onde estão.',
      confirmLabel: 'Sair',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(authControllerProvider.notifier).logout();
  }
}

class _BiometricRow extends ConsumerStatefulWidget {
  const _BiometricRow();

  @override
  ConsumerState<_BiometricRow> createState() => _BiometricRowState();
}

class _BiometricRowState extends ConsumerState<_BiometricRow> {
  bool _available = false;
  bool _enabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = ref.read(authControllerProvider.notifier);
    final available = await auth.biometricsAvailable;
    final enabled = available && await auth.biometricsEnabled;
    if (mounted) {
      setState(() {
        _available = available;
        _enabled = enabled;
      });
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    final auth = ref.read(authControllerProvider.notifier);
    if (value) {
      final enabled = await auth.enableBiometrics();
      if (mounted && !enabled) {
        showAppSnackBar(context, 'Biometria não confirmada. Tente novamente.');
      }
    } else {
      await auth.disableBiometrics();
    }
    if (mounted) {
      setState(() => _busy = false);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    return SwitchListTile.adaptive(
      secondary: const Icon(Icons.fingerprint),
      title: const Text('Entrar com biometria'),
      subtitle: const Text('Segurança deste aparelho'),
      value: _enabled,
      onChanged: _busy ? null : _toggle,
    );
  }
}

/// O interruptor dos avisos no celular.
///
/// **Diz quando o Android esta bloqueando.** Sem isso o interruptor fica ligado,
/// nada chega, e a culpa parece ser do app -- que e o pior desfecho possivel
/// para uma tela de configuracao.
class _PushNotificationsRow extends ConsumerStatefulWidget {
  const _PushNotificationsRow();

  @override
  ConsumerState<_PushNotificationsRow> createState() =>
      _PushNotificationsRowState();
}

class _PushNotificationsRowState extends ConsumerState<_PushNotificationsRow> {
  bool _saving = false;
  bool _blockedBySystem = false;

  @override
  void initState() {
    super.initState();
    _refreshSystemPermission();
  }

  Future<void> _refreshSystemPermission() async {
    if (!PushService.isSupported) return;
    final permitido = await ref.read(pushServiceProvider).hasPermission();
    if (mounted) setState(() => _blockedBySystem = !permitido);
  }

  Future<void> _toggle(bool value) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .updateProfile(pushEnabled: value);

      if (value) {
        // Religar tem duas metades: a conta volta a aceitar aviso, e o
        // aparelho precisa estar registrado e com permissao. Pedir aqui e o
        // segundo momento legitimo -- a pessoa acabou de dizer que quer.
        final permitido =
            await ref.read(pushServiceProvider).requestPermission();
        if (mounted) setState(() => _blockedBySystem = !permitido);
        await ref.read(pushCoordinatorProvider).registerDevice();
      }
    } on ApiException catch (error) {
      if (mounted) {
        showAppSnackBar(context, error.message, tone: AppTone.danger);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ligado = ref.watch(authControllerProvider).user?.pushEnabled ?? true;

    // Sem push na plataforma (Web e desktop hoje), a linha nao aparece: um
    // interruptor que nao liga nada e pior do que interruptor nenhum.
    if (!PushService.isSupported) return const SizedBox.shrink();

    return TourTarget(
      id: TourTargetIds.profilePush,
      child: _row(ligado),
    );
  }

  Widget _row(bool ligado) {
    return AppGroupRow(
      icon: Icons.notifications_active_outlined,
      title: 'Avisos no celular',
      subtitle: ligado && _blockedBySystem
          ? 'Bloqueado nos ajustes do Android'
          : 'Escala publicada, trocas e repertório',
      showChevron: false,
      trailing: Switch(
        value: ligado,
        onChanged: _saving ? null : _toggle,
      ),
    );
  }
}

/// Claro, Escuro e Sistema — no mesmo controle de escolha do resto do app.
///
/// Era um `SegmentedButton`, e num celular estreito ele quebrava: três rótulos
/// com ícone dentro de um cartão com folga de 16px de cada lado não cabem em
/// 320px, e o Material resolvia isso desmanchando o texto em duas linhas
/// dentro do segmento. Quem tem a fonte do sistema aumentada via o mesmo
/// defeito em qualquer largura.
///
/// [AppChoiceBar] em `expanded` é a resposta que o app já tinha: as três
/// opções dividem a largura em partes iguais, cada uma com o mesmo alvo de
/// toque, e quando o rótulo não cabe ao lado do ícone **as três** passam a
/// mostrar o ícone em cima. A folga do cartão encolheu de `lg` para `md` pelo
/// mesmo motivo — são 8px de largura que voltam para os segmentos, e a barra
/// já tem a folga interna dela.
///
/// "Sistema" é o padrão e vem por último, ao lado das duas escolhas manuais:
/// quem já deixou o Android no escuro não precisa mexer aqui.
class _ThemeModeCard extends ConsumerWidget {
  const _ThemeModeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    // Sem cartão em volta: a barra já tem a superfície dela, e o cartão fazia
    // um container dentro de outro.
    return AppChoiceBar<ThemeMode>(
      expanded: true,
      value: mode,
      onChanged: (option) =>
          ref.read(themeModeProvider.notifier).select(option),
      options: [
        for (final option in [
          ThemeMode.light,
          ThemeMode.dark,
          ThemeMode.system,
        ])
          AppChoice(
            value: option,
            label: themeModeLabel(option),
            icon: _iconFor(option),
          ),
      ],
    );
  }

  IconData _iconFor(ThemeMode mode) => switch (mode) {
        ThemeMode.system => Icons.brightness_auto_rounded,
        ThemeMode.light => Icons.light_mode_rounded,
        ThemeMode.dark => Icons.dark_mode_rounded,
      };
}

/// A equipe da pessoa, como linha do mesmo grupo.
///
/// Era um cartão só para si, logo abaixo de outro cartão — dois retângulos para
/// duas informações do mesmo assunto.
/// A equipe ativa, e o caminho para trocar de equipe.
///
/// Mostrava a **primeira** equipe da lista, e não a ativa — errado justamente
/// para quem serve em duas, que é quem precisa desta linha. E não levava a
/// lugar nenhum: no celular, trocar de equipe só existia no cabeçalho da Home
/// e da Agenda. Com duas ou mais equipes, a linha abre o mesmo seletor delas.
class _TeamRow extends ConsumerWidget {
  const _TeamRow({required this.teams});

  final List<TeamSummary> teams;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (teams.isEmpty) {
      return const AppGroupRow(
        icon: Icons.groups_outlined,
        title: 'Sem equipe',
        subtitle: 'Você ainda não faz parte de uma equipe.',
        showChevron: false,
      );
    }

    final activeId = ref.watch(activeTeamIdProvider);
    final team =
        teams.where((t) => t.teamId == activeId).firstOrNull ?? teams.first;
    final canSwitch = teams.length > 1;

    return AppGroupRow(
      icon: Icons.groups_outlined,
      title: team.name,
      subtitle:
          canSwitch ? 'Sua equipe ativa · toque para trocar' : 'Sua equipe',
      showChevron: false,
      trailing: AppBadge(
        label: roleLabel(team.role),
        tone: team.role == 'MEMBER' ? AppTone.neutral : AppTone.primary,
        semanticsLabel: 'Seu papel na equipe: ${roleLabel(team.role)}',
      ),
      onTap: canSwitch
          ? () async {
              final id = await showTeamPicker(
                context,
                teams: [
                  for (final item in teams) (id: item.teamId, name: item.name),
                ],
                activeTeamId: team.teamId,
              );
              if (id != null) {
                ref.read(activeTeamIdProvider.notifier).select(id);
              }
            }
          : null,
    );
  }
}

String roleLabel(String role) => switch (role) {
      'OWNER' => 'Dono',
      'LEADER' => 'Líder',
      _ => 'Membro',
    };
