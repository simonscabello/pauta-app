import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/shared/widgets/app_fact_list.dart';

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(24), child: child),
      ),
    );

void main() {
  testWidgets('dois cultos e funções longas aparecem inteiros, sem estourar',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: _app(
          const AppFactList(
            facts: [
              AppFact(
                icon: Icons.church_rounded,
                label: 'Cultos',
                value: 'Manhã 08:30\nNoite 19:00',
              ),
              AppFact(
                icon: Icons.schedule_rounded,
                label: 'Ensaio',
                value: 'sáb 19:00',
              ),
              AppFact(
                icon: Icons.star_rounded,
                label: 'Sua função',
                value: 'Ministra · Vocal · Violão',
                highlight: true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Manhã 08:30'), findsOneWidget);
    expect(find.text('Noite 19:00'), findsOneWidget);
    expect(find.text('Ministra · Vocal · Violão'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
