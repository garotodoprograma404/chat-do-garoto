// Sales search, filters, totals and receivables.
import 'package:chat_do_garoto/src/sales/sale_math.dart';
import 'package:chat_do_garoto/src/sales/sales_controller.dart';
import 'package:chat_do_garoto/src/sales/sales_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_sales_repository.dart';

final _today = DateTime(2026, 10, 15, 15);

SaleItem _item(String description, int price, {int cost = 0}) => SaleItem(
  variantId: 1,
  description: description,
  quantity: 1000,
  unitPrice: price,
  unitCost: cost,
);

Future<(SalesController, FakeSalesRepository)> _world() async {
  final repo = FakeSalesRepository()..names.addAll({1: 'Ana Souza', 2: 'Bia'});
  // 1: paid today by Pix.
  await repo.conclude(
    Sale(
      soldAt: DateTime(2026, 10, 15, 10),
      items: [_item('Camiseta (Azul / P)', 5000, cost: 2000)],
      payments: [SalePayment(method: PayMethod.pix, amount: 5000, at: _today)],
    ),
  );
  // 2: Ana on credit since September, first installment overdue.
  await repo.conclude(
    Sale(
      clientId: 1,
      soldAt: DateTime(2026, 9, 20),
      items: [_item('Caneca', 9000, cost: 3000)],
      installments: splitInstallments(9000, 3, DateTime(2026, 10, 1)),
    ),
  );
  // 3: Bia on credit 5 days ago, nothing due yet.
  await repo.conclude(
    Sale(
      clientId: 2,
      soldAt: DateTime(2026, 10, 10),
      items: [_item('Consultoria', 20000)],
      payments: [SalePayment(method: PayMethod.cash, amount: 5000, at: _today)],
      installments: splitInstallments(15000, 1, DateTime(2026, 11, 10)),
    ),
  );
  // 4: canceled.
  final canceled = await repo.conclude(
    Sale(
      soldAt: DateTime(2026, 10, 14),
      items: [_item('Camiseta (Preto / G)', 5500)],
      payments: [
        SalePayment(method: PayMethod.credit, amount: 5500, at: _today),
      ],
    ),
  );
  await repo.cancel(canceled);
  final controller = SalesController(repo: repo, clock: () => _today);
  await controller.load();
  return (controller, repo);
}

List<int> _numbers(SalesController c) => [for (final s in c.sales) s.number];

void main() {
  test('newest first; status of each sale', () async {
    final (c, _) = await _world();
    expect(_numbers(c), [1, 4, 3, 2]);
    final status = {for (final s in c.all) s.number: s.status(_today)};
    expect(status, {
      1: SaleStatus.paid,
      2: SaleStatus.overdue,
      3: SaleStatus.open,
      4: SaleStatus.canceled,
    });
  });

  test('search by client, number and product', () async {
    final (c, _) = await _world();
    c.search('ana');
    expect(_numbers(c), [2]);
    c.search('3');
    expect(_numbers(c), [3]);
    c.search('camiseta');
    expect(_numbers(c), [1, 4]);
    c.search('consumidor');
    expect(_numbers(c), [1, 4]);
  });

  test('periods and statuses', () async {
    final (c, _) = await _world();
    c.setPeriod(SalePeriod.today);
    expect(_numbers(c), [1]);
    c.setPeriod(SalePeriod.week);
    expect(_numbers(c), [1, 4, 3]);
    c.setPeriod(SalePeriod.month);
    expect(_numbers(c), [1, 4, 3]);
    c.setPeriod(SalePeriod.lastMonth);
    expect(_numbers(c), [2]);
    c.setPeriod(SalePeriod.all);
    c.toggleStatus(SaleStatus.overdue);
    c.toggleStatus(SaleStatus.open);
    expect(_numbers(c), [3, 2]);
    c.toggleStatus(SaleStatus.overdue);
    c.toggleStatus(SaleStatus.open);
    c.toggleStatus(SaleStatus.canceled);
    expect(_numbers(c), [4]);
  });

  test('totals leave canceled sales out', () async {
    final (c, _) = await _world();
    final t = c.totals;
    expect(t.sold, 5000 + 9000 + 20000);
    expect(t.received, 5000 + 5000);
    expect(t.open, 9000 + 15000);
    expect(t.profit, 3000 + 6000 + 20000);
    c.toggleStatus(SaleStatus.canceled);
    expect(c.totals.sold, 0);
  });

  test('receivables: overdue first, then by due date', () async {
    final (c, repo) = await _world();
    var r = c.receivables;
    expect(r.map((x) => (x.sale.number, x.installment.number, x.overdue)), [
      (2, 1, true),
      (2, 2, false),
      (3, 1, false),
      (2, 3, false),
    ]);
    expect(c.receivableTotals, (open: 24000, overdue: 3000));

    // Receiving Ana's first installment clears the overdue one.
    await repo.receive(2, PayMethod.pix, 3000, _today);
    await c.load();
    r = c.receivables;
    expect(r.first.overdue, isFalse);
    expect(c.receivableTotals.overdue, 0);
  });

  test('a client\'s own list', () async {
    final (_, repo) = await _world();
    final c = SalesController(repo: repo, clock: () => _today, clientId: 1);
    await c.load();
    expect(_numbers(c), [2]);
  });
}
