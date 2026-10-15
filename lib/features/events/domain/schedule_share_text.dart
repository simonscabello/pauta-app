import 'package:intl/intl.dart';

import '../domain/event_datetime.dart';
import '../domain/event_models.dart';

/// Gera o texto da escala para WhatsApp.
///
/// **O modelo é a mensagem que a equipe digitava à mão no grupo**, antes do
/// app. É o formato que eles já leem sem pensar, e cada linha a mais empurra o
/// repertório para fora da primeira tela do celular:
///
/// ```
/// *Domingo 13/09*
///
/// *Vocal:* Josy (ministrante), Gisely, Simon
/// *Instrumentos:* Gerson (violão), Simon (baixo), Jennifer (bateria)
/// *Datashow:* Larissa
///
/// *Manhã*
///
/// *Dízimos e Ofertas:* 314 CC - Estou Seguro
///
/// * Essa Paz
/// * Alfa e Ômega
/// ```
///
/// Sem cabeçalho "Escala de Louvor" (o grupo já é o do louvor), sem horários
/// (quem recebe já os sabe) e sem tom (cada músico o tem na cifra).
///
/// **Sem emoji, com negrito.** O WhatsApp formata `*assim*`, e o negrito marca
/// seção sem depender de o emoji renderizar igual em todo aparelho.
String buildScheduleShareText(Event event) {
  final timezone =
      event.timezone.isEmpty ? 'America/Sao_Paulo' : event.timezone;
  final buffer = StringBuffer();

  // Na equipe que escala por culto, o culto vai junto da data: as quatro
  // mensagens do domingo começariam todas com o mesmo "*Domingo 13/09*".
  final tag = event.serviceTag;
  final date = _shareDate(event.startsAt, timezone);
  buffer.writeln(_bold(tag == null ? date : '$date · $tag'));
  // O título só existe em culto especial ("Páscoa", "Ceia"), e aí entra logo
  // abaixo da data: é o que transforma "Domingo 13/09" numa data com ocasião.
  if (event.hasTitle) {
    buffer.writeln(_bold(event.title!));
  }
  if (event.location?.isNotEmpty ?? false) {
    buffer.writeln(event.location!);
  }

  _writeTeam(buffer, event);
  _writeSongs(buffer, event);

  if (event.colorPalette?.isNotEmpty ?? false) {
    buffer.writeln();
    // "Roupas", e não "Paleta": quem lê a mensagem no grupo precisa entender
    // sem tradução que aquilo é o combinado de como se vestir no domingo.
    buffer.writeln('${_bold('Roupas:')} ${event.colorPalette}');
  }

  if (event.notes?.isNotEmpty ?? false) {
    buffer.writeln();
    buffer.writeln(_bold('Observações'));
    buffer.writeln(event.notes);
  }

  return buffer.toString().trimRight();
}

/// "Domingo 13/09", "Quinta 17/09" -- como a equipe escreve a data no grupo.
///
/// Sem "-feira" e sem ano: a escala compartilhada é sempre a desta semana ou
/// da próxima, e o dia por extenso já desfaz qualquer dúvida sobre o mês.
String _shareDate(DateTime utc, String timezone) {
  final dia = capitalizeWeekday(formatEventWeekdayName(utc, timezone));
  final data = DateFormat('dd/MM', 'pt_BR').format(
    eventLocalTime(utc, timezone),
  );
  return '$dia $data';
}

