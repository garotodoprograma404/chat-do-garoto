// "Conversas sem resposta" on the Início.
import 'package:chat_do_garoto/src/chats/chat_filters.dart';
import 'package:chat_do_garoto/src/chats/chat_screen.dart';
import 'package:chat_do_garoto/src/chats/chats_controller.dart';
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:chat_do_garoto/src/home/home_shell.dart';
import 'package:chat_do_garoto/src/home/start_controller.dart';
import 'package:chat_do_garoto/src/home/start_screen.dart';
import 'package:chat_do_garoto/src/whatsapp/whatsapp_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';
import 'support/fake_connection_keeper.dart';
import 'support/fake_core_bridge.dart';
import 'support/fake_products_repository.dart';
import 'support/fake_sales_repository.dart';
import 'support/fake_wa_key.dart';

final _now = DateTime(2026, 10, 2, 12);

ChatSummary _chat(
  String jid,
  String name,
  Duration ago, {
  bool mine = false,
  DateTime? now,
}) => ChatSummary(
  jid: jid,
  name: name,
  lastText: 'mensagem de $name',
  lastTs: (now ?? _now).subtract(ago).millisecondsSinceEpoch,
  lastFromMe: mine,
);

List<ChatSummary> _chats({DateTime? now}) => [
  _chat(
    '5511900000001@s.whatsapp.net',
    'Pedro',
    const Duration(minutes: 5),
    now: now,
  ),
  _chat(
    '5511900000002@s.whatsapp.net',
    'Maria',
    const Duration(hours: 2),
    now: now,
  ),
  _chat(
    '5511900000003@s.whatsapp.net',
    'Ana',
    const Duration(hours: 3),
    mine: true,
    now: now,
  ),
  _chat(
    '5511900000004@s.whatsapp.net',
    'João',
    const Duration(days: 1),
    now: now,
  ),
  _chat(
    '5511900000005@s.whatsapp.net',
    'Bia',
    const Duration(days: 3),
    now: now,
  ),
  _chat(
    '120363000000000001@g.us',
    'Família',
    const Duration(hours: 1),
    now: now,
  ),
];

Future<FakeClientsRepository> _clients() async {
  final repo = FakeClientsRepository();
  await repo.save(const Client(name: 'Maria Souza', phone: '5511900000002'));
  return repo;
}

void main() {
  test('the waiting label', () {
    expect(waitingLabel(_now, _now), 'agora');
    expect(
      waitingLabel(_now.subtract(const Duration(minutes: 5)), _now),
      'há 5 min',
    );
    expect(
      waitingLabel(_now.subtract(const Duration(hours: 2)), _now),
      'há 2 h',
    );
    expect(
      waitingLabel(_now.subtract(const Duration(days: 1)), _now),
      'há 1 dia',
    );
    expect(
      waitingLabel(_now.subtract(const Duration(days: 3)), _now),
      'há 3 dias',
    );
  });

  test('the waiting chats, the longest first, with clients', () async {
    final bridge = FakeCoreBridge()..chats = _chats();
    final c = StartController(
      clients: await _clients(),
      products: null,
      sales: null,
      bridge: bridge,
      clock: () => _now,
    );
    await c.load();
    expect(
      [for (final w in c.waiting) w.name],
      ['Bia', 'João', 'Maria', 'Pedro'],
    );
    expect(c.waitingClients.values.single.name, 'Maria Souza');
    // Waiting chats are something to do: not the first run.
    expect(c.firstRun, isFalse);
  });

  testWidgets('the block, a tap opens the chat, "Ver todas"', (tester) async {
    final bridge = FakeCoreBridge()..chats = _chats();
    var all = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StartScreen(
          clients: await _clients(),
          products: FakeProductsRepository(),
          sales: FakeSalesRepository(),
          bridge: bridge,
          clock: () => _now,
          onOpenWaiting: () => all++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('4 conversas sem resposta'), findsOneWidget);
    expect(find.text('Bia'), findsOneWidget);
    expect(find.text('há 3 dias'), findsOneWidget);
    expect(find.text('Maria Souza'), findsOneWidget); // the client's name
    expect(find.text('Pedro'), findsNothing); // only the 3 waiting longest
    expect(find.textContaining('Tudo em dia'), findsNothing);

    await tester.tap(find.text('Ver todas'));
    expect(all, 1);

    await tester.tap(find.text('João'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
  });

  testWidgets('"Tudo em dia" only with nobody waiting', (tester) async {
    final bridge = FakeCoreBridge()
      ..chats = [
        _chat(
          '5511900000003@s.whatsapp.net',
          'Ana',
          const Duration(hours: 3),
          mine: true,
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: StartScreen(
          clients: await _clients(),
          products: FakeProductsRepository(),
          sales: FakeSalesRepository(),
          bridge: bridge,
          clock: () => _now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('nenhuma conversa espera resposta'),
      findsOneWidget,
    );
  });

  testWidgets('a new message updates the block', (tester) async {
    final bridge = FakeCoreBridge()..chats = [];
    await tester.pumpWidget(
      MaterialApp(
        home: StartScreen(
          clients: await _clients(),
          products: FakeProductsRepository(),
          sales: FakeSalesRepository(),
          bridge: bridge,
          clock: () => _now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('sem resposta'), findsNothing);

    bridge.chats = [
      _chat('5511900000001@s.whatsapp.net', 'Pedro', Duration.zero),
    ];
    bridge.push('wa_message', {'chat': '5511900000001@s.whatsapp.net'});
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('1 conversa sem resposta'), findsOneWidget);
  });

  testWidgets('"Ver todas" opens Conversas on "Sem resposta"', (tester) async {
    final bridge = FakeCoreBridge(paired: true)
      ..chats = _chats(now: DateTime.now());
    final whatsapp = WhatsAppController(
      bridge: bridge,
      sessionPath: () async => '/tmp/test-wa.db',
      keeper: FakeConnectionKeeper(),
      keys: FakeWaKeyProvider(),
    );
    await whatsapp.start();
    final chats = ChatsController(bridge: bridge)..start();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          bridge: bridge,
          whatsapp: whatsapp,
          chats: chats,
          clients: await _clients(),
          products: FakeProductsRepository(),
          sales: FakeSalesRepository(),
          onOpenSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver todas'));
    await tester.pumpAndSettle();

    expect(chats.filter, ChatFilter.waiting);
    expect(find.text('Sem resposta 4'), findsOneWidget);
    expect(find.text('Família'), findsNothing); // a group never waits
    expect(find.text('Pedro'), findsOneWidget);
  });
}
