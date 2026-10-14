import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/features/home/domain/team_setup.dart';
import 'package:louvor_app/features/team/domain/service_template.dart';
import 'package:louvor_app/features/team/domain/team_models.dart';

/// Os primeiros passos de uma equipe nova são lidos do que ela já tem. O que
/// se trava aqui: convidado não conta como integrante, e a equipe montada não
/// tem passo nenhum por fazer -- é isso que faz o bloco sumir da Home.
void main() {
  test('equipe recém-criada: tudo por fazer', () {
    final passos = teamSetupSteps(
      templates: const [],
      members: [_member('dono', hasAccount: true)],
      hasSchedules: false,
    );
    expect(passos.where((p) => p.done), isEmpty);
    expect(passos.first.route, '/equipe/cultos');
  });

  test('convidado não conta como integrante nem como convite aceito', () {
    final passos = teamSetupSteps(
      templates: const [],
      members: [
        _member('dono', hasAccount: true),
        _member('de fora', hasAccount: false, isGuest: true),
      ],
      hasSchedules: false,
    );
    expect(passos[1].done, isFalse);
    expect(passos[2].done, isFalse);
  });

  test('equipe montada não tem nada por fazer', () {
    final passos = teamSetupSteps(
      templates: [_template()],
      members: [
        _member('dono', hasAccount: true),
        _member('maria', hasAccount: true),
      ],
      hasSchedules: true,
    );
    expect(passos.every((p) => p.done), isTrue);
  });
}

Member _member(String name, {required bool hasAccount, bool isGuest = false}) =>
    Member.fromJson({
      'id': 'm-$name',
      'displayName': name,
      'role': 'MEMBER',
      'hasAccount': hasAccount,
      'isGuest': isGuest,
      'positions': const <dynamic>[],
    });

ServiceTemplate _template() => ServiceTemplate.fromJson({
      'id': 't1',
      'label': 'Manhã',
      'weekday': 0,
      'startMinutes': 540,
    });
