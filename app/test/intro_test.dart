// The first-run screens.
import 'package:chat_do_garoto/src/intro/intro_controller.dart';
import 'package:chat_do_garoto/src/intro/intro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_key_vault.dart';

Future<void> _continue(WidgetTester tester) async {
  await tester.tap(find.text('Continuar'));
  await tester.pumpAndSettle();
}

FilledButton _button(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

void main() {
  test('the mark is kept in the vault; restoring is asked once', () async {
    final store = FakeKeyVault();
    final c = IntroController(store: store);
    expect(c.seen, isNull);
    await c.start();
    expect(c.seen, isFalse);
    await c.complete(restore: true);
    expect((c.seen, c.restoreWanted, store.key), (true, true, '1'));
    c.restoreOffered();
    expect(c.restoreWanted, isFalse);

    final again = IntroController(store: store);
    await again.start();
    expect(again.seen, isTrue);
  });

  testWidgets('new install: three pages, the warning must be confirmed', (
    tester,
  ) async {
    bool? restored;
    await tester.pumpWidget(
      MaterialApp(
        home: IntroScreen(
          mode: IntroMode.newInstall,
          onDone: ({required restore}) => restored = restore,
        ),
      ),
    );
    expect(find.text('O que o app protege'), findsOneWidget);
    expect(find.text('1 de 3'), findsOneWidget);
    expect(find.text('Voltar'), findsNothing);
    await _continue(tester);
    expect(find.text('O que o app não protege'), findsOneWidget);
    expect(find.textContaining('14 dias'), findsOneWidget);
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(find.text('O que o app protege'), findsOneWidget);
    await _continue(tester);
    await _continue(tester);
    expect(find.text('Faça backup'), findsOneWidget);
    expect(_button(tester).onPressed, isNull); // not confirmed yet
    await tester.tap(find.textContaining('Entendi que, sem backup'));
    await tester.pump();
    await tester.tap(find.text('Tenho um backup para restaurar'));
    await tester.pump();
    await _continue(tester);
    expect(restored, isTrue);
  });

  testWidgets('already in use: confirmed, without restoring', (tester) async {
    bool? restored;
    await tester.pumpWidget(
      MaterialApp(
        home: IntroScreen(
          mode: IntroMode.existing,
          onDone: ({required restore}) => restored = restore,
        ),
      ),
    );
    await _continue(tester);
    await _continue(tester);
    expect(find.text('Tenho um backup para restaurar'), findsNothing);
    await tester.tap(find.textContaining('Entendi que, sem backup'));
    await tester.pump();
    await _continue(tester);
    expect(restored, isFalse);
  });

  testWidgets('reading mode: no confirmation, closes at the end', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const IntroScreen(mode: IntroMode.read),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Privacidade e segurança'), findsOneWidget);
    await _continue(tester);
    await _continue(tester);
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(find.text('abrir'), findsOneWidget);
  });
}
