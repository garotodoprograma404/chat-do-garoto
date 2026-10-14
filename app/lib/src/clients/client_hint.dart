import '../products/pricing.dart' show isoDay;
import '../sales/sale_math.dart';
import '../sales/sales_repository.dart';
import 'clients_controller.dart' show daysUntilBirthday;
import 'clients_repository.dart';
import 'validation.dart';

const _weekdays = [
  'segunda',
  'terça',
  'quarta',
  'quinta',
  'sexta',
  'sábado',
  'domingo',
];

/// "vence hoje", "vence amanhã", "vence sexta, 10/10" within a week,
/// "vence dia 10/11" after.
String nextDueLabel(String due, DateTime today) {
  final [y, m, d] = due.split('-').map(int.parse).toList();
  final days = DateTime.utc(
    y,
    m,
    d,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  if (days <= 1) return dueLabel(due, today);
  final day = '${d.toString().padLeft(2, '0')}/${m.toString().padLeft(2, '0')}';
  if (days >= 7) return 'vence dia $day';
  return 'vence ${_weekdays[DateTime(y, m, d).weekday - 1]}, $day';
}

/// "Comprou hoje", "Comprou ontem", "Comprou há 12 dias".
String boughtLabel(DateTime at, DateTime today) {
  final days = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(at.year, at.month, at.day)).inDays;
  return switch (days) {
    <= 0 => 'Comprou hoje',
    1 => 'Comprou ontem',
    _ => 'Comprou há $days dias',
  };
}

/// The most useful line about a client in the list: the
/// oldest installment overdue, the next one due, a birthday within a
/// week, the last purchase or, without any of these, the phone.
String clientHint(Client client, List<Sale> sales, DateTime today) {
  final todayIso = isoDay(today);
  Installment? overdue, next;
  DateTime? last;
  for (final s in sales) {
    if (s.canceled) continue;
    if (last == null || s.soldAt.isAfter(last)) last = s.soldAt;
    if (s.open == 0) continue;
    final paid = s.installmentPaid;
    for (final (i, inst) in s.installments.indexed) {
      if (paid[i] >= inst.amount) continue;
      if (inst.due.compareTo(todayIso) < 0) {
        if (overdue == null || inst.due.compareTo(overdue.due) < 0) {
          overdue = inst;
        }
      } else if (next == null || inst.due.compareTo(next.due) < 0) {
        next = inst;
      }
    }
  }
  if (overdue != null) {
    return '${overdue.number}ª parcela ${dueLabel(overdue.due, today)}';
  }
  if (next != null) {
    return '${next.number}ª parcela ${nextDueLabel(next.due, today)}';
  }
  switch (daysUntilBirthday(client.birthday, today)) {
    case 0:
      return 'Aniversário hoje';
    case 1:
      return 'Aniversário amanhã';
    case final d? when d <= 7:
      return 'Aniversário em $d dias';
  }
  if (last != null) return boughtLabel(last, today);
  return formatPhone(client.phone);
}
