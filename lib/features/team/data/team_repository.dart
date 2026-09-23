import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/date/civil_date.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/shared_preferences_provider.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/service_template.dart';
import '../domain/team_models.dart';
import '../domain/workload_report.dart';

class TeamRepository {
  const TeamRepository(this._dio);

  final Dio _dio;

  Future<Team> create({required String name}) async {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/teams',
        data: {'name': name},
      );
      return Team.fromJson(response.data!);
    });
  }

  Future<Team> find(String teamId) async {
    return _guard(() async {
      final response = await _dio.get<Map<String, dynamic>>('/teams/$teamId');
      return Team.fromJson(response.data!);
    });
  }

  Future<List<Member>> members(
    String teamId, {
    bool includeGuests = false,
  }) async {
    return _guard(() async {
      final response = await _dio.get<List<dynamic>>(
        '/teams/$teamId/members',
        queryParameters: includeGuests ? {'includeGuests': true} : null,
      );
      return response.data!
          .map((e) => Member.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// O fuso não entra: é sempre o de Brasília, e a API nem aceita o campo.
  Future<Team> update(String teamId, {required String name}) async {
    return _guard(() async {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/teams/$teamId',
        data: {'name': name},
      );
      return Team.fromJson(response.data!);
    });
  }

  Future<List<Position>> positions(
    String teamId, {
    bool includeInactive = false,
  }) async {
    return _guard(() async {
      final response = await _dio.get<List<dynamic>>(
        '/teams/$teamId/positions',
        queryParameters: includeInactive ? {'includeInactive': true} : null,
      );
      return response.data!
          .map((e) => Position.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Position> addPosition(
    String teamId, {
    required String name,
    required String category,
  }) async {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/teams/$teamId/positions',
        data: {'name': name, 'category': category},
      );
      return Position.fromJson(response.data!);
    });
  }

  Future<Position> updatePosition(
    String teamId,
    String positionId, {
    String? name,
    String? category,
    bool? isActive,
  }) async {
    return _guard(() async {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/teams/$teamId/positions/$positionId',
        data: {
          if (name != null) 'name': name,
          if (category != null) 'category': category,
          if (isActive != null) 'isActive': isActive,
        },
      );
      return Position.fromJson(response.data!);
    });
  }

  /// A API desativa em vez de apagar: escalas passadas continuam apontando
  /// para a função, e apagá-la reescreveria o histórico.
  Future<void> deactivatePosition(String teamId, String positionId) async {
    return _guard(() async {
      await _dio.delete<void>('/teams/$teamId/positions/$positionId');
    });
  }

  // --- Grade de cultos da igreja ---

  Future<List<ServiceTemplate>> serviceTemplates(String teamId) async {
    return _guard(() async {
      final response =
          await _dio.get<List<dynamic>>('/teams/$teamId/service-templates');
      return response.data!
          .map((e) => ServiceTemplate.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<ServiceTemplate> addServiceTemplate(
    String teamId, {
    required String label,
    required int weekday,
    required int startMinutes,
  }) async {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/teams/$teamId/service-templates',
        data: {
          'label': label,
          'weekday': weekday,
          'startMinutes': startMinutes,
        },
      );
      return ServiceTemplate.fromJson(response.data!);
    });
  }

  /// Escalas futuras que usam esta linha da grade.
  ///
  /// Consultado **antes** de salvar, para o app perguntar se a mudança também
  /// vale para elas em vez de decidir sozinho.
  Future<List<AffectedEvent>> serviceTemplateFutureEvents(
    String teamId,
    String templateId,
  ) async {
    return _guard(() async {
      final response = await _dio.get<List<dynamic>>(
        '/teams/$teamId/service-templates/$templateId/future-events',
      );
      return response.data!
          .map((e) => AffectedEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<ServiceTemplate> updateServiceTemplate(
    String teamId,
    String templateId, {
    String? label,
    int? weekday,
    int? startMinutes,
    bool applyToFutureEvents = false,
  }) async {
    return _guard(() async {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/teams/$teamId/service-templates/$templateId',
        data: {
          if (label != null) 'label': label,
          if (weekday != null) 'weekday': weekday,
          if (startMinutes != null) 'startMinutes': startMinutes,
          if (applyToFutureEvents) 'applyToFutureEvents': true,
        },
      );
      return ServiceTemplate.fromJson(response.data!);
    });
  }

  Future<void> removeServiceTemplate(String teamId, String templateId) async {
    return _guard(() async {
      await _dio.delete<void>('/teams/$teamId/service-templates/$templateId');
    });
  }

  Future<Member> addMember(
    String teamId, {
    required String displayName,
    String? phone,
    String? notes,
    List<String> positionIds = const [],
  }) async {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/teams/$teamId/members',
        data: {
          'displayName': displayName,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
          if (positionIds.isNotEmpty) 'positionIds': positionIds,
        },
      );
      return Member.fromJson(response.data!);
    });
  }

  /// Convidado: entra na escala e no texto compartilhado, mas não vira
  /// integrante nem recebe convite.
  Future<Member> addGuest(String teamId, String displayName) {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/teams/$teamId/members',
        data: {'displayName': displayName, 'isGuest': true},
      );
      return Member.fromJson(response.data!);
    });
  }

  /// O afastamento vai **inteiro** ou não vai: `onLeave`, a previsão e o
  /// motivo saem juntos do formulário, e mandar um sem o outro deixaria no
  /// banco a metade que ninguém escreveu.
  Future<Member> updateMember(
    String teamId,
    String membershipId, {
    String? displayName,
    String? phone,
    String? notes,
    List<String>? positionIds,

    /// `LEADER` ou `MEMBER`. `OWNER` o servidor não aceita: o dono é quem criou
    /// a equipe, e isso não se atribui.
    String? role,
    bool? onLeave,
    DateTime? leaveUntil,
    String? leaveReason,
  }) async {
    return _guard(() async {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/teams/$teamId/members/$membershipId',
        data: {
          if (displayName != null) 'displayName': displayName,
          if (phone != null) 'phone': phone,
          // String vazia é intenção de apagar, e o servidor a lê como `null`.
          if (notes != null) 'notes': notes,
          if (positionIds != null) 'positionIds': positionIds,
          if (role != null) 'role': role,
          if (onLeave != null) ...{
            'onLeave': onLeave,
            // Desligar já limpa os dois no servidor; mandá-los aqui seria
            // repetir a regra em dois lugares.
            if (onLeave) 'leaveUntil':
                leaveUntil == null ? null : dateKey(leaveUntil),
            if (onLeave) 'leaveReason': leaveReason ?? '',
          },
        },
      );
      return Member.fromJson(response.data!);
    });
  }

  /// Redefine a senha de um integrante e devolve a temporária — **uma vez**.
  ///
  /// Substitui a recuperação por e-mail, que o projeto não tem: quem esquece a
  /// senha fala com quem lidera, e a pessoa entra com esta e é obrigada a
  /// trocar no próximo acesso. As sessões abertas caem junto, do lado do
  /// servidor.
  ///
  /// A senha **não volta a aparecer**: ela nunca é gravada em claro, nem aqui
  /// nem lá. Se a tela perder o texto, o caminho é redefinir de novo.
  Future<String> resetMemberPassword(String teamId, String membershipId) async {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/teams/$teamId/members/$membershipId/reset-password',
      );
      return response.data!['temporaryPassword'] as String;
    });
  }

  /// Passa a posse da equipe. Só o dono chama; ele sai dela como LEADER.
  Future<Member> transferOwnership(String teamId, String membershipId) async {
    return _guard(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/teams/$teamId/members/$membershipId/transfer-ownership',
      );
      return Member.fromJson(response.data!);
    });
  }

  Future<void> removeMember(String teamId, String membershipId) async {
    return _guard(() async {
      await _dio.delete<void>('/teams/$teamId/members/$membershipId');
    });
  }

  Future<WorkloadReport> workload(String teamId, {int weeks = 8}) async {
    return _guard(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/teams/$teamId/reports/workload',
        queryParameters: {'weeks': weeks},
      );
      return WorkloadReport.fromJson(response.data!);
    });
  }

  Future<RotationReport> rotation(String teamId, {int weeks = 8}) async {
    return _guard(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/teams/$teamId/reports/rotation',
        queryParameters: {'weeks': weeks},
      );
      return RotationReport.fromJson(response.data!);
    });
  }

  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final teamRepositoryProvider = Provider<TeamRepository>((ref) {
  return TeamRepository(ref.watch(dioProvider));
});

