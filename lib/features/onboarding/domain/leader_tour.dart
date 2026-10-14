import 'member_tour.dart';

/// As paradas do tour de quem lidera, na ordem em que se monta uma equipe.
///
/// **Curto de propósito**: é onde fica cada coisa, e não como se faz cada uma
/// — o passo a passo é o guia do líder no site, que o fim do tour oferece. O
/// tour que mostra tudo seria o maçante que ninguém termina.
///
/// Cada alvo mora num bloco filho direto de lista não preguiçosa (ver
/// `docs/produto/onboarding.md`). Mudou uma destas telas, confira o tour — e
/// o mapa do conteúdo no mesmo arquivo.
List<TourStep> leaderTourSteps() => const [
      TourStep(
        title: 'A equipe, num lugar só',
        body: 'A aba Equipe é o painel: repertório, pessoas, cultos e '
            'configurações, cada um no seu grupo. É por aqui que você monta a '
            'equipe.',
        route: '/equipe',
        target: TourTargetIds.teamManage,
      ),
      TourStep(
        title: 'Cultos da igreja',
        body: 'Comece pelos horários que se repetem toda semana. Eles vêm '
            'prontos ao criar uma escala. Aqui também você escolhe se a escala '
            'é do dia inteiro ou de cada culto.',
        route: '/equipe/cultos',
        target: TourTargetIds.servicesAdd,
      ),
      TourStep(
        title: 'Integrantes',
        body: 'Cadastre quem canta, toca e opera, com as funções de cada um. '
            'A pessoa não precisa ter o app para entrar na escala.',
        route: '/equipe/integrantes',
        target: TourTargetIds.membersAdd,
      ),
      TourStep(
        title: 'Convites',
        body: 'Com o código, cada um entra no app e passa a ver onde está '
            'escalado. Mande pelo WhatsApp do grupo.',
        route: '/equipe/convites',
        target: TourTargetIds.invitesGeneral,
      ),
      TourStep(
        title: 'Repertório',
        body: 'As músicas da equipe, com letra, cifra e tom. A busca acha a '
            'música na internet e preenche quase tudo.',
        route: '/equipe/musicas',
        target: TourTargetIds.songsAdd,
      ),
      TourStep(
        title: 'A escala',
        body: 'Em "Nova", você monta a escala: quem serve, as músicas e o '
            'ensaio. Ela nasce como rascunho, e a equipe só vê e recebe o '
            'aviso quando você publica.',
        route: '/agenda',
        target: TourTargetIds.agendaNew,
      ),
      TourStep(
        title: 'O que falta',
        body: 'Na Início, os primeiros passos mostram o que ainda falta para a '
            'equipe ficar pronta. O passo a passo completo está no guia do '
            'líder.',
        route: '/inicio',
        target: TourTargetIds.homeSetup,
      ),
    ];
