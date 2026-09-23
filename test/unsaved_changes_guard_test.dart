import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:louvor_app/shared/widgets/unsaved_changes_guard.dart';

/// Um formulário mínimo: um campo, e "alterado" é o texto diferente do salvo.
class _Form extends StatefulWidget {
  const _Form();

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> with UnsavedChangesTracker {
  final _text = TextEditingController();

  @override
  String unsavedSignature() => _text.text;

  @override
  Widget build(BuildContext context) {
    markUnsavedBaseline();
    return UnsavedChangesGuard(
      isDirty: hasUnsavedChanges,
      child: Scaffold(
        appBar: AppBar(title: const Text('Formulário')),
        body: Column(
          children: [
            TextField(controller: _text),
            TextButton(
              onPressed: () {
                markSaved();
                context.pop();
              },
              child: const Text('Salvar'),
            ),
            TextButton(
              onPressed: () => context.go('/outra'),
              child: const Text('Barra lateral'),
            ),
          ],
        ),
      ),
    );
  }
}

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/form'),
              child: const Text('Abrir'),
            ),
          ),
        ),
        GoRoute(
          path: '/form',
          onExit: confirmLeaveIfUnsaved,
          builder: (_, __) => const _Form(),
        ),
        GoRoute(
          path: '/outra',
          builder: (_, __) => const Scaffold(body: Text('Outra tela')),
        ),
      ],
    );

Future<void> _openForm(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sem alteração, voltar não pergunta nada', (tester) async {
    await _openForm(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Sair sem salvar?'), findsNothing);
    expect(find.text('Abrir'), findsOneWidget);
  });

  testWidgets('com alteração, voltar pergunta e "Continuar editando" fica',
      (tester) async {
    await _openForm(tester);
    await tester.enterText(find.byType(TextField), 'três músicas');
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Sair sem salvar?'), findsOneWidget);

    await tester.tap(find.text('Continuar editando'));
    await tester.pumpAndSettle();
    expect(find.text('Formulário'), findsOneWidget);
    expect(find.text('três músicas'), findsOneWidget);
  });

  testWidgets('"Descartar alterações" sai, e pergunta uma vez só',
      (tester) async {
    await _openForm(tester);
    await tester.enterText(find.byType(TextField), 'tom G');
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar alterações'));
    await tester.pumpAndSettle();

    expect(find.text('Sair sem salvar?'), findsNothing);
    expect(find.text('Abrir'), findsOneWidget);
  });

  testWidgets('navegar por fora (go) também pergunta', (tester) async {
    await _openForm(tester);
    await tester.enterText(find.byType(TextField), 'recado');
    await tester.pump();

    await tester.tap(find.text('Barra lateral'));
    await tester.pumpAndSettle();
    expect(find.text('Sair sem salvar?'), findsOneWidget);

    await tester.tap(find.text('Continuar editando'));
    await tester.pumpAndSettle();
    expect(find.text('Formulário'), findsOneWidget);

    await tester.tap(find.text('Barra lateral'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar alterações'));
    await tester.pumpAndSettle();
    expect(find.text('Outra tela'), findsOneWidget);
  });

  testWidgets('salvar e sair não pergunta', (tester) async {
    await _openForm(tester);
    await tester.enterText(find.byType(TextField), 'salvo');
    await tester.pump();

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Sair sem salvar?'), findsNothing);
    expect(find.text('Abrir'), findsOneWidget);
  });
}
