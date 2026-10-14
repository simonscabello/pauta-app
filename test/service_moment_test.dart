import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';
import 'package:louvor_app/features/events/domain/service_moments.dart';

/// O momento do culto: opcional, desta escala, e nunca deduzido.
///
/// A armadilha que estes testes fecham é a mesma do `isNew`: preencher sozinho
/// um campo que é julgamento de quem monta a escala. "Momento de Louvor" seria
/// o palpite fácil — e poria na escala publicada uma decisão de ninguém.
void main() {
  EventSong musica(Map<String, dynamic> extra) => EventSong.fromJson({
        'songId': 's1',
        'serviceId': 'c1',
        'title': 'Estou Seguro',
        ...extra,
      });

  group('vocabulário', () {
    test('os momentos estão na ordem do culto, não na alfabética', () {
      // É a ordem em que eles acontecem no domingo: quem escolhe percorre a
      // lista como percorre o culto, e não como percorre um dicionário.
      expect(serviceMoments.keys.toList(), [
        'PRELUDIO',
        'ABERTURA',
        'DIZIMOS_E_OFERTAS',
        'LOUVOR',
        'ESPECIAL',
        'POSLUDIO',
        'OUTRO',
      ]);
    });

    test('o rótulo é o nome que a igreja usa', () {
      expect(serviceMomentLabel('DIZIMOS_E_OFERTAS'), 'Dízimos e Ofertas');
      expect(serviceMomentLabel('LOUVOR'), 'Momento de Louvor');
    });

    test('sem momento não há rótulo nenhum', () {
      // Nulo, e não "—" nem "Sem momento": a maioria das músicas de uma escala
      // não tem momento, e um marcador de vazio em cada linha seria mais tinta
      // que as próprias músicas.
      expect(serviceMomentLabel(null), isNull);
      expect(serviceMomentLabel(''), isNull);
    });

    test('"Outro" mostra o que a pessoa escreveu', () {
      expect(serviceMomentLabel('OUTRO', 'Santa Ceia'), 'Santa Ceia');
      // Sem texto, o rótulo genérico ainda serve: ela marcou que há um
      // momento, só não o nomeou.
      expect(serviceMomentLabel('OUTRO'), 'Outro');
      expect(serviceMomentLabel('OUTRO', '  '), 'Outro');
    });

    test('momento que esta versão do app não conhece não some da tela', () {
      // O servidor pode ganhar um momento novo antes do próximo APK. O valor
      // cru é feio; sumir com a informação seria pior.
      expect(serviceMomentLabel('CONSAGRACAO'), 'CONSAGRACAO');
    });
  });

  group('a música da escala', () {
    test('lê o momento do servidor', () {
      final song = musica({
        'moment': 'DIZIMOS_E_OFERTAS',
        'hymnals': [
          {
            'hymnalId': 'h-cc',
            'name': 'Cantor Cristão',
            'abbreviation': 'CC',
            'number': 314,
            'isPrimary': true,
          },
        ],
      });

      expect(song.moment, 'DIZIMOS_E_OFERTAS');
      expect(song.momentText, 'Dízimos e Ofertas');
      expect(song.hymnal?.label, '314 CC');
    });

    test('ausente continua ausente', () {
      final song = musica(const {});

      expect(song.moment, isNull);
      expect(song.momentText, isNull);
      // Cache gravado antes desta versão: a lista ausente vale vazia, e a
      // escala continua abrindo.
      expect(song.hymnals, isEmpty);
      expect(song.hymnal, isNull);
    });

    test('"Outro" carrega o nome escrito à mão', () {
      final song = musica({'moment': 'OUTRO', 'momentLabel': 'Batismo'});
      expect(song.momentText, 'Batismo');
    });
  });

  group('a lista da equipe', () {
    test('o nome da equipe vence o de fábrica (renomeado)', () {
      final song = musica({
        'moment': 'ABERTURA',
        'momentId': 'm1',
        'momentName': 'Entrada',
      });
      expect(song.momentText, 'Entrada');
    });

    test('o momento cadastrado viaja como "Outro" com o nome', () {
      final escolha = MomentChoice.ofTeam(
        const TeamMoment(id: 'm9', name: 'Culto de Missões'),
      );
      expect(escolha.moment, 'OUTRO');
      expect(escolha.momentLabel, 'Culto de Missões');
      expect(escolha.momentId, 'm9');
      expect(escolha.isOneOffOther, isFalse);
    });

    test('o de fábrica leva a chave, sem rótulo', () {
      final escolha = MomentChoice.ofTeam(
        const TeamMoment(id: 'm2', name: 'Entrada', systemKey: 'ABERTURA'),
      );
      expect(escolha.moment, 'ABERTURA');
      expect(escolha.momentLabel, isNull);
      expect(escolha.name, 'Entrada');
    });

    test('a chave que veio de fora é ligada ao momento da equipe', () {
      final lista = [
        const TeamMoment(id: 'm2', name: 'Entrada', systemKey: 'ABERTURA'),
      ];
      final ligada = MomentChoice.ofKey('ABERTURA', lista)!;
      expect(ligada.momentId, 'm2');
      expect(ligada.name, 'Entrada');

      // A equipe excluiu o Prelúdio: fica a chave, com o nome de fábrica.
      final solta = MomentChoice.ofKey('PRELUDIO', lista)!;
      expect(solta.momentId, isNull);
      expect(solta.name, 'Prelúdio');
      expect(MomentChoice.ofKey(null, lista), isNull);
    });

    test('a reserva sem servidor são os seis de fábrica, sem "Outro"', () {
      final reserva = fallbackTeamMoments();
      expect(reserva, hasLength(6));
      expect(reserva.every((m) => m.id.isEmpty), isTrue);
      expect(reserva.map((m) => m.systemKey), isNot(contains('OUTRO')));
      // Escolhida por aqui, vai pela chave e o servidor liga.
      expect(MomentChoice.ofTeam(reserva[1]).momentId, isNull);
    });

    test('"Outro" sem nome continua sendo "Outro"', () {
      final escolha = MomentChoice.other('  ');
      expect(escolha.momentLabel, isNull);
      expect(escolha.name, 'Outro');
      expect(escolha.isOneOffOther, isTrue);
    });
  });
}
