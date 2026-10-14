// The client's file: numbers, timeline, "Receber" and "Cobrar".
import 'package:chat_do_garoto/src/chats/chat_screen.dart';
import 'package:chat_do_garoto/src/clients/client_screen.dart';
import 'package:chat_do_garoto/src/clients/client_summary.dart';
import 'package:chat_do_garoto/src/clients/client_timeline.dart';
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:chat_do_garoto/src/home/crm_scope.dart';
import 'package:chat_do_garoto/src/sales/charge_message.dart';
import 'package:chat_do_garoto/src/sales/sale_math.dart';
import 'package:chat_do_garoto/src/sales/sales_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_prefs.dart';
import 'support/fake_clients_repository.dart';
import 'support/fake_core_bridge.dart';
import 'support/fake_products_repository.dart';
import 'support/fake_sales_repository.dart';

final _today = DateTime(2026, 10, 2, 9);
const _pn = '5511900000001@s.whatsapp.net';

Sale _sale(
  int number, {
  required DateTime soldAt,
  int total = 10000,
  int clientId = 1,
  List<Installment> installments = const [],
  List<SalePayment> payments = const [],
  DateTime? canceledAt,
}) => Sale(
  number: number,
  clientId: clientId,
  soldAt: soldAt,
  items: [
    SaleItem(
      variantId: 1,
      description: 'Item',
      quantity: 1000,
      unitPrice: total,
    ),
  ],
  installments: installments,
  payments: payments,
  canceledAt: canceledAt,
);

/// A client with two sales on credit: nº 1 (R$ 100,00, overdue since
/// 29/09) and nº 2 (R$ 50,00, due 20/10).
Future<
  ({
    FakeClientsRepository clients,
    FakeSalesRepository sales,
    FakeCoreBridge bridge,
    int id,
  })
>
_world({bool chat = true}) async {
  final clients = FakeClientsRepository();
  final sales = FakeSalesRepository()..now = _today;
  final bridge = FakeCoreBridge();
  final id = await clients.save(
    Client(
      name: 'Maria Souza',
      phone: '5511900000001',
      chatJid: chat ? _pn : null,
    ),
  );
  sales.names[id] = 'Maria Souza';
  await sales.conclude(
    _sale(
      1,
      clientId: id,
      soldAt: DateTime(2026, 9, 1),
      installments: const [
        Installment(number: 1, due: '2026-09-29', amount: 10000),
      ],
    ),
  );
  await sales.conclude(
    _sale(
      2,
      clientId: id,
      soldAt: DateTime(2026, 9, 20),
      total: 5000,
      installments: const [
        Installment(number: 1, due: '2026-10-20', amount: 5000),
      ],
    ),
  );
  return (clients: clients, sales: sales, bridge: bridge, id: id);
}

