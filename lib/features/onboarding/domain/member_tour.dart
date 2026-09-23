/// Os pontos da interface que o tour sabe destacar.
///
/// Cada tela marca o seu com [TourTarget] (ver `tour_target.dart`), usando
/// estes nomes. Nome fora desta lista não é destacado por ninguém — por isso
/// eles moram juntos, e não como texto solto em cada tela.
abstract final class TourTargetIds {
  /// A manchete da Home: a minha próxima escala, ou o "livre por enquanto".
  static const homeNext = 'home.next';

  /// A seção "Músicas" do detalhe da escala.
  static const eventSongs = 'event.songs';

  /// O atalho "Minha disponibilidade" da Home.
  static const homeAvailability = 'home.availability';

  /// O calendário da Agenda.
  static const agendaCalendar = 'agenda.calendar';

  /// A linha "Repertório" da aba Equipe (Sugestões fica logo abaixo).
  static const teamRepertoire = 'team.repertoire';

  /// O interruptor "Avisos no celular" do Perfil (só existe no Android).
  static const profilePush = 'profile.push';
}

/// Uma parada do tour: para onde ir, o que destacar e o que dizer.
///
/// [route] é para onde o app navega antes de destacar — o tour anda pelo app
/// de verdade, em vez de mostrar desenhos dele. [target] nulo é um cartão no
/// meio da tela, sem destaque: é o que sobra quando o ponto não existe nesta
/// plataforma (o interruptor de avisos na Web).
class TourStep {
  const TourStep({
    required this.title,
    required this.body,
    this.route,
    this.target,
  });

  final String title;
  final String body;
  final String? route;
  final String? target;
}

/// O que o tour precisa saber da pessoa para escolher o caminho.
class MemberTourContext {
  const MemberTourContext({
    required this.nextScheduleId,
    required this.pushSupported,
  });

  /// A minha próxima escala. Nula quando a pessoa não está em nenhuma — e aí
  /// as músicas são explicadas a partir da manchete da Home, em vez de abrir
  /// uma escala que não é dela.
  final String? nextScheduleId;

  /// Se este aparelho recebe aviso. Na Web não recebe, e o Perfil nem mostra
  /// o interruptor — o tour não pode apontar para ele.
  final bool pushSupported;
}

/// O tour dos integrantes, na ordem em que a pessoa usa o app numa semana.
///
/// **Oito paradas, uma ideia cada.** Não é manual: ensina onde as coisas
/// ficam e para que servem, e o resto a pessoa descobre tocando. Os textos
/// seguem a regra dos avisos — curtos, sem termo técnico, e dizendo o que a
/// pessoa faz, não como o app funciona.
///
/// **Disponibilidade tem duas paradas**, e é a única: é o que o integrante
/// *faz* no app além de ler, é o que tem prazo, e a Home mostra só a porta —
/// a segunda parada mostra o botão lá dentro.
List<TourStep> memberTourSteps(MemberTourContext context) {
  final nextId = context.nextScheduleId;

  return [
    TourStep(
      route: '/inicio',
      target: TourTargetIds.homeNext,
      title: 'Sua próxima escala',
      body: nextId != null
          ? 'Aqui aparece a próxima vez que você vai servir: o dia, o horário, '
              'a sua função e o ensaio. Toque no cartão para ver a escala '
              'completa.'
          : 'Quando você for escalado, a escala aparece aqui, com o dia, o '
              'horário, a sua função e o ensaio.',
    ),
    if (nextId != null)
      TourStep(
        route: '/agenda/$nextId',
        target: TourTargetIds.eventSongs,
        title: 'Músicas da escala',
        body: 'Estas são as músicas para preparar. Toque em uma delas para ver '
            'a letra, a cifra, o vídeo e o tom combinado para esta escala.',
      )
    else
      const TourStep(
        route: '/inicio',
        target: TourTargetIds.homeNext,
        title: 'Músicas da escala',
        body: 'Dentro da escala ficam as músicas para preparar. Toque em uma '
            'delas para ver a letra, a cifra, o vídeo e o tom combinado.',
      ),
    // **Uma parada para a disponibilidade, e não duas.** O tour tinha oito
    // paradas em cinco telas — longo demais para quem tem pouca intimidade com
    // aplicativo, que é justamente quem mais precisa dele. "Escolher dias"
    // virou uma frase desta parada, em vez de uma tela a mais.
    const TourStep(
      route: '/inicio',
      target: TourTargetIds.homeAvailability,
      title: 'Informe sua disponibilidade',
      body: 'Aqui você avisa os dias em que não pode servir: toque em Escolher '
          'dias e marque no calendário. Se você já estiver escalado num '
          'desses dias, quem lidera fica sabendo.',
    ),
    const TourStep(
      route: '/agenda',
      target: TourTargetIds.agendaCalendar,
      title: 'Agenda da equipe',
      body: 'Os dias pintados têm compromisso: escalas, com o horário do '
          'ensaio, e eventos, como reuniões. Toque num dia para ver o que está '
          'marcado. Em Minhas escalas, só as suas.',
    ),
    // Repertório e Sugestões numa parada só: as duas moram lado a lado na
    // aba Equipe, e eram duas paradas na mesma tela.
    const TourStep(
      route: '/equipe',
      target: TourTargetIds.teamRepertoire,
      title: 'Repertório e sugestões',
      body: 'No Repertório estão todas as músicas da equipe, com letra, cifra '
          'e vídeo. Em Sugestões, logo abaixo, você sugere uma música e conta '
          'por que ela faria bem à equipe.',
    ),
    if (context.pushSupported)
      const TourStep(
        route: '/perfil',
        target: TourTargetIds.profilePush,
        title: 'Avisos no celular',
        body: 'O Pauta avisa quando você é escalado, quando a escala ou as '
            'músicas mudam e quando sua sugestão é respondida. Também lembra '
            'do ensaio e do dia de servir. Deixe ligado.',
      )
    else
      // Onde não há push (a Web), a parada diz como ter os avisos, em vez de
      // só descrever o que o app faria: instalar o app para Android.
      const TourStep(
        title: 'Avisos no celular',
        body: 'Os avisos chegam pelo aplicativo do Pauta para Android: quando '
            'você é escalado, quando a escala ou as músicas mudam e quando sua '
            'sugestão é respondida. Para instalar, peça o link a quem lidera a '
            'equipe.',
      ),
  ];
}
