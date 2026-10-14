import '../products/money.dart';
import '../products/pricing.dart';
import 'sale_math.dart';
import 'sales_repository.dart';

String _day(DateTime d) => formatDay(isoDay(d));

/// The text put in the client's conversation. The user
/// reviews it and taps send; the app never sends it.
String saleSummary(Sale s) {
  final lines = <String>['Pedido nº ${s.number} – ${_day(s.soldAt)}', ''];
  for (final i in s.items) {
    final discount = i.discount > 0
        ? ' (desconto ${formatMoney(i.discount)})'
        : '';
    lines.add(
      '${formatQuantity(i.quantity)} ${i.unit} × ${i.description}: '
      '${formatMoney(i.total)}$discount',
    );
  }
  lines.add('');
  if (s.discount > 0) lines.add('Desconto: ${formatMoney(s.discount)}');
  if (s.freight > 0) lines.add('Frete: ${formatMoney(s.freight)}');
  lines.add('Total: ${formatMoney(s.total)}');
  final paid = [
    for (final p in s.validPayments)
      if (!p.receipt) '${payMethodLabels[p.method]} ${formatMoney(p.amount)}',
  ];
  if (paid.isNotEmpty) lines.add('Pago: ${paid.join('; ')}');
  if (s.installments.isNotEmpty) {
    final n = s.installments.length;
    lines.add(n == 1 ? 'A prazo:' : 'A prazo, em $n parcelas:');
    for (final i in s.installments) {
      lines.add(
        '${i.number}ª ${formatMoney(i.amount)} – vence ${formatDay(i.due)}',
      );
    }
  }
  return lines.join('\n');
}
