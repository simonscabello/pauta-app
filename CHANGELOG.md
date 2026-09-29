# Changelog — Pauta (app)

As versões do aplicativo, Android e Web. Cada versão é uma tag `vX.Y.Z`
neste repositório e um Release no GitHub com o APK; a versão Web vai ao ar
com o push em `master`. A mais recente vem primeiro.

As mudanças de servidor que acompanham cada versão estão no `CHANGELOG.md`
do `pauta-api`.

## 0.31.0 — 29/09/2026

### Melhorias
- Sugerir uma música ficou mais rápido: o motivo agora é opcional. Acima do
  campo há frases prontas — "Letra bíblica", "Música animada", "Boa para
  adoração", "Fácil de aprender", "A igreja já conhece" — que um toque
  escreve no campo e outro toque tira. Dá para completar à mão.
- Sugestão enviada sem motivo aparece sem linha em branco na lista, na
  montagem das músicas da escala e na tela da sugestão.

## 0.30.0 — 28/09/2026

### Novidades
- Grupo do WhatsApp: em Gerenciar equipe, quem lidera vincula o grupo do
  louvor colando um código nele. Depois, "Enviar para o grupo", na tela da
  escala publicada, manda a escala para lá pelo número do Pauta — o mesmo
  texto do botão de compartilhar. Só aparece quando o envio está ligado.

### Melhorias
- A política de privacidade explica o envio da escala ao grupo do WhatsApp
  pelo número do Pauta: só quando a liderança pede, e sem ler as conversas.

## 0.29.1 — 28/09/2026

### Correções
- Criar equipe agora leva ao Início logo depois de criar, já com a equipe
  nova escolhida. Antes a tela ficava parada, e tocar de novo criava outra
  equipe com o mesmo nome.

## 0.29.0 — 28/09/2026

### Melhorias
- A chave de assistente de IA com "Também criar escalas" agora também põe as
  músicas nas escalas; os textos da chave, da lista de chaves, da Ajuda e da
  política de privacidade dizem isso.

## 0.28.0 — 28/09/2026

### Novidades
- "Também criar escalas" ao criar a chave de assistente de IA, só para quem
  lidera: o assistente monta as escalas do mês a partir de uma imagem ou
  texto, sempre em rascunho. Publicar continua sendo no app.
- Selo "Cria escalas" na lista de chaves.
- Ajuda: "Posso cadastrar a escala do mês mandando uma imagem para a IA?".

### Melhorias
- Política de privacidade descreve a conexão que também cria escalas.

## 0.27.0 — 26/09/2026

### Novidades
- Relatórios com o período escolhido (últimos meses ou datas marcadas) e
  filtro por dia da semana.
- Participação por função: quem serviu, quem não pôde e quem ficou livre,
  incluindo quem sabe a função e não foi chamado.
- Aba "Por pessoa" em "Quem não pode", para quem lidera.

### Melhorias
- Participação ordenada de quem mais serviu para quem menos.

## 0.26.0 — 26/09/2026

### Novidades
- Perfil › Segurança › Assistentes de IA: criar a chave (com senha e prazo),
  vê-la uma vez com o comando do Claude Code, e a lista com último uso, prazo
  e revogar.

### Melhorias
- O motivo de quem avisou que não pode fica visível só para quem lidera; o
  campo avisa isso.
- Política de privacidade fala dos assistentes de IA.

## 0.25.0 — 23/09/2026

### Novidades
- Excluir a própria conta, em Perfil › Meus dados.
- Passar a posse da equipe, na ficha do integrante.
- Política de privacidade, termos de uso e página de exclusão de conta no
  site, com o aviso no cadastro.

### Melhorias
- Idade mínima de 13 anos na data de nascimento.
- Música copiada de outra equipe não traz mais a letra digitada por ela.

## 0.24.0 — 23/09/2026

### Novidades
- "Sair sem salvar?" em todos os formulários (voltar, barra lateral e F5 na
  Web).
- Quem está escalado e avisou que não pode aparece na Home, na agenda e na
  escala, com "Substituir".
- Letra com A−/A+, tela sempre ligada e "Próxima".
- "Esqueci minha senha", "Esta semana na equipe" na Home e filtro de
  rascunhos na agenda.

### Melhorias
- Montagem da escala mais direta: contagem nas abas, momento à vista no
  seletor e "Copiar de Manhã".
- Web mais acessível: leitor de tela, navegação por teclado, anel de foco e
  título da aba por tela.
- Tour de boas-vindas mais curto, com seis paradas.

### Correções
- Toque duplo não pula mais etapa ao criar a escala.
- Avisos não cobrem mais a barra de ação.

## 0.23.0 — 22/09/2026

### Novidades
- Excluir música, com confirmação; quando ela já entrou em escala, o app
  oferece arquivar.
- "Ver no repertório" na sugestão ligada a uma música.

## 0.22.0 — 19/09/2026

### Melhorias
- O pedido de biometria aparece sobre a tela de abertura do app, e não mais
  sobre o formulário de login (parecia que o app tinha deslogado).

## 0.21.0 — 19/09/2026

### Melhorias
- O aviso de versão nova confere de novo ao voltar ao app e ao tocar na
  notificação de atualização.

### Correções
- Um teste da Home dependia do relógio e quebrava a geração do APK.

## 0.20.0 — 18/09/2026

### Melhorias
- Aceitar uma sugestão que veio do Spotify cadastra a música direto, sem
  buscá-la de novo.

### Correções
- `pubspec.yaml` sem BOM e com os acentos dos comentários de volta.

## 0.19.0 — 18/09/2026

