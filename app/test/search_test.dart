// Search in the conversations and opening on the message found.
import 'package:chat_do_garoto/src/chats/chat_search_screen.dart';
import 'package:chat_do_garoto/src/chats/chats_controller.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:chat_do_garoto/src/search/text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_core_bridge.dart';

const _ana = '5511900000001@s.whatsapp.net';

ChatMessage _m(String id, int ts, String text) => ChatMessage(
  chat: _ana,
  id: id,
  fromMe: false,
  senderName: '',
  kind: 'text',
  text: text,
  ts: ts,
);

void main() {
  test('fold and textMatches ignore accents and case; every word counts', () {
    expect(fold('Ação ORÇAMENTO'), 'acao orcamento');
    expect(textMatches('Segue o Orçamento da Ação', 'acao orc'), isTrue);
    expect(textMatches('Segue o Orçamento', 'orcamento aprovado'), isFalse);
    expect(textMatches('qualquer', ''), isTrue);
  });

  testWidgets(
    'finds chats by name and messages by text; a message opens there',
    (tester) async {
      final bridge = FakeCoreBridge()
        ..chats = const [
          ChatSummary(jid: _ana, name: 'Ana Souza', lastText: 'oi', lastTs: 9),
          ChatSummary(
            jid: '5511900000002@s.whatsapp.net',
            name: 'Bruno',
            lastText: 'x',
            lastTs: 8,
          ),
        ]
        ..messages[_ana] = [
          _m('1', 100, 'segue o orçamento'),
          _m('2', 200, 'obrigado'),
        ]
        ..searchable.add(_m('1', 100, 'segue o orçamento'));
      final chats = ChatsController(bridge: bridge)..start();
      await tester.pumpWidget(
        MaterialApp(
          home: ChatSearchScreen(bridge: bridge, chats: chats),
        ),
      );

      await tester.enterText(find.byType(TextField), 'ana');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Conversas'), findsOneWidget);
      expect(find.text('Ana Souza'), findsOneWidget);
      expect(find.text('Bruno'), findsNothing);

      await tester.enterText(find.byType(TextField), 'orçamento');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Mensagens'), findsOneWidget);
      expect(find.text('segue o orçamento'), findsOneWidget);

      await tester.tap(find.text('segue o orçamento'));
      await tester.pumpAndSettle();
      expect(find.text('Ir para as mais recentes'), findsOneWidget);
      await tester.tap(find.text('Ir para as mais recentes'));
      await tester.pumpAndSettle();
      expect(find.text('Ir para as mais recentes'), findsNothing);
    },
  );

  testWidgets('nothing found says so', (tester) async {
    final bridge = FakeCoreBridge();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatSearchScreen(
          bridge: bridge,
          chats: ChatsController(bridge: bridge)..start(),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'xyz');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Nada encontrado.'), findsOneWidget);
  });

  test(
    'opening on a message: the past page, new messages wait, sending jumps',
    () {
      final bridge = FakeCoreBridge()
        ..messages[_ana] = [_m('1', 100, 'antiga')];
      final focus = _m('1', 100, 'antiga');
      final c = ChatController(
        bridge: bridge,
        chat: const ChatSummary(
          jid: _ana,
          name: 'Ana',
          lastText: '',
          lastTs: 0,
        ),
        focus: focus,
      )..start();
      expect(c.inPast, isTrue);

      bridge.push('wa_message', {
        'chat': _ana,
        'id': '9',
        'from_me': false,
        'sender': '',
        'sender_name': '',
        'kind': 'text',
        'text': 'nova',
        'ts': 900,
      });
      expect(c.messages.map((m) => m.text), [
        'antiga',
      ], reason: 'waits behind the button');

      c.send('resposta');
      expect(c.inPast, isFalse);
      expect(c.messages.last.text, 'resposta');
    },
  );
}
