// Venda rápida.
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/home/crm_scope.dart';
import 'package:chat_do_garoto/src/products/products_repository.dart';
import 'package:chat_do_garoto/src/sales/quick_sale_screen.dart';
import 'package:chat_do_garoto/src/sales/sale_form_screen.dart';
import 'package:chat_do_garoto/src/sales/sale_math.dart';
import 'package:chat_do_garoto/src/sales/sales_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';
import 'support/fake_products_repository.dart';
import 'support/fake_sales_repository.dart';

final _today = DateTime(2026, 10, 3, 10);

typedef _World = ({
  FakeSalesRepository sales,
  FakeProductsRepository products,
  FakeClientsRepository clients,
  SaleContext ctx,
});

Future<_World> _open(
  WidgetTester tester, {
  Widget Function(SaleContext)? home,
}) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final sales = FakeSalesRepository()..now = _today;
  final products = FakeProductsRepository();
  final clients = FakeClientsRepository();
  final ana = await clients.save(
    const Client(name: 'Ana Souza', phone: '5511900000001'),
  );
  sales.names[ana] = 'Ana Souza';
  await products.save(
    const Product(
      name: 'Caneca',
      price: 2500,
      variants: [Variant(stock: 5000)],
    ),
  );
  final ctx = SaleContext(
    sales: sales,
    products: products,
    clients: clients,
    clock: () => _today,
  );
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          CrmScope(products: products, sales: sales, child: child!),
      home: home?.call(ctx) ?? SalesScreen(ctx: ctx),
    ),
  );
  await tester.pumpAndSettle();
  return (sales: sales, products: products, clients: clients, ctx: ctx);
}

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextField, label), text);
  await tester.pump();
}

void main() {
  test('a quick sale is one item without a product', () {
    final paid = quickSale(
      amount: 5000,
      description: ' ',
      soldAt: _today,
      method: PayMethod.cash,
    );
    expect(paid.items.single.variantId, isNull);
    expect(paid.items.single.description, 'Venda rápida');
    expect(paid.total, 5000);
    expect(paid.payments.single.method, PayMethod.cash);
    expect(paid.installments, isEmpty);
    final credit = quickSale(
      amount: 8000,
      description: 'Conserto',
      soldAt: _today,
      clientId: 1,
      due: '2026-11-02',
    );
    expect(credit.payments, isEmpty);
    expect(credit.onCredit, 8000);
  });

  testWidgets('R\$ 50 paid by Pix, from Vendas, moves no stock', (
    tester,
  ) async {
    final w = await _open(tester);
    await tester.tap(find.text('Venda rápida'));
    await tester.pumpAndSettle();

    await _type(tester, 'Valor', '50,00');
    await _type(tester, 'Descrição (opcional)', 'Conserto');
    await tester.tap(find.text('Registrar venda'));
    await tester.pumpAndSettle();

    final sale = (await w.sales.list()).single;
    expect(sale.items.single.variantId, isNull);
    expect(sale.items.single.description, 'Conserto');
    expect(sale.total, 5000);
    expect(sale.payments.single.method, PayMethod.pix);
    expect(sale.open, 0);
    expect(find.text('Venda registrada'), findsOneWidget);
    expect((await w.products.list()).single.stock, 5000);
  });

  testWidgets('credit needs a client, then it is to receive', (tester) async {
    final w = await _open(tester);
    await tester.tap(find.text('Venda rápida'));
    await tester.pumpAndSettle();
    await _type(tester, 'Valor', '80,00');
    await tester.tap(find.text('Fiado'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Vence em'), findsOneWidget);

    await tester.tap(find.text('Registrar venda'));
    await tester.pumpAndSettle();
    expect(find.text('Fiado precisa de um cliente.'), findsOneWidget);
    expect(await w.sales.list(), isEmpty);

    await tester.tap(find.text('Escolher cliente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana Souza'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar venda'));
    await tester.pumpAndSettle();

    final sale = (await w.sales.list()).single;
    expect(sale.clientName, 'Ana Souza');
    expect(sale.open, 8000);
    expect(sale.installments.single.due, '2026-11-02');
  });

  testWidgets('"Só o valor?" in the new sale opens the quick sale', (
    tester,
  ) async {
    await _open(tester, home: (ctx) => SaleFormScreen(ctx: ctx));
    await tester.tap(find.text('Só o valor? Venda rápida'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Venda rápida'), findsOneWidget);
  });

  testWidgets('the bar shows the items and the total, and concludes', (
    tester,
  ) async {
    final w = await _open(tester, home: (ctx) => SaleFormScreen(ctx: ctx));
    expect(find.text('0 itens'), findsOneWidget);

    await tester.tap(find.text('Adicionar item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caneca').last);
    await tester.pumpAndSettle();
    expect(find.text('1 item'), findsOneWidget);
    expect(find.text('R\$ 25,00'), findsWidgets);

    await tester.tap(find.text('Mais detalhes'));
    await tester.pumpAndSettle();
    await _type(tester, 'Frete', '10,00');
    await tester.pumpAndSettle();
    expect(find.text('R\$ 35,00'), findsWidgets);

    // The bar's "Concluir" does what the top one does.
    await tester.tap(find.widgetWithText(FilledButton, 'Concluir'));
    await tester.pumpAndSettle();
    expect(find.text('Escolha como vai pagar.'), findsOneWidget);

    await tester.tap(find.text('Pix'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Concluir'));
    await tester.pumpAndSettle();
    expect((await w.sales.list()).single.total, 3500);
  });

  testWidgets('money formats while typing in the quick and the new sale', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.text('Venda rápida'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Valor'), '1290');
    await tester.pump();
    expect(find.text(r'R$ 12,90'), findsOneWidget);
  });
}
