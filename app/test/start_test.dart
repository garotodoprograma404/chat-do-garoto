// The Início: today, shortcuts and the month.
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/home/start_controller.dart';
import 'package:chat_do_garoto/src/home/start_screen.dart';
import 'package:chat_do_garoto/src/products/products_repository.dart';
import 'package:chat_do_garoto/src/sales/sale_math.dart';
import 'package:chat_do_garoto/src/sales/sales_repository.dart';
import 'package:chat_do_garoto/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';
import 'support/fake_products_repository.dart';
import 'support/fake_sales_repository.dart';

final _today = DateTime(2026, 10, 2, 9);

SaleItem _item(String name, int cents, {int qty = 1000}) => SaleItem(
  variantId: 1,
  description: name,
  quantity: qty,
  unitPrice: cents,
  unitCost: cents ~/ 2,
);

/// A world with a client owing (one installment overdue, one due today, one
/// in the future), a birthday tomorrow, a product out of stock and sales in
/// two months.
Future<
  ({
    FakeClientsRepository clients,
    FakeProductsRepository products,
    FakeSalesRepository sales,
  })
>
_world() async {
  final clients = FakeClientsRepository();
  final products = FakeProductsRepository();
  final sales = FakeSalesRepository()..now = _today;
  final carla = await clients.save(
    const Client(name: 'Carla Dias', phone: '5511900000001'),
  );
  await clients.save(
    const Client(
      name: 'Marcos Reis',
      phone: '5511900000002',
      birthday: '--10-03',
    ),
  );
  await clients.save(
    const Client(name: 'Longe', phone: '5511900000003', birthday: '--12-25'),
  );
  sales.names[carla] = 'Carla Dias';
  await products.save(
    const Product(name: 'Caneca', price: 2500, variants: [Variant(stock: 0)]),
  );
  await products.save(
    const Product(
      name: 'Camiseta',
      price: 5000,
      minStock: 1000,
      variants: [Variant(stock: 9000)],
    ),
  );
  // On credit: 3 × R$ 30,00 (overdue, today, next month), R$ 10,00 paid.
  await sales.conclude(
    Sale(
      clientId: carla,
      soldAt: DateTime(2026, 9, 2),
      items: [_item('Camiseta', 9000)],
      installments: const [
        Installment(number: 1, due: '2026-09-29', amount: 3000),
        Installment(number: 2, due: '2026-10-02', amount: 3000),
        Installment(number: 3, due: '2026-11-02', amount: 3000),
      ],
    ),
  );
  // Paid in October: R$ 50,00 and R$ 25,00; one cancelled.
  await sales.conclude(
    Sale(
      soldAt: DateTime(2026, 10, 1),
      items: [_item('Camiseta', 5000)],
      payments: [
        SalePayment(
          method: PayMethod.pix,
          amount: 5000,
          at: DateTime(2026, 10, 1),
        ),
      ],
    ),
  );
  await sales.conclude(
    Sale(
      soldAt: DateTime(2026, 10, 2),
      items: [_item('Caneca', 2500)],
      payments: [
        SalePayment(
          method: PayMethod.cash,
          amount: 2500,
          at: DateTime(2026, 10, 2),
        ),
      ],
    ),
  );
  final cancelled = await sales.conclude(
    Sale(
      soldAt: DateTime(2026, 10, 2),
      items: [_item('Caneca', 9900)],
      payments: [
        SalePayment(
          method: PayMethod.cash,
          amount: 9900,
          at: DateTime(2026, 10, 2),
        ),
      ],
    ),
  );
  await sales.cancel(cancelled);
  return (clients: clients, products: products, sales: sales);
}

