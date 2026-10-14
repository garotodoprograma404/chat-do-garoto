/// The arithmetic of sales: money in cents, quantities
/// in thousandths, never doubles.
library;

import '../products/money.dart';
import '../products/pricing.dart';

/// How a payment was made.
enum PayMethod { cash, pix, debit, credit, transfer, boleto, cheque, other }

const payMethodLabels = {
  PayMethod.cash: 'Dinheiro',
  PayMethod.pix: 'Pix',
  PayMethod.debit: 'Cartão de débito',
  PayMethod.credit: 'Cartão de crédito',
  PayMethod.transfer: 'Transferência',
  PayMethod.boleto: 'Boleto',
  PayMethod.cheque: 'Cheque',
  PayMethod.other: 'Outro',
};

/// A discount from "5,00" (reais) or "10%" over [base] cents; 0 when blank,
/// null when invalid. Percentages round half up to the cent.
int? parseDiscount(String text, int base) {
  final t = text.replaceAll(RegExp(r'\s'), '');
  if (t.isEmpty) return 0;
  if (!t.endsWith('%')) return parseMoney(t);
  final m = RegExp(r'^(\d{1,3})(?:[.,](\d{1,2}))?%$').firstMatch(t);
  if (m == null) return null;
  // Hundredths of a percent: 12,5% = 1250.
  final hundredths =
      int.parse(m[1]!) * 100 + int.parse((m[2] ?? '').padRight(2, '0'));
  if (hundredths > 10000) return null;
  return (base * hundredths + 5000) ~/ 10000;
}

/// [quantity] thousandths × [cents], rounded half up to the cent.
int timesQuantity(int quantity, int cents) =>
    (quantity ~/ 1000) * cents + ((quantity % 1000) * cents + 500) ~/ 1000;

/// Quantity × price − discount.
int lineTotal(int quantity, int unitPrice, int discount) =>
    timesQuantity(quantity, unitPrice) - discount;

/// What a cash payment records and the change: only what was due.
({int recorded, int change}) cashPayment(int typed, int due) => typed > due
    ? (recorded: due, change: typed - due)
    : (recorded: typed, change: 0);

/// One installment of a sale on credit.
class Installment {
  const Installment({
    this.id,
    required this.number,
    required this.due,
    required this.amount,
  });

  final int? id;
  final int number;

  /// "AAAA-MM-DD".
  final String due;
  final int amount;
}

/// [day] plus [months], on the last day of the month when it is shorter
/// (31/01 + 1 month = 28/02).
DateTime addMonths(DateTime day, int months) {
  final first = DateTime(day.year, day.month + months);
  final last = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, day.day > last ? last : day.day);
}

/// [amount] in [count] equal installments, the leftover cents in the first,
/// due monthly from [first].
List<Installment> splitInstallments(int amount, int count, DateTime first) {
  final part = amount ~/ count;
  final rest = amount - part * count;
  return [
    for (var i = 0; i < count; i++)
      Installment(
        number: i + 1,
        due: isoDay(addMonths(first, i)),
        amount: i == 0 ? part + rest : part,
      ),
  ];
}

/// How much of each installment [received] covers, oldest due first
/// The result follows the order of [installments].
List<int> allocate(List<Installment> installments, int received) {
  final order = [for (var i = 0; i < installments.length; i++) i]
    ..sort((a, b) {
      final byDue = installments[a].due.compareTo(installments[b].due);
      return byDue != 0
          ? byDue
          : installments[a].number.compareTo(installments[b].number);
    });
  final paid = List.filled(installments.length, 0);
  var left = received;
  for (final i in order) {
    final take = left < installments[i].amount ? left : installments[i].amount;
    paid[i] = take < 0 ? 0 : take;
    left -= paid[i];
  }
  return paid;
}

/// "venceu há 3 dias", "venceu ontem", "vence hoje", "vence amanhã",
/// "vence em 5 dias".
String dueLabel(String due, DateTime today) {
  final [y, m, d] = due.split('-').map(int.parse).toList();
  final days = DateTime.utc(
    y,
    m,
    d,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  return switch (days) {
    < -1 => 'venceu há ${-days} dias',
    -1 => 'venceu ontem',
    0 => 'vence hoje',
    1 => 'vence amanhã',
    _ => 'vence em $days dias',
  };
}

enum SaleStatus { paid, open, overdue, canceled }

const saleStatusLabels = {
  SaleStatus.paid: 'Paga',
  SaleStatus.open: 'Em aberto',
  SaleStatus.overdue: 'Vencida',
  SaleStatus.canceled: 'Cancelada',
};

/// The situation of a sale on [today]: never stored.
SaleStatus saleStatus({
  required bool canceled,
  required List<Installment> installments,
  required int receipts,
  required DateTime today,
}) {
  if (canceled) return SaleStatus.canceled;
  final paid = allocate(installments, receipts);
  final day = isoDay(today);
  var open = false;
  for (var i = 0; i < installments.length; i++) {
    if (paid[i] >= installments[i].amount) continue;
    if (installments[i].due.compareTo(day) < 0) return SaleStatus.overdue;
    open = true;
  }
  return open ? SaleStatus.open : SaleStatus.paid;
}
