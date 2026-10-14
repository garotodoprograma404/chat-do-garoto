// Internal notes in the conversation: saved as the
// client's notes, never sent.
import 'package:chat_do_garoto/src/chats/chat_notes.dart';
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

ChatMessage _msg(String id, DateTime at, {bool mine = false}) => ChatMessage(
  chat: _pn,
  id: id,
  fromMe: mine,
  senderName: '',
  kind: 'text',
  text: 'mensagem $id',
  ts: at.millisecondsSinceEpoch,
);

ClientNote _note(int id, DateTime at) =>
    ClientNote(id: id, body: 'nota $id', at: at);

List<String> _order(List<ChatEntry> entries) => [
  for (final e in entries)
    switch (e) {
      MessageEntry(:final message) => message.id,
      NoteEntry(:final note) => 'n${note.id}',
    },
];

Future<(FakeCoreBridge, FakeClientsRepository, int)> _open(
  WidgetTester tester, {
  String jid = _pn,
  bool client = true,
  List<String> notes = const [],
}) async {
  final bridge = FakeCoreBridge()
    ..messages[jid] = [
      ChatMessage(
        chat: jid,
        id: 'm1',
        fromMe: false,
        senderName: '',
        kind: 'text',
        text: 'Oi, tem a camiseta azul?',
        ts: DateTime(2026, 10, 2, 8).millisecondsSinceEpoch,
      ),
    ];
  final repo = FakeClientsRepository();
  var id = 0;
  if (client) {
    id = await repo.save(
      Client(name: 'Maria Souza', phone: '5511900000001', chatJid: jid),
    );
    for (final n in notes) {
      await repo.addNote(id, n);
    }
  }
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          CrmScope(chatPrefs: FakeChatPrefs(), child: child!),
      home: ChatScreen(
        bridge: bridge,
        chat: ChatSummary(jid: jid, name: 'Maria', lastText: '', lastTs: 0),
        clients: repo,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (bridge, repo, id);
}

void main() {
  test('notes are placed among the messages by time', () {
    final m = [
      _msg('a', DateTime(2026, 10, 2, 8)),
      _msg('b', DateTime(2026, 10, 2, 10)),
    ];
    final notes = [
      _note(3, DateTime(2026, 10, 2, 11)),
      _note(1, DateTime(2026, 10, 1, 9)),
      _note(2, DateTime(2026, 10, 2, 9)),
    ];
    expect(_order(mergeNotes(m, notes, hasOlder: false)), [
      'n1',
      'a',
      'n2',
      'b',
      'n3',
    ]);
    // With older messages still to load, older notes wait for them.
    expect(_order(mergeNotes(m, notes, hasOlder: true)), [
      'a',
      'n2',
      'b',
      'n3',
    ]);
    expect(_order(mergeNotes(m, const [], hasOlder: false)), ['a', 'b']);
  });

  testWidgets('"Anotar" saves a note and sends nothing', (tester) async {
    final (bridge, repo, id) = await _open(tester);

    await tester.tap(find.byTooltip('Nota interna'));
    await tester.pump();
    expect(find.text('Nota interna · só você vê'), findsOneWidget);
    expect(find.byTooltip('Enviar'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Quer a azul no tam. M');
    await tester.tap(find.text('Anotar'));
    await tester.pumpAndSettle();

    expect((await repo.notes(id)).single.body, 'Quer a azul no tam. M');
    expect(
      bridge.calls.where((c) => c.startsWith('send')),
      isEmpty,
      reason: 'a note never goes to WhatsApp',
    );
    expect(find.text('Nota · só você vê'), findsOneWidget);
    expect(find.text('Quer a azul no tam. M'), findsOneWidget);
    // Still in note mode until the button is tapped again.
    expect(find.text('Anotar'), findsOneWidget);
    await tester.tap(find.byTooltip('Voltar para mensagem'));
    await tester.pump();
    expect(find.text('Anotar'), findsNothing);
    expect(find.text('Mensagem'), findsOneWidget);
  });

  testWidgets('a note written in the file shows in the conversation', (
    tester,
  ) async {
    await _open(tester, notes: ['Prefere entrega à tarde']);
    expect(find.text('Prefere entrega à tarde'), findsOneWidget);
    expect(find.text('Nota · só você vê'), findsOneWidget);
  });

  testWidgets('deleting a note takes it out of both places', (tester) async {
    final (_, repo, id) = await _open(tester, notes: ['Ligar na sexta']);

    await tester.longPress(find.text('Ligar na sexta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar nota'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar'));
    await tester.pumpAndSettle();

    expect(find.text('Ligar na sexta'), findsNothing);
    expect(await repo.notes(id), isEmpty);
  });

  testWidgets('without a client, the note button explains and offers', (
    tester,
  ) async {
    await _open(tester, client: false);
    await tester.tap(find.byTooltip('Nota interna'));
    await tester.pumpAndSettle();
    expect(find.textContaining('As notas ficam na ficha'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Cadastrar'), findsOneWidget);
    expect(find.text('Anotar'), findsNothing);
  });

  testWidgets('groups have no notes', (tester) async {
    await _open(tester, jid: '120363000000000001@g.us', client: false);
    expect(find.byTooltip('Nota interna'), findsNothing);
  });
}
