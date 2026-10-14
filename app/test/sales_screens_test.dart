// Sale screens with in-memory repositories.
import 'package:chat_do_garoto/src/clients/client_screen.dart';
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/home/crm_scope.dart';
import 'package:chat_do_garoto/src/products/pricing.dart';
import 'package:chat_do_garoto/src/products/product_screen.dart';
import 'package:chat_do_garoto/src/products/products_repository.dart';
import 'package:chat_do_garoto/src/products/variants.dart';
import 'package:chat_do_garoto/src/sales/sale_math.dart';
import 'package:chat_do_garoto/src/sales/sale_screen.dart';
import 'package:chat_do_garoto/src/sales/sale_summary.dart';
import 'package:chat_do_garoto/src/sales/sales_repository.dart';
import 'package:chat_do_garoto/src/sales/sales_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';
import 'support/fake_core_bridge.dart';
import 'support/fake_products_repository.dart';
import 'support/fake_sales_repository.dart';

final _today = DateTime(2026, 10, 2, 15);

class _World {
  final sales = FakeSalesRepository();
  final products = FakeProductsRepository();
  final clients = FakeClientsRepository();
  final bridge = FakeCoreBridge(paired: true);
  late int ana, camiseta, caneca;

  Future<void> build() async {
    ana = await clients.save(
      const Client(
        name: 'Ana',
        phone: '5511900000001',
        chatJid: '5511900000001@s.whatsapp.net',
      ),
    );
    sales.names[ana] = 'Ana';
    camiseta = await products.save(
      const Product(
        name: 'Camiseta',
        price: 5000,
        tiers: [WholesaleTier(10000, 4000)],
        attributes: [
          Attribute('Cor', ['Azul', 'Preto']),
        ],
        variants: [
          Variant(options: ['Azul'], cost: 2000, stock: 10000),
          Variant(options: ['Preto'], cost: 2000, stock: 1000),
        ],
      ),
    );
    caneca = await products.save(
      const Product(
        name: 'Caneca',
        price: 3990,
        variants: [Variant(cost: 1500, stock: 5000)],
      ),
    );
  }

  SaleContext get ctx => SaleContext(
    sales: sales,
    products: products,
    clients: clients,
    bridge: bridge,
    clock: () => _today,
  );

  Variant variant(int product, int i) =>
      products.products[product]!.variants[i];
}

/// A tall screen, so long forms are built at once.
Future<_World> _open(
  WidgetTester tester, {
  Widget Function(_World)? home,
}) async {
  tester.view.physicalSize = const Size(1000, 7000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final w = _World();
  await w.build();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          CrmScope(products: w.products, sales: w.sales, child: child!),
      home: home?.call(w) ?? SalesScreen(ctx: w.ctx),
    ),
  );
  await tester.pumpAndSettle();
  return w;
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextField, label).last, text);
  await tester.pumpAndSettle();
}

Future<void> _addItem(
  WidgetTester tester,
  String name, [
  String? option,
]) async {
  await _tap(tester, 'Adicionar item');
  await _tap(tester, name);
  if (option != null) {
    await tester.tap(find.textContaining('$option ·'));
    await tester.pumpAndSettle();
  }
}

Future<void> _pay(WidgetTester tester, String method, String amount) async {
  await tester.tap(find.byType(DropdownButtonFormField<PayMethod>));
  await tester.pumpAndSettle();
  await _tap(tester, method);
  await _type(tester, 'Valor', amount);
  await _tap(tester, 'Adicionar');
}

