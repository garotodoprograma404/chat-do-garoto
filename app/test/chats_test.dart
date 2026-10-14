// Chat list and conversation with a fake bridge.
import 'package:chat_do_garoto/src/chats/chat_screen.dart';
import 'package:chat_do_garoto/src/chats/chats_controller.dart';
import 'package:chat_do_garoto/src/chats/chats_screen.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_core_bridge.dart';

const _ana = ChatSummary(
  jid: '5511900000001@s.whatsapp.net',
  name: 'Ana',
  lastText: 'até amanhã',
  lastTs: 2000,
);
const _unnamed = ChatSummary(
  jid: '5511900000002@s.whatsapp.net',
  name: '',
  lastText: '[imagem]',
  lastTs: 1000,
);
const _group = ChatSummary(
  jid: '120363000000000001@g.us',
  name: 'Família',
  lastText: 'bom dia',
  lastTs: 500,
);

ChatMessage _msg(
  String chat,
  String id,
  int ts, {
  String text = '',
  String kind = 'text',
  bool fromMe = false,
  String sender = 'Bia',
}) => ChatMessage(
  chat: chat,
  id: id,
  fromMe: fromMe,
  senderName: sender,
  kind: kind,
  text: text,
  ts: ts,
);

Map<String, Object?> _json(ChatMessage m) => {
  'chat': m.chat,
  'id': m.id,
  'from_me': m.fromMe,
  'sender': '',
  'sender_name': m.senderName,
  'kind': m.kind,
  'text': m.text,
  'ts': m.ts,
};

Future<(FakeCoreBridge, ChatsController)> _openList(WidgetTester tester) async {
  final bridge = FakeCoreBridge()..chats = [_ana, _unnamed, _group];
  final controller = ChatsController(bridge: bridge)..start();
  await tester.pumpWidget(
    MaterialApp(
      home: ChatsScreen(
        bridge: bridge,
        controller: controller,
        status: 'Conectado',
      ),
    ),
  );
  return (bridge, controller);
}