class ActiveTeamController extends StateNotifier<String?> {
  ActiveTeamController(this._prefs, List<String> availableTeamIds)
      : _availableTeamIds = availableTeamIds.toSet(),
        super(_initialValue(_prefs, availableTeamIds));

  static const _key = 'active_team_id';

  final SharedPreferences _prefs;
  final Set<String> _availableTeamIds;

  static String? _initialValue(
    SharedPreferences prefs,
    List<String> availableTeamIds,
  ) {
    final saved = prefs.getString(_key);
    if (saved != null && availableTeamIds.contains(saved)) return saved;
    return availableTeamIds.firstOrNull;
  }

  Future<void> select(String teamId) async {
    if (!_availableTeamIds.contains(teamId) || state == teamId) return;
    state = teamId;
    await _prefs.setString(_key, teamId);
  }
}

/// Equipe usada pela Agenda e pelas telas de gestão. A escolha fica no
/// aparelho e só é restaurada quando a conta ainda participa daquela equipe.
final activeTeamIdProvider =
    StateNotifierProvider<ActiveTeamController, String?>((ref) {
  final teams = ref.watch(authControllerProvider).teams;
  return ActiveTeamController(
    ref.watch(sharedPreferencesProvider),
    teams.map((team) => team.teamId).toList(),
  );
});

