import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../products/money.dart';
import '../sales/sale_math.dart';
import '../sales/sales_repository.dart';
import '../sales/sales_screen.dart' show saleDay, saleStatusPill;
import '../theme/components.dart';
import 'clients_repository.dart';

/// One event in a client's story.
sealed class TimelineEvent {
  const TimelineEvent();
  DateTime get at;
}

class PurchaseEvent extends TimelineEvent {
  const PurchaseEvent(this.sale);
  final Sale sale;
  @override
  DateTime get at => sale.soldAt;
}

class ReceiptEvent extends TimelineEvent {
  const ReceiptEvent(this.sale, this.payment);
  final Sale sale;
  final SalePayment payment;
  @override
  DateTime get at => payment.at;
}

class CancelEvent extends TimelineEvent {
  const CancelEvent(this.sale);
  final Sale sale;
  @override
  DateTime get at => sale.canceledAt!;
}

class NoteEvent extends TimelineEvent {
  const NoteEvent(this.note);
  final ClientNote note;
  @override
  DateTime get at => note.at;
}

/// Purchases, receipts (not reversed), cancellations and notes, newest
/// first. What was paid at the sale is part of the purchase.
List<TimelineEvent> buildTimeline(List<Sale> sales, List<ClientNote> notes) {
  final events = <TimelineEvent>[
    for (final s in sales) ...[
      PurchaseEvent(s),
      for (final p in s.payments)
        if (p.receipt && !p.voided) ReceiptEvent(s, p),
      if (s.canceled) CancelEvent(s),
    ],
    for (final n in notes) NoteEvent(n),
  ];
  // Stable: the same moment keeps the order above.
  final indexed = events.indexed.toList()
    ..sort((a, b) {
      final byTime = b.$2.at.compareTo(a.$2.at);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
  return [for (final (_, e) in indexed) e];
}

/// One line of the timeline.
class TimelineTile extends StatelessWidget {
  const TimelineTile({
    super.key,
    required this.event,
    required this.today,
    this.onOpenSale,
    this.onDeleteNote,
    this.noteTime,
  });

  final TimelineEvent event;
  final DateTime today;
  final ValueChanged<Sale>? onOpenSale;
  final ValueChanged<ClientNote>? onDeleteNote;

  /// How a note's time reads ("02/10/2026 09:05").
  final String Function(DateTime)? noteTime;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget icon(IconData data) => CircleAvatar(
      radius: 20,
      backgroundColor: colors.surfaceContainerHigh,
      foregroundColor: colors.onSurfaceVariant,
      child: Icon(data, size: 20),
    );
    return switch (event) {
      PurchaseEvent(:final sale) => AppListTile(
        leading: icon(Symbols.shopping_bag_rounded),
        title: Text('Compra nº ${sale.number}'),
        subtitle: Text(saleDay(sale.soldAt)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatMoney(sale.total), style: tabular),
            const SizedBox(height: 2),
            saleStatusPill(sale.status(today)),
          ],
        ),
        onTap: onOpenSale == null ? null : () => onOpenSale!(sale),
      ),
      ReceiptEvent(:final sale, :final payment) => AppListTile(
        leading: icon(Symbols.payments_rounded),
        title: Text('Recebido ${formatMoney(payment.amount)}'),
        subtitle: Text(
          '${payMethodLabels[payment.method]} · venda nº ${sale.number} · '
          '${saleDay(payment.at)}',
        ),
        onTap: onOpenSale == null ? null : () => onOpenSale!(sale),
      ),
      CancelEvent(:final sale) => AppListTile(
        leading: icon(Symbols.block_rounded),
        title: Text('Venda nº ${sale.number} cancelada'),
        subtitle: Text(
          [
            saleDay(sale.canceledAt!),
            if (sale.cancelReason.isNotEmpty) sale.cancelReason,
          ].join(' · '),
        ),
        onTap: onOpenSale == null ? null : () => onOpenSale!(sale),
      ),
      NoteEvent(:final note) => AppListTile(
        leading: icon(Symbols.sticky_note_2_rounded),
        title: Text(note.body),
        subtitle: Text(noteTime?.call(note.at) ?? saleDay(note.at)),
        trailing: onDeleteNote == null
            ? null
            : IconButton(
                tooltip: 'Apagar anotação',
                icon: const Icon(Symbols.close_rounded),
                onPressed: () => onDeleteNote!(note),
              ),
      ),
    };
  }
}
