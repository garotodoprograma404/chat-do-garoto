// The arithmetic of sales.
import 'package:chat_do_garoto/src/sales/sale_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('discounts in reais or percent', () {
    expect(parseDiscount('', 10000), 0);
    expect(parseDiscount('5,00', 10000), 500);
    expect(parseDiscount('10%', 10000), 1000);
    expect(parseDiscount('12,5%', 3990), 499); // 498,75 rounds up
    expect(parseDiscount('100%', 3990), 3990);
    expect(parseDiscount('101%', 3990), isNull);
    expect(parseDiscount('abc', 3990), isNull);
    expect(parseDiscount('-5', 3990), isNull);
  });

  test('line and sale totals', () {
    // 2 × R$ 50,00 − R$ 10,00.
    expect(lineTotal(2000, 5000, 1000), 9000);
    // 1,25 kg × R$ 39,90 = R$ 49,875 -> R$ 49,88.
    expect(lineTotal(1250, 3990, 0), 4988);
    expect(timesQuantity(333, 100), 33);
  });

  test('cash records what was due and gives change', () {
    expect(cashPayment(5000, 3990), (recorded: 3990, change: 1010));
    expect(cashPayment(2000, 3990), (recorded: 2000, change: 0));
  });

  test('installments: leftover cents in the first, monthly', () {
    final parts = splitInstallments(10000, 3, DateTime(2026, 1, 31));
    expect(parts.map((p) => p.amount), [3334, 3333, 3333]);
    expect(parts.map((p) => p.due), ['2026-01-31', '2026-02-28', '2026-03-31']);
    expect(parts.map((p) => p.number), [1, 2, 3]);
    expect(splitInstallments(500, 1, DateTime(2026, 10, 2)).single.amount, 500);
  });

  test('receipts cover the oldest installments first', () {
    const parts = [
      Installment(number: 2, due: '2026-12-02', amount: 3000),
      Installment(number: 1, due: '2026-11-02', amount: 3000),
      Installment(number: 3, due: '2027-01-02', amount: 3000),
    ];
    expect(allocate(parts, 4000), [1000, 3000, 0]);
    expect(allocate(parts, 0), [0, 0, 0]);
    expect(allocate(parts, 9000), [3000, 3000, 3000]);
  });

  test('status with fixed dates', () {
    const parts = [
      Installment(number: 1, due: '2026-10-01', amount: 3000),
      Installment(number: 2, due: '2026-11-01', amount: 3000),
    ];
    final today = DateTime(2026, 10, 2, 15);
    SaleStatus status(int receipts, {bool canceled = false}) => saleStatus(
      canceled: canceled,
      installments: parts,
      receipts: receipts,
      today: today,
    );
    expect(status(0), SaleStatus.overdue); // the first was due yesterday
    expect(status(2999), SaleStatus.overdue);
    expect(status(3000), SaleStatus.open);
    expect(status(6000), SaleStatus.paid);
    expect(status(0, canceled: true), SaleStatus.canceled);
    // Due today is not overdue yet.
    expect(
      saleStatus(
        canceled: false,
        installments: const [
          Installment(number: 1, due: '2026-10-02', amount: 100),
        ],
        receipts: 0,
        today: today,
      ),
      SaleStatus.open,
    );
    // Paid at the sale: nothing on credit.
    expect(
      saleStatus(
        canceled: false,
        installments: const [],
        receipts: 0,
        today: today,
      ),
      SaleStatus.paid,
    );
  });

  test('months', () {
    expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
    expect(addMonths(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
    expect(addMonths(DateTime(2026, 11, 15), 2), DateTime(2027, 1, 15));
  });
}
