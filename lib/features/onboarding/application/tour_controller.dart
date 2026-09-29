import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/push/push_service.dart';
import '../../../core/router/app_router.dart';
import '../../auth/application/auth_controller.dart';
import '../../events/data/event_repository.dart';
import '../../home/domain/home_summary.dart';
import '../../team/data/team_repository.dart';
import '../data/onboarding_repository.dart';
import '../domain/member_tour.dart';
import '../domain/onboarding_models.dart';

enum TourPhase {
  /// Nada na tela.
  idle,

  /// As boas-vindas, com "Conhecer o Pauta" — e só com ele: o primeiro
  /// acesso passa pelo tour. Dentro dele, "Pular" continua valendo.
  welcome,

  /// Montando o caminho (a próxima escala ainda está chegando).
  preparing,

  /// Uma parada destacada.
  touring,

  /// "Complete seu perfil": a foto e os dados, entre a última parada e o
  /// final. Só existe quando falta a foto ou a data de nascimento.
  profile,

  /// A pessoa foi preencher "Meus dados". O tour continua ativo (não se
  /// reoferece nada), mas nada é desenhado por cima da tela; ao sair de lá,
  /// volta para [profile].
  paused,

  /// "Tudo pronto!".
  finished,
}

class TourState {
  const TourState({
    this.phase = TourPhase.idle,
    this.steps = const [],
    this.index = 0,
    this.manual = false,
    this.origin,
    this.showedProfile = false,
  });

  final TourPhase phase;
  final List<TourStep> steps;
  final int index;

  /// Aberto pela Ajuda. **Rever não grava nada**: o registro no servidor
  /// responde "o app ainda deve oferecer?", e quem pediu para ver de novo já
  /// respondeu a isso antes.
  final bool manual;

  /// Onde a pessoa estava quando o tour começou. Pular devolve a pessoa para
  /// lá — quem abriu pela Ajuda volta para a Ajuda.
  final String? origin;

  /// Se "Complete seu perfil" apareceu neste tour — é para lá que o "Voltar"
  /// do final leva, mesmo que a pessoa já tenha preenchido tudo.
  final bool showedProfile;

  bool get isActive => phase != TourPhase.idle;
  TourStep? get step =>
      phase == TourPhase.touring && index < steps.length ? steps[index] : null;
  bool get isFirst => index == 0;

  TourState copyWith({
    TourPhase? phase,
    List<TourStep>? steps,
    int? index,
    bool? manual,
    String? origin,
    bool? showedProfile,
  }) {
    return TourState(
      phase: phase ?? this.phase,
      steps: steps ?? this.steps,
      index: index ?? this.index,
      manual: manual ?? this.manual,
      origin: origin ?? this.origin,
      showedProfile: showedProfile ?? this.showedProfile,
    );
  }
}

/// A rota de "Meus dados", para onde "Complete seu perfil" leva.
const profileDataRoute = '/perfil/dados';

/// O estado do tour de primeiro acesso, de ponta a ponta.
///
/// Quem desenha é o `OnboardingTourHost`, que fica acima de todas as telas;
/// este controlador só decide em que parada se está e **o que fica
/// registrado** — e só registra quando o tour foi oferecido pelo app, nunca
/// quando a pessoa pediu para rever.
class TourController extends StateNotifier<TourState> {
  TourController(this._ref) : super(const TourState()) {
    // Sair da conta no meio do tour não pode deixar o escuro por cima da tela
    // de login — nem a próxima pessoa a entrar começar na parada 4.
    _ref.listen<AuthStatus>(
      authControllerProvider.select((auth) => auth.status),
      (_, status) {
        if (status != AuthStatus.authenticated) {
          _offeredFor = null;
          _stopWatchingRoute();
          state = const TourState();
        }
      },
    );
  }

  final Ref _ref;

  /// A conta para quem as boas-vindas já apareceram nesta abertura do app.
  /// Evita reoferecer enquanto a resposta ainda está a caminho do servidor.
  String? _offeredFor;

  /// As boas-vindas, se ainda não apareceram nesta abertura.
  void offerWelcome() {
    final userId = _ref.read(authControllerProvider).user?.id;
    if (userId == null || state.isActive || _offeredFor == userId) return;
    _offeredFor = userId;
    state = const TourState(phase: TourPhase.welcome, origin: '/inicio');
  }

  /// Começa pela primeira parada — vindo das boas-vindas ou da Ajuda.
  Future<void> start({bool manual = false, String? origin}) async {
    final wasManual = manual || state.manual;
    final from = origin ?? state.origin ?? '/inicio';
    state = TourState(
      phase: TourPhase.preparing,
      manual: wasManual,
      origin: from,
    );

    final steps = memberTourSteps(
      MemberTourContext(
        nextScheduleId: await _nextScheduleId(),
        pushSupported: PushService.isSupported,
      ),
    );
    // Cancelado enquanto a escala chegava (saiu da conta, por exemplo).
    if (state.phase != TourPhase.preparing) return;

    state = state.copyWith(phase: TourPhase.touring, steps: steps, index: 0);
  }

