// Deleting chats and messages.
import 'package:chat_do_garoto/src/chats/chat_screen.dart';
import 'package:chat_do_garoto/src/chats/chats_controller.dart';
import 'package:chat_do_garoto/src/chats/chats_screen.dart';
import 'package:chat_do_garoto/src/chats/media/media_platform.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_core_bridge.dart';
import 'support/fake_media_platform.dart';

const _chat = '5511900000001@s.whatsapp.net';
const _summary = ChatSummary(jid: _chat, name: 'Ana', lastText: '', lastTs: 0);

ChatMessage _msg(String id, String text, {bool mine = false, int? ts}) =>
    ChatMessage(
      chat: _chat,
      id: id,
      fromMe: mine,
      senderName: mine ? '' : 'Ana',
      kind: 'text',
      text: text,
      ts: ts ?? DateTime.now().millisecondsSinceEpoch,
      status: mine ? 'delivered' : '',
    );

/// Opens the conversation over a first page, so closing it can be seen.
Future<FakeCoreBridge> _open(WidgetTester tester) async {
  final bridge = FakeCoreBridge()
    ..chats = [_summary]
    ..messages[_chat] = [
      _msg('R1', 'recebida'),
      _msg('M1', 'minha agora', mine: true),
      _msg(
        'OLD',
        'minha antiga',
        mine: true,
        ts: DateTime.now()
            .subtract(const Duration(hours: 61))
            .millisecondsSinceEpoch,
      ),
    ];
  mediaPlatform = FakeMediaPlatform();
  addTearDown(() => mediaPlatform = const ChannelMediaPlatform());
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChatScreen(bridge: bridge, chat: _summary),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return bridge;
}

