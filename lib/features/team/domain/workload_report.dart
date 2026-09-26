import '../../../core/date/civil_date.dart';
import '../../../core/date/report_period.dart';

class WorkloadPosition {
  const WorkloadPosition({
    required this.name,
    required this.count,
    this.positionId,
    this.lastScheduledAt,
  });

  factory WorkloadPosition.fromJson(Map<String, dynamic> json) {
    return WorkloadPosition(
      positionId: json['positionId'] as String?,
      name: json['name'] as String,
      count: json['count'] as int,
      lastScheduledAt: json['lastScheduledAt'] == null
          ? null
          : DateTime.parse(json['lastScheduledAt'] as String).toUtc(),
    );
  }

  /// Nulo só em resposta de servidor antigo, que mandava a função pelo nome.
  final String? positionId;
  final String name;

  /// Escalas em que a pessoa serviu nesta função.
  final int count;
  final DateTime? lastScheduledAt;
}

class WorkloadMember {
  const WorkloadMember({
    required this.membershipId,
    required this.displayName,
    required this.scheduleCount,
    required this.assignmentCount,
    required this.positions,
    this.lastScheduledAt,
    this.onLeave = false,
    this.unavailableCount = 0,
    this.freeCount = 0,
    this.markedDays = 0,
    this.positionIds = const [],
  });

