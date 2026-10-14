import 'package:chat_do_garoto/src/prototype/prototype_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_core_bridge.dart';

Widget _screen(FakeCoreBridge bridge) =>
    MaterialApp(home: PrototypeScreen(bridge: bridge));

void main() {
  testWidgets('shows the core version on start', (tester) async {
    await tester.pumpWidget(_screen(FakeCoreBridge()));

    expect(
      find.text('Motor Go conectado: core 9.9.9 · go1.99'),
      findsOneWidget,
    );
  });

  testWidgets('shows the text sent back by the core', (tester) async {
    await tester.pumpWidget(_screen(FakeCoreBridge()));

    await tester.enterText(find.byType(TextField), 'Olá, ação! 🚀');
    await tester.tap(find.text('Enviar ao Go'));
    await tester.pump();

    expect(find.text('Resposta: Olá, ação! 🚀'), findsOneWidget);
  });

  testWidgets('shows a core error and keeps working', (tester) async {
    await tester.pumpWidget(_screen(FakeCoreBridge(echoFails: true)));

    await tester.tap(find.text('Enviar ao Go'));
    await tester.pump();

    expect(
      find.text('Erro do motor Go: invalid_argument (text is null)'),
      findsOneWidget,
    );
    expect(find.text('Enviar ao Go'), findsOneWidget);
  });

  testWidgets('live counter follows tick events and stops', (tester) async {
    final bridge = FakeCoreBridge();
    await tester.pumpWidget(_screen(bridge));

    await tester.tap(find.text('Iniciar contador'));
    await tester.pump();
    expect(bridge.tickerRunning, isTrue);

    bridge.pushTick(1);
    bridge.pushTick(2);
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text('Parar'));
    await tester.pump();
    expect(bridge.tickerRunning, isFalse);
  });
}
