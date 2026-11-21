import 'musical_keys.dart';

typedef ChordSegment = ({String? chord, String text});

const maxChordSheetLength = 30000;
const _note = r'[A-G][#b]?';
// Extensões brasileiras também aparecem como 7M, 5-, 7(9,13) e 6/9.
const _degree = r'[#b]?(?:13|11|[245679])(?:[M+-]|#(?![0-9]))?';
const _quality = r'(?:dim|aug|sus|m|°|ø|\+)?';
const _extension = '(?:(?:maj|Maj|sus|add|/)?$_degree|'
    '\\($_degree(?:[,/]?$_degree)*\\))';
final _chord = RegExp('^($_note)($_quality$_extension*)(?:/($_note))?\$');
final _brackets = RegExp(r'\[([^\[\]\r\n]*)\]');
final _tokens = RegExp(r'\S+');
// Barras, parênteses e a marca de repetição, solta ou entre parênteses: "(2x)".
final _repeat = RegExp(r'^\(?(?:x\d+|\d+x)\)?$');
final _separator = RegExp(r'^(?:[|():]+|\(?(?:x\d+|\d+x)\)?)$');

/// Sílaba esticada para caber o acorde, como os sites escrevem: "te___ste",
/// "ver---so", "pou--[C]--co", "me[Bb]---do". Hífen simples fica:
/// "dispensou-me" é letra.
final _stretch =
    RegExp(r'(\p{L})((?:-|\[[^\]]*\])+)(?=\p{L})', unicode: true);
String _unstretch(String line) =>
    line.replaceAll('_', '').replaceAllMapped(
          _stretch,
          // Só os traços fora do colchete contam: "[A5-]" é acorde.
          (m) => m[2]!.replaceAll(_brackets, '').length >= 2
              ? '${m[1]}${_brackets.allMatches(m[2]!).map((b) => b[0]).join()}'
              : m[0]!,
        );

/// Tablatura ("D|-0--2--|"): os traços são as cordas, e não sílaba esticada.
final _tabLine = RegExp(r'^\s*[A-Ga-g][#b]?\|');

bool isChord(String token) => _chord.hasMatch(token);

Iterable<RegExpMatch> _chordMarkers(String text) =>
    _brackets.allMatches(text).where((match) => isChord(match[1]!));

List<List<ChordSegment>> parseChordSheet(String sheet) {
  return [
    // A limpeza também na leitura: vale para a cifra já guardada.
    for (final line in sheet.split(RegExp(r'\r\n?|\n')))
      _parseLine(_tabLine.hasMatch(line) ? line : _unstretch(line)),
  ];
}

List<ChordSegment> _parseLine(String line) {
  final segments = <ChordSegment>[];
  String? chord;
  var start = 0;
  for (final marker in _chordMarkers(line)) {
    if (chord != null || start < marker.start) {
      segments.add((chord: chord, text: line.substring(start, marker.start)));
    }
    chord = marker[1];
    start = marker.end;
  }
  segments.add((chord: chord, text: line.substring(start)));
  return segments;
}

bool isChordSectionLabel(String line) {
  final text = line.trim();
  return text.endsWith(':') ||
      _brackets.matchAsPrefix(text)?.end == text.length;
}

// Só a linha inteira decide. "Em tua casa" é letra, mesmo começando em "Em".
bool _isChordLine(String line) {
  var foundChord = false;
  for (final token in _tokens.allMatches(line)) {
    if (isChord(token[0]!)) {
      foundChord = true;
    } else if (!_separator.hasMatch(token[0]!)) {
      return false;
    }
  }
  return foundChord;
}

String _expandTabs(String line) {
  if (!line.contains('\t')) return line;
  final result = StringBuffer();
  var column = 0;
  for (final rune in line.runes) {
    if (rune == 9) {
      final spaces = 4 - column % 4;
      result.write(' ' * spaces);
      column += spaces;
    } else {
      result.writeCharCode(rune);
      column++;
    }
  }
  return result.toString();
}

final _labelPrefix = RegExp(r'\s*(?:[^:\[\]]{1,30}:|\[[^\]]+\])\s*(?=\S)');

String _bracketChords(String line) => line.replaceAllMapped(_tokens, (m) {
      final token = m[0]!;
      return isChord(token) ? '[$token]' : token;
    });