### Novidades
- Entrar com biometria (Android).
- Senha salva e sugerida pelo gerenciador de senhas do aparelho e do
  navegador.

### Melhorias
- A sessão se renova sozinha e sobrevive à falta de rede — antes, abrir o app
  sem sinal podia deslogar.

## 0.18.0 — 18/09/2026

### Novidades
- Boas-vindas e tour pela interface no primeiro acesso de quem é integrante.
- Central de Ajuda, com perguntas frequentes, em Perfil › Ajuda.

## 0.17.1 — 17/09/2026

### Correções
- Os dois cultos voltam a aparecer no celular, na faixa de horários.
- "Voltar" com o teclado aberto só fecha o teclado.
- Tocar num dia de "Quem não pode" só mostra quem não pode.

## 0.17.0 — 17/09/2026

### Melhorias
- Revisão visual do app inteiro no padrão da tela da música: cabeçalho de
  detalhe, botão principal no rodapé, folhas no celular e diálogos no
  monitor, e horas de 15 em 15 minutos.
- Gerenciar equipe em dois grupos; Análise e Uso do repertório numa tela com
  abas.

## 0.16.1 — 17/09/2026

### Melhorias
- O tom desta escala também é escolhido numa lista; textos mais diretos.

## 0.16.0 — 16/09/2026

### Melhorias
- Tela da música na ordem do ensaio: tom, tipo e andamento, temas, Preparação
  (Cifra, Letra, YouTube e Spotify) e a letra completa.
- O tom é escolhido numa grade com os 34 tons, e não mais digitado.

## 0.15.2 — 14/09/2026

### Melhorias
- No texto do WhatsApp, o momento do culto é dito uma vez para as músicas
  seguidas.

## 0.15.1 — 14/09/2026

### Melhorias
- As músicas novas viram o atalho "Músicas novas" na Home, no lugar da lista.

## 0.15.0 — 14/09/2026

### Novidades
- O seletor da escala mostra quando cada música foi cantada e quantas vezes.
- Sugestões do Pauta por momento do culto.
- Análise do repertório e histórico de uso na tela da música (para quem
  lidera).

### Melhorias
- Diagnóstico de conexão reescrito para quem usa o app.

## 0.14.0 — 12/09/2026

### Novidades
- Hinários: o número do hino em qualquer livro (Cantor Cristão, HCC, Harpa
  Cristã), com um principal.
- Momento do culto em cada música da escala, na tela e no texto do WhatsApp.

## 0.13.0 — 12/09/2026

### Melhorias
- Texto do WhatsApp mais curto, no formato que a equipe já usava no grupo.
- O link da letra deixa de ser obrigatório para sugerir uma música.
- O motivo de uma ausência se corrige por dia.

## 0.12.0 — 11/09/2026

### Novidades
- A sugestão traz onde encontrar a música: letra ou cifra, Spotify e
  YouTube.

### Melhorias
- Lista de sugestões compacta, com uma tela própria para aceitar ou recusar.

## 0.11.0 — 11/09/2026

### Melhorias
- Calendário da agenda com os dias pintados e um traço por compromisso.
- Um botão só, "+ Nova", para escala ou evento.
- Da música da escala para o repertório em um toque.
- Escala com a foto de quem está escalado e "Ver mais N integrantes".

## 0.10.0 — 09/09/2026

### Novidades
- Repertório "definido na hora", para o culto em que as músicas saem no
  momento.

### Melhorias
- Criar escala mais curto: o dia vem da grade de cultos e os campos raros
  ficam recolhidos; "paleta de roupas".

## 0.9.0 — 09/09/2026

### Novidades
- Eventos da equipe (reunião, ensaio geral, confraternização) na agenda.

### Melhorias
- A Home deixa de listar escalas; atalho para Minha disponibilidade.

## 0.8.0 — 09/09/2026

### Melhorias
- A agenda ganha o visual da Home e o recorte "Minhas escalas".

## 0.7.0 — 09/09/2026

### Novidades
- Agenda mensal com calendário e os compromissos de cada dia.

## 0.6.0 — 09/09/2026

### Novidades
- Início (Home): a primeira tela responde "quando eu toco?".

## 0.5.0 — 08/09/2026

### Novidades
- Notificações push; tocar no aviso abre a escala certa, na equipe certa.

## 0.4.0 — 08/09/2026

### Melhorias
- A próxima escala ganha uma manchete em destaque, e a lista embaixo fica em
  degraus.

## 0.3.0 — 07/09/2026

### Melhorias
- Louve! passa a se chamar Pauta.

### Correções
- Um comentário no `colors.xml` quebrava o build do Android.

## 0.2.0 — 06/09/2026

Primeira versão distribuída como APK.

### Novidades
- Agenda com as escalas da equipe e as datas da grade ainda sem escala.
- Escalas com um ou mais cultos, ensaio, local, observações e ministrante.
- Escalação com as regras da banda (um instrumento por pessoa, técnica fora
  da banda), recado individual e convidados de fora.
- Rascunho e publicação, histórico de alterações e edição simultânea
  protegida.
- Repertório: cadastro, busca no Spotify e em outras equipes, temas, hinos,
  música nova e arquivo.
- Músicas por culto na escala, com tom desta escala; criar a escala emenda
  em escalar a equipe e escolher as músicas.
- Sugestões de música pela equipe.
- Minha disponibilidade e o calendário "Quem não pode".
- Ficha do integrante, aniversários, promover a líder e redefinir senha.
- Perfil com dados, senha e foto; compartilhar a escala no WhatsApp.
- Versão Web responsiva, com barra lateral no computador.

### Correções
- O título vazio de outra escala não derruba mais a tela.
- Testes que dependiam do relógio da máquina.
