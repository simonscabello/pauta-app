import '../../team/domain/service_template.dart';
import '../../team/domain/team_models.dart';

/// Um passo para a equipe começar a usar o Pauta.
class TeamSetupStep {
  const TeamSetupStep({
    required this.title,
    required this.hint,
    required this.route,
    required this.done,
  });

  final String title;

  /// O que fazer, numa linha. Some quando o passo está feito.
  final String hint;
  final String route;
  final bool done;
}

/// Os primeiros passos de quem acabou de criar a equipe, na ordem em que
/// fazem sentido: a grade diz quando há culto, os integrantes são quem toca,
/// o convite traz cada um para o app, e a primeira escala junta tudo.
///
/// **Cada passo é lido do que a equipe já tem**, e não de uma lista de
/// tarefas marcadas: quem cadastrou a grade pelo assistente ou recebeu a
/// equipe pronta já vê o passo feito. Uma equipe que já passou por tudo não
/// vê nada -- o bloco só existe enquanto falta alguma coisa.
List<TeamSetupStep> teamSetupSteps({
  required List<ServiceTemplate> templates,
  required List<Member> members,
  required bool hasSchedules,
}) {
  final daEquipe = members.where((m) => !m.isGuest).toList();
  final comConta = daEquipe.where((m) => m.hasAccount).length;
  return [
    TeamSetupStep(
      title: 'Cadastrar os cultos da semana',
      hint: 'Dia e horário de cada culto. É a base de toda escala.',
      route: '/equipe/cultos',
      done: templates.isNotEmpty,
    ),
    TeamSetupStep(
      title: 'Cadastrar os integrantes',
      hint: 'Nome e o que cada um toca. Não precisa ter o app ainda.',
      route: '/equipe',
      done: daEquipe.length >= 2,
    ),
    TeamSetupStep(
      title: 'Convidar a equipe para o app',
      hint: 'Com o convite, cada um vê onde está escalado.',
      route: '/equipe/convites',
      done: comConta >= 2,
    ),
    TeamSetupStep(
      title: 'Montar a primeira escala',
      hint: 'Quem toca o quê, o ensaio e as músicas.',
      route: '/agenda/novo',
      done: hasSchedules,
    ),
  ];
}