void main() {
  testWidgets('a paid sale: items, % discount, freight, divided in Pix and '
      'cash with change', (tester) async {
    final w = await _open(tester);
    expect(find.text('Nenhuma venda ainda.'), findsOneWidget);
    await _tap(tester, 'Nova venda');
    expect(find.text('Cliente: Consumidor final'), findsOneWidget);

    await _addItem(tester, 'Camiseta', 'Azul');
    await _type(tester, 'Qtd. (UN)', '2');
    expect(find.text('Total do item: R\$ 100,00'), findsOneWidget);
    await _addItem(tester, 'Caneca');
    await _type(tester, 'Desconto', '10%');
    expect(find.text('Total do item: R\$ 35,91'), findsOneWidget);
    // Freight in "Mais detalhes" goes into the total of the bar.
    await _tap(tester, 'Mais detalhes');
    await _type(tester, 'Frete', '15,00');
    expect(find.text('R\$ 150,91'), findsOneWidget);
    // (100 + 35,91) − cost (2 × 20 + 15).
    expect(find.textContaining('lucro R\$ 80,91'), findsOneWidget);

    await _tap(tester, 'Dividir em mais de uma forma');
    await _pay(tester, 'Pix', '50,00');
    await _pay(tester, 'Dinheiro', '200,00');
    expect(find.text('Troco: R\$ 99,09'), findsOneWidget);
    expect(find.text('Pagamento completo.'), findsOneWidget);
    await _tap(tester, 'Concluir');

    expect(find.text('Venda nº 1'), findsOneWidget);
    expect(find.text('Paga'), findsOneWidget);
    // The highlight of a sale just registered.
    expect(find.text('Venda registrada'), findsOneWidget);
    final sale = w.sales.sales.values.single;
    expect(sale.total, 15091);
    expect(sale.items.map((i) => i.description), ['Camiseta (Azul)', 'Caneca']);
    expect(sale.items.last.discount, 399);
    expect(sale.payments.map((p) => (p.method, p.amount)), [
      (PayMethod.pix, 5000),
      (PayMethod.cash, 10091),
    ]);

    // Back in the list, with the totals.
    await tester.pageBack();
    await tester.pumpAndSettle();
    // Grouped by day, the client, the number and the totals.
    expect(find.text('Consumidor final'), findsOneWidget);
    expect(find.textContaining('Nº 1 · '), findsOneWidget);
    expect(find.text('Vendido · 1 venda'), findsOneWidget);
    expect(find.textContaining('Recebido'), findsOneWidget);
    expect(find.text('R\$ 150,91'), findsWidgets);
  });

  testWidgets('the price follows the quantity until typed by hand', (
    tester,
  ) async {
    await _open(tester);
    await _tap(tester, 'Nova venda');
    await _addItem(tester, 'Camiseta', 'Azul');
    await _type(tester, 'Qtd. (UN)', '10');
    expect(find.text('Total do item: R\$ 400,00'), findsOneWidget); // atacado
    await _type(tester, 'Preço', '45,00');
    await _type(tester, 'Qtd. (UN)', '12');
    expect(find.text('Total do item: R\$ 540,00'), findsOneWidget);
  });

  testWidgets('leaving a sale being filled in asks first', (tester) async {
    final w = await _open(tester);
    await _tap(tester, 'Nova venda');
    await tester.pageBack(); // empty: leaves at once
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma venda ainda.'), findsOneWidget);
    await _tap(tester, 'Nova venda');
    await _addItem(tester, 'Caneca');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Descartar a venda?'), findsOneWidget);
    await _tap(tester, 'Continuar a venda');
    expect(find.text('Caneca'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tap(tester, 'Descartar');
    expect(find.text('Nenhuma venda ainda.'), findsOneWidget);
    expect(w.sales.sales, isEmpty);
  });

  testWidgets('a sale that does not add up is refused', (tester) async {
    final w = await _open(tester);
    await _tap(tester, 'Nova venda');
    await _tap(tester, 'Concluir');
    expect(find.text('Adicione pelo menos um item.'), findsOneWidget);
    await _addItem(tester, 'Caneca');
    await _tap(tester, 'Concluir');
    expect(find.text('Escolha como vai pagar.'), findsOneWidget);
    await _tap(tester, 'Dinheiro');
    await _type(tester, 'Valor recebido', '20,00');
    await _tap(tester, 'Concluir');
    expect(find.textContaining('Menor que o total.'), findsOneWidget);
    await _tap(tester, 'Dividir em mais de uma forma');
    await _tap(tester, 'Concluir');
    expect(
      find.text('Falta R\$ 39,90: adicione um pagamento ou parcele.'),
      findsOneWidget,
    );
    await _tap(tester, 'Voltar para uma forma só');
    await _tap(tester, 'Pix');
    // An error in "Mais detalhes" opens it.
    await _tap(tester, 'Mais detalhes');
    await _type(tester, 'Data da venda', '03/10/2026');
    await _tap(tester, 'Mais detalhes');
    await _tap(tester, 'Concluir');
    expect(find.text('A data não pode ser no futuro.'), findsOneWidget);
    expect(w.sales.sales, isEmpty);
  });

  testWidgets('the first due date follows the sale date until typed', (
    tester,
  ) async {
    await _open(tester);
    await _tap(tester, 'Nova venda');
    await _tap(tester, 'Fiado');
    await _tap(tester, 'Mais detalhes');
    String due() => tester
        .widget<TextField>(find.widgetWithText(TextField, 'Vence em'))
        .controller!
        .text;
    expect(due(), '01/11/2026'); // 30 days after today
    await _type(tester, 'Data da venda', '20/09/2026');
    expect(due(), '20/10/2026');
    await _type(tester, 'Vence em', '05/11/2026');
    await _type(tester, 'Data da venda', '25/09/2026');
    expect(due(), '05/11/2026'); // typed by the user: kept
  });

  testWidgets('on credit: a client is required; receive part and undo', (
    tester,
  ) async {
    final w = await _open(tester);
    await _tap(tester, 'Nova venda');
    await _addItem(tester, 'Caneca');
    // Fiado in 3.
    await _tap(tester, 'Fiado');
    await _tap(tester, 'Parcelar');
    await _type(tester, 'Parcelas', '3');
    expect(find.text('3ª · vence 01/01/2027 · R\$ 13,30'), findsOneWidget);
    await _tap(tester, 'Concluir');
    expect(find.text('Fiado precisa de um cliente.'), findsWidgets);
    expect(w.sales.sales, isEmpty);
    await _tap(tester, 'Escolher cliente');
    await _tap(tester, 'Ana');
    await _tap(tester, 'Concluir');

    expect(find.text('Em aberto'), findsOneWidget);
    final sale = w.sales.sales.values.single;
    expect(sale.installments.map((i) => i.amount), [1330, 1330, 1330]);
    expect(sale.installments.first.due, '2026-11-01');

    await _tap(tester, 'Receber');
    await _type(tester, 'Valor', '10,00');
    await tester.tap(find.widgetWithText(FilledButton, 'Receber').last);
    await tester.pumpAndSettle();
    expect(find.text('pago R\$ 10,00 · em aberto'), findsOneWidget);
    expect(find.text('Recebimento registrado'), findsOneWidget);
    expect(find.text('Pix R\$ 10,00'), findsOneWidget);

    await tester.tap(find.byTooltip('Desfazer recebimento'));
    await tester.pumpAndSettle();
    await _tap(tester, 'Desfazer');
    expect(find.text('Pix R\$ 10,00'), findsNothing);
    expect(w.sales.sales.values.single.open, 3990);

    // A receber lists the three installments.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'A receber'));
    await tester.pumpAndSettle();
    expect(find.text('A receber · 3 parcelas'), findsOneWidget);
    expect(find.text('R\$ 39,90'), findsWidgets); // the card and "A vencer"
    expect(find.textContaining('Venda nº 1 · '), findsNWidgets(3));
  });

  testWidgets('canceling keeps the sale as canceled', (tester) async {
    final w = await _open(tester);
    await _tap(tester, 'Nova venda');
    await _addItem(tester, 'Caneca');
    await _tap(tester, 'Pix');
    await _tap(tester, 'Concluir');
    await tester.tap(find.byTooltip('Cancelar venda'));
    await tester.pumpAndSettle();
    await _type(tester, 'Motivo (opcional)', 'desistiu');
    await tester.tap(find.widgetWithText(FilledButton, 'Cancelar venda'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelada'), findsWidgets);
    expect(find.text('Motivo: desistiu'), findsOneWidget);
    expect(find.textContaining('estornado'), findsOneWidget);
    expect(w.sales.sales.values.single.canceled, isTrue);
  });

  testWidgets('negative stock warns before concluding', (tester) async {
    final w = await _open(tester);
    await _tap(tester, 'Nova venda');
    await _addItem(tester, 'Camiseta', 'Preto');
    await _type(tester, 'Qtd. (UN)', '3');
    await _tap(tester, 'Pix');
    await _tap(tester, 'Concluir');
    expect(find.text('Estoque negativo'), findsOneWidget);
    expect(find.textContaining('Camiseta (Preto): -2 UN'), findsOneWidget);
    await _tap(tester, 'Voltar');
    expect(w.sales.sales, isEmpty);
    await _tap(tester, 'Concluir');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Concluir'),
      ),
    );
    await tester.pumpAndSettle();
    expect(w.sales.sales.length, 1);
  });

  testWidgets('the summary goes to the conversation box, never sent', (
    tester,
  ) async {
    final w = await _open(tester);
    await w.sales.conclude(
      Sale(
        clientId: w.ana,
        soldAt: _today,
        items: [
          SaleItem(
            variantId: w.variant(w.caneca, 0).id!,
            description: 'Caneca',
            quantity: 1000,
            unitPrice: 3990,
          ),
        ],
        installments: splitInstallments(3990, 1, DateTime(2026, 11, 2)),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: SaleScreen(ctx: w.ctx, id: 1)));
    await tester.pumpAndSettle();
    await _tap(tester, 'Resumo pelo WhatsApp');
    final box = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Mensagem'),
    );
    expect(box.controller!.text, startsWith('Pedido nº 1 – 02/10/2026'));
    expect(box.controller!.text, contains('Total: R\$ 39,90'));
    expect(w.bridge.calls.where((c) => c.startsWith('sendText')), isEmpty);
  });

  testWidgets('the client page shows purchases; a client who owes stays', (
    tester,
  ) async {
    late _World world;
    await _open(
      tester,
      home: (w) {
        world = w;
        return ClientScreen(repo: w.clients, id: w.ana, bridge: w.bridge);
      },
    );
    expect(find.text('Linha do tempo'), findsOneWidget);
    expect(find.text('Nenhuma compra ainda.'), findsOneWidget);
    await world.sales.conclude(
      Sale(
        clientId: world.ana,
        soldAt: _today,
        items: [
          SaleItem(
            variantId: world.variant(world.caneca, 0).id!,
            description: 'Caneca',
            quantity: 1000,
            unitPrice: 3990,
          ),
        ],
        installments: splitInstallments(3990, 1, DateTime(2026, 11, 2)),
      ),
    );
    // Open a new sale and come back: the numbers reload.
    await _tap(tester, 'Nova venda');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Comprou R\$ 39,90 em 1 compra · ticket médio R\$ 39,90 · última em 02/10/2026',
      ),
      findsOneWidget,
    );
    expect(find.text('Compra nº 1'), findsOneWidget);
    await _tap(tester, 'Ver todas as compras');
    expect(find.text('Vendas: Ana'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    world.clients.deleteError = const ClientHasOpenSales(3990);
    await tester.tap(find.byTooltip('Apagar cliente'));
    await tester.pumpAndSettle();
    await _tap(tester, 'Apagar');
    expect(find.text('Não dá para apagar'), findsOneWidget);
    expect(find.textContaining('R\$ 39,90 a receber'), findsOneWidget);
  });

  testWidgets('a sold product cannot be deleted', (tester) async {
    late _World world;
    await _open(
      tester,
      home: (w) {
        world = w;
        return ProductScreen(repo: w.products, id: w.caneca);
      },
    );
    world.products.deleteError = const ProductHasSales();
    await tester.tap(find.byTooltip('Apagar produto'));
    await tester.pumpAndSettle();
    await _tap(tester, 'Apagar');
    expect(find.textContaining('Este produto já foi vendido'), findsOneWidget);
    expect(world.products.products.containsKey(world.caneca), isTrue);
  });

  test('summary text', () {
    final sale = Sale(
      number: 7,
      soldAt: DateTime(2026, 10, 2),
      items: const [
        SaleItem(
          variantId: 1,
          description: 'Camiseta (Azul)',
          quantity: 2000,
          unitPrice: 5000,
          discount: 1000,
        ),
      ],
      discount: 500,
      freight: 1500,
      payments: [
        SalePayment(method: PayMethod.pix, amount: 5000, at: DateTime(2026)),
      ],
      installments: const [
        Installment(number: 1, due: '2026-11-02', amount: 2500),
        Installment(number: 2, due: '2026-12-02', amount: 2500),
      ],
    );
    expect(
      saleSummary(sale),
      'Pedido nº 7 – 02/10/2026\n'
      '\n'
      '2 UN × Camiseta (Azul): R\$ 90,00 (desconto R\$ 10,00)\n'
      '\n'
      'Desconto: R\$ 5,00\n'
      'Frete: R\$ 15,00\n'
      'Total: R\$ 100,00\n'
      'Pago: Pix R\$ 50,00\n'
      'A prazo, em 2 parcelas:\n'
      '1ª R\$ 25,00 – vence 02/11/2026\n'
      '2ª R\$ 25,00 – vence 02/12/2026',
    );
  });
}