Future<void> _file(
  WidgetTester tester,
  ({
    FakeClientsRepository clients,
    FakeSalesRepository sales,
    FakeCoreBridge bridge,
    int id,
  })
  w,
) async {
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => CrmScope(
        sales: w.sales,
        products: FakeProductsRepository(),
        chatPrefs: FakeChatPrefs(),
        child: child!,
      ),
      home: ClientScreen(
        repo: w.clients,
        id: w.id,
        bridge: w.bridge,
        clock: () => _today,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('the numbers: owed, overdue, bought, purchases, last', () {
    final sales = [
      _sale(
        1,
        soldAt: DateTime(2026, 9, 1),
        installments: const [
          Installment(number: 1, due: '2026-09-15', amount: 6000),
          Installment(number: 2, due: '2026-10-15', amount: 4000),
        ],
        payments: [
          SalePayment(
            receipt: true,
            method: PayMethod.pix,
            amount: 2000,
            at: DateTime(2026, 9, 10),
          ),
        ],
      ),
      _sale(2, soldAt: DateTime(2026, 9, 25), total: 3000),
      _sale(
        3,
        soldAt: DateTime(2026, 9, 28),
        canceledAt: DateTime(2026, 9, 29),
      ),
    ];
    final s = ClientSummary.of(sales, _today);
    expect(s.bought, 13000);
    expect(s.purchases, 2);
    expect(s.owes, 8000);
    expect(s.overdue, 4000); // what is left of the 1st installment
    expect(s.lastPurchase, DateTime(2026, 9, 25));
  });

  test('the timeline, newest first', () {
    final sales = [
      _sale(
        1,
        soldAt: DateTime(2026, 9, 1),
        installments: const [
          Installment(number: 1, due: '2026-09-29', amount: 10000),
        ],
        payments: [
          SalePayment(
            receipt: true,
            method: PayMethod.pix,
            amount: 3000,
            at: DateTime(2026, 9, 10),
          ),
          SalePayment(
            receipt: true,
            method: PayMethod.cash,
            amount: 1000,
            at: DateTime(2026, 9, 12),
            voided: true,
          ),
        ],
      ),
      _sale(
        2,
        soldAt: DateTime(2026, 9, 20),
        canceledAt: DateTime(2026, 9, 21),
      ),
    ];
    final notes = [ClientNote(id: 1, body: 'nota', at: DateTime(2026, 9, 15))];
    final order = [
      for (final e in buildTimeline(sales, notes))
        switch (e) {
          PurchaseEvent(:final sale) => 'compra ${sale.number}',
          ReceiptEvent(:final payment) => 'recebido ${payment.amount}',
          CancelEvent(:final sale) => 'cancelada ${sale.number}',
          NoteEvent() => 'nota',
        },
    ];
    expect(order, [
      'cancelada 2',
      'compra 2',
      'nota',
      'recebido 3000', // the reversed one is left out
      'compra 1',
    ]);
  });

  test('the charge text', () async {
    final w = await _world();
    final all = await w.sales.list();
    expect(
      chargeMessage(name: 'Maria Souza', sales: all, today: _today),
      'Oi, Maria! Tudo bem? Passando para lembrar do valor em aberto de '
      'R\$ 150,00, dos pedidos nº 1 e nº 2. A parcela mais antiga venceu '
      'em 29/09/2026. Qualquer dúvida, é só me chamar.',
    );
    final second = all.where((s) => s.number == 2).toList();
    expect(
      chargeMessage(name: 'Maria', sales: second, today: _today),
      'Oi, Maria! Tudo bem? Passando para lembrar do valor em aberto de '
      'R\$ 50,00, do pedido nº 2. A parcela vence em 20/10/2026. Qualquer '
      'dúvida, é só me chamar.',
    );
    expect(
      chargeMessage(name: '', sales: second, today: DateTime(2026, 10, 20)),
      startsWith('Oi! Tudo bem?'),
    );
    expect(
      chargeMessage(
        name: 'Maria',
        sales: second,
        today: DateTime(2026, 10, 20),
      ),
      contains('A parcela vence hoje.'),
    );
    expect(
      chargeMessage(name: 'Maria', sales: const [], today: _today),
      isNull,
    );
  });

  testWidgets('the file shows the numbers and the timeline', (tester) async {
    final w = await _world();
    await w.clients.addNote(w.id, 'Prefere entrega à tarde');
    await _file(tester, w);

    expect(find.text('R\$ 150,00'), findsOneWidget);
    expect(find.text('Vencido R\$ 100,00'), findsOneWidget);
    expect(
      find.text(
        'Comprou R\$ 150,00 em 2 compras · ticket médio R\$ 75,00 · última em 20/09/2026',
      ),
      findsOneWidget,
    );
    for (final action in ['Conversar', 'Nova venda', 'Receber', 'Cobrar']) {
      expect(find.text(action), findsOneWidget, reason: action);
    }
    // The note (02/10) above purchase nº 2 (20/09) above nº 1 (01/09).
    final note = tester.getTopLeft(find.text('Prefere entrega à tarde')).dy;
    final second = tester.getTopLeft(find.text('Compra nº 2')).dy;
    final first = tester.getTopLeft(find.text('Compra nº 1')).dy;
    expect(note, lessThan(second));
    expect(second, lessThan(first));
  });

  testWidgets('"Ver mais" after 20 events', (tester) async {
    final w = await _world();
    for (var i = 0; i < 20; i++) {
      await w.clients.addNote(w.id, 'nota $i');
    }
    await _file(tester, w);
    expect(find.text('Compra nº 1'), findsNothing); // the 22nd event
    await tester.tap(find.text('Ver mais'));
    await tester.pumpAndSettle();
    expect(find.text('Compra nº 1'), findsOneWidget);
    expect(find.text('Ver mais'), findsNothing);
  });

  testWidgets('"Receber" picks among the open sales, oldest first', (
    tester,
  ) async {
    final w = await _world();
    await _file(tester, w);

    await tester.tap(find.text('Receber'));
    await tester.pumpAndSettle();
    expect(find.text('Receber de qual venda?'), findsOneWidget);
    final first = tester.getTopLeft(find.text('Venda nº 1 · 01/09/2026')).dy;
    final second = tester.getTopLeft(find.text('Venda nº 2 · 20/09/2026')).dy;
    expect(first, lessThan(second));

    await tester.tap(find.text('Venda nº 2 · 20/09/2026'));
    await tester.pumpAndSettle();
    expect(find.text('Falta R\$ 50,00'), findsWidgets);
    // The amount starts formatted.
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Valor'))
          .controller!
          .text,
      'R\$ 50,00',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Receber'),
      ),
    );
    await tester.pumpAndSettle();

    final sales = await w.sales.list();
    expect(sales.firstWhere((s) => s.number == 2).open, 0);
    expect(sales.firstWhere((s) => s.number == 1).open, 10000);
    expect(find.text('Recebimento registrado.'), findsOneWidget);
    expect(find.text('Recebido R\$ 50,00'), findsOneWidget); // the timeline
  });

  testWidgets('with one open sale, "Receber" goes straight to it', (
    tester,
  ) async {
    final w = await _world();
    await w.sales.receive(1, PayMethod.pix, 10000, _today);
    await _file(tester, w);
    await tester.tap(find.text('Receber'));
    await tester.pumpAndSettle();
    expect(find.text('Receber de qual venda?'), findsNothing);
    expect(find.text('Falta R\$ 50,00'), findsOneWidget);
  });

  testWidgets('"Cobrar" opens the conversation with the text, unsent', (
    tester,
  ) async {
    final w = await _world();
    await _file(tester, w);
    await tester.tap(find.text('Cobrar'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsOneWidget);
    final box = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Mensagem'),
    );
    expect(box.controller!.text, startsWith('Oi, Maria! Tudo bem?'));
    expect(box.controller!.text, contains('R\$ 150,00'));
    expect(w.bridge.calls.where((c) => c.startsWith('send')), isEmpty);
  });

  testWidgets('without a conversation, "Cobrar" is off and says why', (
    tester,
  ) async {
    final w = await _world(chat: false);
    await _file(tester, w);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Cobrar'),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('precisa ter uma conversa'), findsOneWidget);
    expect(find.text('Conversar'), findsNothing);
  });

  testWidgets('"Cobrar" in the panel fills the box of the conversation', (
    tester,
  ) async {
    final w = await _world();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => CrmScope(
          sales: w.sales,
          products: FakeProductsRepository(),
          chatPrefs: FakeChatPrefs(),
          child: child!,
        ),
        home: ChatScreen(
          bridge: w.bridge,
          chat: const ChatSummary(
            jid: _pn,
            name: 'Maria',
            lastText: '',
            lastTs: 0,
          ),
          clients: w.clients,
          clock: () => _today,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maria Souza'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cobrar'));
    await tester.pumpAndSettle();

    final box = tester.widget<TextField>(find.byType(TextField));
    expect(box.controller!.text, contains('dos pedidos nº 1 e nº 2'));
    expect(w.bridge.calls.where((c) => c.startsWith('send')), isEmpty);
  });
}
