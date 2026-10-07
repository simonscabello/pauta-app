import '../../songs/domain/song_models.dart';

// Os modelos dos copilotos de IA, escritos à mão como o resto do app.
//
// O Copiloto de Escalas devolve a proposta do mês **inteira** a cada chamada
// (dias, equilíbrio, avisos): a tela não soma nada, só desenha. O de
// Repertório devolve as músicas no formato da lista do repertório, para
// entrarem no culto sem outra ida ao servidor.

/// O que a liderança desta equipe pode usar agora.
class AiFeatures {
  const AiFeatures({
    required this.scheduleCopilot,
    required this.repertoireCopilot,
  });

  static const none =
      AiFeatures(scheduleCopilot: false, repertoireCopilot: false);

  final bool scheduleCopilot;
  final bool repertoireCopilot;

  factory AiFeatures.fromJson(Map<String, dynamic> json) => AiFeatures(
        scheduleCopilot: json['scheduleCopilot'] == true,
        repertoireCopilot: json['repertoireCopilot'] == true,
      );
}

/// Estado de um dia do mês: sem escala, rascunho ou publicada.
enum CopilotDayState {
  empty,
  draft,
  published;

  static CopilotDayState fromJson(Object? value) => switch (value) {
        'DRAFT' => draft,
        'PUBLISHED' => published,
        _ => empty,
      };

  String get label => switch (this) {
        empty => 'Sem escala',
        draft => 'Rascunho',
        published => 'Publicada',
      };
}

class CopilotService {
  const CopilotService({required this.label, required this.time});

  final String label;
  final String time;

  factory CopilotService.fromJson(Map<String, dynamic> json) => CopilotService(
        label: json['label'] as String? ?? '',
        time: json['time'] as String? ?? '',
      );

  @override
  String toString() => '$label $time';
}

// ---------------------------------------------------------------------------
// Prévia do mês
// ---------------------------------------------------------------------------

class MonthPreviewDay {
  const MonthPreviewDay({
    required this.dateKey,
    required this.weekday,
    required this.past,
    required this.state,
    required this.title,
    required this.services,
  });

  final String dateKey;
  final int weekday;
  final bool past;
  final CopilotDayState state;
  final String? title;
  final List<CopilotService> services;

  factory MonthPreviewDay.fromJson(Map<String, dynamic> json) =>
      MonthPreviewDay(
        dateKey: json['dateKey'] as String,
        weekday: json['weekday'] as int? ?? 0,
        past: json['past'] == true,
        state: CopilotDayState.fromJson(json['state']),
        title: json['title'] as String?,
        services: _list(json['services']).map(CopilotService.fromJson).toList(),
      );
}

class LineupPosition {
  const LineupPosition({
    required this.positionId,
    required this.name,
    required this.category,
    required this.count,
  });

  final String positionId;
  final String name;
  final String category;
  final int count;

  LineupPosition copyWith({int? count}) => LineupPosition(
        positionId: positionId,
        name: name,
        category: category,
        count: count ?? this.count,
      );

  factory LineupPosition.fromJson(Map<String, dynamic> json) => LineupPosition(
        positionId: json['positionId'] as String,
        name: json['name'] as String? ?? '',
        category: json['category'] as String? ?? 'OTHER',
        count: json['count'] as int? ?? 0,
      );
}

/// A formação de um dia da semana. `source` diz de onde ela veio: gravada
/// pelo líder (`SAVED`), sugerida pelo histórico (`HISTORY`) ou nenhuma.
class WeekdayLineup {
  const WeekdayLineup({
    required this.weekday,
    required this.weekdayName,
    required this.source,
    required this.positions,
  });

  final int weekday;
  final String weekdayName;
  final String source;
  final List<LineupPosition> positions;

  int get total => positions.fold(0, (sum, p) => sum + p.count);

  factory WeekdayLineup.fromJson(Map<String, dynamic> json) => WeekdayLineup(
        weekday: json['weekday'] as int? ?? 0,
        weekdayName: json['weekdayName'] as String? ?? '',
        source: json['source'] as String? ?? 'EMPTY',
        positions:
            _list(json['positions']).map(LineupPosition.fromJson).toList(),
      );
}

class CopilotHint {
  const CopilotHint({
    required this.kind,
    required this.text,
    this.membershipId,
  });

  final String kind;
  final String text;
  final String? membershipId;

  factory CopilotHint.fromJson(Map<String, dynamic> json) => CopilotHint(
        kind: json['kind'] as String? ?? '',
        text: json['text'] as String? ?? '',
        membershipId: json['membershipId'] as String?,
      );
}

class MonthPreview {
  const MonthPreview({
    required this.month,
    required this.days,
    required this.lineups,
    required this.hints,
    required this.openSessionId,
  });

  final String month;
  final List<MonthPreviewDay> days;
  final List<WeekdayLineup> lineups;
  final List<CopilotHint> hints;
  final String? openSessionId;

