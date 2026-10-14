import 'package:flutter/material.dart';

import '../products/money.dart';
import '../products/pricing.dart' show isoDay;
import '../sales/sales_repository.dart';
import '../sales/sales_screen.dart' show saleDay;
import '../theme/components.dart';
import '../theme/status_colors.dart';

/// A client's numbers at a glance, from their sales.
class ClientSummary {
  const ClientSummary({
    this.bought = 0,
    this.purchases = 0,
    this.owes = 0,
    this.overdue = 0,
    this.lastPurchase,
  });

  /// What the client bought, canceled sales left out.
  final int bought;
  final int purchases;

  /// What is left to receive, and the part of it already overdue.
  final int owes;
  final int overdue;
  final DateTime? lastPurchase;

  /// The average purchase.
  int get ticket => purchases == 0 ? 0 : bought ~/ purchases;

  factory ClientSummary.of(List<Sale> sales, DateTime today) {
    final todayIso = isoDay(today);
    var bought = 0, purchases = 0, owes = 0, overdue = 0;
    DateTime? last;
    for (final s in sales) {
      if (s.canceled) continue;
      bought += s.total;
      purchases++;
      owes += s.open;
      if (last == null || s.soldAt.isAfter(last)) last = s.soldAt;
      final paid = s.installmentPaid;
      for (final (i, inst) in s.installments.indexed) {
        final left = inst.amount - paid[i];
        if (left > 0 && inst.due.compareTo(todayIso) < 0) overdue += left;
      }
    }
    return ClientSummary(
      bought: bought,
      purchases: purchases,
      owes: owes,
      overdue: overdue,
      lastPurchase: last,
    );
  }

  /// The client's sales still to receive, the oldest first.
  static List<Sale> openSales(List<Sale> sales) =>
      [
        for (final s in sales)
          if (s.open > 0) s,
      ]..sort((a, b) {
        final byDay = a.soldAt.compareTo(b.soldAt);
        return byDay != 0 ? byDay : a.number.compareTo(b.number);
      });
}

/// The numbers of [summary]: what the client owes, with the
/// overdue part in evidence, and what they bought.
class ClientNumbers extends StatelessWidget {
  const ClientNumbers(this.summary, {super.key});

  final ClientSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.owes > 0)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text('Deve', style: t.bodyMedium!.copyWith(color: muted)),
              MoneyText(formatMoney(s.owes), small: true),
              if (s.overdue > 0)
                StatusPill(
                  'Vencido ${formatMoney(s.overdue)}',
                  Situation.overdue,
                ),
            ],
          )
        else if (s.purchases > 0)
          const StatusPill('Nada a receber', Situation.ok),
        const SizedBox(height: 8),
        Text(
          s.purchases == 0
              ? 'Nenhuma compra ainda.'
              : 'Comprou ${formatMoney(s.bought)} em '
                    '${plural(s.purchases, 'compra', 'compras')}'
                    ' · ticket médio ${formatMoney(s.ticket)}'
                    ' · última em ${saleDay(s.lastPurchase!)}',
          style: t.bodyMedium!.copyWith(color: muted),
        ),
      ],
    );
  }
}
