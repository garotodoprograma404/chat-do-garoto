import '../products/money.dart';
import '../products/pricing.dart';
import 'sales_repository.dart';

/// The message "Cobrar" puts in the client's conversation:
/// the first name, what is open, the orders and the oldest due date. The
/// user reviews it and taps send; the app never sends it. Null when
/// nothing is open.
String? chargeMessage({
  required String name,
  required List<Sale> sales,
  required DateTime today,
}) {
  final open = [
    for (final s in sales)
      if (s.open > 0) s,
  ]..sort((a, b) => a.number.compareTo(b.number));
  if (open.isEmpty) return null;
  final total = open.fold(0, (sum, s) => sum + s.open);

  // The installments still to pay, the oldest due first.
  final dues = <String>[];
  for (final s in open) {
    final paid = s.installmentPaid;
    for (final (i, inst) in s.installments.indexed) {
      if (inst.amount - paid[i] > 0) dues.add(inst.due);
    }
  }
  dues.sort();

  final first = name.trim().split(RegExp(r'\s+')).first;
  final hello = first.isEmpty ? 'Oi! Tudo bem?' : 'Oi, $first! Tudo bem?';
  final numbers = [for (final s in open) 'nº ${s.number}'];
  final orders = numbers.length == 1
      ? 'do pedido ${numbers.single}'
      : 'dos pedidos ${numbers.sublist(0, numbers.length - 1).join(', ')} '
            'e ${numbers.last}';
  final lines = [
    '$hello Passando para lembrar do valor em aberto de '
        '${formatMoney(total)}, $orders.',
  ];
  if (dues.isNotEmpty) {
    final due = dues.first;
    final todayIso = isoDay(today);
    final which = dues.length == 1 ? 'A parcela' : 'A parcela mais antiga';
    lines.add(switch (due.compareTo(todayIso)) {
      < 0 => '$which venceu em ${formatDay(due)}.',
      0 => '$which vence hoje.',
      _ =>
        '${dues.length == 1 ? 'A parcela' : 'A próxima parcela'} vence em '
            '${formatDay(due)}.',
    });
  }
  lines.add('Qualquer dúvida, é só me chamar.');
  return lines.join(' ');
}
