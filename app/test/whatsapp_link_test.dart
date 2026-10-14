// The client page's WhatsApp block and client names in the chat list
import 'package:chat_do_garoto/src/chats/chats_controller.dart';
import 'package:chat_do_garoto/src/chats/chats_screen.dart';
import 'package:chat_do_garoto/src/clients/client_screen.dart';
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';
import 'support/fake_core_bridge.dart';

const _pn = '5511900000001@s.whatsapp.net';
const _lid = '28175035842608@lid';

ChatMessage _m(
  String chat,
  String id,
  int ts,
  String text, {
  bool mine = false,
}) => ChatMessage(
  chat: chat,
  id: id,
  fromMe: mine,
  senderName: '',
  kind: 'text',
  text: text,
  ts: ts,
);

Future<void> _page(
  WidgetTester tester,
  FakeCoreBridge bridge,
  FakeClientsRepository repo,
  int id,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ClientScreen(repo: repo, id: id, bridge: bridge),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the client page shows the last messages and opens the chat', (
    tester,
  ) async {
    final bridge = FakeCoreBridge()
      ..messages[_pn] = [
        _m(_pn, '2', 2000, 'tudo bem?'),
        _m(_pn, '3', 3000, 'sim!', mine: true),
      ];
    final repo = FakeClientsRepository();
    final id = await repo.save(
      const Client(name: 'Ana', phone: '5511900000001', chatJid: _pn),
    );
    await _page(tester, bridge, repo, id);

    expect(find.text('tudo bem?'), findsOneWidget);
    expect(find.text('Você: sim!'), findsOneWidget);
    expect(bridge.calls, contains('listMessages:$_pn'));

    // The WhatsApp block is at the end of the page.
    await tester.ensureVisible(find.text('Abrir conversa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir conversa'));
    await tester.pumpAndSettle();
    expect(
      find.byTooltip('Enviar'),
      findsOneWidget,
      reason: 'the conversation',
    );
  });

  testWidgets('a client saved by phone finds the chat under a private ID', (
    tester,
  ) async {
    final bridge = FakeCoreBridge()
      ..chatsByPhone['5511900000009'] = _lid
      ..messages[_lid] = [_m(_lid, '1', 1000, 'oi')];
    final repo = FakeClientsRepository();
    final id = await repo.save(
      const Client(name: 'Bia', phone: '5511900000009'),
    );
    await _page(tester, bridge, repo, id);
    expect(find.text('oi'), findsOneWidget);
  });

  testWidgets('a client without WhatsApp says so', (tester) async {
    final repo = FakeClientsRepository();
    final id = await repo.save(
      const Client(name: 'Caio', phone: '5511900000007'),
    );
    await _page(tester, FakeCoreBridge(), repo, id);
    expect(find.text('Sem conversa no WhatsApp'), findsOneWidget);
    expect(find.text('Abrir conversa'), findsNothing);
  });

  testWidgets('client chats show the name in the file and a mark', (
    tester,
  ) async {
    final bridge = FakeCoreBridge()
      ..phones[_lid] = '5511900000009'
      ..chats = const [
        ChatSummary(jid: _pn, name: 'Ana WhatsApp', lastText: 'a', lastTs: 3),
        ChatSummary(jid: _lid, name: 'Bia WhatsApp', lastText: 'b', lastTs: 2),
        ChatSummary(
          jid: '5511900000005@s.whatsapp.net',
          name: 'Desconhecido',
          lastText: 'c',
          lastTs: 1,
        ),
      ];
    final repo = FakeClientsRepository();
    await repo.save(const Client(name: 'Ana Souza', phone: '5511900000001'));
    await repo.save(const Client(name: 'Bia Lima', phone: '5511900000009'));
    await tester.pumpWidget(
      MaterialApp(
        home: ChatsScreen(
          bridge: bridge,
          controller: ChatsController(bridge: bridge)..start(),
          status: 'Conectado',
          clients: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ana Souza'), findsOneWidget);
    expect(
      find.text('Bia Lima'),
      findsOneWidget,
      reason: 'phone behind the LID',
    );
    expect(find.text('Desconhecido'), findsOneWidget);
    expect(find.text('cliente'), findsNWidgets(2));
    expect(find.text('Ana WhatsApp'), findsNothing);
  });
}
