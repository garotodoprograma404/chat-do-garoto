// The new screens with large text and in the dark theme
import 'package:chat_do_garoto/src/home/crm_scope.dart';
import 'package:chat_do_garoto/src/home/start_screen.dart';
import 'package:chat_do_garoto/src/products/products_repository.dart';
import 'package:chat_do_garoto/src/products/products_screen.dart';
import 'package:chat_do_garoto/src/sales/quick_sale_screen.dart';
import 'package:chat_do_garoto/src/sales/sale_form_screen.dart';
import 'package:chat_do_garoto/src/sales/sales_screen.dart';
import 'package:chat_do_garoto/src/scan/barcode_scanner.dart';
import 'package:chat_do_garoto/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_barcode_scanner.dart';
import 'support/fake_clients_repository.dart';
import 'support/fake_products_repository.dart';
import 'support/fake_sales_repository.dart';

final _today = DateTime(2026, 10, 3, 10);

void main() {
  setUp(() => barcodeScanner = FakeBarcodeScanner());
  tearDown(() => barcodeScanner = null);

  for (final dark in [false, true]) {
    testWidgets('200% text, ${dark ? 'dark' : 'light'} theme', (tester) async {
      final products = FakeProductsRepository();
      await products.save(
        const Product(
          name: 'Hidratante corporal de amêndoas e karité',
          price: 1234567,
          barcode: '7891234567895',
          expiresOn: '2026-10-13',
          variants: [Variant(stock: 5000)],
        ),
      );
      final sales = FakeSalesRepository()..now = _today;
      final clients = FakeClientsRepository();
      final ctx = SaleContext(
        sales: sales,
        products: products,
        clients: clients,
        clock: () => _today,
      );
      final screens = <String, Widget>{
        'Venda rápida': QuickSaleScreen(ctx: ctx),
        'Nova venda': SaleFormScreen(ctx: ctx),
        'Vendas': SalesScreen(ctx: ctx),
        'Produtos': ProductsScreen(repo: products, clock: () => _today),
        'Início': StartScreen(
          clients: clients,
          products: products,
          sales: sales,
          clock: () => _today,
        ),
      };
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      for (final MapEntry(:key, :value) in screens.entries) {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(2),
            ),
            child: MaterialApp(
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              builder: (context, child) =>
                  CrmScope(products: products, sales: sales, child: child!),
              home: value,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: key);
      }
    });
  }
}
