import 'package:flutter/material.dart';

import '../clients/client_summary.dart';
import '../products/money.dart';
import '../products/pricing.dart';
import '../theme/components.dart';
import '../theme/form_parts.dart';
import '../theme/motion.dart';
import '../theme/status_colors.dart';
import 'sale_math.dart';
import 'sales_repository.dart';
import 'sales_screen.dart' show saleDay;

/// A receipt typed in the dialog: amount, method and day.
typedef Receipt = ({int amount, PayMethod method, DateTime at});

/// What is left of the first installment not paid yet, or the whole open
/// amount: the value the dialog starts with.
int nextAmount(Sale s) {
  final paid = s.installmentPaid;
  for (var i = 0; i < s.installments.length; i++) {
    final left = s.installments[i].amount - paid[i];
    if (left > 0) return left;
  }
  return s.open;
}

/// Asks the value, method and date of a receipt of [sale]; null when cancelled.
Future<Receipt?> askReceipt(BuildContext context, Sale sale, DateTime today) =>
    showDialog<Receipt>(
      context: context,
      builder: (_) =>
          _ReceiveDialog(open: sale.open, next: nextAmount(sale), today: today),
    );

/// "Receber" from a client: picks among their open sales,
/// the oldest first (straight to it when there is only one), then the same
/// receipt as on the sale's page. True when a receipt was registered.
Future<bool> receiveFromClient(
  BuildContext context, {
  required SalesRepository sales,
  required int clientId,
  required DateTime today,
}) async {
  final open = ClientSummary.openSales(await sales.byClient(clientId));
  if (open.isEmpty || !context.mounted) return false;
  final sale = open.length == 1
      ? open.single
      : await showModalBottomSheet<Sale>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _OpenSales(sales: open, today: today),
        );
  if (sale == null || !context.mounted) return false;
  final receipt = await askReceipt(context, sale, today);
  if (receipt == null) return false;
  await sales.receive(sale.id!, receipt.method, receipt.amount, receipt.at);
  Haptics.success();
  return true;
}

/// "Qual venda?": the client's open sales with what is left of each.
class _OpenSales extends StatelessWidget {
  const _OpenSales({required this.sales, required this.today});

  final List<Sale> sales;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.only(
        bottom: 16 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            'Receber de qual venda?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        for (final s in sales)
          AppListTile(
            title: Text('Venda nº ${s.number} · ${saleDay(s.soldAt)}'),
            subtitle: Text('Falta ${formatMoney(s.open)}', style: tabular),
            trailing: s.status(today) == SaleStatus.overdue
                ? const StatusPill('Vencida', Situation.overdue)
                : const StatusPill('Em aberto', Situation.open),
            onTap: () => Navigator.pop(context, s),
          ),
      ],
    );
  }
}

/// Value, method and date of a receipt. Owns its fields,
/// so they live until the dialog is gone.
class _ReceiveDialog extends StatefulWidget {
  const _ReceiveDialog({
    required this.open,
    required this.next,
    required this.today,
  });

  final int open;
  final int next;
  final DateTime today;

  @override
  State<_ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<_ReceiveDialog> {
  late final _amount = moneyController(widget.next);
  late final _day = TextEditingController(text: saleDay(widget.today));
  var _method = PayMethod.pix;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _day.dispose();
    super.dispose();
  }

  void _done() {
    final value = parseMoney(_amount.text);
    final iso = parseDay(_day.text);
    if (value == null || value <= 0 || value > widget.open) {
      setState(() => _error = 'Até ${formatMoney(widget.open)}.');
      return;
    }
    if (iso == null || iso.isEmpty) {
      setState(() => _error = 'Data inválida (dd/mm/aaaa).');
      return;
    }
    final [y, m, d] = iso.split('-').map(int.parse).toList();
    final now = widget.today;
    Navigator.pop<Receipt>(context, (
      amount: value,
      method: _method,
      at: DateTime(y, m, d, now.hour, now.minute),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Receber'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Falta ${formatMoney(widget.open)}'),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [Masks.money],
              decoration: InputDecoration(
                labelText: 'Valor',
                errorText: _error,
              ),
            ),
            DropdownButtonFormField<PayMethod>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Forma'),
              items: [
                for (final MapEntry(:key, :value) in payMethodLabels.entries)
                  DropdownMenuItem(value: key, child: Text(value)),
              ],
              onChanged: (m) => _method = m!,
            ),
            TextField(
              controller: _day,
              keyboardType: TextInputType.number,
              inputFormatters: [Masks.date],
              decoration: const InputDecoration(labelText: 'Data'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _done, child: const Text('Receber')),
      ],
    );
  }
}