/// A equipe: uma linha por função, e **os instrumentos numa linha só**.
///
/// Violão, baixo e bateria em três linhas de uma pessoa cada gastavam a tela
/// com rótulo; juntos, com o instrumento entre parênteses, cabem numa linha e
/// a pessoa continua achando o próprio nome. Vocal, técnica e o resto seguem
/// uma linha por função, porque ali várias pessoas dividem o mesmo papel.
///
/// A linha "Instrumentos" entra onde estaria o primeiro instrumento na ordem
/// da equipe. Função sem categoria (cache de antes do campo) fica na própria
/// linha: melhor não juntar do que juntar errado.
///
/// **Quem ministra vem primeiro na própria função**, com "(ministrante)" ao
/// lado. Já está escalado ali; a linha separada repetiria o nome. O selo vai
/// **uma vez**, na primeira linha em que a pessoa aparece: quem ministra e
/// dirige o culto lia "Ana (ministrante)" nas duas.
void _writeTeam(StringBuffer buffer, Event event) {
  buffer.writeln();

  if (event.assignments.isEmpty) {
    buffer.writeln('Ninguém escalado ainda.');
    _writeLooseMinister(buffer, event, const {});
    return;
  }

  final curtos = _shortNames(event);
  final ministranteId = event.minister?.membershipId;
  var ministranteEscalado = false;

  // A linha dos instrumentos fica onde estaria o primeiro instrumento: se o
  // primeiro grupo com quem ministra é instrumento, o selo vai para o
  // primeiro instrumento dela.
  bool temMinistrante(AssignmentGroup g) =>
      g.members.any((m) => m.membershipId == ministranteId);
  final primeiro = event.assignments.where(temMinistrante).firstOrNull;
  final grupoDoSelo = primeiro != null && primeiro.isInstrument
      ? event.assignments
          .where((g) => g.isInstrument && temMinistrante(g))
          .firstOrNull
      : primeiro;

  String pessoa(
    AssignmentMember member,
    AssignmentGroup group, {
    String? instrumento,
  }) {
    final detalhes = <String>[
      if (instrumento != null) instrumento,
      if (ministranteId != null &&
          member.membershipId == ministranteId &&
          identical(group, grupoDoSelo))
        'ministrante',
      // O recado que o líder escreveu para aquela pessoa ("chega 8h30"): é
      // dirigido a alguém, e fora da linha dela vira aviso de ninguém.
      if (member.note?.isNotEmpty ?? false) member.note!,
    ];
    if (member.membershipId == ministranteId) ministranteEscalado = true;
    final nome = curtos[member.membershipId] ?? member.displayName;
    return detalhes.isEmpty ? nome : '$nome (${detalhes.join(', ')})';
  }

  List<AssignmentMember> ministranteNaFrente(List<AssignmentMember> members) {
    if (ministranteId == null) return members;
    return [
      ...members.where((m) => m.membershipId == ministranteId),
      ...members.where((m) => m.membershipId != ministranteId),
    ];
  }

  final instrumentistas = [
    for (final group in event.assignments.where((g) => g.isInstrument))
      for (final member in ministranteNaFrente(group.members))
        pessoa(member, group, instrumento: _lowerFirst(group.positionName)),
  ];
  var instrumentosEscritos = false;

  for (final group in event.assignments) {
    if (group.isInstrument) {
      if (instrumentosEscritos || instrumentistas.isEmpty) continue;
      instrumentosEscritos = true;
      buffer.writeln(
        '${_bold('Instrumentos:')} ${instrumentistas.join(', ')}',
      );
      continue;
    }
    final pessoas = [
      for (final member in ministranteNaFrente(group.members))
        pessoa(member, group),
    ];
    if (pessoas.isEmpty) continue;
    buffer.writeln('${_bold('${group.positionName}:')} ${pessoas.join(', ')}');
  }

  if (!ministranteEscalado) _writeLooseMinister(buffer, event, curtos);
}

/// Quem ministra sem estar escalado em função nenhuma.
///
/// Acontece com quem só conduz: aí a linha separada volta, porque a
/// alternativa é a mensagem não dizer a quem a equipe se reporta. A regra é
/// não **repetir** o nome, não escondê-lo.
void _writeLooseMinister(
  StringBuffer buffer,
  Event event,
  Map<String, String> curtos,
) {
  final minister = event.minister;
  if (minister == null) return;
  buffer.writeln(
    '${_bold('Ministrante:')} '
    '${curtos[minister.membershipId] ?? minister.displayName}',
  );
}

