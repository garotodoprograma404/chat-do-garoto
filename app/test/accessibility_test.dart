// Large text and no animations.
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/clients/clients_screen.dart';
import 'package:chat_do_garoto/src/home/start_screen.dart';
import 'package:chat_do_garoto/src/products/products_repository.dart';
import 'package:chat_do_garoto/src/products/products_screen.dart';
import 'package:chat_do_garoto/src/sales/sale_math.dart';
import 'package:chat_do_garoto/src/sales/sale_screen.dart';
import 'package:chat_do_garoto/src/sales/sales_repository.dart';
import 'package:chat_do_garoto/src/sales/sales_screen.dart';
import 'package:chat_do_garoto/src/theme/app_theme.dart';
import 'package:chat_do_garoto/src/theme/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';
import 'support/fake_products_repository.dart';
import 'support/fake_sales_repository.dart';

final _today = DateTime(2026, 10, 2, 9);

Future<
  ({
    FakeClientsRepository clients,
    FakeProductsRepository products,
    FakeSalesRepository sales,
    int saleId,
  })
>
_world() async {
  final clients = FakeClientsRepository();
  final products = FakeProductsRepository();
  final sales = FakeSalesRepository()..now = _today;
  final id = await clients.save(
    const Client(
      name: 'Maria Aparecida dos Santos Oliveira',
      phone: '5511900000001',
      birthday: '--10-03',
      tags: ['revenda', 'atacado'],
    ),
  );
  sales.names[id] = 'Maria Aparecida dos Santos Oliveira';
  await products.save(
    const Product(
      name: 'Camiseta básica de algodão orgânico',
      price: 12990,
      promoPrice: 9990,
      promoUntil: '2026-10-31',
      category: 'Vestuário',
      variants: [Variant(stock: 0)],
    ),
  );
  final saleId = await sales.conclude(
    Sale(
      clientId: id,
      soldAt: DateTime(2026, 9, 2),
      items: const [
        SaleItem(
          variantId: 1,
          description: 'Camiseta básica de algodão orgânico (Azul / GG)',
          quantity: 3000,
          unitPrice: 12990,
        ),
      ],
      installments: const [
        Installment(number: 1, due: '2026-09-29', amount: 19485),
        Installment(number: 2, due: '2026-10-29', amount: 19485),
      ],
    ),
  );
  return (clients: clients, products: products, sales: sales, saleId: saleId);
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(
        size: Size(360, 800),
        textScaler: TextScaler.linear(2),
      ),
      child: MaterialApp(theme: AppTheme.light(), home: home),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('text at 200%: the main screens do not overflow', (tester) async {
    final w = await _world();
    final ctx = SaleContext(
      sales: w.sales,
      products: w.products,
      clients: w.clients,
      clock: () => _today,
    );
    final screens = <String, Widget>{
      'Início': StartScreen(
        clients: w.clients,
        products: w.products,
        sales: w.sales,
        clock: () => _today,
        onOpenSettings: () {},
      ),
      'Clientes': ClientsScreen(repo: w.clients, onOpenSettings: () {}),
      'Produtos': ProductsScreen(
        repo: w.products,
        clock: () => _today,
        onOpenSettings: () {},
      ),
      'Vendas': SalesScreen(ctx: ctx, onOpenSettings: () {}),
      'Venda': SaleScreen(ctx: ctx, id: w.saleId),
    };
    for (final MapEntry(:key, :value) in screens.entries) {
      await _pump(tester, value);
      expect(tester.takeException(), isNull, reason: key);
    }
  });

  testWidgets('no animations: highlights and new items show at once', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              Highlight(child: Text('Venda registrada')),
              EnterOnce(child: Text('nova mensagem')),
            ],
          ),
        ),
      ),
    );
    for (final f in tester.widgetList<FadeTransition>(
      find.byType(FadeTransition),
    )) {
      expect(f.opacity.value, 1);
    }
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('with animations, a new item slides in', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: EnterOnce(child: Text('nova mensagem')),
      ),
    );
    final fade = tester.widget<FadeTransition>(find.byType(FadeTransition));
    expect(fade.opacity.value, lessThan(1));
    await tester.pumpAndSettle();
    expect(fade.opacity.value, 1);
  });
}
