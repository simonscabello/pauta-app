import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/features/team/domain/workload_report.dart';

void main() {
  final json = <String, dynamic>{
    'vacancies': [
      {
        'positionId': 'violao',
        'positionName': 'Violão',
        'vacancies': 1,
        'candidates': [
          {
            'membershipId': 'bia',
            'name': 'Bia',
            'score': 96,
            'reasons': ['Há 5 semanas sem servir', 'Já serve no culto da noite'],
          },
        ],
      },
    ],
  };

  test('lê os candidatos da função pedida, com os motivos', () {
    final list = AssignmentSuggestion.forPosition(json, 'violao');
    expect(list.single.membershipId, 'bia');
    expect(list.single.reasons, hasLength(2));
  });

  test('função sem vaga não tem sugestão', () {
    expect(AssignmentSuggestion.forPosition(json, 'vocal'), isEmpty);
    expect(AssignmentSuggestion.forPosition({'vacancies': []}, 'violao'), isEmpty);
  });
}