Future<void> _hold(WidgetTester tester, String text) async {
  await tester.longPress(find.text(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Apagar'));
  await tester.pumpAndSettle();
}

void main() {
  test('delete for everyone: mine, sent, under 60 hours', () {
    final now = DateTime(2026, 10, 2, 12);
    ChatMessage at(Duration ago, {String status = 'read', bool mine = true}) =>
        ChatMessage(
          chat: _chat,
          id: 'x',
          fromMe: mine,
          senderName: '',
          kind: 'text',
          text: 'oi',
          ts: now.subtract(ago).millisecondsSinceEpoch,
          status: status,
        );
    expect(canRevoke(at(const Duration(hours: 59)), now), isTrue);
    expect(canRevoke(at(const Duration(hours: 61)), now), isFalse);
    expect(canRevoke(at(Duration.zero, status: 'failed'), now), isFalse);
    expect(canRevoke(at(Duration.zero, status: 'sending'), now), isFalse);
    expect(canRevoke(at(Duration.zero, mine: false), now), isFalse);
  });

  testWidgets('my recent message: deleted for everyone when WhatsApp '
      'confirms', (tester) async {
    final bridge = await _open(tester);
    await _hold(tester, 'minha agora');
    expect(find.text('Apagar para todos'), findsOneWidget);
    await tester.tap(find.text('Apagar para todos'));
    await tester.pumpAndSettle();
    expect(bridge.calls, contains('deleteMessage:M1:everyone'));
    // Nothing changes until the core confirms.
    expect(find.text('minha agora'), findsOneWidget);
    bridge.push('wa_deleted', {
      'chat': _chat,
      'id': 'M1',
      'scope': 'revoked',
      'message': {
        'chat': _chat,
        'id': 'M1',
        'from_me': true,
        'sender_name': '',
        'kind': 'revoked',
        'text': '',
        'ts': 1,
        'status': 'delivered',
      },
    });
    await tester.pump();
    expect(find.text('minha agora'), findsNothing);
    expect(find.text('🚫 Você apagou esta mensagem'), findsOneWidget);
    // Only the old message still shows its delivery.
    expect(find.textContaining('✓✓'), findsOneWidget);
  });

  testWidgets('received or old messages: only for me, gone at once', (
    tester,
  ) async {
    final bridge = await _open(tester);
    await _hold(tester, 'minha antiga');
    expect(find.text('Apagar para todos'), findsNothing);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await _hold(tester, 'recebida');
    expect(find.text('Apagar para todos'), findsNothing);
    await tester.tap(find.text('Apagar para mim'));
    await tester.pumpAndSettle();
    expect(bridge.calls, contains('deleteMessage:R1:me'));
    expect(find.text('recebida'), findsNothing);
  });

  testWidgets('deleted by the other side shows "Mensagem apagada"', (
    tester,
  ) async {
    final bridge = await _open(tester);
    bridge.push('wa_deleted', {
      'chat': _chat,
      'id': 'R1',
      'scope': 'revoked',
      'message': {
        'chat': _chat,
        'id': 'R1',
        'from_me': false,
        'sender_name': 'Ana',
        'kind': 'revoked',
        'text': '',
        'ts': 1,
      },
    });
    await tester.pump();
    expect(find.text('🚫 Mensagem apagada'), findsOneWidget);
    // It can still be deleted for me.
    await _hold(tester, '🚫 Mensagem apagada');
    expect(find.text('Apagar para mim'), findsOneWidget);
  });

  testWidgets('offline and refusals are explained', (tester) async {
    final bridge = await _open(tester);
    bridge.deleteError = const CoreException('offline', 'not connected');
    await _hold(tester, 'minha agora');
    await tester.tap(find.text('Apagar para todos'));
    await tester.pumpAndSettle();
    expect(
      find.text('Sem conexão. Apagar para todos precisa de internet.'),
      findsOneWidget,
    );
    expect(find.text('minha agora'), findsOneWidget);

    ScaffoldMessenger.of(tester.element(find.byType(ChatScreen)))
        .clearSnackBars();
    await tester.pumpAndSettle();
    bridge.push('wa_delete_failed', {'chat': _chat, 'id': 'M1'});
    await tester.pump();
    expect(find.text('Não foi possível apagar para todos.'), findsOneWidget);
  });

  testWidgets('delete the chat from its ⋮ menu: back to the list', (
    tester,
  ) async {
    final bridge = await _open(tester);
    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir conversa'));
    await tester.pumpAndSettle();
    expect(find.text('Excluir esta conversa?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(bridge.calls, isNot(contains('deleteChat:$_chat')));

    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir conversa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(bridge.calls, contains('deleteChat:$_chat'));
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.text('abrir'), findsOneWidget);
  });

  testWidgets('deleted or cleared on the phone while open', (tester) async {
    final bridge = await _open(tester);
    bridge.push('wa_deleted', {'chat': _chat, 'scope': 'clear'});
    await tester.pump();
    expect(find.text('recebida'), findsNothing);
    expect(find.byType(ChatScreen), findsOneWidget);

    bridge.push('wa_deleted', {'chat': _chat, 'id': 'X', 'scope': 'message'});
    bridge.push('wa_deleted', {
      'chat': 'other@s.whatsapp.net',
      'scope': 'chat',
    });
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);

    bridge.push('wa_deleted', {'chat': _chat, 'scope': 'chat'});
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsNothing);
  });

  testWidgets('hold a chat in the list to delete it', (tester) async {
    final bridge = FakeCoreBridge()..chats = [_summary];
    final controller = ChatsController(bridge: bridge)..start();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatsScreen(
          bridge: bridge,
          controller: controller,
          status: 'Conectado',
        ),
      ),
    );
    await tester.longPress(find.text('Ana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir conversa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(bridge.calls, contains('deleteChat:$_chat'));
    expect(find.text('Conversa excluída.'), findsOneWidget);
    // The core's event reloads the list.
    bridge.chats = [];
    bridge.push('wa_deleted', {'chat': _chat, 'scope': 'chat'});
    await tester.pump();
    expect(find.text('Ana'), findsNothing);
  });

  testWidgets('delete the chat and my recent messages for everyone', (
    tester,
  ) async {
    final bridge = await _open(tester);
    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir conversa'));
    await tester.pumpAndSettle();
    // One of mine is recent; the old one and the received one do not count.
    final option = find.text(
      'Apagar também para todos as minhas mensagens das últimas 60 horas (1)',
    );
    expect(option, findsOneWidget);

    bridge.deleteError = const CoreException('offline', 'not connected');
    await tester.tap(option);
    await tester.pump();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(
      find.text('Sem conexão. Apagar para todos precisa de internet.'),
      findsOneWidget,
    );
    expect(find.byType(ChatScreen), findsOneWidget);

    bridge.deleteError = null;
    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir conversa'));
    await tester.pumpAndSettle();
    await tester.tap(option);
    await tester.pump();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(bridge.calls, contains('deleteChat:$_chat:everyone'));
    expect(find.byType(ChatScreen), findsNothing);
  });

  testWidgets('no option without recent messages of mine; the list tells '
      'how it went', (tester) async {
    final bridge = FakeCoreBridge()
      ..chats = [_summary]
      ..messages[_chat] = [_msg('R1', 'recebida')];
    final controller = ChatsController(bridge: bridge)..start();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatsScreen(
          bridge: bridge,
          controller: controller,
          status: 'Conectado',
        ),
      ),
    );
    await tester.longPress(find.text('Ana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir conversa'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    bridge.push('wa_revoke_done', {'chat': _chat, 'revoked': 2, 'failed': 1});
    await tester.pump();
    expect(find.text('1 mensagem não foi apagada para todos.'), findsOneWidget);
  });

  test('at most 50 messages count', () {
    final now = DateTime.now();
    final bridge = FakeCoreBridge()
      ..messages[_chat] = [
        for (var i = 0; i < 60; i++)
          _msg('M$i', 'x', mine: true, ts: now.millisecondsSinceEpoch - i),
      ];
    expect(revocableCount(bridge, _chat, now: now), 50);
  });
}