/// O repertório, com uma seção por culto quando há mais de um.
///
/// Com um culto só o rótulo é "Músicas"; com dois, é o nome de cada um -- é o
/// que impede o vocalista da noite de ensaiar o repertório da manhã.
///
/// **Repertório que falta é dito, e não omitido** -- quem recebe este texto
/// não tem o app para conferir, e a seção que some deixa "esqueceram de
/// mandar" e "ainda não escolheram" com a mesma cara.
///
/// **"Falta" e "é assim que fazemos" são coisas diferentes**, e é o modo de
/// repertório da escala que as separa: no culto em que as músicas saem na hora
/// a lista vazia é o combinado, e anunciá-la como pendência manda a equipe
/// esperar uma mensagem que nunca vem.
void _writeSongs(StringBuffer buffer, Event event) {
  final grupos = [
    for (final grupo in event.songsByService)
      (service: grupo.service, blocos: _songBlocks(grupo.songs)),
  ];
  if (grupos.isEmpty) return;

  final naHora = event.isRepertoireOnTheFly;
  final semNenhuma = grupos.every((grupo) => grupo.blocos.isEmpty);

  // Nada escolhido em culto nenhum: uma seção só. Nomear "Manhã" e "Noite"
  // aqui para dizer o mesmo dos dois lados gastaria quatro linhas com uma
  // informação só.
  if (semNenhuma) {
    buffer.writeln();
    buffer.writeln(_bold('Músicas'));
    buffer.writeln(_semRepertorio(naHora));
    return;
  }

  // Escala de repertório na hora com alguma música já escolhida acontece: o
  // ministrante deixa uma ou duas encaminhadas e resolve o resto no culto. A
  // linha diz isso antes da lista, para ninguém a receber como definitiva.
  if (naHora) {
    buffer.writeln();
    buffer.writeln('Definidas na hora. Por enquanto:');
  }

  // Daqui para baixo pelo menos um culto tem repertório, e aí o culto vazio
  // **precisa** ser nomeado: sem isso, quem canta à noite lê a lista da manhã
  // como o repertório do dia inteiro.
  final separar = grupos.length > 1;
  for (final grupo in grupos) {
    buffer.writeln();
    buffer.writeln(_bold(separar ? grupo.service.label : 'Músicas'));
    if (grupo.blocos.isEmpty) {
      buffer.writeln();
      buffer.writeln(_semRepertorio(naHora));
      continue;
    }
    for (final bloco in grupo.blocos) {
      buffer.writeln();
      bloco.forEach(buffer.writeln);
    }
  }
}

String _semRepertorio(bool naHora) =>
    naHora ? 'Definidas na hora, no culto.' : 'Ainda não escolhidas.';

/// O repertório de um culto em blocos, **na ordem em que vai ser tocado**.
///
/// Músicas **seguidas com o mesmo momento** formam um bloco só, e o momento é
/// dito uma vez:
///
/// ```
/// *Dízimos e Ofertas:* 319 CC - Abrigo Perfeito
///
/// *Momento de Louvor:*
/// * Ajuntamento - Vencedores Por Cristo
/// * Falar Com Deus - Novo Tom
/// ```
///
/// Com uma música só, o momento continua como rótulo na mesma linha. Com duas
/// ou mais, ele vira título e as músicas uma lista embaixo: repetir "*Momento de
/// Louvor:*" em cada linha era rótulo ocupando a tela para dizer a mesma coisa
/// três vezes.
///
/// **Só as seguidas.** Se a oferta cai entre dois louvores, o louvor aparece
/// duas vezes, porque a ordem da mensagem é a ordem do culto -- juntar os dois
/// mandaria a oferta para o lugar errado. "Outro" com nomes diferentes ("Santa
/// Ceia", "Batismo") são momentos diferentes.
///
/// As músicas sem momento seguem a mesma regra, sem título: uma lista com `* `
/// -- o marcador do próprio WhatsApp -- e não numerada, porque com os momentos
/// intercalados "a 3ª" já não diz nada.
List<List<String>> _songBlocks(List<EventSong> songs) {
  final grupos = <({String? momento, List<EventSong> musicas})>[];
  for (final song in songs) {
    if (song.title.isEmpty) continue;

    final momento = song.momentText;
    if (grupos.isNotEmpty && grupos.last.momento == momento) {
      grupos.last.musicas.add(song);
    } else {
      grupos.add((momento: momento, musicas: [song]));
    }
  }

  return [
    for (final grupo in grupos)
      if (grupo.momento == null)
        [for (final song in grupo.musicas) '* ${_songLine(song)}']
      else if (grupo.musicas.length == 1)
        ['${_bold('${grupo.momento}:')} ${_songLine(grupo.musicas.single)}']
      else
        [
          _bold('${grupo.momento}:'),
          for (final song in grupo.musicas) '* ${_songLine(song)}',
        ],
  ];
}