void main() {
  test(
    'today: due and overdue, birthdays within the week, low stock',
    () async {
      final w = await _world();
      final c = StartController(
        clients: w.clients,
        products: w.products,
        sales: w.sales,
        clock: () => _today,
      );
      await c.load();
      expect(c.firstRun, isFalse);
      expect(
        [for (final r in c.receivables) (r.number, r.left)],
        [(1, 3000), (2, 3000)],
      );
      expect(c.receivableTotal, 6000);
      expect(
        [for (final b in c.birthdays) (b.client.name, b.inDays)],
        [('Marcos Reis', 1)],
      );
      expect([for (final p in c.lowStock) p.name], ['Caneca']);
    },
  );

  test('a receipt pays the oldest installment first', () async {
    final w = await _world();
    final credit = (await w.sales.list()).firstWhere(
      (s) => s.installments.isNotEmpty,
    );
    await w.sales.receive(credit.id!, PayMethod.pix, 3500, _today);
    final c = StartController(
      clients: w.clients,
      products: w.products,
      sales: w.sales,
      clock: () => _today,
    );
    await c.load();
    expect([for (final r in c.receivables) (r.number, r.left)], [(2, 2500)]);
  });

  test('the month: revenue, count, profit, best sellers, arrows', () async {
    final w = await _world();
    final c = StartController(
      clients: w.clients,
      products: w.products,
      sales: w.sales,
      clock: () => _today,
    );
    await c.load();
    var n = c.numbers;
    expect((n.revenue, n.count, n.profit), (7500, 2, 3750));
    expect([for (final p in n.top) p.name], ['Camiseta', 'Caneca']);
    expect(c.atCurrentMonth, isTrue);
    c.moveMonth(-1);
    n = c.numbers;
    expect((n.revenue, n.count), (9000, 1));
    expect(c.atCurrentMonth, isFalse);
    expect(monthLabel(c.month), 'Setembro de 2026');
  });

  test('first run without anything', () async {
    final c = StartController(
      clients: FakeClientsRepository(),
      products: FakeProductsRepository(),
      sales: FakeSalesRepository(),
      clock: () => _today,
    );
    await c.load();
    expect(c.firstRun, isTrue);
  });

  test('labels', () {
    expect(dueLabel('2026-10-02', _today), 'vence hoje');
    expect(dueLabel('2026-10-01', _today), 'venceu ontem');
    expect(dueLabel('2026-09-29', _today), 'venceu há 3 dias');
    expect(inDaysLabel(0), 'Hoje');
    expect(inDaysLabel(1), 'Amanhã');
    expect(inDaysLabel(4), 'Em 4 dias');
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: home));
    await tester.pumpAndSettle();
  }

  testWidgets('the screen: today, the month and opening a sale', (
    tester,
  ) async {
    final w = await _world();
    var settings = 0;
    await pump(
      tester,
      StartScreen(
        clients: w.clients,
        products: w.products,
        sales: w.sales,
        clock: () => _today,
        onOpenSettings: () => settings++,
      ),
    );
    expect(find.text('A receber até hoje'), findsOneWidget);
    expect(find.text('R\$ 60,00'), findsOneWidget);
    expect(find.textContaining('1ª parcela venceu há 3 dias'), findsOneWidget);
    expect(find.text('Aniversário amanhã'), findsOneWidget);
    expect(find.text('Sem estoque'), findsNWidgets(2)); // text and pill
    expect(find.text('Outubro de 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Configurações'));
    expect(settings, 1);

    await tester.scrollUntilVisible(find.text('Mais vendidos'), 200);
    await tester.tap(find.byTooltip('Mês anterior'));
    await tester.pumpAndSettle();
    expect(find.text('Setembro de 2026'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Carla Dias').first, -200);
    await tester.tap(find.text('Carla Dias').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Venda nº'), findsWidgets);
  });

  testWidgets('first run shows the first step, not zeros', (tester) async {
    await pump(
      tester,
      StartScreen(
        clients: FakeClientsRepository(),
        products: FakeProductsRepository(),
        sales: FakeSalesRepository(),
        clock: () => _today,
      ),
    );
    expect(find.text('Comece por aqui'), findsOneWidget);
    expect(find.text('Faturamento'), findsNothing);
    expect(find.text('Novo cliente'), findsOneWidget);
    expect(find.text('Novo produto'), findsOneWidget);
  });
}