/// `{title: Santo}`, `{soc}`, `{c: Refrão}`: as diretivas do ChordPro que
/// outros apps exportam.
final _directive = RegExp(r'^\s*\{\s*([A-Za-z_]+)\s*(?::\s*(.*?))?\s*\}\s*$');

/// O tom que um arquivo ChordPro declara em `{key: G}`, quando é um tom da
/// lista. Serve de sugestão para o "Tom da cifra".
String? chordSheetKey(String raw) {
  for (final line in raw.split(RegExp(r'\r\n?|\n'))) {
    final match = _directive.firstMatch(line);
    if (match != null && match[1]!.toLowerCase() == 'key') {
      return normalizeMusicalKey(match[2]);
    }
    // "Tom: C", como o .txt do Cifra Club escreve quando traz o tom.
    if (_keyLine.firstMatch(line) case final m?) {
      if (normalizeMusicalKey(m[1]) case final key?) return key;
    }
  }
  return null;
}

/// A diretiva como o Pauta guarda: um rótulo, ou nada. Título, artista e tom
/// já moram na música; abre e fecha de bloco só importam pelo nome.
String? _directiveLine(String name, String? value) {
  final text = value?.replaceAll(RegExp(r'[\[\]]'), '').trim() ?? '';
  String label(String fallback) {
    final shown = text.isEmpty ? fallback : text;
    // "[A]" seria lido como acorde.
    return isChord(shown) ? '$shown:' : '[$shown]';
  }

  return switch (name.toLowerCase()) {
    'comment' || 'c' || 'comment_italic' || 'ci' || 'comment_box' || 'cb' ||
    'highlight' =>
      text.isEmpty ? null : label(text),
    'start_of_chorus' || 'soc' => label('Refrão'),
    'start_of_bridge' || 'sob' => label('Ponte'),
    'start_of_verse' || 'sov' || 'start_of_tab' || 'sot' =>
      text.isEmpty ? null : label(text),
    'capo' => _capoLabel(text),
    _ => null,
  };
}

String? _capoLabel(String text) {
  final casa = int.tryParse(text);
  return casa != null && casa > 0 ? '[Capotraste na $casaª casa]' : null;
}

/// Tira as diretivas do ChordPro (e os comentários `#` que vêm com elas).
String _withoutDirectives(String raw) {
  final lines = raw.split(RegExp(r'\r\n?|\n'));
  if (!lines.any(_directive.hasMatch)) return raw;
  return [
    for (final line in lines)
      if (_directive.firstMatch(line) case final match?)
        _directiveLine(match[1]!, match[2])
      else if (!line.trimLeft().startsWith('#'))
        line,
  ].nonNulls.join('\n');
}

// O .txt do "Baixar cifra" do Cifra Club: "Artista - Música" na primeira
// linha, "Tom: C" às vezes, e a tabela dos desenhos no fim.
final _diagramsMarker = RegExp(r'^\s*-{3,}\s*acordes\s*-{3,}\s*$', caseSensitive: false);
final _keyLine = RegExp(r'^\s*tom:\s*(\S+)\s*$', caseSensitive: false);

/// Tira do texto colado o que não é cifra: a tabela de desenhos dos acordes,
/// a linha "Tom: C" e o cabeçalho "Artista - Música". O cabeçalho só sai
/// quando a tabela está lá — sem ela, uma primeira linha com hífen pode ser
/// verso.
String _withoutFileExtras(String raw) {
  final lines = raw.replaceFirst('﻿', '').split(RegExp(r'\r\n?|\n'));
  final cut = lines.indexWhere(_diagramsMarker.hasMatch);
  bool isKeyLine(String line) =>
      normalizeMusicalKey(_keyLine.firstMatch(line)?[1]) != null;
  final kept = [
    for (final line in cut < 0 ? lines : lines.sublist(0, cut))
      if (!isKeyLine(line)) line,
  ];
  if (cut < 0 && kept.length == lines.length) return raw;
  if (cut >= 0) {
    final first = kept.indexWhere((line) => line.trim().isNotEmpty);
    if (first >= 0 &&
        kept[first].contains(' - ') &&
        !_isChordLine(kept[first]) &&
        (first + 1 == kept.length || kept[first + 1].trim().isEmpty)) {
      kept.removeAt(first);
    }
  }
  return kept.join('\n').replaceFirst(RegExp(r'^\s*\n'), '').trimRight();
}