void main() {
  testWidgets('lists chats with name or number and last message', (
    tester,
  ) async {
    await _openList(tester);

    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('até amanhã'), findsOneWidget);
    expect(find.text('+55 11 90000-0002'), findsOneWidget); // no name: number
    expect(find.text('Família'), findsOneWidget);
  });

  testWidgets('reloads the list when a message or history arrives', (
    tester,
  ) async {
    final (bridge, _) = await _openList(tester);
    final before = bridge.calls.where((c) => c == 'listChats').length;

    bridge.chats = [_ana.copyWithText('nova!'), _unnamed, _group];
    bridge.push('wa_message', _json(_msg(_ana.jid, 'x', 3000, text: 'nova!')));
    bridge.push('wa_history', {'chats': 1, 'messages': 10});
    await tester.pump();

    expect(bridge.calls.where((c) => c == 'listChats').length, before + 2);
    expect(find.text('nova!'), findsOneWidget);
  });

  testWidgets('logging out empties the list', (tester) async {
    final (bridge, _) = await _openList(tester);

    bridge.push('wa_logged_out', {'reason': 'user'});
    await tester.pump();

    expect(find.text('Nenhuma conversa ainda.'), findsOneWidget);
  });

  testWidgets('opens a conversation with mine, theirs and markers', (
    tester,
  ) async {
    final (bridge, _) = await _openList(tester);
    bridge.messages[_group.jid] = [
      _msg(_group.jid, '1', 100, text: 'bom dia'),
      _msg(_group.jid, '2', 200, kind: 'image', text: 'olha'),
      _msg(_group.jid, '3', 300, text: 'oi', fromMe: true),
    ];

    await tester.tap(find.text('Família'));
    await tester.pumpAndSettle();

    expect(find.text('bom dia'), findsWidgets);
    expect(find.text('[imagem] olha'), findsOneWidget);
    expect(find.text('oi'), findsOneWidget);
    expect(find.text('Bia'), findsNWidgets(2)); // sender shown in groups
  });

  testWidgets('a new message appears live, once, only in its chat', (
    tester,
  ) async {
    final (bridge, _) = await _openList(tester);
    bridge.messages[_ana.jid] = [_msg(_ana.jid, '1', 100, text: 'oi')];
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();

    final live = _msg(_ana.jid, '2', 200, text: 'chegou agora');
    bridge.push('wa_message', _json(live));
    bridge.push('wa_message', _json(live)); // delivered twice
    bridge.push(
      'wa_message',
      _json(_msg(_group.jid, '9', 300, text: 'outro chat')),
    );
    await tester.pump();

    expect(find.text('chegou agora'), findsOneWidget);
    expect(find.text('outro chat'), findsNothing);
  });

  testWidgets('loads older messages a page at a time', (tester) async {
    final bridge = FakeCoreBridge()
      ..messages[_ana.jid] = [
        for (var i = 1; i <= ChatController.pageSize; i++)
          _msg(_ana.jid, '$i', i * 10, text: 'm$i'),
      ];
    final controller = ChatController(bridge: bridge, chat: _ana)..start();

    expect(controller.hasOlder, isTrue);
    controller.loadOlder();
    expect(
      bridge.calls.where((c) => c == 'listMessages:${_ana.jid}'),
      hasLength(2),
    );
  });

  testWidgets('sends a reply that shows at once as sending', (tester) async {
    final (bridge, _) = await _openList(tester);
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'resposta');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();

    expect(bridge.calls, contains('sendText:${_ana.jid}'));
    expect(find.text('resposta'), findsOneWidget);
    expect(find.textContaining('enviando'), findsOneWidget);
    // The field is cleared after sending.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );

    // The core echoes it as wa_message: still shown once.
    bridge.push('wa_message', {
      ..._json(
        _msg(_ana.jid, 'sent1', 1000001, text: 'resposta', fromMe: true),
      ),
      'status': 'sending',
    });
    await tester.pump();
    expect(find.text('resposta'), findsOneWidget);
  });

  testWidgets('blank text is not sent', (tester) async {
    final (bridge, _) = await _openList(tester);
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();

    expect(bridge.calls.where((c) => c.startsWith('sendText')), isEmpty);
  });

  testWidgets('a refused send keeps the text and warns', (tester) async {
    final (bridge, _) = await _openList(tester);
    bridge.sendError = const CoreException('invalid_state', 'not paired');
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'oi');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();

    expect(find.text('Não foi possível enviar.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'oi',
    );
  });

  testWidgets('status changes live, and a failed message can be retried', (
    tester,
  ) async {
    final (bridge, _) = await _openList(tester);
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'teste');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump();

    void status(String s) => bridge.push('wa_message_status', {
      'chat': _ana.jid,
      'id': 'sent1',
      'status': s,
    });

    status('failed');
    await tester.pump();
    expect(find.textContaining('falhou'), findsOneWidget);

    bridge.messages[_ana.jid] = [
      _msg(_ana.jid, 'sent1', 1000001, text: 'teste', fromMe: true),
    ];
    await tester.tap(find.text('Tentar de novo'));
    await tester.pump();
    expect(bridge.calls, contains('retryMessage:sent1'));
    expect(find.textContaining('enviando'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsNothing);

    status('sent');
    await tester.pump();
    expect(find.textContaining('✓'), findsOneWidget);
    status('read');
    await tester.pump();
    expect(find.textContaining('✓✓ lida'), findsOneWidget);

    // A status for another chat changes nothing here.
    bridge.push('wa_message_status', {
      'chat': _group.jid,
      'id': 'sent1',
      'status': 'failed',
    });
    await tester.pump();
    expect(find.textContaining('falhou'), findsNothing);
  });

  test('a chat tells whether its last message is mine', () {
    final base = {
      'jid': _ana.jid,
      'name': 'Ana',
      'last_text': 'oi',
      'last_ts': 1,
    };
    expect(
      ChatSummary.fromJson({...base, 'last_from_me': false}).lastFromMe,
      isFalse,
    );
    // An older core without the field: nothing claims a reply is due.
    expect(ChatSummary.fromJson(base).lastFromMe, isTrue);
  });

  test('statusLabel shows each delivery status', () {
    expect(statusLabel('sending'), 'enviando');
    expect(statusLabel('sent'), '✓');
    expect(statusLabel('delivered'), '✓✓');
    expect(statusLabel('read'), '✓✓ lida');
    expect(statusLabel('failed'), 'falhou');
    expect(statusLabel(''), '');
  });

  test('shortTime shows the hour today and the date otherwise', () {
    final now = DateTime(2026, 10, 1, 18);
    final today = DateTime(2026, 10, 1, 9, 5).millisecondsSinceEpoch;
    final earlier = DateTime(2026, 9, 28, 9, 5).millisecondsSinceEpoch;
    expect(shortTime(today, now: now), '09:05');
    expect(shortTime(earlier, now: now), '28/09');
  });

  test('messageText marks media and keeps captions', () {
    expect(messageText(_msg('c', '1', 1, kind: 'audio')), '[áudio]');
    expect(
      messageText(_msg('c', '1', 1, kind: 'video', text: 'x')),
      '[vídeo] x',
    );
    expect(messageText(_msg('c', '1', 1, text: 'texto')), 'texto');
  });
}

extension on ChatSummary {
  ChatSummary copyWithText(String text) =>
      ChatSummary(jid: jid, name: name, lastText: text, lastTs: lastTs + 1);
}