  factory WorkloadMember.fromJson(Map<String, dynamic> json) {
    return WorkloadMember(
      membershipId: json['membershipId'] as String,
      displayName: json['displayName'] as String,
      onLeave: json['onLeave'] as bool? ?? false,
      scheduleCount: json['scheduleCount'] as int? ?? 0,
      assignmentCount: json['assignmentCount'] as int? ?? 0,
      unavailableCount: json['unavailableCount'] as int? ?? 0,
      freeCount: json['freeCount'] as int? ?? 0,
      markedDays: json['markedDays'] as int? ?? 0,
      lastScheduledAt: json['lastScheduledAt'] == null
          ? null
          : DateTime.parse(json['lastScheduledAt'] as String).toUtc(),
      positionIds: (json['positionIds'] as List<dynamic>? ?? const [])
          .map((item) => item as String)
          .toList(),
      positions: (json['positions'] as List<dynamic>? ?? const [])
          .map(
            (item) => WorkloadPosition.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  final String membershipId;
  final String displayName;
  final bool onLeave;

  /// Escalas em que serviu. Duas funções no mesmo dia contam uma.
  final int scheduleCount;
  final int assignmentCount;

  /// Escalas em que **não serviu** porque tinha avisado que não podia.
  final int unavailableCount;

  /// Escalas em que não serviu e não tinha avisado nada: estava livre e
  /// ninguém chamou. É a pergunta que a contagem sozinha não respondia.
  final int freeCount;

  /// Dias marcados como indisponível no período, com ou sem escala.
  final int markedDays;
  final DateTime? lastScheduledAt;

  /// Funções que a pessoa sabe exercer, do cadastro do integrante.
  final List<String> positionIds;

  /// Funções que ela exerceu no período, da mais frequente para a menos.
  final List<WorkloadPosition> positions;

  WorkloadPosition? servedIn(String positionId) {
    for (final position in positions) {
      if (position.positionId == positionId) return position;
    }
    return null;
  }
}

/// Uma função da equipe, para o filtro da participação.
class WorkloadPositionOption {
  const WorkloadPositionOption({required this.positionId, required this.name});

  factory WorkloadPositionOption.fromJson(Map<String, dynamic> json) {
    return WorkloadPositionOption(
      positionId: json['positionId'] as String,
      name: json['name'] as String,
    );
  }

  final String positionId;
  final String name;
}

class WorkloadReport {
  const WorkloadReport({
    required this.since,
    required this.until,
    required this.members,
    this.weeks,
    this.months,
    this.from,
    this.to,
    this.weekday,
    this.weekdays = const [],
    this.scheduleTotal = 0,
    this.positions = const [],
  });

  factory WorkloadReport.fromJson(Map<String, dynamic> json) {
    return WorkloadReport(
      weeks: json['weeks'] as int?,
      months: json['months'] as int?,
      from: parseDateKey(json['from'] as String?),
      to: parseDateKey(json['to'] as String?),
      since: DateTime.parse(json['since'] as String).toUtc(),
      until: DateTime.parse(json['until'] as String).toUtc(),
      weekday: json['weekday'] as int?,
      weekdays: reportWeekdaysFromJson(json['weekdays']),
      scheduleTotal: json['scheduleTotal'] as int? ?? 0,
      positions: (json['positions'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                WorkloadPositionOption.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      members: (json['members'] as List<dynamic>? ?? const [])
          .map((item) => WorkloadMember.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  final int? weeks;
  final int? months;

  /// Os dias civis do período, no fuso da equipe.
  final DateTime? from;
  final DateTime? to;
  final DateTime since;
  final DateTime until;

  /// O dia da semana filtrado; nulo = todos.
  final int? weekday;

  /// Os dias da semana com escala no período, contados **antes** do filtro.
  final List<ReportWeekday> weekdays;

  /// Escalas publicadas no período: o "de 12" de "serviu em 5 de 12".
  final int scheduleTotal;

  /// As funções que têm alguém — quem sabe exercer ou quem exerceu.
  final List<WorkloadPositionOption> positions;
  final List<WorkloadMember> members;
}

/// A ordem da participação.
enum WorkloadOrder {
  /// Quem está segurando a equipe. É o padrão.
  most,

  /// Quem está sumindo.
  least,
}

/// Uma linha da participação: a pessoa e o número que a lista está contando.
class WorkloadRow {
  const WorkloadRow({
    required this.member,
    required this.count,
    this.lastScheduledAt,
  });

  final WorkloadMember member;

  /// Escalas no período — ou, com uma função escolhida, escalas **nela**.
  final int count;
  final DateTime? lastScheduledAt;
}

/// As linhas da participação, com o filtro de função e a ordem aplicados.
///
/// Com uma função escolhida entra quem **sabe** exercê-la e quem a exerceu no
/// período. Só quem tocou deixaria de fora justamente a resposta mais útil:
/// quem toca violão e não tocou nenhuma vez.
List<WorkloadRow> workloadRows(
  WorkloadReport report, {
  String? positionId,
  WorkloadOrder order = WorkloadOrder.most,
}) {
  final rows = <WorkloadRow>[];
  for (final member in report.members) {
    if (positionId == null) {
      rows.add(
        WorkloadRow(
          member: member,
          count: member.scheduleCount,
          lastScheduledAt: member.lastScheduledAt,
        ),
      );
      continue;
    }
    final served = member.servedIn(positionId);
    if (served == null && !member.positionIds.contains(positionId)) continue;
    rows.add(
      WorkloadRow(
        member: member,
        count: served?.count ?? 0,
        lastScheduledAt: served?.lastScheduledAt,
      ),
    );
  }

  rows.sort((a, b) {
    final byCount = order == WorkloadOrder.most
        ? b.count.compareTo(a.count)
        : a.count.compareTo(b.count);
    if (byCount != 0) return byCount;
    return a.member.displayName.compareTo(b.member.displayName);
  });
  return rows;
}

/// A ordem da aba "Por pessoa" do "Quem não pode".
enum AbsenceOrder {
  /// Quem mais avisou que não podia.
  mostAbsent,

  /// Quem menos.
  leastAbsent,

  /// Quem mais ficou livre sem ser chamado — a pessoa disponível que a
  /// escala esquece.
  mostFree,
}

List<WorkloadMember> absenceRanking(
  WorkloadReport report, {
  AbsenceOrder order = AbsenceOrder.mostAbsent,
}) {
  int compare(WorkloadMember a, WorkloadMember b) {
    switch (order) {
      case AbsenceOrder.mostAbsent:
        final byCount = b.unavailableCount.compareTo(a.unavailableCount);
        if (byCount != 0) return byCount;
        return b.markedDays.compareTo(a.markedDays);
      case AbsenceOrder.leastAbsent:
        final byCount = a.unavailableCount.compareTo(b.unavailableCount);
        if (byCount != 0) return byCount;
        return a.markedDays.compareTo(b.markedDays);
      case AbsenceOrder.mostFree:
        return b.freeCount.compareTo(a.freeCount);
    }
  }

  return [...report.members]..sort((a, b) {
      final result = compare(a, b);
      return result != 0 ? result : a.displayName.compareTo(b.displayName);
    });
}

/// Contexto de rodízio de uma pessoa, para o seletor da escalação.
///
/// É deliberadamente magro: o seletor precisa de duas frases curtas ao lado do
/// nome, não de um relatório. O relatório inteiro é [WorkloadReport], e ele
/// tem tela própria.
class RotationMember {
  const RotationMember({
    required this.membershipId,
    required this.recentCount,
    this.lastScheduledAt,
  });

  factory RotationMember.fromJson(Map<String, dynamic> json) {
    return RotationMember(
      membershipId: json['membershipId'] as String,
      recentCount: json['recentCount'] as int? ?? 0,
      lastScheduledAt: json['lastScheduledAt'] == null
          ? null
          : DateTime.parse(json['lastScheduledAt'] as String).toUtc(),
    );
  }

  final String membershipId;

  /// Escalas na janela recente. Conta escalas, e não funções: quem tocou
  /// baixo e cantou no mesmo domingo serviu uma vez.
  final int recentCount;

  /// Nulo = ninguém a escalou nos últimos 12 meses.
  final DateTime? lastScheduledAt;
}

class RotationReport {
  const RotationReport({required this.weeks, required this.members});

  factory RotationReport.fromJson(Map<String, dynamic> json) {
    return RotationReport(
      weeks: json['weeks'] as int? ?? 8,
      members: {
        for (final item in json['members'] as List<dynamic>? ?? const [])
          (item as Map<String, dynamic>)['membershipId'] as String:
              RotationMember.fromJson(item),
      },
    );
  }

  final int weeks;

  /// Indexado por `membershipId`: o seletor consulta pessoa por pessoa
  /// enquanto desenha a lista.
  final Map<String, RotationMember> members;
}
