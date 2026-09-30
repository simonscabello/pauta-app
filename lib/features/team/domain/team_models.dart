import '../../../core/date/civil_date.dart';
import '../../../shared/domain/person_fields.dart';

class Position {
  const Position({
    required this.id,
    required this.name,
    required this.category,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String category;
  final int sortOrder;
  final bool isActive;

  bool get isVocal => category == 'VOCAL';
  bool get isInstrument => category == 'INSTRUMENT';

  /// Multimídia e som: apoio ao culto, fora da banda.
  bool get isTech => category == 'TECH';

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      sortOrder: json['sortOrder'] as int? ?? 0,
      isActive: json['isActive'] as bool? ?? true,
    );
  }
}

class Member {
  const Member({
    required this.id,
    required this.displayName,
    required this.role,
    required this.hasAccount,
    this.isGuest = false,
    required this.positions,
    this.phone,
    this.email,
    this.avatarUrl,
    this.birthDate,
    this.gender,
    this.notes,
    this.onLeave = false,
    this.leaveUntil,
    this.leaveReason,
    this.leaveOverdue = false,
  });

  final String id;
  final String displayName;
  final String role;

  /// false = cadastrado pelo líder, ainda sem conta no app.
  final bool hasAccount;

  /// De fora da equipe: de outro ministério da igreja ou convidado de outra
  /// igreja. Não tem conta e não é integrante; só entra nas escalas.
  final bool isGuest;
  final List<Position> positions;
  final String? phone;
  final String? email;

  /// Foto da conta, quando o integrante tem uma. Membro sem conta cai na
  /// inicial do nome.
  final String? avatarUrl;

  /// Nascimento e gênero **vêm da conta**, não da ficha da equipe: são da
  /// pessoa, e quem os preenche é ela, em Perfil → Meus dados. Por isso são
  /// nulos para quem ainda não criou conta — e a tela diz isso, em vez de
  /// mostrar um traço que parece cadastro esquecido.
  final DateTime? birthDate;
  final Gender? gender;

  /// Anotação da liderança. Nulo para quem é MEMBER — e é nulo de verdade: o
  /// servidor não manda o campo, a tela não o esconde.
  final String? notes;

  /// Afastamento temporário. Ligado e desligado à mão por quem lidera; a data
  /// é **previsão** de retorno, e não um gatilho — ninguém volta para a escala
  /// porque o calendário virou.
  final bool onLeave;
  final DateTime? leaveUntil;
  final String? leaveReason;

  /// A previsão passou e o afastamento continua ligado. Não é erro: é a decisão
  /// de quem lidera esperando ser tomada.
  final bool leaveOverdue;

  bool get isOwner => role == 'OWNER';
  bool get canManage => role == 'OWNER' || role == 'LEADER';

  String get roleLabel => switch (role) {
        'OWNER' => 'Dono',
        'LEADER' => 'Líder',
        _ => 'Membro',
      };

  /// "Em afastamento", "Em afastamento até 12 de março".
  ///
  /// Substantivo em vez de adjetivo: "Afastado" erraria o gênero de metade da
  /// equipe, e o app não sabe o de quem não preencheu.
  ///
  /// Uma frase só, montada aqui e não em cada tela: a etiqueta aparece na
  /// lista, na ficha e no seletor da escalação, e três montagens diferentes da
  /// mesma informação já custaram caro neste app.
  String get leaveLabel {
    if (!onLeave) return '';
    if (leaveUntil != null) {
      return 'Em afastamento até ${formatBirthday(leaveUntil!)}';
    }
    return 'Em afastamento';
  }

  /// Quantos dias faltam para o aniversário. Nulo quando não há data.
  int? get daysToBirthday =>
      birthDate == null ? null : daysUntilBirthday(birthDate!);

  /// Telefone só com dígitos, para o link do WhatsApp. Nulo quando não dá para
  /// montar um número — melhor não oferecer o botão do que abrir uma conversa
  /// com ninguém.
  String? get phoneDigits {
    final digits = phone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    // 10 = fixo com DDD, 11 = celular com DDD. Abaixo disso é ramal, recado ou
    // um número pela metade.
    if (digits.length < 10) return null;
    // O WhatsApp exige o código do país. Quem digitou o DDD e mais nada está
    // no Brasil — o app não tem equipe fora daqui, e assumir 55 é melhor que
    // não abrir nada.
    return digits.length <= 11 ? '55$digits' : digits;
  }

  factory Member.fromJson(Map<String, dynamic> json) {
    return Member(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      role: json['role'] as String,
      hasAccount: json['hasAccount'] as bool? ?? false,
      isGuest: json['isGuest'] as bool? ?? false,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      birthDate: parseDateKey(json['birthDate'] as String?),
      gender: Gender.fromApi(json['gender'] as String?),
      notes: json['notes'] as String?,
      onLeave: json['onLeave'] as bool? ?? false,
      leaveUntil: parseDateKey(json['leaveUntil'] as String?),
      leaveReason: json['leaveReason'] as String?,
      leaveOverdue: json['leaveOverdue'] as bool? ?? false,
      positions: (json['positions'] as List<dynamic>? ?? [])
          .map((e) => Position.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class Team {
  const Team({
    required this.id,
    required this.name,
    required this.timezone,
    this.memberCount = 0,
  });

  final String id;
  final String name;
  final String timezone;
  final int memberCount;

  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      id: json['id'] as String,
      name: json['name'] as String,
      timezone: json['timezone'] as String? ?? 'America/Sao_Paulo',
      memberCount: json['memberCount'] as int? ?? 0,
    );
  }
}