/// `314 CC - Estou Seguro`, `Maravilhoso Senhor - Rafaela Pinho`.
///
/// **O hinário vem na frente**: ninguém pede "Estou Seguro", pede "o 314". Com
/// ele o artista não entra -- o hino é o do livro, e "Cantor Cristão" como
/// artista repetiria a sigla por extenso.
///
/// **Sem hinário, entra o artista**: "Invoca-me" existe em mais de uma versão,
/// e é o nome de quem canta que diz qual ouvir durante a semana.
///
/// Nunca o tom: está na cifra que cada um já abre. "Nova" é o único recado que
/// muda o que a pessoa faz antes do domingo.
String _songLine(EventSong song) {
  final linha = StringBuffer();
  final hinario = song.hymnal;
  if (hinario != null) {
    linha.write('${hinario.label} - ${song.title}');
  } else {
    linha.write(song.title);
    final artista = song.artist?.trim() ?? '';
    if (artista.isNotEmpty) linha.write(' - $artista');
  }
  if (song.isNew) linha.write(' — ${_bold('Nova')}');
  return linha.toString();
}

/// "Violão" vira "violão" dentro do parêntese, onde a maiúscula parece começo
/// de frase. Sigla ("DJ") fica como está.
String _lowerFirst(String value) {
  if (value.isEmpty) return value;
  if (value.length > 1 && value[1] == value[1].toUpperCase() &&
      value[1] != value[1].toLowerCase()) {
    return value;
  }
  return value[0].toLowerCase() + value.substring(1);
}

/// Como a equipe chama cada um: só o primeiro nome.
///
/// É como as pessoas se tratam no grupo, e o nome completo de nove integrantes
/// enche a mensagem de sobrenome que ninguém usa. Mais partes entram **só**
/// quando dois escalados desta escala começam igual -- aí "Simon" viraria
/// adivinhação, e "Simon Lopes"/"Simon Pedro" resolvem. Esgotadas as partes
/// (dois "João Silva" existem), vai o nome como está: nada mais aqui os
/// separa.
Map<String, String> _shortNames(Event event) {
  final completos = <String, String>{};
  for (final group in event.assignments) {
    for (final member in group.members) {
      completos[member.membershipId] = member.displayName.trim();
    }
  }
  final minister = event.minister;
  if (minister != null) {
    completos.putIfAbsent(
      minister.membershipId,
      () => minister.displayName.trim(),
    );
  }

  final porPrimeiroNome = <String, List<String>>{};
  completos.forEach((id, nome) {
    porPrimeiroNome
        .putIfAbsent(_nameKey(_nameParts(nome).first), () => [])
        .add(id);
  });

  final curtos = <String, String>{};
  completos.forEach((id, nome) {
    final partes = _nameParts(nome);
    final homonimos = porPrimeiroNome[_nameKey(partes.first)]!;
    if (homonimos.length == 1) {
      curtos[id] = partes.first;
      return;
    }
    for (var n = 2; n <= partes.length; n++) {
      final prefixo = partes.take(n).toList();
      final unico = homonimos.every(
        (outro) => outro == id || !_startsWithParts(completos[outro]!, prefixo),
      );
      if (unico) {
        curtos[id] = prefixo.join(' ');
        return;
      }
    }
    curtos[id] = nome;
  });
  return curtos;
}

List<String> _nameParts(String name) {
  final partes =
      name.split(RegExp(r'\s+')).where((parte) => parte.isNotEmpty).toList();
  return partes.isEmpty ? [name] : partes;
}

bool _startsWithParts(String name, List<String> prefixo) {
  final partes = _nameParts(name);
  if (partes.length < prefixo.length) return false;
  for (var i = 0; i < prefixo.length; i++) {
    if (_nameKey(partes[i]) != _nameKey(prefixo[i])) return false;
  }
  return true;
}

String _nameKey(String value) => value.toLowerCase();

/// Negrito do WhatsApp.
String _bold(String value) => '*$value*';