final membersProvider =
    FutureProvider.autoDispose.family<List<Member>, String>((ref, teamId) {
  return ref.watch(teamRepositoryProvider).members(teamId);
});

/// Quem pode ser escalado: integrantes + convidados. Separado do
/// [membersProvider] porque convidado não é integrante e não deve aparecer na
/// tela de equipe.
final schedulableMembersProvider =
    FutureProvider.autoDispose.family<List<Member>, String>((ref, teamId) {
  return ref.watch(teamRepositoryProvider).members(teamId, includeGuests: true);
});

/// Cadastra um músico de fora e devolve o registro criado.
final addGuestProvider =
    Provider<Future<Member> Function(String teamId, String displayName)>((ref) {
  return (teamId, displayName) =>
      ref.read(teamRepositoryProvider).addGuest(teamId, displayName);
});

final positionsProvider =
    FutureProvider.autoDispose.family<List<Position>, String>((ref, teamId) {
  return ref.watch(teamRepositoryProvider).positions(teamId);
});

/// Inclui as funções desativadas — só a tela de gestão precisa vê-las.
final allPositionsProvider =
    FutureProvider.autoDispose.family<List<Position>, String>((ref, teamId) {
  return ref
      .watch(teamRepositoryProvider)
      .positions(teamId, includeInactive: true);
});

final teamProvider =
    FutureProvider.autoDispose.family<Team, String>((ref, teamId) {
  return ref.watch(teamRepositoryProvider).find(teamId);
});

typedef WorkloadQuery = ({String teamId, int weeks});

final workloadProvider = FutureProvider.autoDispose
    .family<WorkloadReport, WorkloadQuery>((ref, query) {
  return ref
      .watch(teamRepositoryProvider)
      .workload(query.teamId, weeks: query.weeks);
});

/// Janela do rodízio: oito semanas, dois meses de domingos. Curta o bastante
/// para descrever o momento da equipe, longa o bastante para que quem serve
/// uma vez por mês apareça com mais de um.
const rotationWeeks = 8;

/// Quanto tempo faz e quantas escalas cada pessoa teve. Alimenta o seletor da
/// escalação, e por isso é por equipe, não por escala.
final rotationProvider =
    FutureProvider.autoDispose.family<RotationReport, String>((ref, teamId) {
  return ref.watch(teamRepositoryProvider).rotation(teamId, weeks: rotationWeeks);
});

/// A grade de cultos da igreja. Leitura liberada a qualquer integrante: a tela
/// de nova escala depende dela.
final serviceTemplatesProvider = FutureProvider.autoDispose
    .family<List<ServiceTemplate>, String>((ref, teamId) {
  return ref.watch(teamRepositoryProvider).serviceTemplates(teamId);
});
