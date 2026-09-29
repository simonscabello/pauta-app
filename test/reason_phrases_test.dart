import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/features/suggestions/domain/reason_phrases.dart';

void main() {
  test('acrescenta ao fim, com ponto quando falta', () {
    expect(toggleReasonPhrase('', 'Letra bíblica'), 'Letra bíblica');
    expect(
      toggleReasonPhrase('A igreja canta junto', 'Letra bíblica'),
      'A igreja canta junto. Letra bíblica',
    );
    expect(
      toggleReasonPhrase('A igreja canta junto!', 'Letra bíblica'),
      'A igreja canta junto! Letra bíblica',
    );
  });

  test('tira a frase de qualquer ponto, deixando o resto como estava', () {
    expect(toggleReasonPhrase('Letra bíblica', 'Letra bíblica'), '');
    expect(
      toggleReasonPhrase('Letra bíblica. Música animada', 'Letra bíblica'),
      'Música animada',
    );
    expect(
      toggleReasonPhrase(
        'Canta junto. Letra bíblica. Fácil de aprender',
        'Letra bíblica',
      ),
      'Canta junto. Fácil de aprender',
    );
    expect(
      toggleReasonPhrase('Canta junto. Letra bíblica.', 'Letra bíblica'),
      'Canta junto.',
    );
  });

  test('só casa a frase como trecho inteiro', () {
    expect(
      containsReasonPhrase('A letra bíblica me marcou', 'Letra bíblica'),
      isFalse,
    );
    expect(containsReasonPhrase('letra bíblica.', 'Letra bíblica'), isTrue);
    expect(
      toggleReasonPhrase('A letra bíblica me marcou', 'Letra bíblica'),
      'A letra bíblica me marcou. Letra bíblica',
    );
  });
}
