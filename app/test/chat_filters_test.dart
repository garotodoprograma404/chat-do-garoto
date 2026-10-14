// The filters above the chat list.
import 'package:chat_do_garoto/src/chats/chat_clients.dart';
import 'package:chat_do_garoto/src/chats/chat_filters.dart';
import 'package:chat_do_garoto/src/chats/chats_controller.dart';
import 'package:chat_do_garoto/src/chats/chats_screen.dart';
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:chat_do_garoto/src/home/crm_scope.dart';
import 'package:chat_do_garoto/src/sales/sale_math.dart';
import 'package:chat_do_garoto/src/sales/sales_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_prefs.dart';
import 'support/fake_clients_repository.dart';
import 'support/fake_core_bridge.dart';
import 'support/fake_sales_repository.dart';

final _now = DateTime(2026, 10, 2, 12);
int _ago(Duration d) => _now.subtract(d).millisecondsSinceEpoch;

ChatSummary _chat(String jid, String name, Duration ago, {bool mine = false}) =>
    ChatSummary(
      jid: jid,
      name: name,
      lastText: 'oi',
      lastTs: _ago(ago),
      lastFromMe: mine,
    );

const _mariaJid = '5511900000001@s.whatsapp.net';
const _anaJid = '5511900000006@s.whatsapp.net';
const _ignoredJid = '5511900000005@s.whatsapp.net';

// The chats, newest first, as the core lists them.
final _chats = [
  _chat('5511900000004@s.whatsapp.net', 'Pedro', const Duration(hours: 1)),
  _chat(_mariaJid, 'Maria', const Duration(hours: 2)),
  _chat('120363000000000001@g.us', 'Família', const Duration(hours: 3)),
  _chat(_anaJid, 'Ana', const Duration(hours: 4), mine: true),
  _chat(_ignoredJid, 'Vizinho', const Duration(days: 2)),
  _chat('5511900000002@s.whatsapp.net', 'João', const Duration(days: 10)),
];

typedef _World = ({
  FakeCoreBridge bridge,
  FakeClientsRepository clients,
  FakeSalesRepository sales,
  FakeChatPrefs prefs,
});

Future<_World> _world() async {
  final bridge = FakeCoreBridge()..chats = _chats;
  final clients = FakeClientsRepository();
  final sales = FakeSalesRepository()..now = _now;
  final prefs = FakeChatPrefs()..ignoredChats.add(_ignoredJid);
  final maria = await clients.save(
    const Client(name: 'Maria Souza', phone: '5511900000001'),
  );
  await clients.save(
    const Client(name: 'Ana Lima', phone: '5511900000006', chatJid: _anaJid),
  );
  // Maria owes the second installment.
  await sales.conclude(
    Sale(
      clientId: maria,
      soldAt: DateTime(2026, 9, 20),
      items: const [
        SaleItem(
          variantId: 1,
          description: 'Camiseta',
          quantity: 1000,
          unitPrice: 10000,
        ),
      ],
      payments: [
        SalePayment(
          method: PayMethod.pix,
          amount: 5000,
          at: DateTime(2026, 9, 20),
        ),
      ],
      installments: const [
        Installment(number: 1, due: '2026-10-20', amount: 5000),
      ],
    ),
  );
  return (bridge: bridge, clients: clients, sales: sales, prefs: prefs);
}

List<String> _names(List<ChatSummary> chats) => [for (final c in chats) c.name];

void main() {
  test('waiting for a reply: one person, theirs, within 7 days', () {
    expect(waitingReply(_chats[0], _now), isTrue); // Pedro, 1 h
    expect(waitingReply(_chats[2], _now), isFalse); // a group
    expect(waitingReply(_chats[3], _now), isFalse); // I replied
    expect(waitingReply(_chats[5], _now), isFalse); // 10 days ago
    expect(
      waitingReply(_chat('1@lid', 'LID', const Duration(days: 7)), _now),
      isTrue,
    );
    expect(
      waitingReply(_chat('x@newsletter', 'Canal', Duration.zero), _now),
      isFalse,
    );
    // The ones waiting longest come first.
    expect(_names(waitingChats(_chats, _now)), ['Vizinho', 'Maria', 'Pedro']);
  });

  test('each filter shows exactly its chats', () async {
    final w = await _world();
    final clients = ChatClients(
      bridge: w.bridge,
      repo: w.clients,
      sales: w.sales,
      prefs: w.prefs,
      clock: () => _now,
    );
    await clients.load();
    List<String> of(ChatFilter f) =>
        _names(filterChats(_chats, f, now: _now, clients: clients));

    expect(of(ChatFilter.all), hasLength(6));
    expect(of(ChatFilter.waiting), ['Pedro', 'Maria', 'Vizinho']);
    expect(of(ChatFilter.clients), ['Maria', 'Ana']);
    expect(of(ChatFilter.owing), ['Maria']);
    expect(of(ChatFilter.newContacts), ['Pedro', 'João']);

    // "Desfazer" brings the ignored contact back.
    await clients.setIgnored(_ignoredJid, ignored: false);
    expect(of(ChatFilter.newContacts), ['Pedro', 'Vizinho', 'João']);
    expect(w.prefs.ignoredChats, isEmpty);

    // Without the CRM, the client filters keep nothing.
    expect(filterChats(_chats, ChatFilter.clients, now: _now), isEmpty);
  });

  testWidgets('the chips filter the list and count "Sem resposta"', (
    tester,
  ) async {
    final w = await _world();
    final controller = ChatsController(bridge: w.bridge)..start();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            CrmScope(sales: w.sales, chatPrefs: w.prefs, child: child!),
        home: ChatsScreen(
          bridge: w.bridge,
          controller: controller,
          status: 'Conectado',
          clients: w.clients,
          clock: () => _now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sem resposta 3'), findsOneWidget);
    expect(find.text('Família'), findsOneWidget);

    await tester.tap(find.text('Devendo'));
    await tester.pumpAndSettle();
    expect(find.text('Maria Souza'), findsOneWidget);
    expect(find.text('Pedro'), findsNothing);
    expect(controller.filter, ChatFilter.owing);

    await tester.tap(find.text('Novos contatos'));
    await tester.pumpAndSettle();
    expect(find.text('Pedro'), findsOneWidget);
    expect(find.text('João'), findsOneWidget);
    expect(find.text('Vizinho'), findsNothing);
    expect(find.text('Maria Souza'), findsNothing);

    await tester.tap(find.text('Todas'));
    await tester.pumpAndSettle();
    expect(find.text('Família'), findsOneWidget);
  });

  testWidgets('an empty filter says what it shows', (tester) async {
    final bridge = FakeCoreBridge()
      ..chats = [_chat(_anaJid, 'Ana', const Duration(hours: 1), mine: true)];
    final controller = ChatsController(bridge: bridge)..start();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatsScreen(
          bridge: bridge,
          controller: controller,
          status: 'Conectado',
          clock: () => _now,
        ),
      ),
    );
    // Without the CRM there are only "Todas" and "Sem resposta".
    expect(find.text('Clientes'), findsNothing);
    await tester.tap(find.text('Sem resposta'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma conversa esperando resposta.'), findsOneWidget);
  });
}
