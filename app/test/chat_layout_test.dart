// The conversation lays itself out by the room it has (not by the window):
// header, messages and message box on one left edge, the client panel docked
// on big panes, bubbles that follow the column.
import 'package:chat_do_garoto/src/chats/chat_screen.dart';
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:chat_do_garoto/src/home/crm_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_prefs.dart';
import 'support/fake_clients_repository.dart';
import 'support/fake_core_bridge.dart';

const _pn = '5511900000001@s.whatsapp.net';

Future<void> _open(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  final bridge = FakeCoreBridge()
    ..messages[_pn] = [
      for (final (i, mine) in [false, true].indexed)
        ChatMessage(
          chat: _pn,
          id: 'm$i',
          fromMe: mine,
          senderName: '',
          kind: 'text',
          text: mine ? 'Tem sim, preta ou branca?' : 'Oi, tem a camiseta azul?',
          ts: DateTime(2026, 10, 2, 8, i).millisecondsSinceEpoch,
        ),
    ];
  final repo = FakeClientsRepository();
  await repo.save(
    Client(name: 'Maria Souza', phone: '5511900000001', chatJid: _pn),
  );
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          CrmScope(chatPrefs: FakeChatPrefs(), child: child!),
      home: ChatScreen(
        bridge: bridge,
        chat: ChatSummary(jid: _pn, name: 'Maria', lastText: '', lastTs: 0),
        clients: repo,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a big pane docks the client panel beside the conversation', (
    tester,
  ) async {
    await _open(tester, const Size(1500, 900));
    // The panel is there without a tap: its actions are in view.
    expect(find.text('Ver ficha'), findsOneWidget);
    expect(find.text('Cliente'), findsOneWidget);
    // The name no longer opens a sheet: the panel is already in view.
    await tester.tap(find.text('Maria Souza').first);
    await tester.pumpAndSettle();
    expect(find.text('Ver ficha'), findsOneWidget);
  });

  testWidgets('a narrow pane keeps the panel in a sheet opened by the name', (
    tester,
  ) async {
    await _open(tester, const Size(900, 900));
    expect(find.text('Ver ficha'), findsNothing);
    await tester.tap(find.text('Maria Souza').first);
    await tester.pumpAndSettle();
    expect(find.text('Ver ficha'), findsOneWidget);
  });

  for (final width in [700.0, 1000.0, 1500.0, 2400.0]) {
    testWidgets('title, messages and box share a left edge at $width', (
      tester,
    ) async {
      await _open(tester, Size(width, 900));
      final title = tester.getTopLeft(find.text('Maria Souza').first).dx;
      // The bubble's text sits 12 inside its edge.
      final bubble =
          tester.getTopLeft(find.text('Oi, tem a camiseta azul?')).dx - 12;
      final box = tester.getTopLeft(find.byType(TextField)).dx;
      expect(bubble, closeTo(title, 0.5));
      // The box starts after the 48 wide attach button, which has its own
      // 8 of padding around the icon and the field's 8 margin.
      expect(box, greaterThan(bubble));
    });
  }

  testWidgets('a bubble never goes past its share of the column', (
    tester,
  ) async {
    await _open(tester, const Size(2400, 900));
    final mine = tester.getSize(find.text('Tem sim, preta ou branca?'));
    expect(mine.width, lessThan(680));
    final theirs = tester.getTopLeft(find.text('Oi, tem a camiseta azul?')).dx;
    final yours = tester.getTopRight(find.text('Tem sim, preta ou branca?')).dx;
    // Both sit inside the 1040 column (plus the docked panel's 340 on the
    // right), not at the window's edges.
    expect(theirs, greaterThan(200));
    expect(yours, lessThan(2400 - 340));
  });
}
