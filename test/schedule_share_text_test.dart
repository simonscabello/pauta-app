import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:louvor_app/features/events/domain/schedule_share_text.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    await initializeDateFormatting('pt_BR');
  });

  Event sampleEvent({List<Object?> songs = const []}) {
    return Event.fromJson({
      'id': 'e1',
      'teamId': 't1',
      'title': 'Culto da Manhã',
      'startsAt': '2026-08-16T12:00:00.000Z',
      'rehearsalAt': '2026-08-15T22:00:00.000Z',
      'location': 'Templo',
      'notes': 'Chegar cedo',
      'colorPalette': 'Preto e dourado',
      'status': 'PUBLISHED',
      'timezone': 'America/Sao_Paulo',
      'assignments': [
        {
          'positionId': 'p1',
          'positionName': 'Guitarra',
          'sortOrder': 1,
          'members': [
            {
              'id': 'a1',
              'membershipId': 'm1',
              'displayName': 'Samuel',
              'note': null,
              'isRegisteredForPosition': true,
            },
          ],
        },
      ],
      'songs': songs,
    });
  }

  Map<String, Object?> membro(String id, String nome, {String? note}) => {
        'id': 'a-$id',
        'membershipId': id,
        'displayName': nome,
        'note': note,
        'isRegisteredForPosition': true,
      };

  Map<String, Object?> funcao(
    String nome,
    String categoria,
    int ordem,
    List<Map<String, Object?>> membros,
  ) =>
      {
        'positionId': 'p-$nome',
        'positionName': nome,
        'positionCategory': categoria,
        'sortOrder': ordem,
        'members': membros,
      };

  test('abre pela data curta, sem cabeçalho e sem rótulo de equipe', () {
    final text = buildScheduleShareText(sampleEvent());

    expect(text, startsWith('*Domingo 16/08*\n'));
    expect(text, contains('*Culto da Manhã*'));
    expect(text, isNot(contains('Escala de Louvor')));
    expect(text, isNot(contains('Equipe')));
    expect(text, contains('*Guitarra:* Samuel'));
    expect(text, contains('*Roupas:* Preto e dourado'));
    expect(text, contains('*Observações*'));
    expect(text, contains('Chegar cedo'));
    // A seção entra mesmo vazia: escala publicada sem repertório é caso
    // normal, e sumir com ela deixaria quem recebe sem saber se as músicas
    // não saíram ou se o texto veio pela metade.
    expect(text, contains('*Músicas*'));
    expect(text, contains('Ainda não escolhidas.'));
  });

  test('horários de culto e de ensaio não vão na mensagem', () {
    final text = buildScheduleShareText(sampleEvent());

    expect(text, isNot(contains('09:00')));
    expect(text, isNot(contains('19:00')));
    expect(text, isNot(contains('Ensaio')));
  });

  test('domingo com dois cultos sem repertório não nomeia os cultos', () {
    final event = Event.fromJson({
      'id': 'e2',
      'teamId': 't1',
      'startsAt': '2026-08-16T11:30:00.000Z',
      'rehearsalAt': '2026-08-16T16:00:00.000Z',
      'status': 'PUBLISHED',
      'timezone': 'America/Sao_Paulo',
      'services': [
        {'id': 's1', 'label': 'Manhã', 'startsAt': '2026-08-16T11:30:00.000Z'},
        {'id': 's2', 'label': 'Noite', 'startsAt': '2026-08-16T22:00:00.000Z'},
      ],
      'assignments': [],
      'songs': [],
    });

    final text = buildScheduleShareText(event);

    expect(text, isNot(contains('08:30')));
    expect('Manhã'.allMatches(text).length, 0);
  });

  test('a equipe no formato do grupo: instrumentos numa linha só', () {
    final event = Event.fromJson({
      'id': 'e-modelo',
      'teamId': 't1',
      'startsAt': '2026-09-13T12:00:00.000Z',
      'status': 'PUBLISHED',
      'timezone': 'America/Sao_Paulo',
      'minister': {'membershipId': 'josy', 'displayName': 'Josy'},
      'assignments': [
        funcao('Vocal', 'VOCAL', 1, [
          membro('gisely', 'Gisely Ramos'),
          membro('josy', 'Josy'),
          membro('simon', 'Simon Pereira'),
        ]),
        funcao('Violão', 'INSTRUMENT', 2, [membro('gerson', 'Gerson')]),
        funcao('Baixo', 'INSTRUMENT', 3, [membro('simon', 'Simon Pereira')]),
        funcao('Bateria', 'INSTRUMENT', 4, [membro('jennifer', 'Jennifer')]),
        funcao('Datashow', 'TECH', 5, [membro('larissa', 'Larissa')]),
        funcao('Direção do culto', 'OTHER', 6, [membro('dirce', 'Dirce')]),
      ],
      'songs': [],
    });

    final text = buildScheduleShareText(event);

    expect(
      text,
      startsWith(
        '*Domingo 13/09*\n'
        '\n'
        '*Vocal:* Josy (ministrante), Gisely, Simon\n'
        '*Instrumentos:* Gerson (violão), Simon (baixo), Jennifer (bateria)\n'
        '*Datashow:* Larissa\n'
        '*Direção do culto:* Dirce\n',
      ),
    );
    expect(text, isNot(contains('*Violão:*')));
    expect(text, isNot(contains('*Ministrante:*')));
    expect('Josy'.allMatches(text).length, 1);
  });

  test('quem ministra e dirige o culto leva o selo uma vez só', () {
    final event = Event.fromJson({
      'id': 'e-selo',
      'teamId': 't1',
      'startsAt': '2026-10-15T22:30:00.000Z',
      'status': 'PUBLISHED',
      'timezone': 'America/Sao_Paulo',
      'minister': {'membershipId': 'ana', 'displayName': 'Ana'},
      'assignments': [
        funcao('Vocal', 'VOCAL', 1, [membro('ana', 'Ana')]),
        funcao('Violão', 'INSTRUMENT', 2, [membro('marcos', 'Marcos')]),
        funcao('Multimídia', 'TECH', 3, [membro('laudiceia', 'Laudiceia')]),
        funcao('Direção do culto', 'OTHER', 4, [membro('ana', 'Ana')]),
      ],
      'songs': [],
    });

    final text = buildScheduleShareText(event);

    expect(text, contains('*Vocal:* Ana (ministrante)\n'));
    expect(text, contains('*Direção do culto:* Ana\n'));
    expect('ministrante'.allMatches(text).length, 1);
  });

  test('recado do líder divide o parêntese com o instrumento', () {
    final event = Event.fromJson({
      'id': 'e-recado',
      'teamId': 't1',
      'startsAt': '2026-09-13T12:00:00.000Z',
      'status': 'PUBLISHED',
      'timezone': 'America/Sao_Paulo',
      'assignments': [
        funcao('Violão', 'INSTRUMENT', 1, [
          membro('gerson', 'Gerson', note: 'chega 8h30'),
        ]),
        funcao('Som', 'TECH', 2, [
          membro('lucas', 'Lucas', note: 'liga a mesa'),
        ]),
      ],
      'songs': [],
    });

    final text = buildScheduleShareText(event);

    expect(text, contains('*Instrumentos:* Gerson (violão, chega 8h30)'));
    expect(text, contains('*Som:* Lucas (liga a mesa)'));
  });

  test('função sem categoria (cache antigo) fica na própria linha', () {
    // Juntar pelo nome seria adivinhar: melhor uma linha a mais do que
    // "Instrumentos: Pedro (datashow)".
    final text = buildScheduleShareText(sampleEvent());

    expect(text, contains('*Guitarra:* Samuel'));
    expect(text, isNot(contains('Instrumentos')));
  });

  test('quem só conduz, sem função, mantém a linha de ministrante', () {
    final event = Event.fromJson({
      'id': 'e4b',
      'teamId': 't1',
      'startsAt': '2026-08-16T12:00:00.000Z',
      'status': 'PUBLISHED',
      'timezone': 'America/Sao_Paulo',
      'minister': {'membershipId': 'm9', 'displayName': 'Ana Clara Souza'},
      'assignments': [
        funcao('Violão', 'INSTRUMENT', 1, [membro('m1', 'Gerson')]),
      ],
      'songs': [],
    });

    expect(buildScheduleShareText(event), contains('*Ministrante:* Ana'));
  });

  test('sem ministrante escolhido, ninguém é marcado', () {
    final event = Event.fromJson({
      'id': 'e5',
      'teamId': 't1',
      'startsAt': '2026-08-16T12:00:00.000Z',
      'status': 'PUBLISHED',
      'timezone': 'America/Sao_Paulo',
      'assignments': [
        funcao('Vocal', 'VOCAL', 1, [membro('m1', 'Gisely')]),
      ],
      'songs': [],
    });

    expect(event.minister, isNull);
    expect(buildScheduleShareText(event), isNot(contains('inistrante')));
  });

  group('só o primeiro nome', () {
    Event comVocal(List<Map<String, Object?>> membros) {
      return Event.fromJson({
        'id': 'e-nomes',
        'teamId': 't1',
        'startsAt': '2026-08-16T12:00:00.000Z',
        'status': 'PUBLISHED',
        'timezone': 'America/Sao_Paulo',
        'assignments': [funcao('Vocal', 'VOCAL', 1, membros)],
        'songs': [],
      });
    }

    test('sem ambiguidade, o sobrenome não entra', () {
      final text = buildScheduleShareText(
        comVocal([membro('m1', 'Gisely Ramos'), membro('m2', 'Simon Pereira')]),
      );

      expect(text, contains('*Vocal:* Gisely, Simon'));
      expect(text, isNot(contains('Ramos')));
    });

    test('dois com o mesmo primeiro nome ganham a parte que os separa', () {
      final text = buildScheduleShareText(
        comVocal([
          membro('m1', 'Simon Lopes'),
          membro('m2', 'simon pedro'),
          membro('m3', 'Larissa'),
        ]),
      );

      // A comparação ignora a caixa: "simon pedro" digitado em minúscula é o
      // mesmo primeiro nome de "Simon Lopes".
      expect(text, contains('Simon Lopes'));
      expect(text, contains('simon pedro'));
      expect(text, contains(', Larissa'));
    });

    test('nomes iguais até o fim vão inteiros, sem laço infinito', () {
      final text = buildScheduleShareText(
        comVocal([membro('m1', 'João Silva'), membro('m2', 'João Silva')]),
      );

      expect(text, contains('*Vocal:* João Silva, João Silva'));
    });

    test('a mesma pessoa em duas funções sai curta nas duas', () {
      final event = Event.fromJson({
        'id': 'e-duas',
        'teamId': 't1',
        'startsAt': '2026-08-16T12:00:00.000Z',
        'status': 'PUBLISHED',
        'timezone': 'America/Sao_Paulo',
        'assignments': [
          funcao('Vocal', 'VOCAL', 1, [membro('m1', 'Simon Pereira')]),
          funcao('Teclado', 'INSTRUMENT', 2, [membro('m1', 'Simon Pereira')]),
        ],
        'songs': [],
      });

      final text = buildScheduleShareText(event);

      expect(text, contains('*Vocal:* Simon\n'));
      expect(text, contains('*Instrumentos:* Simon (teclado)'));
    });
  });

  test('escala sem services (cache antigo) não inventa horário', () {
    final event = Event.fromJson({
      'id': 'e3',
      'teamId': 't1',
      'title': 'Escala antiga',
      'startsAt': '2026-08-16T12:00:00.000Z',
      'status': 'PUBLISHED',
      'timezone': 'America/Sao_Paulo',
      'assignments': [],
      'songs': [],
    });

    expect(event.services, isEmpty);
    expect(event.displayServices, hasLength(1));
    expect(buildScheduleShareText(event), isNot(contains('Culto às')));
  });

  test('músicas sem hinário saem em lista, com o artista e sem o tom', () {
    final text = buildScheduleShareText(
      sampleEvent(
        songs: [
          {
            'songId': 's1',
            'title': 'Grande é o Senhor',
            'artist': 'Adoração',
            'key': 'G',
            'keyOverride': 'G',
            'defaultKey': 'E',
          },
          {
            'songId': 's2',
            'title': 'Aclame ao Senhor',
            'artist': 'Diante do Trono',
            'key': 'A',
            'defaultKey': 'A',
          },
        ],
      ),
    );

    expect(
      text,
      contains(
        '*Músicas*\n'
        '\n'
        '* Grande é o Senhor - Adoração\n'
        '* Aclame ao Senhor - Diante do Trono\n',
      ),
    );
    expect(text, isNot(contains('1.')));
    expect(text, isNot(contains('(G)')));
  });

  test('música nova sai marcada, e só ela', () {
    final text = buildScheduleShareText(
      sampleEvent(
        songs: [
          {
            'songId': 's1',
            'title': 'Bondade de Deus',
            'artist': 'Isaias Saad',
            'key': 'G',
            'isNew': true,
          },
          {'songId': 's2', 'title': 'Aclame ao Senhor', 'key': 'A'},
        ],
      ),
    );

    expect(text, contains('* Bondade de Deus - Isaias Saad — *Nova*'));
    expect(text, contains('* Aclame ao Senhor\n'));
    expect('*Nova*'.allMatches(text).length, 1);
  });

  /// Escala de domingo com manhã e noite, cada culto com o próprio repertório.
  Event doisCultos({required List<Object?> songs}) {
    return Event.fromJson({
      'id': 'e6',
      'teamId': 't1',
      'startsAt': '2026-08-16T11:30:00.000Z',
      'status': 'PUBLISHED',
      'timezone': 'America/Sao_Paulo',
      'services': [
        {
          'id': 's-manha',
          'label': 'Manhã',
          'startsAt': '2026-08-16T11:30:00.000Z',
        },
        {
          'id': 's-noite',
          'label': 'Noite',
          'startsAt': '2026-08-16T22:00:00.000Z',
        },
      ],
      'assignments': [],
      'songs': songs,
    });
  }

  test('com dois cultos, cada um ganha sua seção', () {
    final text = buildScheduleShareText(
      doisCultos(
        songs: [
          {'songId': 's1', 'serviceId': 's-manha', 'title': 'Abre Manhã'},
          {'songId': 's2', 'serviceId': 's-manha', 'title': 'Segue Manhã'},
          {'songId': 's3', 'serviceId': 's-noite', 'title': 'Abre Noite'},
          {
            'songId': 's1',
            'serviceId': 's-noite',
            'title': 'Abre Manhã',
            'key': 'Bm',
          },
        ],
      ),
    );

    expect(text, contains('*Manhã*\n\n* Abre Manhã\n* Segue Manhã'));
    expect(text, contains('*Noite*\n\n* Abre Noite\n* Abre Manhã'));
    expect(text, isNot(contains('*Músicas*')));
  });

  test('culto sem música aparece dizendo que o repertório não saiu', () {
    final text = buildScheduleShareText(
      doisCultos(
        songs: [
          {'songId': 's1', 'serviceId': 's-manha', 'title': 'Só de Manhã'},
        ],
      ),
    );

    expect(text, contains('* Só de Manhã'));
    expect(text, contains('*Noite*\n\nAinda não escolhidas.'));
  });

  test('repertório agrupado por culto, com o culto vazio preservado', () {
    final event = doisCultos(
      songs: [
        {'songId': 's1', 'serviceId': 's-noite', 'title': 'Da Noite'},
      ],
    );

    final grupos = event.songsByService;

    expect(grupos, hasLength(2));
    expect(grupos[0].service.label, 'Manhã');
    expect(grupos[0].songs, isEmpty);
    expect(grupos[1].service.label, 'Noite');
    expect(grupos[1].songs.single.title, 'Da Noite');
  });

  test('música de cache antigo, sem serviceId, cai no primeiro culto', () {
    final event = doisCultos(
      songs: [
        {'songId': 's1', 'title': 'Gravada antes desta versão'},
      ],
    );

    expect(event.songs.single.serviceId, isEmpty);
    expect(
      event.songsByService[0].songs.single.title,
      'Gravada antes desta versão',
    );
    expect(event.songsByService[1].songs, isEmpty);
  });

  group('hinário e momento', () {
    Map<String, Object?> hinario(int numero, String sigla) => {
          'hymnalId': 'h-$sigla',
          'name': sigla,
          'abbreviation': sigla,
          'number': numero,
          'isPrimary': true,
        };

    test('o domingo do modelo: momentos como rótulo, o resto em lista', () {
      final text = buildScheduleShareText(
        doisCultos(
          songs: [
            {
              'songId': 's1',
              'serviceId': 's-manha',
              'title': 'Estou Seguro',
              'hymnals': [hinario(314, 'CC')],
              'moment': 'DIZIMOS_E_OFERTAS',
            },
            {'songId': 's2', 'serviceId': 's-manha', 'title': 'Essa Paz'},
            {'songId': 's3', 'serviceId': 's-manha', 'title': 'Alfa e Ômega'},
            {
              'songId': 's4',
              'serviceId': 's-noite',
              'title': 'Eu Não Posso Fugir do Teu Espírito',
              'hymnals': [hinario(208, 'HCC')],
              'moment': 'ABERTURA',
            },
            {
              'songId': 's5',
              'serviceId': 's-noite',
              'title': 'Os Que Confiam',
              'hymnals': [hinario(451, 'CC')],
              'moment': 'DIZIMOS_E_OFERTAS',
            },
            {'songId': 's6', 'serviceId': 's-noite', 'title': 'Santo'},
            {
              'songId': 's7',
              'serviceId': 's-noite',
              'title': 'Invoca-me',
              'artist': 'Trazendo a Arca',
            },
            {
              'songId': 's8',
              'serviceId': 's-noite',
              'title': 'Maravilhoso Senhor',
              'artist': 'Rafaela Pinho',
            },
          ],
        ),
      );

      expect(
        text,
        contains(
          '*Manhã*\n'
          '\n'
          '*Dízimos e Ofertas:* 314 CC - Estou Seguro\n'
          '\n'
          '* Essa Paz\n'
          '* Alfa e Ômega\n'
          '\n'
          '*Noite*\n'
          '\n'
          '*Abertura:* 208 HCC - Eu Não Posso Fugir do Teu Espírito\n'
          '\n'
          '*Dízimos e Ofertas:* 451 CC - Os Que Confiam\n'
          '\n'
          '* Santo\n'
          '* Invoca-me - Trazendo a Arca\n'
          '* Maravilhoso Senhor - Rafaela Pinho',
        ),
      );
    });

    test('a ordem é a da escala, e não "momentos primeiro"', () {
      final text = buildScheduleShareText(
        sampleEvent(
          songs: [
            {'songId': 's1', 'title': 'Essa Paz'},
            {
              'songId': 's2',
              'title': 'Estou Seguro',
              'hymnals': [hinario(314, 'CC')],
              'moment': 'DIZIMOS_E_OFERTAS',
            },
            {'songId': 's3', 'title': 'Alfa e Ômega'},
          ],
        ),
      );

      expect(
        text,
        contains(
          '* Essa Paz\n'
          '\n'
          '*Dízimos e Ofertas:* 314 CC - Estou Seguro\n'
          '\n'
          '* Alfa e Ômega\n',
        ),
      );
    });

    test('só o hinário: número na frente, na lista', () {
      final text = buildScheduleShareText(
        sampleEvent(
          songs: [
            {
              'songId': 's1',
              'title': 'Eu Não Posso Fugir do Teu Espírito',
              'hymnals': [hinario(208, 'HCC')],
            },
          ],
        ),
      );

      expect(text, contains('* 208 HCC - Eu Não Posso Fugir do Teu Espírito\n'));
    });

    test('com hinário o artista não entra, e o tom nunca', () {
      final text = buildScheduleShareText(
        sampleEvent(
          songs: [
            {
              'songId': 's1',
              'title': 'Estou Seguro',
              'artist': 'Cantor Cristão',
              'key': 'G',
              'hymnals': [hinario(314, 'CC')],
              'moment': 'ABERTURA',
            },
          ],
        ),
      );

      expect(text, contains('*Abertura:* 314 CC - Estou Seguro\n'));
      expect(text, isNot(contains('Cantor Cristão')));
      expect(text, isNot(contains('(G)')));
    });

    test('sem hinário e sem artista, sai só o nome', () {
      final text = buildScheduleShareText(
        sampleEvent(
          songs: [
            {'songId': 's1', 'title': 'Nosso General'},
          ],
        ),
      );

      expect(text, contains('* Nosso General\n'));
      expect(text, isNot(contains('Nosso General -')));
    });

    test('"Outro" sai com o nome escrito à mão', () {
      final text = buildScheduleShareText(
        sampleEvent(
          songs: [
            {
              'songId': 's1',
              'title': 'Invoca-me',
              'moment': 'OUTRO',
              'momentLabel': 'Santa Ceia',
            },
          ],
        ),
      );

      expect(text, contains('*Santa Ceia:* Invoca-me'));
      expect(text, isNot(contains('Outro')));
    });

    test('músicas seguidas no mesmo momento dizem o momento uma vez só', () {
      final text = buildScheduleShareText(
        sampleEvent(
          songs: [
            {
              'songId': 's1',
              'title': 'Abrigo Perfeito',
              'hymnals': [hinario(319, 'CC')],
              'moment': 'DIZIMOS_E_OFERTAS',
            },
            {
              'songId': 's2',
              'title': 'Ajuntamento',
              'artist': 'Vencedores Por Cristo',
              'moment': 'LOUVOR',
            },
            {
              'songId': 's3',
              'title': 'Falar Com Deus',
              'artist': 'Novo Tom',
              'moment': 'LOUVOR',
            },
            {
              'songId': 's4',
              'title': 'Bondade de Deus',
              'artist': 'Ibab Celebração',
              'moment': 'LOUVOR',
            },
          ],
        ),
      );

      expect(
        text,
        contains(
          '*Dízimos e Ofertas:* 319 CC - Abrigo Perfeito\n'
          '\n'
          '*Momento de Louvor:*\n'
          '* Ajuntamento - Vencedores Por Cristo\n'
          '* Falar Com Deus - Novo Tom\n'
          '* Bondade de Deus - Ibab Celebração',
        ),
      );
      expect('*Momento de Louvor:*'.allMatches(text), hasLength(1));
    });

    test('o mesmo momento separado por outro aparece de novo, na ordem', () {
      final text = buildScheduleShareText(
        sampleEvent(
          songs: [
            {'songId': 's1', 'title': 'Ajuntamento', 'moment': 'LOUVOR'},
            {
              'songId': 's2',
              'title': 'Não Sei Por Que',
              'hymnals': [hinario(377, 'CC')],
              'moment': 'DIZIMOS_E_OFERTAS',
            },
            {'songId': 's3', 'title': 'Tremenda Graça', 'moment': 'LOUVOR'},
            {
              'songId': 's4',
              'title': 'Em Memória de Mim',
              'moment': 'OUTRO',
              'momentLabel': 'Santa Ceia',
            },
            {
              'songId': 's5',
              'title': 'Porque Ele Vive',
              'moment': 'OUTRO',
              'momentLabel': 'Batismo',
            },
          ],
        ),
      );

      expect(
        text,
        contains(
          '*Momento de Louvor:* Ajuntamento\n'
          '\n'
          '*Dízimos e Ofertas:* 377 CC - Não Sei Por Que\n'
          '\n'
          '*Momento de Louvor:* Tremenda Graça\n'
          '\n'
          '*Santa Ceia:* Em Memória de Mim\n'
          '\n'
          '*Batismo:* Porque Ele Vive',
        ),
      );
    });

    test('hinário, momento e "Nova" convivem na mesma linha', () {
      final text = buildScheduleShareText(
        sampleEvent(
          songs: [
            {
              'songId': 's1',
              'title': 'Os Que Confiam',
              'hymnals': [hinario(451, 'CC')],
              'moment': 'DIZIMOS_E_OFERTAS',
              'isNew': true,
            },
          ],
        ),
      );

      expect(
        text,
        contains('*Dízimos e Ofertas:* 451 CC - Os Que Confiam — *Nova*'),
      );
    });

    test('a música em dois hinários mostra só a principal', () {
      final text = buildScheduleShareText(
        sampleEvent(
          songs: [
            {
              'songId': 's1',
              'title': 'Santo, Santo, Santo',
              'hymnals': [hinario(12, 'HCC'), hinario(5, 'CC')],
            },
          ],
        ),
      );

      expect(text, contains('* 12 HCC - Santo, Santo, Santo\n'));
      expect(text, isNot(contains('5 CC')));
    });
  });

  test('a mensagem não tem emoji nenhum', () {
    final text = buildScheduleShareText(
      Event.fromJson({
        'id': 'e1',
        'teamId': 't1',
        'startsAt': '2026-08-09T12:00:00.000Z',
        'rehearsalAt': '2026-08-08T22:00:00.000Z',
        'location': 'Templo',
        'notes': 'Chegar 30 min antes',
        'timezone': 'America/Sao_Paulo',
        'status': 'PUBLISHED',
        'minister': {'membershipId': 'm1', 'displayName': 'Samuel'},
        'services': [
          {
            'id': 'sv1',
            'label': 'Manhã',
            'startsAt': '2026-08-09T11:30:00.000Z',
          },
          {
            'id': 'sv2',
            'label': 'Noite',
            'startsAt': '2026-08-09T22:00:00.000Z',
          },
        ],
        'assignments': [
          funcao('Vocal', 'VOCAL', 1, [
            membro('m1', 'Samuel'),
            membro('m2', 'Maria'),
          ]),
          funcao('Violão', 'INSTRUMENT', 2, [membro('m3', 'João')]),
        ],
        'songs': [
          {'songId': 's1', 'serviceId': 'sv1', 'title': 'Primeira'},
          {'songId': 's2', 'serviceId': 'sv2', 'title': 'Segunda'},
        ],
      }),
    );

    final emojis = RegExp(
      r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]',
      unicode: true,
    ).allMatches(text).length;

    expect(emojis, 0, reason: 'texto gerado:\n$text');
    expect(text, contains('*Vocal:* Samuel (ministrante), Maria'));
  });
}
