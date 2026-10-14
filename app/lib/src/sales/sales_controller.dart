import 'package:flutter/foundation.dart';

import '../products/pricing.dart';
import '../search/text.dart';
import 'sale_math.dart';
import 'sales_repository.dart';

/// The period of the sales list.
enum SalePeriod { today, week, month, lastMonth, all }

const salePeriodLabels = {
  SalePeriod.today: 'Hoje',
  SalePeriod.week: 'Últimos 7 dias',
  SalePeriod.month: 'Este mês',
  SalePeriod.lastMonth: 'Mês passado',
  SalePeriod.all: 'Todo o período',
};

/// An installment still open.
class Receivable {
  const Receivable({
    required this.sale,
    required this.installment,
    required this.left,
    required this.overdue,
  });

  final Sale sale;
  final Installment installment;
  final int left;
  final bool overdue;
}

/// The sales list with search, filters and totals, and what is left to
/// receive.
class SalesController extends ChangeNotifier {
  SalesController({
    required this._repo,
    DateTime Function()? clock,
    this.clientId,
  }) : _clock = clock ?? DateTime.now;

  final SalesRepository _repo;
  final DateTime Function() _clock;

  /// Only this client's sales ("Ver todas" on the client page).
  final int? clientId;

  List<Sale> all = const [];
  String query = '';
  SalePeriod period = SalePeriod.all;
  final Set<SaleStatus> statuses = {};

  DateTime get today => _clock();

  Future<void> load() async {
    all = clientId == null
        ? await _repo.list()
        : await _repo.byClient(clientId!);
    notifyListeners();
  }

  bool _inPeriod(DateTime soldAt) {
    final now = today;
    final day = DateTime(soldAt.year, soldAt.month, soldAt.day);
    final start = DateTime(now.year, now.month, now.day);
    return switch (period) {
      SalePeriod.all => true,
      SalePeriod.today => day == start,
      SalePeriod.week =>
        !day.isBefore(start.subtract(const Duration(days: 6))) &&
            !day.isAfter(start),
      SalePeriod.month => soldAt.year == now.year && soldAt.month == now.month,
      SalePeriod.lastMonth => () {
        final last = DateTime(now.year, now.month - 1);
        return soldAt.year == last.year && soldAt.month == last.month;
      }(),
    };
  }

  bool _matches(Sale s) {
    if (query.trim().isEmpty) return true;
    final text = [
      '${s.number}',
      s.clientLabel,
      for (final i in s.items) i.description,
    ].join(' ');
    return textMatches(text, query);
  }

  /// The sales shown, newest first.
  List<Sale> get sales {
    final now = today;
    return [
      for (final s in all)
        if (_inPeriod(s.soldAt) &&
            _matches(s) &&
            (statuses.isEmpty || statuses.contains(s.status(now))))
          s,
    ];
  }

  /// Totals of the sales shown; canceled ones do not count.
  ({int sold, int received, int open, int profit}) get totals {
    var sold = 0, received = 0, open = 0, profit = 0;
    for (final s in sales) {
      if (s.canceled) continue;
      sold += s.total;
      received += s.received;
      open += s.open;
      profit += s.profit;
    }
    return (sold: sold, received: received, open: open, profit: profit);
  }

  /// Open installments: overdue first, then by due date.
  List<Receivable> get receivables {
    final day = isoDay(today);
    final out = <Receivable>[];
    for (final s in all) {
      if (s.canceled) continue;
      final paid = s.installmentPaid;
      for (var i = 0; i < s.installments.length; i++) {
        final left = s.installments[i].amount - paid[i];
        if (left <= 0) continue;
        out.add(
          Receivable(
            sale: s,
            installment: s.installments[i],
            left: left,
            overdue: s.installments[i].due.compareTo(day) < 0,
          ),
        );
      }
    }
    out.sort((a, b) {
      if (a.overdue != b.overdue) return a.overdue ? -1 : 1;
      final byDue = a.installment.due.compareTo(b.installment.due);
      return byDue != 0 ? byDue : a.sale.number.compareTo(b.sale.number);
    });
    return out;
  }

  ({int open, int overdue}) get receivableTotals {
    var open = 0, overdue = 0;
    for (final r in receivables) {
      open += r.left;
      if (r.overdue) overdue += r.left;
    }
    return (open: open, overdue: overdue);
  }

  void search(String text) {
    query = text;
    notifyListeners();
  }

  void setPeriod(SalePeriod value) {
    period = value;
    notifyListeners();
  }

  void toggleStatus(SaleStatus status) {
    if (!statuses.remove(status)) statuses.add(status);
    notifyListeners();
  }
}
