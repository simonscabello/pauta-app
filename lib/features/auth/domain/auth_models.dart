import '../../../core/date/civil_date.dart';
import '../../../shared/domain/person_fields.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.mustChangePassword,
    this.birthDate,
    this.gender,
    this.avatarUrl,
    this.pushEnabled = true,
  });

  final String id;
  final String name;
  final String email;
  final bool mustChangePassword;

  /// Dia civil, sem hora. Mora na conta porque e da PESSOA: nao muda de equipe
  /// para equipe, e quem a conhece e o dono da conta. Quem ainda nao criou
  /// conta nao tem aniversario cadastrado, e a lista da equipe diz isso.
  final DateTime? birthDate;

  /// Nulo = nao informou. E o padrao, e nao um cadastro pela metade.
  final Gender? gender;

  /// Caminho da foto relativo ao host da API ("/uploads/avatars/x.jpg"), ou
  /// null. Quem monta o endereco completo e o AppAvatar.
  final String? avatarUrl;

  /// Avisos no celular. Explicito e ligado a mao: desligar a notificacao nos
  /// ajustes do Android some com o aviso mas nao conta nada ao servidor, que
  /// continuaria mandando para o vazio.
  final bool pushEnabled;

  /// Primeiro nome, usado nas saudacoes da interface.
  String get firstName => name.split(' ').first;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      mustChangePassword: json['mustChangePassword'] as bool? ?? false,
      birthDate: parseDateKey(json['birthDate'] as String?),
      gender: Gender.fromApi(json['gender'] as String?),
      avatarUrl: json['avatarUrl'] as String?,
      pushEnabled: json['pushEnabled'] as bool? ?? true,
    );
  }
}

/// Resumo de uma equipe da qual o usuario participa. A Etapa 2 usa isto no
/// onboarding para decidir entre "criar equipe" e ir direto para a agenda.
class TeamSummary {
  const TeamSummary({
    required this.membershipId,
    required this.teamId,
    required this.name,
    required this.role,
    required this.displayName,
  });

  final String membershipId;
  final String teamId;
  final String name;
  final String role;
  final String displayName;

  bool get canManage => role == 'OWNER' || role == 'LEADER';

  factory TeamSummary.fromJson(Map<String, dynamic> json) {
    return TeamSummary(
      membershipId: json['membershipId'] as String,
      teamId: json['teamId'] as String,
      name: json['name'] as String,
      role: json['role'] as String,
      displayName: json['displayName'] as String,
    );
  }
}

class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

/// Uma equipe citada na prévia da exclusão da conta.
class TeamRef {
  const TeamRef({required this.teamId, required this.name});

  final String teamId;
  final String name;

  factory TeamRef.fromJson(Map<String, dynamic> json) {
    return TeamRef(
      teamId: json['teamId'] as String,
      name: json['name'] as String,
    );
  }
}

/// O que a exclusão da conta faria agora (`GET /users/me/deletion-preview`).
///
/// [blockedBy]: equipes de que a pessoa é dona e em que ainda há outro
/// integrante com conta -- a posse precisa passar antes. [teamsDeleted]:
/// equipes de que ela é dona e em que ninguém mais tem conta, e que vão junto.
class AccountDeletionPreview {
  const AccountDeletionPreview({
    required this.blockedBy,
    required this.teamsDeleted,
  });

  final List<TeamRef> blockedBy;
  final List<TeamRef> teamsDeleted;

  bool get isBlocked => blockedBy.isNotEmpty;

  factory AccountDeletionPreview.fromJson(Map<String, dynamic> json) {
    List<TeamRef> teams(String key) => ((json[key] as List<dynamic>?) ?? [])
        .map((e) => TeamRef.fromJson(e as Map<String, dynamic>))
        .toList();
    return AccountDeletionPreview(
      blockedBy: teams('blockedBy'),
      teamsDeleted: teams('teamsDeleted'),
    );
  }
}
