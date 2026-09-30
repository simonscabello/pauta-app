import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:louvor_app/core/theme/app_status_colors.dart';
import 'package:louvor_app/core/theme/app_theme.dart';
import 'package:louvor_app/shared/widgets/app_feedback.dart';

/// Um botão que mostra o aviso, para o teste tocar nele.
Widget _app({SnackBarAction? action}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showAppSnackBar(
            context,
            'Escala publicada para a equipe.',
            tone: AppTone.success,
            action: action,
          ),
          child: const Text('mostrar'),
        ),
      ),
    ),
  );
}

void main() {
  // O "Escala publicada · Compartilhar" ficava na tela até alguém tocar nele:
  // no Flutter 3.29+ o aviso com ação persiste por padrão.
  testWidgets('aviso com ação some sozinho depois de 8 segundos',
      (tester) async {
    await tester.pumpWidget(
      _app(action: SnackBarAction(label: 'Compartilhar', onPressed: () {})),
    );
    await tester.tap(find.text('mostrar'));
    await tester.pumpAndSettle();
    expect(find.text('Escala publicada para a equipe.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    expect(find.text('Escala publicada para a equipe.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Escala publicada para a equipe.'), findsNothing);
  });

  testWidgets('aviso com ação tem o X, que fecha na hora', (tester) async {
    await tester.pumpWidget(
      _app(action: SnackBarAction(label: 'Compartilhar', onPressed: () {})),
    );
    await tester.tap(find.text('mostrar'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Escala publicada para a equipe.'), findsNothing);
  });

  testWidgets('aviso sem ação some em 4 segundos e não tem o X',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('mostrar'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Escala publicada para a equipe.'), findsNothing);
  });
}
