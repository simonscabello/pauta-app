/// Frases prontas para o motivo da sugestão.
///
/// O motivo deixou de ser obrigatório (09/2026): a cobrança fazia a sugestão
/// não chegar. Estas frases são o meio-termo — um toque escreve no campo, e o
/// líder continua recebendo um argumento, não só um título.
///
/// A folha mostra cada uma como chip; o chip fica marcado enquanto a frase
/// está no texto, e tocar de novo a tira. Quem quiser completa à mão.
const reasonPhrases = [
  'Letra bíblica',
  'Música animada',
  'Boa para adoração',
  'Fácil de aprender',
  'A igreja já conhece',
];

/// Só faz sentido quando a sugestão é para um dia.
const datedReasonPhrases = ['Combina com a mensagem do dia'];

/// A frase como um trecho inteiro do texto: no começo ou depois de pontuação,
/// e terminando no fim ou antes de pontuação. "Letra bíblica" não casa dentro
/// de "A letra bíblica me marcou".
RegExp _segment(String phrase) => RegExp(
      r'(^|(?<=[.!?]))\s*' + RegExp.escape(phrase) + r'\s*(\.|(?=[!?])|$)',
      caseSensitive: false,
    );

bool containsReasonPhrase(String text, String phrase) =>
    _segment(phrase).hasMatch(text.trim());

/// Acrescenta a frase ao fim do texto, ou a tira se ela já está lá. O resto
/// do que a pessoa escreveu fica como estava.
String toggleReasonPhrase(String text, String phrase) {
  final trimmed = text.trim();
  if (containsReasonPhrase(trimmed, phrase)) {
    return trimmed
        .replaceFirst(_segment(phrase), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }
  if (trimmed.isEmpty) return phrase;
  final separator = RegExp(r'[.!?]$').hasMatch(trimmed) ? ' ' : '. ';
  return '$trimmed$separator$phrase';
}
