/// Uma apresentação guiada, numa edição.
///
/// **Assunto e edição separados**, e não um nome só: o assunto
/// (`member_onboarding`) é o que o app oferece; a edição (`1`) é qual versão
/// dele a pessoa viu. Refazer o tour dos integrantes é publicar a edição 2 —
/// ninguém respondeu a ela, então ela volta a aparecer, e o que a pessoa fez
/// com a 1 continua registrado no servidor.
class OnboardingFlow {
  const OnboardingFlow(this.flow, this.version);

  final String flow;
  final int version;

  /// "member_onboarding_v1": o nome que se usa para conversar sobre a versão.
  String get key => '${flow}_v$version';

  @override
  bool operator ==(Object other) =>
      other is OnboardingFlow && other.flow == flow && other.version == version;

  @override
  int get hashCode => Object.hash(flow, version);

  @override
  String toString() => key;
}

/// As apresentações que o app conhece hoje.
///
/// Uma só, a do primeiro acesso, que vale para todos os papéis — o nome
/// `member_onboarding` ficou da época em que era só dos integrantes, e trocá-lo
/// faria todo mundo que já respondeu receber o tour de novo. Um tour de líder,
/// ou o de uma funcionalidade nova, entra aqui como outra constante — o
/// servidor aceita qualquer assunto no formato certo, sem precisar ser
/// publicado antes.
abstract final class OnboardingFlows {
  static const member = OnboardingFlow('member_onboarding', 1);
}

/// Como a pessoa saiu da apresentação. As duas encerram a oferta automática.
enum OnboardingOutcome {
  completed('COMPLETED'),
  skipped('SKIPPED');

  const OnboardingOutcome(this.apiValue);

  final String apiValue;

  static OnboardingOutcome? fromApi(String? value) {
    for (final outcome in values) {
      if (outcome.apiValue == value) return outcome;
    }
    return null;
  }
}

/// Uma resposta já registrada no servidor.
class OnboardingRecord {
  const OnboardingRecord({required this.flow, required this.outcome});

  factory OnboardingRecord.fromJson(Map<String, dynamic> json) {
    return OnboardingRecord(
      flow: OnboardingFlow(
        json['flow'] as String,
        (json['version'] as num).toInt(),
      ),
      outcome: OnboardingOutcome.fromApi(json['status'] as String?) ??
          OnboardingOutcome.completed,
    );
  }

  final OnboardingFlow flow;
  final OnboardingOutcome outcome;
}

/// Se o app deve oferecer [flow] a esta pessoa agora.
///
/// **Qualquer resposta encerra a oferta**, inclusive pular no meio: quem pulou
/// não quer ser perguntado a cada abertura, e a Ajuda continua mostrando o
/// tour para quem mudar de ideia. [pendingLocally] é a resposta que o aparelho
/// ainda não conseguiu entregar ao servidor — ela vale do mesmo jeito.
bool shouldOfferOnboarding(
  OnboardingFlow flow, {
  required Iterable<OnboardingRecord> records,
  required bool pendingLocally,
}) {
  if (pendingLocally) return false;
  return !records.any((record) => record.flow == flow);
}

/// O inverso de [OnboardingFlow.key]: "member_onboarding_v1" → assunto e
/// edição. Nulo quando o texto não tem o formato.
OnboardingFlow? parseOnboardingKey(String key) {
  final match = RegExp(r'^(.+)_v(\d+)$').firstMatch(key);
  if (match == null) return null;
  return OnboardingFlow(match.group(1)!, int.parse(match.group(2)!));
}
