import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/features/events/domain/event_models.dart';

Event _escala({required DateTime quando, String status = 'PUBLISHED'}) =>
    Event.fromJson({
      'id': 'e1',
      'teamId': 't1',
      'title': null,
      'startsAt': quando.toUtc().toIso8601String(),
      'rehearsalAt': null,
      'location': null,
      'notes': null,
      'colorPalette': null,
      'status': status,
      'timezone': 'America/Sao_Paulo',
      'songs': const <Object>[],
      'assignments': [
        for (final (funcao, pessoas) in [
          ('Vocal', ['a', 'b']),
          // A mesma pessoa em duas funções conta uma vez.
          ('Violão', ['a', 'c']),
        ])
          {
            'positionId': funcao,
            'positionName': funcao,
            'sortOrder': 0,
            'members': [
              for (final p in pessoas)
                {
                  'id': '$funcao-$p',
                  'membershipId': p,
                  'displayName': p,
                  'note': null,
                  'isRegisteredForPosition': true,
                },
            ],
          },
      ],
      'confirmations': [
        {'membershipId': 'a', 'status': 'CONFIRMED'},
        {'membershipId': 'b', 'status': 'DECLINED'},
        // Resposta de quem já saiu da escala não entra na conta.
        {'membershipId': 'z', 'status': 'CONFIRMED'},
      ],
    });

void main() {
  final futuro = DateTime.now().add(const Duration(days: 3));

  test('conta cada pessoa uma vez, e só quem está na escala', () {
    expect(
      _escala(quando: futuro).presenceCounts,
      (confirmed: 1, declined: 1, total: 3),
    );
  });

  test('rascunho e escala passada não têm o que responder', () {
    expect(_escala(quando: futuro, status: 'DRAFT').presenceCounts, isNull);
    expect(
      _escala(quando: DateTime.now().subtract(const Duration(days: 1)))
          .presenceCounts,
      isNull,
    );
  });
}
