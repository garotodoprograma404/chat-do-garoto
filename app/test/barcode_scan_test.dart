// The barcode reader in the product form, the product list and the sale,
// with a fake scanner.
import 'package:chat_do_garoto/src/home/crm_scope.dart';
import 'package:chat_do_garoto/src/products/product_form_screen.dart';
import 'package:chat_do_garoto/src/products/products_repository.dart';
import 'package:chat_do_garoto/src/products/products_screen.dart';
import 'package:chat_do_garoto/src/products/variants.dart';
import 'package:chat_do_garoto/src/sales/sale_form_screen.dart';
import 'package:chat_do_garoto/src/sales/sales_screen.dart';
import 'package:chat_do_garoto/src/scan/barcode_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_barcode_scanner.dart';
import 'support/fake_clients_repository.dart';
import 'support/fake_products_repository.dart';
import 'support/fake_sales_repository.dart';

final _today = DateTime(2026, 10, 3, 10);

Future<FakeProductsRepository> _catalog() async {
  final repo = FakeProductsRepository();
  await repo.save(
    const Product(
      name: 'Caneca',
      price: 2500,
      barcode: '7890000000001',
      variants: [Variant(stock: 5000)],
    ),
  );
  await repo.save(
    const Product(
      name: 'Camiseta',
      price: 5000,
      attributes: [
        Attribute('Cor', ['Azul', 'Preto']),
      ],
      variants: [
        Variant(options: ['Azul'], barcode: '7890000000003', stock: 5000),
        Variant(options: ['Preto'], stock: 5000),
      ],
    ),
  );
  await repo.save(
    const Product(
      name: 'Velha',
      price: 100,
      barcode: '7890000000009',
      active: false,
      variants: [Variant(stock: 1000)],
    ),
  );
  return repo;
}

void main() {
  late FakeBarcodeScanner scanner;
  setUp(() => barcodeScanner = scanner = FakeBarcodeScanner());
  tearDown(() => barcodeScanner = null);

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('reading fills the barcode in the form', (tester) async {
    tall(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: ProductFormScreen(
          repo: FakeProductsRepository(),
          clock: () => _today,
        ),
      ),
    );
    scanner.one.add('7891234567895');
    await tester.tap(find.text('Código de barras e código interno'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ler código de barras').first);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Código de barras'))
          .controller!
          .text,
      '7891234567895',
    );
  });

  testWidgets('a known code opens the product; an unknown one offers '
      'to register it', (tester) async {
    tall(tester);
    final repo = await _catalog();
    await tester.pumpWidget(
      MaterialApp(
        home: ProductsScreen(repo: repo, clock: () => _today),
      ),
    );
    await tester.pumpAndSettle();

    scanner.one.add('7890000000003');
    await tester.tap(find.byTooltip('Ler código de barras'));
    await tester.pumpAndSettle();
    expect(find.text('Camiseta'), findsWidgets);
    expect(find.byTooltip('Apagar produto'), findsOneWidget); // its page
    await tester.pageBack();
    await tester.pumpAndSettle();

    scanner.one.add('7899999999999');
    await tester.tap(find.byTooltip('Ler código de barras'));
    await tester.pumpAndSettle();
    expect(find.text('Código não cadastrado'), findsOneWidget);
    await tester.tap(find.text('Cadastrar produto com este código'));
    await tester.pumpAndSettle();
    // Closed, the group already shows the code.
    expect(find.text('7899999999999'), findsOneWidget);
    await tester.tap(find.text('Código de barras e código interno'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Código de barras'))
          .controller!
          .text,
      '7899999999999',
    );
  });

  testWidgets('in the sale, A, B, A, unknown and inactive', (tester) async {
    tall(tester);
    final products = await _catalog();
    final sales = FakeSalesRepository()..now = _today;
    final ctx = SaleContext(
      sales: sales,
      products: products,
      clients: FakeClientsRepository(),
      clock: () => _today,
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            CrmScope(products: products, sales: sales, child: child!),
        home: SaleFormScreen(ctx: ctx),
      ),
    );
    scanner.many = [
      '7890000000001',
      '7890000000003',
      '7890000000001',
      '000',
      '7890000000009',
    ];
    await tester.tap(find.text('Ler código'));
    await tester.pumpAndSettle();

    expect(scanner.messages, [
      'Caneca: 1 UN',
      'Camiseta (Azul): 1 UN',
      'Caneca: 2 UN',
      'Código não cadastrado',
      'Velha está inativo',
    ]);
    expect(find.text('2 itens'), findsOneWidget);
    expect(find.text('R\$ 100,00'), findsWidgets); // 2 × 25 + 50
  });
}