  factory MonthPreview.fromJson(Map<String, dynamic> json) => MonthPreview(
        month: json['month'] as String,
        days: _list(json['days']).map(MonthPreviewDay.fromJson).toList(),
        lineups: _list(json['lineups']).map(WeekdayLineup.fromJson).toList(),
        hints: _list(json['hints']).map(CopilotHint.fromJson).toList(),
        openSessionId:
            (json['openSession'] as Map<String, dynamic>?)?['id'] as String?,
      );
}

// ---------------------------------------------------------------------------
// A proposta
// ---------------------------------------------------------------------------

class CopilotSlot {
  const CopilotSlot({
    required this.index,
    required this.membershipId,
    required this.name,
    required this.locked,
    required this.reason,
    required this.candidates,
    required this.warnings,
  });

  final int index;
  final String? membershipId;
  final String? name;
  final bool locked;

  /// O "por quê" desta escolha, escrito pelo servidor a partir de fatos.
  final String? reason;

  /// Quem podia ocupar esta vaga pelas regras (vazio nas travadas).
  final List<String> candidates;
  final List<String> warnings;

  factory CopilotSlot.fromJson(Map<String, dynamic> json) => CopilotSlot(
        index: json['index'] as int? ?? 0,
        membershipId: json['membershipId'] as String?,
        name: json['name'] as String?,
        locked: json['locked'] == true,
        reason: json['reason'] as String?,
        candidates: (json['candidates'] as List?)?.cast<String>() ?? const [],
        warnings: (json['warnings'] as List?)?.cast<String>() ?? const [],
      );
}

class CopilotPosition {
  const CopilotPosition({
    required this.positionId,
    required this.name,
    required this.category,
    required this.slots,
  });

  final String positionId;
  final String name;
  final String category;
  final List<CopilotSlot> slots;

  factory CopilotPosition.fromJson(Map<String, dynamic> json) =>
      CopilotPosition(
        positionId: json['positionId'] as String,
        name: json['name'] as String? ?? '',
        category: json['category'] as String? ?? 'OTHER',
        slots: _list(json['slots']).map(CopilotSlot.fromJson).toList(),
      );
}

class CopilotDay {
  const CopilotDay({
    required this.dateKey,
    required this.weekday,
    required this.state,
    required this.eventId,
    required this.title,
    required this.generated,
    required this.locked,
    required this.changed,
    required this.services,
    required this.unavailable,
    required this.positions,
  });

  final String dateKey;
  final int weekday;
  final CopilotDayState state;
  final String? eventId;
  final String? title;

  /// O copiloto preencheu este dia. Os outros (publicadas, rascunhos
  /// mantidos) aparecem só como contexto.
  final bool generated;
  final bool locked;

  /// A escala deste dia mudou depois da proposta: salvar vai pular o dia.
  final bool changed;
  final List<CopilotService> services;
  final List<String> unavailable;
  final List<CopilotPosition> positions;

  int get filled => positions.fold(
        0,
        (n, p) => n + p.slots.where((s) => s.membershipId != null).length,
      );
  int get empty => positions.fold(
        0,
        (n, p) => n + p.slots.where((s) => s.membershipId == null).length,
      );
  bool get hasWarnings =>
      positions.any((p) => p.slots.any((s) => s.warnings.isNotEmpty));

  factory CopilotDay.fromJson(Map<String, dynamic> json) => CopilotDay(
        dateKey: json['dateKey'] as String,
        weekday: json['weekday'] as int? ?? 0,
        state: CopilotDayState.fromJson(json['state']),
        eventId: json['eventId'] as String?,
        title: json['title'] as String?,
        generated: json['generated'] == true,
        locked: json['locked'] == true,
        changed: json['changed'] == true,
        services: _list(json['services']).map(CopilotService.fromJson).toList(),
        unavailable: (json['unavailable'] as List?)?.cast<String>() ?? const [],
        positions:
            _list(json['positions']).map(CopilotPosition.fromJson).toList(),
      );
}

enum BalanceStatus {
  ok,
  high,
  low,
  leftOut,
  unavailable,
  onLeave;

  static BalanceStatus fromJson(Object? value) => switch (value) {
        'HIGH' => high,
        'LOW' => low,
        'LEFT_OUT' => leftOut,
        'UNAVAILABLE' => unavailable,
        'ON_LEAVE' => onLeave,
        _ => ok,
      };
}

class BalanceMember {
  const BalanceMember({
    required this.membershipId,
    required this.name,
    required this.count,
    required this.target,
    required this.availableDays,
    required this.unavailableDays,
    required this.streak,
    required this.positions,
    required this.status,
    required this.note,
  });

  final String membershipId;
  final String name;
  final int count;

  /// O que a disponibilidade e o histórico sugerem para a pessoa no mês.
  final double target;
  final int availableDays;
  final int unavailableDays;
  final int streak;
  final List<String> positions;
  final BalanceStatus status;
  final String? note;

  factory BalanceMember.fromJson(Map<String, dynamic> json) => BalanceMember(
        membershipId: json['membershipId'] as String,
        name: json['name'] as String? ?? '',
        count: json['count'] as int? ?? 0,
        target: (json['target'] as num?)?.toDouble() ?? 0,
        availableDays: json['availableDays'] as int? ?? 0,
        unavailableDays: json['unavailableDays'] as int? ?? 0,
        streak: json['streak'] as int? ?? 0,
        positions: (json['positions'] as List?)?.cast<String>() ?? const [],
        status: BalanceStatus.fromJson(json['status']),
        note: json['note'] as String?,
      );
}