  void next() {
    if (state.phase != TourPhase.touring) return;
    if (state.index < state.steps.length - 1) {
      state = state.copyWith(index: state.index + 1);
    } else if (_profileIncomplete) {
      state = state.copyWith(phase: TourPhase.profile, showedProfile: true);
    } else {
      state = state.copyWith(phase: TourPhase.finished);
    }
  }

  void back() {
    switch (state.phase) {
      case TourPhase.finished:
        state = state.copyWith(
          phase: state.showedProfile ? TourPhase.profile : TourPhase.touring,
        );
      case TourPhase.profile:
        state = state.copyWith(phase: TourPhase.touring);
      case TourPhase.touring when state.index > 0:
        state = state.copyWith(index: state.index - 1);
      default:
        break;
    }
  }

  /// "Continuar", em "Complete seu perfil".
  void continueFromProfile() {
    if (state.phase != TourPhase.profile) return;
    state = state.copyWith(phase: TourPhase.finished);
  }

  /// "Preencher agora": abre "Meus dados" sem nada por cima, e o tour volta
  /// sozinho a "Complete seu perfil" quando a pessoa sai de lá — salvando ou
  /// voltando, tanto faz.
  void editProfileData() {
    if (state.phase != TourPhase.profile) return;
    final router = _ref.read(routerProvider);
    state = state.copyWith(phase: TourPhase.paused);

    _stopWatchingRoute();
    final delegate = router.routerDelegate;
    var arrived = false;
    void onRoute() {
      // O último match, e não o `uri`: a rota empilhada só aparece no `uri`
      // com `optionURLReflectsImperativeAPIs` ligado, e isto não pode
      // depender de uma opção global.
      final config = delegate.currentConfiguration;
      final here = config.isEmpty ? '' : config.last.matchedLocation;
      // Até o `push` chegar, o caminho ainda é o de antes, e isso não é
      // "saiu de Meus dados".
      // `/perfil/dados/excluir` ainda é "lá dentro".
      if (here == profileDataRoute || here.startsWith('$profileDataRoute/')) {
        arrived = true;
        return;
      }
      if (!arrived) return;
      _stopWatchingRoute();
      if (state.phase == TourPhase.paused) {
        state = state.copyWith(phase: TourPhase.profile);
      }
    }

    // Antes do `push`: ele costuma ser aplicado na mesma chamada, e quem
    // começasse a escutar depois perderia a chegada.
    delegate.addListener(onRoute);
    _routeWatch = (delegate, onRoute);
    router.push(profileDataRoute);
  }

  /// O roteador observado e quem o observa. Guardado, e não relido do
  /// provider: ao descartar o controlador, o container já pode ter ido embora.
  (Listenable, VoidCallback)? _routeWatch;

  void _stopWatchingRoute() {
    final watch = _routeWatch;
    if (watch == null) return;
    watch.$1.removeListener(watch.$2);
    _routeWatch = null;
  }

  @override
  void dispose() {
    _stopWatchingRoute();
    super.dispose();
  }

  /// Falta a foto ou a data de nascimento. O gênero não conta: "não informar"
  /// é uma resposta, e não um campo esquecido.
  bool get _profileIncomplete {
    final user = _ref.read(authControllerProvider).user;
    if (user == null) return false;
    return user.avatarUrl == null || user.birthDate == null;
  }

  /// Pular. Devolve para onde a pessoa estava quando o tour começou.
  Future<String?> skip() async {
    final origin = state.origin;
    final manual = state.manual;
    _stopWatchingRoute();
    state = const TourState();
    if (!manual) await _record(OnboardingOutcome.skipped);
    return origin;
  }

  /// "Começar", na última tela.
  Future<void> finish() async {
    final manual = state.manual;
    _stopWatchingRoute();
    state = const TourState();
    if (!manual) await _record(OnboardingOutcome.completed);
  }

  Future<void> _record(OnboardingOutcome outcome) async {
    await recordOnboardingOutcome(_ref, OnboardingFlows.member, outcome);
    _ref.invalidate(memberOnboardingDueProvider);
  }

  /// A próxima escala **em que a pessoa entra**, pela mesma leitura da Home.
  ///
  /// Mesma consulta e mesma chave de cache da Home, então vinda de lá ela já
  /// está pronta. Vinda da Ajuda pode precisar buscar — e não esperar para
  /// sempre: sem resposta em poucos segundos, o tour segue sem abrir escala.
  Future<String?> _nextScheduleId() async {
    final auth = _ref.read(authControllerProvider);
    final teamId = _ref.read(activeTeamIdProvider);
    final team = auth.teams.where((t) => t.teamId == teamId).firstOrNull;
    if (teamId == null || team == null) return null;

    final provider = eventsProvider((teamId, 'upcoming'));
    // Escutar, e não só ler: a consulta é `autoDispose`, e sem ninguém
    // olhando ela seria descartada antes de responder.
    final subscription = _ref.listen(provider, (_, __) {});
    try {
      final cached =
          await _ref.read(provider.future).timeout(const Duration(seconds: 5));
      return HomeSummary.of(
        cached.data,
        membershipId: team.membershipId,
        canManage: team.canManage,
        now: DateTime.now(),
      ).myNext?.id;
    } on Object {
      return null;
    } finally {
      subscription.close();
    }
  }
}

final tourControllerProvider =
    StateNotifierProvider<TourController, TourState>(TourController.new);
