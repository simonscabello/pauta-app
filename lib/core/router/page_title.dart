/// O nome da página para a aba do navegador (WCAG 2.4.2).
///
/// A aba dizia "Pauta" em qualquer tela: com três abas do app abertas, ou no
/// histórico do navegador, não havia como saber qual era a escala e qual era o
/// repertório — e o leitor de tela anuncia o título ao trocar de página.
///
/// Pela **forma** da rota, e não por tela: o roteador é o único lugar que sabe
/// de todas, e o título acompanha qualquer caminho de navegação (barra
/// lateral, voltar do navegador, link colado).
String pageTitleFor(String path) {
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  final nome = switch (segments) {
    [] => 'Pauta',
    ['login'] => 'Entrar',
    ['cadastro'] => 'Criar conta',
    ['desbloquear'] => 'Desbloquear',
    ['trocar-senha'] => 'Trocar senha',
    ['diagnostico'] => 'Diagnóstico de conexão',
    ['convite'] => 'Entrar numa equipe',
    ['inicio'] || ['home'] => 'Início',
    ['agenda'] => 'Agenda',
    ['agenda', 'novo'] => 'Nova escala',
    ['agenda', _] => 'Escala',
    ['agenda', _, 'editar'] => 'Editar escala',
    ['agenda', _, 'escalar'] => 'Escalar equipe',
    ['agenda', _, 'repertorio'] => 'Músicas da escala',
    ['agenda', _, 'historico'] => 'Histórico da escala',
    ['eventos', 'novo'] => 'Novo evento',
    ['eventos', _] => 'Evento',
    ['eventos', _, 'editar'] => 'Editar evento',
    ['disponibilidade'] => 'Minha disponibilidade',
    ['equipe'] => 'Equipe',
    ['equipe', 'nova'] => 'Criar equipe',
    ['equipe', 'musicas'] => 'Repertório',
    ['equipe', 'musicas', 'nova'] => 'Adicionar música',
    ['equipe', 'musicas', 'arquivadas'] => 'Músicas arquivadas',
    ['equipe', 'musicas', 'uso'] ||
    ['equipe', 'musicas', 'saude'] =>
      'Relatórios do repertório',
    ['equipe', 'musicas', _] => 'Música',
    ['equipe', 'musicas', _, 'editar'] => 'Editar música',
    ['equipe', 'sugestoes'] => 'Sugestões',
    ['equipe', 'sugestoes', _] => 'Sugestão',
    ['equipe', 'convites'] => 'Convites',
    ['equipe', 'cultos'] => 'Cultos da igreja',
    ['equipe', 'gerenciar'] => 'Gerenciar equipe',
    ['equipe', 'funcoes'] => 'Funções',
    ['equipe', 'dados'] => 'Dados da equipe',
    ['equipe', 'indisponibilidade'] => 'Quem não pode',
    ['equipe', 'participacao'] => 'Participação',
    ['equipe', 'membros', 'novo'] => 'Adicionar integrante',
    ['equipe', 'membros', 'editar'] => 'Editar integrante',
    ['perfil'] => 'Perfil',
    ['perfil', 'dados'] => 'Meus dados',
    ['perfil', 'senha'] => 'Alterar senha',
    ['perfil', 'ajuda'] => 'Ajuda',
    _ => 'Pauta',
  };
  return nome == 'Pauta' ? 'Pauta' : '$nome · Pauta';
}
