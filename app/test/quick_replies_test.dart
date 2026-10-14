// Quick replies.
import 'package:chat_do_garoto/src/chats/chat_prefs.dart';
import 'package:chat_do_garoto/src/chats/chat_screen.dart';
import 'package:chat_do_garoto/src/chats/quick_replies.dart';
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:chat_do_garoto/src/home/crm_scope.dart';
import 'package:chat_do_garoto/src/settings/quick_replies_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_prefs.dart';
import 'support/fake_clients_repository.dart';
import 'support/fake_core_bridge.dart';

const _pn = '5511900000001@s.whatsapp.net';
const _pix = QuickReply(shortcut: 'pix', text: 'Oi {nome}, a chave pix é 123.');
const _hours = QuickReply(
  shortcut: 'horario',
  text: 'Atendemos das 9h às 18h, inclusive no pix.',
);

String _box(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

Future<(FakeCoreBridge, FakeChatPrefs)> _chat(
  WidgetTester tester, {
  List<QuickReply> replies = const [],
}) async {
  final bridge = FakeCoreBridge();
  final prefs = FakeChatPrefs()..replies = [...replies];
  final repo = FakeClientsRepository();
  await repo.save(
    const Client(name: 'Maria Souza', phone: '5511900000001', chatJid: _pn),
  );
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => CrmScope(chatPrefs: prefs, child: child!),
      home: ChatScreen(
        bridge: bridge,
        chat: const ChatSummary(
          jid: _pn,
          name: 'Mari',
          lastText: '',
          lastTs: 0,
        ),
        clients: repo,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (bridge, prefs);
}

void main() {
  test('the "/" query, the match and the name', () {
    expect(quickReplyQuery('/pi'), 'pi');
    expect(quickReplyQuery('/'), '');
    expect(quickReplyQuery('oi /pix'), isNull);
    expect(quickReplyQuery('/pix\nmais'), isNull);

    // Shortcuts that start with the query first, then texts with it.
    expect(matchReplies([_hours, _pix], 'pix'), [_pix, _hours]);
    expect(matchReplies([_hours, _pix], 'HORÁRIO'), [_hours]);
    expect(matchReplies([_hours, _pix], ''), [_hours, _pix]);

    expect(fillName(_pix.text, 'Maria Souza'), 'Oi Maria, a chave pix é 123.');
    expect(fillName(_pix.text, ''), 'Oi, a chave pix é 123.');
    expect(fillName('{nome}, tudo bem?', null), 'tudo bem?');

    expect(normalizeShortcut(' /Pix '), 'pix');
    expect(shortcutError('', const []), 'Digite um atalho.');
    expect(shortcutError('a b', const []), 'O atalho não pode ter espaço.');
    expect(shortcutError('pix', const ['pix']), isNotNull);
    expect(shortcutError('pix', const ['horario']), isNull);
  });

  testWidgets('create, edit and delete in Respostas rápidas', (tester) async {
    final prefs = FakeChatPrefs();
    await tester.pumpWidget(
      MaterialApp(home: QuickRepliesScreen(prefs: prefs)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma resposta rápida ainda.'), findsOneWidget);

    await tester.tap(find.text('Nova resposta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Atalho'), '/Pix');
    await tester.enterText(find.widgetWithText(TextField, 'Texto'), _pix.text);
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(prefs.replies.single.shortcut, 'pix');
    expect(find.text('/pix'), findsOneWidget);

    // A second one with the same shortcut is refused.
    await tester.tap(find.text('Nova resposta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Atalho'), 'pix');
    await tester.enterText(find.widgetWithText(TextField, 'Texto'), 'outro');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Já existe uma resposta com /pix.'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('/pix'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Texto'),
      'Chave pix: 123',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(prefs.replies.single.text, 'Chave pix: 123');

    await tester.tap(find.text('/pix'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apagar'));
    await tester.pumpAndSettle();
    expect(prefs.replies, isEmpty);
  });

  testWidgets('"/pi" shows the reply; the tap fills the box only', (
    tester,
  ) async {
    final (bridge, _) = await _chat(tester, replies: [_pix, _hours]);

    await tester.enterText(find.byType(TextField), '/pi');
    await tester.pumpAndSettle();
    expect(find.text('/pix'), findsOneWidget);
    expect(find.text('/horario'), findsOneWidget); // "pix" in its text

    await tester.tap(find.text('/pix'));
    await tester.pumpAndSettle();
    expect(_box(tester), 'Oi Maria, a chave pix é 123.');
    expect(find.text('/horario'), findsNothing); // the list closed
    expect(bridge.calls.where((c) => c.startsWith('send')), isEmpty);
  });

  testWidgets('without replies, "/" says how to create one', (tester) async {
    final (_, prefs) = await _chat(tester);
    await tester.enterText(find.byType(TextField), '/');
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma resposta rápida ainda.'), findsOneWidget);

    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Respostas rápidas'), findsOneWidget);

    prefs.replies = [_pix];
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('/pix'), findsOneWidget); // reloaded on the way back
  });
}
