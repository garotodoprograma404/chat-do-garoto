import 'package:chat_do_garoto/src/sales/sale_math.dart';
import 'package:chat_do_garoto/src/sales/sales_repository.dart';

/// In-memory [SalesRepository] for screen tests. Stock is not touched.
class FakeSalesRepository implements SalesRepository {
  final sales = <int, Sale>{};

  /// Client names, for [Sale.clientName].
  final names = <int, String>{};
  var _next = 1, _payment = 1;
  DateTime now = DateTime(2026, 10, 2, 9);

  @override
  Future<List<Sale>> list() async => sales.values.toList()
    ..sort((a, b) {
      final byDay = b.soldAt.compareTo(a.soldAt);
      return byDay != 0 ? byDay : b.number.compareTo(a.number);
    });

  @override
  Future<Sale?> byId(int id) async => sales[id];

  @override
  Future<List<Sale>> byClient(int clientId) async => [
    for (final s in await list())
      if (s.clientId == clientId) s,
  ];

  Sale _copy(
    Sale s, {
    int? id,
    int? number,
    List<SalePayment>? payments,
    DateTime? canceledAt,
    String? cancelReason,
  }) => Sale(
    id: id ?? s.id,
    number: number ?? s.number,
    clientId: s.clientId,
    clientName: names[s.clientId] ?? '',
    soldAt: s.soldAt,
    items: s.items,
    discount: s.discount,
    freight: s.freight,
    note: s.note,
    payments: payments ?? s.payments,
    installments: s.installments,
    canceledAt: canceledAt ?? s.canceledAt,
    cancelReason: cancelReason ?? s.cancelReason,
  );

  @override
  Future<int> conclude(Sale sale) async {
    final paid = sale.payments.fold(0, (sum, p) => sum + p.amount);
    if (sale.items.isEmpty || paid + sale.onCredit != sale.total) {
      throw ArgumentError('does not add up');
    }
    if (sale.installments.isNotEmpty && sale.clientId == null) {
      throw ArgumentError('credit needs a client');
    }
    final id = _next++;
    sales[id] = _copy(
      sale,
      id: id,
      number: id,
      payments: [
        for (final p in sale.payments)
          SalePayment(
            id: _payment++,
            method: p.method,
            amount: p.amount,
            at: p.at,
          ),
      ],
    );
    return id;
  }

  @override
  Future<void> receive(
    int saleId,
    PayMethod method,
    int amount,
    DateTime at,
  ) async {
    final s = sales[saleId]!;
    if (s.canceled) throw StateError('canceled');
    if (amount <= 0 || amount > s.open) throw const InvalidReceipt();
    sales[saleId] = _copy(
      s,
      payments: [
        ...s.payments,
        SalePayment(
          id: _payment++,
          receipt: true,
          method: method,
          amount: amount,
          at: at,
        ),
      ],
    );
  }

  @override
  Future<void> undoReceipt(int paymentId) async {
    final s = sales.values.firstWhere(
      (s) => s.payments.any((p) => p.id == paymentId),
    );
    sales[s.id!] = _copy(
      s,
      payments: [
        for (final p in s.payments)
          if (p.id != paymentId) p,
      ],
    );
  }

  @override
  Future<void> cancel(int saleId, {String reason = ''}) async {
    final s = sales[saleId]!;
    sales[saleId] = _copy(
      s,
      canceledAt: now,
      cancelReason: reason,
      payments: [
        for (final p in s.payments)
          SalePayment(
            id: p.id,
            receipt: p.receipt,
            method: p.method,
            amount: p.amount,
            at: p.at,
            voided: true,
          ),
      ],
    );
  }
}
