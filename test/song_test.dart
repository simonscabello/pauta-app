import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/features/songs/domain/song_models.dart';

Map<String, dynamic> songJson({
  String? defaultKey,
  String? kind,
  String? pace,
  String? originalKey,
  String? lyrics,
}) {
  return {
    'id': 's1',
    'title': 'Consagração',
    'artist': 'Aline Barros',
    'composer': 'Anderson Mattos',
    'kind': kind,
    'pace': pace,
    'defaultKey': defaultKey,
    'originalKey': originalKey,
    'bpm': 70,
    'lyrics': lyrics,
    'chordsUrl': 'https://www.cifraclub.com.br/aline-barros/consagracao/',
    'isArchived': false,
  };
}

void main() {
  group('Song', () {
    test('le as tres decisoes da equipe: tom, tipo e andamento', () {
      final vazia = Song.fromJson(songJson());
      expect(vazia.defaultKey, isNull);
      expect(vazia.kind, isNull);
      expect(vazia.pace, isNull);

      final completa = Song.fromJson(
        songJson(defaultKey: 'G', kind: 'SONG', pace: 'CALM'),
      );
      expect(completa.defaultKey, 'G');
      expect(completa.kind, 'SONG');
      expect(completa.pace, 'CALM');
    });

    test('a lista não traz letra, e isso não é o mesmo que não ter letra', () {
      // Como a listagem responde: sem o campo `lyrics`.
      final daLista = Song.fromJson(songJson());
      expect(daLista.lyrics, isNull);
      expect(daLista.hasLyrics, isFalse);

      final doDetalhe = Song.fromJson(songJson(lyrics: 'Receba a minha vida'));
      expect(doDetalhe.hasLyrics, isTrue);
    });

    test('letra em branco não conta como letra', () {
      expect(Song.fromJson(songJson(lyrics: '   ')).hasLyrics, isFalse);
    });

    test('a marca de nova é da musica, e falsa quando ausente', () {
      // Ausente vale falso: e o que o acervo inteiro significa, e o que o cache
      // gravado antes desta versao guardou.
      expect(Song.fromJson(songJson()).isNew, isFalse);

      final nova = Song.fromJson({...songJson(), 'isNew': true});
      expect(nova.isNew, isTrue);

      // "Nova" nao diz nada sobre estar preenchida: a equipe pode estar
      // aprendendo uma musica que ja tem tom, tipo e andamento decididos.
      final completaEnova = Song.fromJson({
        ...songJson(defaultKey: 'G', kind: 'SONG', pace: 'CALM'),
        'isNew': true,
      });
      expect(completaEnova.isNew, isTrue);
      expect(completaEnova.defaultKey, 'G');
    });

    test('tom da gravação não vira tom da equipe', () {
      final song = Song.fromJson(songJson(originalKey: 'F#'));
      // O tom lido do CifraClub é sugestão; o campo da equipe segue vazio.
      expect(song.originalKey, 'F#');
      expect(song.defaultKey, isNull);
    });

    test('sem artista, o subtítulo avisa em vez de ficar em branco', () {
      final json = songJson()
        ..['artist'] = null
        ..['composer'] = null;
      expect(Song.fromJson(json).subtitle, 'Sem artista');
    });
  });

  group('rótulos em português', () {
    test('tipo e andamento', () {
      expect(kindLabel('HYMN'), 'Hino');
      expect(kindLabel('SONG'), 'Cântico');
      expect(paceLabel('CALM'), 'Calma');
      expect(paceLabel('UPBEAT'), 'Agitada');
    });

    test('valor ausente ou desconhecido vira travessão, não erro', () {
      expect(kindLabel(null), '—');
      expect(paceLabel('QUALQUER_COISA'), '—');
    });
  });

  group('CatalogCandidate', () {
    // `hasLyrics` saiu: a letra não viaja entre equipes, e um servidor
    // antigo que ainda a mande é ignorado.
    test('lê o que o candidato traz, sem a letra', () {
      final candidate = CatalogCandidate.fromJson({
        'sourceSongId': 'x1',
        'title': 'Consagração',
        'artist': 'Aline Barros',
        'originalKey': 'A',
        'bpm': 70,
        'hasLyrics': true,
        'hasChords': true,
        'hasYoutube': false,
        'hasSpotify': true,
      });

      expect(candidate.hasChords, isTrue);
      expect(candidate.hasYoutube, isFalse);
      expect(candidate.originalKey, 'A');
    });

    test('flags ausentes são falsas, nunca nulas', () {
      final candidate = CatalogCandidate.fromJson({
        'sourceSongId': 'x1',
        'title': 'Alguma',
      });
      expect(candidate.hasChords, isFalse);
      expect(candidate.artist, isNull);
    });
  });
}
