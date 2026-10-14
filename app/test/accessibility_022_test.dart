// The new screens with large text, in the dark theme and
// without animations.
import 'package:chat_do_garoto/src/chats/chat_prefs.dart';
import 'package:chat_do_garoto/src/chats/chat_screen.dart';
import 'package:chat_do_garoto/src/chats/chats_controller.dart';
import 'package:chat_do_garoto/src/chats/chats_screen.dart';
import 'package:chat_do_garoto/src/clients/client_screen.dart';
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:chat_do_garoto/src/home/crm_scope.dart';
import 'package:chat_do_garoto/src/home/start_screen.dart';
import 'package:chat_do_garoto/src/sales/sale_math.dart';
import 'package:chat_do_garoto/src/sales/sales_repository.dart';
import 'package:chat_do_garoto/src/settings/quick_replies_screen.dart';
import 'package:chat_do_garoto/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_prefs.dart';
import 'support/fake_clients_repository.dart';
import 'support/fake_core_bridge.dart';
import 'support/fake_products_repository.dart';
import 'support/fake_sales_repository.dart';

final _today = DateTime(2026, 10, 2, 12);
const _client = '5511900000001@s.whatsapp.net';
const _stranger = '5511900000002@s.whatsapp.net';

typedef _World = ({
  FakeCoreBridge bridge,
  FakeClientsRepository clients,
  FakeSalesRepository sales,
  FakeChatPrefs prefs,
  int id,
});

Future<_World> _world() async {
  final clients = FakeClientsRepository();
  final sales = FakeSalesRepository()..now = _today;
  final prefs = FakeChatPrefs()
    ..replies = const [
      QuickReply(
        shortcut: 'pix',
        text: 'Oi {nome}, a chave pix é 123, em nome da loja.',
      ),
    ];
  final id = await clients.save(
    const Client(
      name: 'Maria Aparecida dos Santos Oliveira',
      phone: '5511900000001',
      chatJid: _client,
      tags: ['revenda', 'atacado'],
    ),
  );
  await clients.addNote(id, 'Prefere entrega à tarde, depois das 15h');
  sales.names[id] = 'Maria Aparecida dos Santos Oliveira';
  await sales.conclude(
    Sale(
      clientId: id,
      soldAt: DateTime(2026, 9, 2),
      items: const [
        SaleItem(
          variantId: 1,
          description: 'Camiseta',
          quantity: 1000,
          unitPrice: 1234567,
        ),
      ],
      installments: const [
        Installment(number: 1, due: '2026-09-29', amount: 617284),
        Installment(number: 2, due: '2026-10-29', amount: 617283),
      ],
    ),
  );
  final bridge = FakeCoreBridge()
    ..chats = [
      for (final (jid, name) in [
        (_client, 'Maria'),
        (_stranger, 'Contato com um nome bem comprido'),
        ('5511900000003@s.whatsapp.net', 'Outro contato'),
      ])
        ChatSummary(
          jid: jid,
          name: name,
          lastText: 'Uma mensagem longa que não cabe numa linha só',
          lastTs: _today
              .subtract(const Duration(hours: 5))
              .millisecondsSinceEpoch,
          lastFromMe: false,
        ),
    ];
  return (bridge: bridge, clients: clients, sales: sales, prefs: prefs, id: id);
}

Future<void> _pump(
  WidgetTester tester,
  _World w,
  Widget home, {
  bool dark = false,
  bool noAnimations = false,
}) async {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: const Size(360, 800),
        textScaler: const TextScaler.linear(2),
        disableAnimations: noAnimations,
      ),
      child: MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        builder: (context, child) => CrmScope(
          sales: w.sales,
          products: FakeProductsRepository(),
          chatPrefs: w.prefs,
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ChatScreen _chat(_World w, String jid, String name) => ChatScreen(
  bridge: w.bridge,
  chat: ChatSummary(jid: jid, name: name, lastText: '', lastTs: 0),
  clients: w.clients,
  clock: () => _today,
);

void main() {
  for (final dark in [false, true]) {
    final theme = dark ? 'escuro' : 'claro';

    testWidgets('200% text, $theme theme: the panel, the notes and "/"', (
      tester,
    ) async {
      final w = await _world();
      await _pump(tester, w, _chat(w, _client, 'Maria'), dark: dark);
      expect(tester.takeException(), isNull, reason: 'conversation');

      await tester.tap(find.byTooltip('Nota interna'));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'note mode');

      await tester.enterText(find.byType(TextField), '/pi');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'quick replies');
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Maria Aparecida dos Santos Oliveira'));
      await tester.pumpAndSettle();
      expect(find.text('Ver ficha'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'panel');
    });

    testWidgets('200% text, $theme theme: the "contato novo" strip', (
      tester,
    ) async {
      final w = await _world();
      await _pump(
        tester,
        w,
        _chat(w, _stranger, 'Contato com um nome bem comprido'),
        dark: dark,
      );
      expect(find.text('Contato novo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('200% text, $theme theme: file, Início, replies and chats', (
      tester,
    ) async {
      final w = await _world();
      final screens = <String, Widget>{
        'Ficha': ClientScreen(
          repo: w.clients,
          id: w.id,
          bridge: w.bridge,
          clock: () => _today,
        ),
        'Início': StartScreen(
          clients: w.clients,
          products: FakeProductsRepository(),
          sales: w.sales,
          bridge: w.bridge,
          clock: () => _today,
          onOpenWaiting: () {},
        ),
        'Respostas rápidas': QuickRepliesScreen(prefs: w.prefs),
        'Conversas': ChatsScreen(
          bridge: w.bridge,
          controller: ChatsController(bridge: w.bridge)..start(),
          status: 'Conectado',
          clients: w.clients,
          clock: () => _today,
        ),
      };
      for (final MapEntry(:key, :value) in screens.entries) {
        await _pump(tester, w, value, dark: dark);
        expect(tester.takeException(), isNull, reason: key);
      }
    });
  }

  testWidgets('without animations, the panel opens at once', (tester) async {
    final w = await _world();
    await _pump(tester, w, _chat(w, _client, 'Maria'), noAnimations: true);
    await tester.tap(find.text('Maria Aparecida dos Santos Oliveira'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Ver ficha'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