class CopilotMember {
  const CopilotMember({
    required this.membershipId,
    required this.name,
    required this.positionIds,
    required this.isGuest,
    required this.onLeave,
    required this.monthCount,
  });

  final String membershipId;
  final String name;
  final List<String> positionIds;
  final bool isGuest;
  final bool onLeave;
  final int monthCount;

  factory CopilotMember.fromJson(Map<String, dynamic> json) => CopilotMember(
        membershipId: json['membershipId'] as String,
        name: json['name'] as String? ?? '',
        positionIds: (json['positionIds'] as List?)?.cast<String>() ?? const [],
        isGuest: json['isGuest'] == true,
        onLeave: json['onLeave'] == true,
        monthCount: json['monthCount'] as int? ?? 0,
      );
}

class CommitResult {
  const CommitResult({
    required this.dateKey,
    required this.action,
    required this.detail,
  });

  final String dateKey;
  final String action;
  final String? detail;

  bool get saved => action != 'SKIPPED';

  factory CommitResult.fromJson(Map<String, dynamic> json) => CommitResult(
        dateKey: json['dateKey'] as String,
        action: json['action'] as String? ?? 'SKIPPED',
        detail: json['detail'] as String?,
      );
}

class ScheduleCopilotSession {
  const ScheduleCopilotSession({
    required this.id,
    required this.month,
    required this.status,
    required this.version,
    required this.versionCount,
    required this.days,
    required this.members,
    required this.balance,
    required this.highlights,
    required this.warnings,
  });

  final String id;
  final String month;
  final String status;
  final int version;
  final int versionCount;
  final List<CopilotDay> days;
  final List<CopilotMember> members;
  final List<BalanceMember> balance;
  final List<String> highlights;
  final List<String> warnings;

  bool get isOpen => status == 'OPEN';
  List<CopilotDay> get generatedDays => days.where((d) => d.generated).toList();

  CopilotMember? member(String? id) =>
      members.where((m) => m.membershipId == id).firstOrNull;

  factory ScheduleCopilotSession.fromJson(Map<String, dynamic> json) {
    final balance = json['balance'] as Map<String, dynamic>? ?? const {};
    return ScheduleCopilotSession(
      id: json['id'] as String,
      month: json['month'] as String,
      status: json['status'] as String? ?? 'OPEN',
      version: json['version'] as int? ?? 1,
      versionCount: (json['versions'] as List?)?.length ?? 1,
      days: _list(json['days']).map(CopilotDay.fromJson).toList(),
      members: _list(json['members']).map(CopilotMember.fromJson).toList(),
      balance: _list(balance['members']).map(BalanceMember.fromJson).toList(),
      highlights: (balance['highlights'] as List?)?.cast<String>() ?? const [],
      warnings: (json['warnings'] as List?)?.cast<String>() ?? const [],
    );
  }
}

// ---------------------------------------------------------------------------
// Copiloto de Repertório
// ---------------------------------------------------------------------------

class SuggestedSong {
  const SuggestedSong({
    required this.song,
    required this.moment,
    required this.reason,
    required this.lastPlayedAt,
    required this.timesLast6Months,
    required this.concerns,
  });

  final Song song;
  final String? moment;
  final String reason;
  final DateTime? lastPlayedAt;
  final int timesLast6Months;

  /// Avisos do servidor (fatos, não do modelo): cantada há poucos dias, em
  /// outra escala próxima.
  final List<String> concerns;

  factory SuggestedSong.fromJson(Map<String, dynamic> json) => SuggestedSong(
        song: Song.fromJson(json['song'] as Map<String, dynamic>),
        moment: json['moment'] as String?,
        reason: json['reason'] as String? ?? '',
        lastPlayedAt: DateTime.tryParse(json['lastPlayedAt'] as String? ?? ''),
        timesLast6Months: json['timesLast6Months'] as int? ?? 0,
        concerns: (json['concerns'] as List?)?.cast<String>() ?? const [],
      );
}

class RepertoireSuggestion {
  const RepertoireSuggestion({
    required this.id,
    required this.version,
    required this.theme,
    required this.summary,
    required this.unmet,
    required this.songs,
  });

  final String id;
  final int version;
  final String theme;
  final String? summary;
  final String? unmet;
  final List<SuggestedSong> songs;

  factory RepertoireSuggestion.fromJson(Map<String, dynamic> json) =>
      RepertoireSuggestion(
        id: json['id'] as String,
        version: json['version'] as int? ?? 1,
        theme: json['theme'] as String? ?? '',
        summary: json['summary'] as String?,
        unmet: json['unmet'] as String?,
        songs: _list(json['songs']).map(SuggestedSong.fromJson).toList(),
      );
}

List<Map<String, dynamic>> _list(Object? value) =>
    (value as List?)?.cast<Map<String, dynamic>>() ?? const [];
