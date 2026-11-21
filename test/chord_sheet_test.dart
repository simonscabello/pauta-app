import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/features/songs/domain/chord_sheet.dart';

void main() {
  test('reconhece as extensões e inversões usadas nas cifras', () {
    for (final chord in [
      'D',
      'Em',
      'A7M',
      'Bbmaj7',
      'F#m7(b5)/A',
      'D7(9,13)/F#',
      'G7sus4',
      'C4',
      'C9',
      'Cadd9',
      'Gdim',
      'B°',
      'C+',
      'D6/9',
      'A5-',
      'D(9)',
      'G7+/B',
    ]) {
      expect(isChord(chord), isTrue, reason: chord);
    }
    for (final word in [
      'Do',
      'Ao',
      'Deus',
      'Amor',
      'Intro',
      '2x',
      'F#m/letra',
    ]) {
      expect(isChord(word), isFalse, reason: word);
    }
  });

  test('segmentos preservam texto, rótulos, intro e estrofes', () {
    expect(parseChordSheet('[Intro]\n[D] [A][Bm]\n\nE [D]eu [2x] [A]vou'), [
      [(chord: null, text: '[Intro]')],
      [
        (chord: 'D', text: ' '),
        (chord: 'A', text: ''),
        (chord: 'Bm', text: ''),
      ],
      [(chord: null, text: '')],
      [
        (chord: null, text: 'E '),
        (chord: 'D', text: 'eu [2x] '),
        (chord: 'A', text: 'vou'),
      ],
    ]);
  });

  test('insere na coluna exata, mesmo dentro de uma palavra', () {
    expect(
      normalizeChordSheet('D            A\nAo único que é digno'),
      '[D]Ao único que [A]é digno',
    );
    expect(normalizeChordSheet('D A\nSanto'), '[D]Sa[A]nto');
    expect(normalizeChordSheet('D   A     Bm\nSim'), '[D]Sim [A]      [Bm]');
    expect(normalizeChordSheet('D A\n🎵 é'), '[D]🎵 [A]é');
  });

  test('palavras soltas no começo da letra continuam como foram escritas', () {
    const lyrics = 'A tua voz\nE eu canto\nEm tua casa\nDo teu amor';
    expect(normalizeChordSheet(lyrics), lyrics);
    expect(normalizeChordSheet('A\nEm tua casa'), '[A]Em tua casa');
  });

  test('intro, repetição, seção e linha em branco não consomem letra', () {
    const raw =
        '[Intro]\n( D | A ) 2x\nBm F#m\n\nC\nRefrão:\nG   D\nA ti canto\nE\n[2x]\n';
    const expected =
        '[Intro]\n( [D] | [A] ) 2x\n[Bm] [F#m]\n\n[C]\nRefrão:\n[G]A ti[D] canto\n[E]\n[2x]\n';
    expect(normalizeChordSheet(raw), expected);
    expect(normalizeChordSheet(expected), expected);
    expect(normalizeChordSheet('D | A x2\nCanto aqui'), '[D]Cant[A]o aqui x2');
  });

  test('tab avança até a próxima coluna múltipla de quatro', () {
    expect(normalizeChordSheet('Bm\tF#\nEm\tcasa'), '[Bm]Em  [F#]casa');
  });

  test('ChordPro com qualquer acorde válido passa intacto', () {
    const raw = '\t[Refrão]  \r\n[D]Ao único [F#m7(b5)/A]digno\r\nD    A\n';
    expect(normalizeChordSheet(raw), raw);
  });

  test('D → E preserva extensões e transpõe baixo e raiz', () {
    const sheet = '[Intro]\n[D]Ao único [A/C#]digno\n[Bm7(b5)/F] [2x]';
    const up = '[Intro]\n[E]Ao único [B/D#]digno\n[C#m7(b5)/G] [2x]';
    expect(transposeChordSheet(sheet, 'D', 'E'), up);
    expect(transposeChordSheet(up, 'E', 'D'), sheet);
    expect(transposeChord('F#m7(b5)/A', -2), 'Em7(b5)/G');
  });

  test('a grafia segue o destino, inclusive em mudanças de modo', () {
    expect(
      transposeChordSheet('[G] [D/F#] [Em]', 'G', 'Bb'),
      '[Bb] [F/A] [Gm]',
    );
    expect(
      transposeChordSheet('[C] [G/B] [Am]', 'C', 'F#'),
      '[F#] [C#/F] [D#m]',
    );
    expect(transposeChordSheet('[C] [Ab]', 'C', 'dm'), '[D] [Bb]');
    expect(transposeChordSheet('[E#/B#] [Fb/Cb]', 'C', 'C'), '[F/C] [E/B]');
    expect(transposeChord('F#m/D#', 0, preferFlats: true), 'Gbm/Eb');
  });

  test('rótulo na mesma linha dos acordes não esconde os acordes', () {
    expect(
      normalizeChordSheet('Intro: D  A/C#  Bm\n[Solo] G D\nEle disse: vem'),
      'Intro: [D]  [A/C#]  [Bm]\n[Solo] [G] [D]\nEle disse: vem',
    );
  });

  test('ChordPro de outro app: diretivas viram rótulo ou somem', () {
    const exportado = '''{title: Canção de teste}
{artist: Banda Fictícia}
{key: G}
{capo: 2}
# arquivo exportado
{c: Intro}
[G] [D/F#] [Em]

{soc}
[G]Primeiro [C]verso
{eoc}
{comment: A}
{start_of_bridge: Ponte final}
[Em]Último [D]verso
{eob}''';

    expect(
      normalizeChordSheet(exportado),
      '[Capotraste na 2ª casa]\n'
      '[Intro]\n'
      '[G] [D/F#] [Em]\n'
      '\n'
      '[Refrão]\n'
      '[G]Primeiro [C]verso\n'
      'A:\n'
      '[Ponte final]\n'
      '[Em]Último [D]verso',
    );
    expect(
      normalizeChordSheet(normalizeChordSheet(exportado)),
      normalizeChordSheet(exportado),
    );
    expect(chordSheetKey(exportado), 'G');
    expect(chordSheetKey('{key: G (capo 2)}\n[G]Verso'), isNull);
    expect(chordSheetKey('G   D\nVerso'), isNull);
  });

  test('a cifra que o importador traz: "(2x)" e sílaba esticada', () {
    // O texto que a API devolve para a página inventada do teste dela.
    const trazida = '[Intro] G  D/F#  Em\n'
        '\n'
        '[Primeira Parte]\n'
        '\n'
        'G              D/F#\n'
        'Primeiro verso inventado para o te___ste\n'
        'Em7     C9  (2x)\n'
        'Segundo ver---so & mais um pou----co';
    expect(
      normalizeChordSheet(trazida),
      '[Intro] [G]  [D/F#]  [Em]\n'
      '\n'
      '[Primeira Parte]\n'
      '\n'
      '[G]Primeiro verso [D/F#]inventado para o teste\n'
      '[Em7]Segundo [C9]verso & mais um pouco (2x)',
    );
    expect(
      normalizeChordSheet('       C   D\nO pou--co dispensou-me'),
      'O pou[C]co d[D]ispensou-me',
    );
  });

  test('sílaba esticada some na leitura, mesmo na cifra já guardada', () {
    String text(String sheet) => parseChordSheet(sheet)
        .map((line) => line.map((s) => '${s.chord ?? ''}|${s.text}').join())
        .join('\n');
    expect(text('ter me[Bb]---d[Bb9]o'), '|ter me' 'Bb|d' 'Bb9|o');
    expect(text('a[Bb9]-----m[Bb]e'), '|a' 'Bb9|m' 'Bb|e');
    expect(text('o santo co---ro'), '|o santo coro');
    expect(text('dispensou-me [A5-]agora'), '|dispensou-me ' 'A5-|agora');
    const tab = 'D|-0--X--2--|';
    expect(text(tab), '|$tab');
  });

  test('o .txt do Cifra Club colado: sem cabeçalho, tom e tabela de acordes',
      () {
    // Inventado no formato do "Baixar cifra"; nenhuma letra de verdade.
    const baixado = '﻿Banda Fictícia - Canção de Teste\n'
        '\n'
        'Tom: C\n'
        '[Intro] C  G/B  F\n'
        '\n'
        'C                 G\n'
        '  Primeiro verso inventado aqui\n'
        '\n'
        '----------------- Acordes -----------------\n'
        'C = X 3 2 0 1 0\n'
        'G = 3 2 0 0 0 3\n';
    expect(
      normalizeChordSheet(baixado),
      '[Intro] [C]  [G/B]  [F]\n'
      '\n'
      '[C]  Primeiro verso i[G]nventado aqui',
    );
    expect(chordSheetKey(baixado), 'C');
  });

  test('sem a tabela de acordes, a primeira linha com hífen fica', () {
    expect(
      normalizeChordSheet('Santo - santo é o Senhor\n\nG   D\nVerso'),
      'Santo - santo é o Senhor\n\n[G]Vers[D]o',
    );
  });

  test('sem diretiva, "#" no começo da linha continua sendo letra', () {
    expect(
      normalizeChordSheet('#1 em louvor\n[G]Verso'),
      '#1 em louvor\n[G]Verso',
    );
  });

  test('o tom do leitor sobe e desce na grafia de costume', () {
    expect(shiftMusicalKey('D', 1), 'Eb');
    expect(shiftMusicalKey('D', -1), 'Db');
    expect(shiftMusicalKey('F', 1), 'F#');
    expect(shiftMusicalKey('Bm', 2), 'C#m');
    expect(shiftMusicalKey('C', -1), 'B');
    expect(shiftMusicalKey('G', 12), 'G');
  });

  test('sem origem ou destino válido, preserva inclusive a grafia', () {
    const sheet = '[Gb]Em tua [Db]casa';
    for (final invalid in [null, 'G (capo 2)', 'Cb']) {
      expect(transposeChordSheet(sheet, invalid, 'D'), sheet);
      expect(transposeChordSheet(sheet, 'D', invalid), sheet);
    }
  });
}