String normalizeChordSheet(String raw) {
  raw = _withoutDirectives(_withoutFileExtras(raw));
  if (_chordMarkers(raw).isNotEmpty) return raw;

  final lines = raw.split(RegExp(r'\r\n?|\n')).map(_expandTabs).toList();
  final result = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    // "Intro: D A Bm": o rótulo fica, os acordes ganham colchete.
    final label = _labelPrefix.matchAsPrefix(line);
    if (label != null && _isChordLine(line.substring(label.end))) {
      result.add(label[0]! + _bracketChords(line.substring(label.end)));
      continue;
    }
    if (!_isChordLine(line)) {
      result.add(line);
      continue;
    }

    final next = i + 1 < lines.length ? lines[i + 1] : '';
    if (next.trim().isEmpty ||
        isChordSectionLabel(next) ||
        _isChordLine(next)) {
      result.add(_bracketChords(line));
      continue;
    }

    i++;
    final lyrics = next.runes.toList();
    final merged = StringBuffer();
    final repeats = <String>[];
    var column = 0;
    for (final token in _tokens.allMatches(line)) {
      if (!isChord(token[0]!)) {
        // "(2x)" na linha de acordes vale para o verso: vai para o fim dele.
        if (_repeat.hasMatch(token[0]!)) repeats.add(token[0]!);
        continue;
      }
      while (column < token.start) {
        merged.writeCharCode(column < lyrics.length ? lyrics[column] : 32);
        column++;
      }
      merged.write('[${token[0]}]');
    }
    merged.write(String.fromCharCodes(lyrics.skip(column)));
    final verse = _unstretch(merged.toString());
    result.add(
      repeats.isEmpty ? verse : '${verse.trimRight()} ${repeats.join(' ')}',
    );
  }
  return result.join('\n');
}

const _naturalPitch = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
final _sharpNotes = _chromaticNotes(preferFlats: false);
final _flatNotes = _chromaticNotes(preferFlats: true);

List<String> _chromaticNotes({required bool preferFlats}) {
  final exclude = preferFlats ? '#' : 'b';
  return musicalKeys
      .where((key) => !isMinorKey(key) && !key.contains(exclude))
      .toList()
    ..sort((a, b) => _pitch(a).compareTo(_pitch(b)));
}

const _flatKeys = {
  'F',
  'Bb',
  'Eb',
  'Ab',
  'Db',
  'Gb',
  'Dm',
  'Gm',
  'Cm',
  'Fm',
  'Bbm',
  'Ebm',
};

int _pitch(String note) =>
    _naturalPitch[note[0]]! +
    (note.startsWith('#', 1)
        ? 1
        : note.startsWith('b', 1)
            ? -1
            : 0);

String transposeChord(String chord, int semitones, {bool preferFlats = false}) {
  final match = _chord.firstMatch(chord);
  if (match == null) return chord;
  final notes = preferFlats ? _flatNotes : _sharpNotes;
  String shift(String note) => notes[(_pitch(note) + semitones) % 12];
  final bass = match[3];
  return '${shift(match[1]!)}${match[2]}${bass == null ? '' : '/${shift(bass)}'}';
}

/// Tom do controle de leitura, sempre calculado a partir do tom inicial.
///
/// A grafia é a de costume do tom de chegada: D sobe para Eb, e não D#.
String shiftMusicalKey(String key, int semitones) => semitones % 12 == 0
    ? key
    : (isMinorKey(key) ? _usualMinorKeys : _usualMajorKeys)[
        (_pitch(key) + semitones) % 12];

const _usualMajorKeys = [
  'C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B', //
];
const _usualMinorKeys = [
  'Cm', 'C#m', 'Dm', 'Ebm', 'Em', 'Fm', 'F#m', 'Gm', 'G#m', 'Am', 'Bbm', 'Bm', //
];

String transposeChordSheet(String sheet, String? sourceKey, String? targetKey) {
  final source = normalizeMusicalKey(sourceKey);
  final target = normalizeMusicalKey(targetKey);
  if (source == null || target == null) return sheet;
  final distance = _pitch(target) - _pitch(source);
  return sheet.replaceAllMapped(_brackets, (marker) {
    final chord = transposeChord(
      marker[1]!,
      distance,
      preferFlats: _flatKeys.contains(target),
    );
    return '[$chord]';
  });
}
