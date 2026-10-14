/// Em que momento do culto uma música da escala entra.
///
/// **Espelho do enum `ServiceMoment` do servidor**, na ordem em que os
/// momentos acontecem no culto — e não em ordem alfabética. A chave é o valor
/// que viaja no JSON; o valor é o rótulo que aparece na tela, mesma divisão de
/// trabalho de [songThemes].
///
/// **Desde 10/2026 cada equipe tem a sua lista** ([TeamMoment]): os seis de
/// fábrica, que ela renomeia ou exclui, e os que ela cadastra (o culto
/// especial, a liturgia que mudou). Estes rótulos continuam valendo para quem
/// não tem a lista em mãos — a escala de antes dela, a lista que não carregou —
/// e as chaves continuam sendo o que o servidor grava ao lado do momento da
/// equipe.
///
/// `OUTRO` segue sendo o momento de uma vez só, com o nome escrito à mão; um
/// momento cadastrado pela equipe também viaja como `OUTRO` com o nome, que é
/// o que o APK antigo sabe mostrar.
const Map<String, String> serviceMoments = {
  'PRELUDIO': 'Prelúdio',
  'ABERTURA': 'Abertura',
  'DIZIMOS_E_OFERTAS': 'Dízimos e Ofertas',
  'LOUVOR': 'Momento de Louvor',
  'ESPECIAL': 'Música Especial',
  'POSLUDIO': 'Pós-lúdio',
  'OUTRO': 'Outro',
};

/// O valor de [serviceMoments] que exige um nome escrito à mão.
const String otherServiceMoment = 'OUTRO';

/// Como o momento aparece na tela e na mensagem.
///
/// Em `OUTRO`, o que a pessoa escreveu — "Santa Ceia" diz mais do que "Outro",
/// que não diz nada. Sem texto, o rótulo genérico ainda serve: ela marcou que
/// há um momento, só não o nomeou.
///
/// Nulo quando não há momento nenhum. **Nada de "—" nem de "Sem momento"**: a
/// maioria das músicas de uma escala não tem momento nomeado, e um marcador de
/// campo vazio em cada linha encheria a tela de nada.
String? serviceMomentLabel(String? moment, [String? customLabel]) {
  if (moment == null || moment.isEmpty) return null;

  if (moment == otherServiceMoment) {
    final escrito = customLabel?.trim() ?? '';
    if (escrito.isNotEmpty) return escrito;
  }

  // Momento que o servidor conhece e esta versão do app ainda não: o valor
  // cru é feio, mas é melhor que sumir com a informação até o próximo APK.
  return serviceMoments[moment] ?? moment;
}

/// Um momento do culto da lista da equipe (`/teams/:teamId/service-moments`).
class TeamMoment {
  const TeamMoment({
    required this.id,
    required this.name,
    this.systemKey,
    this.sortOrder = 0,
    this.isActive = true,
  });

  /// Vazio só nos de reserva ([fallbackTeamMoments]), que não vieram do
  /// servidor.
  final String id;
  final String name;

  /// A chave do de fábrica (`ABERTURA`…), ou nula nos cadastrados pela equipe.
  final String? systemKey;
  final int sortOrder;
  final bool isActive;

  bool get isCustom => systemKey == null;

  factory TeamMoment.fromJson(Map<String, dynamic> json) => TeamMoment(
        id: json['id'] as String,
        name: json['name'] as String,
        systemKey: json['systemKey'] as String?,
        sortOrder: json['sortOrder'] as int? ?? 0,
        isActive: json['isActive'] as bool? ?? true,
      );
}

/// Os seis de fábrica sem passar pelo servidor: o que a folha da escala
/// mostra quando a lista da equipe não carregou. Escolhidos por aqui, vão pela
/// chave, e o servidor liga ao momento da equipe.
List<TeamMoment> fallbackTeamMoments() => [
      for (final (index, entry) in serviceMoments.entries.indexed)
        if (entry.key != otherServiceMoment)
          TeamMoment(
            id: '',
            name: entry.value,
            systemKey: entry.key,
            sortOrder: index,
          ),
    ];

/// O momento escolhido para uma música da escala, nos campos que o servidor
/// grava: o da lista da equipe (`momentId`) com a chave ao lado, ou o "Outro"
/// de uma vez só, com o nome escrito à mão.
class MomentChoice {
  const MomentChoice({
    this.momentId,
    required this.moment,
    this.momentLabel,
    required this.name,
  });

  factory MomentChoice.ofTeam(TeamMoment teamMoment) => MomentChoice(
        momentId: teamMoment.id.isEmpty ? null : teamMoment.id,
        moment: teamMoment.systemKey ?? otherServiceMoment,
        momentLabel: teamMoment.systemKey == null ? teamMoment.name : null,
        name: teamMoment.name,
      );

  /// O "Outro" de uma vez só. Sem nome, continua sendo "Outro".
  factory MomentChoice.other(String label) {
    final escrito = label.trim();
    return MomentChoice(
      moment: otherServiceMoment,
      momentLabel: escrito.isEmpty ? null : escrito,
      name: escrito.isEmpty ? serviceMoments[otherServiceMoment]! : escrito,
    );
  }

  /// A chave de fábrica (`moment`) que veio de outro lugar — o copiloto, uma
  /// escala de antes da lista da equipe —, ligada ao momento da equipe com
  /// aquela chave quando há um.
  static MomentChoice? ofKey(String? moment, List<TeamMoment> moments) {
    if (moment == null || moment.isEmpty) return null;
    for (final m in moments) {
      if (m.systemKey == moment) return MomentChoice.ofTeam(m);
    }
    return MomentChoice(
      moment: moment,
      name: serviceMomentLabel(moment) ?? moment,
    );
  }

  final String? momentId;
  final String moment;
  final String? momentLabel;
  final String name;

  bool get isOneOffOther => momentId == null && moment == otherServiceMoment;

  /// O que identifica a escolha, para marcar o chip: o momento da equipe pelo
  /// id; o de reserva pela chave.
  String get key => momentId ?? 'chave:$moment';

  bool matches(TeamMoment teamMoment) =>
      key == MomentChoice.ofTeam(teamMoment).key;
}
