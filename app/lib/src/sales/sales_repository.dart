import 'package:drift/drift.dart';

import '../products/products_repository.dart' show MoveKind, moveForSale;
import '../storage/app_database.dart';
import 'sale_math.dart';

/// One item of a sale, as it was when sold.
class SaleItem {
  const SaleItem({
    this.id,
    required this.variantId,
    required this.description,
    this.unit = 'UN',
    this.isService = false,
    required this.quantity,
    required this.unitPrice,
    this.discount = 0,
    this.unitCost = 0,
  });

  final int? id;

  /// Null for a quick sale's item, which has no product.
  final int? variantId;

  /// "Camiseta (Azul / P)".
  final String description;
  final String unit;
  final bool isService;

  /// Thousandths.
  final int quantity;
  final int unitPrice;
  final int discount;

  /// The variation's average cost when sold; set by the repository.
  final int unitCost;

  int get total => lineTotal(quantity, unitPrice, discount);
  int get cost => timesQuantity(quantity, unitCost);
}

/// Paid at the sale, or a [receipt] received later.
class SalePayment {
  const SalePayment({
    this.id,
    this.receipt = false,
    required this.method,
    required this.amount,
    required this.at,
    this.voided = false,
  });

  final int? id;
  final bool receipt;
  final PayMethod method;
  final int amount;
  final DateTime at;

  /// Reversed by the cancellation of the sale.
  final bool voided;
}

/// A sale.
class Sale {
  const Sale({
    this.id,
    this.number = 0,
    this.clientId,
    this.clientName = '',
    this.clientRemoved = false,
    required this.soldAt,
    required this.items,
    this.discount = 0,
    this.freight = 0,
    this.note = '',
    this.payments = const [],
    this.installments = const [],
    this.canceledAt,
    this.cancelReason = '',
  });

  final int? id;
  final int number;
  final int? clientId;

  /// The client's current name; empty without a client.
  final String clientName;
  final bool clientRemoved;
  final DateTime soldAt;
  final List<SaleItem> items;
  final int discount;
  final int freight;
  final String note;
  final List<SalePayment> payments;
  final List<Installment> installments;
  final DateTime? canceledAt;
  final String cancelReason;

  bool get canceled => canceledAt != null;
  int get itemsTotal => items.fold(0, (sum, i) => sum + i.total);

  /// Items − discount + freight.
  int get total => itemsTotal - discount + freight;
  int get cost => items.fold(0, (sum, i) => sum + i.cost);

  /// Items with discounts − cost; the freight is not profit.
  int get profit => itemsTotal - discount - cost;

  List<SalePayment> get validPayments => [
    for (final p in payments)
      if (!p.voided) p,
  ];
  int get received => validPayments.fold(0, (sum, p) => sum + p.amount);
  int get receipts =>
      validPayments.where((p) => p.receipt).fold(0, (sum, p) => sum + p.amount);
  int get onCredit => installments.fold(0, (sum, i) => sum + i.amount);

  /// What is left to receive.
  int get open {
    if (canceled) return 0;
    final left = onCredit - receipts;
    return left > 0 ? left : 0;
  }

  /// How much of each installment was received, in order.
  List<int> get installmentPaid => allocate(installments, receipts);

  SaleStatus status(DateTime today) => saleStatus(
    canceled: canceled,
    installments: installments,
    receipts: receipts,
    today: today,
  );

  String get clientLabel => clientName.isNotEmpty
      ? clientName
      : clientRemoved
      ? 'Cliente apagado'
      : 'Consumidor final';
}

/// More than what is left to receive, or nothing.
class InvalidReceipt implements Exception {
  const InvalidReceipt();
}

/// Sales in app.db.
abstract interface class SalesRepository {
  /// Every sale, newest first.
  Future<List<Sale>> list();
  Future<Sale?> byId(int id);
  Future<List<Sale>> byClient(int clientId);

  /// Concludes [sale] (without id) in one transaction: the next number,
  /// the items with their cost of now, the payments, the installments and
  /// the stock movements. Returns the id. Payments plus installments must
  /// add up to the total, and installments need a client.
  Future<int> conclude(Sale sale);

  /// Throws [InvalidReceipt] for more than what is left, or nothing.
  Future<void> receive(int saleId, PayMethod method, int amount, DateTime at);

  /// Deletes a receipt typed by mistake.
  Future<void> undoReceipt(int paymentId);

  /// The stock comes back and the payments are reversed.
  Future<void> cancel(int saleId, {String reason = ''});
}

class DriftSalesRepository implements SalesRepository {
  DriftSalesRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  static DateTime _time(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

  Future<List<Sale>> _load({int? id, int? clientId}) async {
    final db = _db;
    final s = db.sales, c = db.clients;
    final query = db.select(s).join([
      leftOuterJoin(c, c.id.equalsExp(s.clientId)),
    ])..orderBy([OrderingTerm.desc(s.soldAt), OrderingTerm.desc(s.number)]);
    if (id != null) query.where(s.id.equals(id));
    if (clientId != null) query.where(s.clientId.equals(clientId));
    final rows = await query.get();
    if (rows.isEmpty) return const [];
    final ids = [for (final r in rows) r.readTable(s).id];

    final items = <int, List<SaleItem>>{};
    for (final i
        in await (db.select(db.saleItems)
              ..where((i) => i.saleId.isIn(ids))
              ..orderBy([(i) => OrderingTerm(expression: i.id)]))
            .get()) {
      (items[i.saleId] ??= []).add(
        SaleItem(
          id: i.id,
          variantId: i.variantId,
          description: i.description,
          unit: i.unit,
          isService: i.isService,
          quantity: i.quantity,
          unitPrice: i.unitPrice,
          discount: i.discount,
          unitCost: i.unitCost,
        ),
      );
    }
    final payments = <int, List<SalePayment>>{};
    for (final p
        in await (db.select(db.salePayments)
              ..where((p) => p.saleId.isIn(ids))
              ..orderBy([
                (p) => OrderingTerm(expression: p.paidAt),
                (p) => OrderingTerm(expression: p.id),
              ]))
            .get()) {
      (payments[p.saleId] ??= []).add(
        SalePayment(
          id: p.id,
          receipt: p.kind == 'receipt',
          method: PayMethod.values.byName(p.method),
          amount: p.amount,
          at: _time(p.paidAt),
          voided: p.voided,
        ),
      );
    }
    final installments = <int, List<Installment>>{};
    for (final i
        in await (db.select(db.saleInstallments)
              ..where((i) => i.saleId.isIn(ids))
              ..orderBy([(i) => OrderingTerm(expression: i.number)]))
            .get()) {
      (installments[i.saleId] ??= []).add(
        Installment(
          id: i.id,
          number: i.number,
          due: i.dueDate,
          amount: i.amount,
        ),
      );
    }
    return [
      for (final r in rows)
        if (r.readTable(s) case final sale)
          Sale(
            id: sale.id,
            number: sale.number,
            clientId: sale.clientId,
            clientName: r.readTableOrNull(c)?.name ?? '',
            clientRemoved: sale.clientRemoved,
            soldAt: _time(sale.soldAt),
            items: items[sale.id] ?? const [],
            discount: sale.discount,
            freight: sale.freight,
            note: sale.note,
            payments: payments[sale.id] ?? const [],
            installments: installments[sale.id] ?? const [],
            canceledAt: sale.canceledAt == null
                ? null
                : _time(sale.canceledAt!),
            cancelReason: sale.cancelReason,
          ),
    ];
  }

  @override
  Future<List<Sale>> list() => _load();

  @override
  Future<Sale?> byId(int id) async {
    final found = await _load(id: id);
    return found.isEmpty ? null : found.first;
  }

  @override
  Future<List<Sale>> byClient(int clientId) => _load(clientId: clientId);

  @override
  Future<int> conclude(Sale sale) {
    if (sale.items.isEmpty) throw ArgumentError('a sale needs items');
    final paid = sale.payments.fold(0, (sum, p) => sum + p.amount);
    if (paid + sale.onCredit != sale.total) {
      throw ArgumentError('payments must add up to the total');
    }
    if (sale.installments.isNotEmpty && sale.clientId == null) {
      throw ArgumentError('a sale on credit needs a client');
    }
    final db = _db;
    final now = _clock().millisecondsSinceEpoch;
    return db.transaction(() async {
      final last = await db
          .customSelect(
            'SELECT COALESCE(MAX(number), 0) AS n FROM sales',
            readsFrom: {db.sales},
          )
          .getSingle();
      // The cost of now, from each variation.
      final costs = <int, int>{
        for (final v
            in await (db.select(db.productVariants)..where(
                  (v) => v.id.isIn([for (final i in sale.items) ?i.variantId]),
                ))
                .get())
          v.id: v.cost,
      };
      final items = [
        for (final i in sale.items)
          SaleItem(
            variantId: i.variantId,
            description: i.description,
            unit: i.unit,
            isService: i.isService,
            quantity: i.quantity,
            unitPrice: i.unitPrice,
            discount: i.discount,
            unitCost: costs[i.variantId] ?? 0,
          ),
      ];
      final id = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              number: last.read<int>('n') + 1,
              clientId: Value(sale.clientId),
              soldAt: sale.soldAt.millisecondsSinceEpoch,
              discount: Value(sale.discount),
              freight: Value(sale.freight),
              total: sale.total,
              cost: items.fold(0, (sum, i) => sum + i.cost),
              note: Value(sale.note),
              createdAt: now,
            ),
          );
      for (final i in items) {
        await db
            .into(db.saleItems)
            .insert(
              SaleItemsCompanion.insert(
                saleId: id,
                variantId: Value(i.variantId),
                description: i.description,
                unit: i.unit,
                isService: Value(i.isService),
                quantity: i.quantity,
                unitPrice: i.unitPrice,
                discount: Value(i.discount),
                unitCost: Value(i.unitCost),
              ),
            );
        // An item without a product moves no stock.
        if (i.variantId case final variant?) {
          await moveForSale(
            db,
            variantId: variant,
            kind: MoveKind.sale,
            delta: -i.quantity,
            saleId: id,
            at: now,
          );
        }
      }
      for (final p in sale.payments) {
        await db
            .into(db.salePayments)
            .insert(
              SalePaymentsCompanion.insert(
                saleId: id,
                kind: 'sale',
                method: p.method.name,
                amount: p.amount,
                paidAt: p.at.millisecondsSinceEpoch,
              ),
            );
      }
      for (final i in sale.installments) {
        await db
            .into(db.saleInstallments)
            .insert(
              SaleInstallmentsCompanion.insert(
                saleId: id,
                number: i.number,
                dueDate: i.due,
                amount: i.amount,
              ),
            );
      }
      return id;
    });
  }

  @override
  Future<void> receive(int saleId, PayMethod method, int amount, DateTime at) =>
      _db.transaction(() async {
        final sale = await byId(saleId);
        if (sale == null || sale.canceled) throw StateError('no open sale');
        if (amount <= 0 || amount > sale.open) throw const InvalidReceipt();
        await _db
            .into(_db.salePayments)
            .insert(
              SalePaymentsCompanion.insert(
                saleId: saleId,
                kind: 'receipt',
                method: method.name,
                amount: amount,
                paidAt: at.millisecondsSinceEpoch,
              ),
            );
      });

  @override
  Future<void> undoReceipt(int paymentId) => _db.transaction(() async {
    final p = await (_db.select(
      _db.salePayments,
    )..where((p) => p.id.equals(paymentId))).getSingle();
    final sale = await byId(p.saleId);
    if (p.kind != 'receipt' || p.voided || sale == null || sale.canceled) {
      throw StateError('only a receipt of an open sale can be undone');
    }
    await (_db.delete(
      _db.salePayments,
    )..where((r) => r.id.equals(paymentId))).go();
  });

  @override
  Future<void> cancel(int saleId, {String reason = ''}) =>
      _db.transaction(() async {
        final sale = await byId(saleId);
        if (sale == null || sale.canceled) throw StateError('not cancelable');
        final now = _clock().millisecondsSinceEpoch;
        await (_db.update(_db.sales)..where((s) => s.id.equals(saleId))).write(
          SalesCompanion(canceledAt: Value(now), cancelReason: Value(reason)),
        );
        await (_db.update(_db.salePayments)
              ..where((p) => p.saleId.equals(saleId)))
            .write(const SalePaymentsCompanion(voided: Value(true)));
        for (final i in sale.items) {
          if (i.variantId == null) continue; // no stock
          await moveForSale(
            _db,
            variantId: i.variantId!,
            kind: MoveKind.saleCancel,
            delta: i.quantity,
            saleId: saleId,
            at: now,
          );
        }
      });
}

/// What each client owes, from [sales] at [today]: the amount left and
/// whether some of it is overdue.
Map<int, ({int open, bool overdue})> debtsByClient(
  List<Sale> sales,
  DateTime today,
) {
  final out = <int, ({int open, bool overdue})>{};
  for (final s in sales) {
    final id = s.clientId;
    if (id == null || s.open == 0) continue;
    final was = out[id] ?? (open: 0, overdue: false);
    out[id] = (
      open: was.open + s.open,
      overdue: was.overdue || s.status(today) == SaleStatus.overdue,
    );
  }
  return out;
}

/// How long without buying makes a client "sumido".
const goneAfterDays = 60;

/// The clients who bought before and whose last purchase (canceled ones
/// left out) was more than [goneAfterDays] days before [today].
Set<int> goneClients(List<Sale> sales, DateTime today) {
  final last = <int, DateTime>{};
  for (final s in sales) {
    final id = s.clientId;
    if (id == null || s.canceled) continue;
    if (last[id] case final was? when !s.soldAt.isAfter(was)) continue;
    last[id] = s.soldAt;
  }
  final day = DateTime(today.year, today.month, today.day);
  return {
    for (final MapEntry(:key, :value) in last.entries)
      if (day.difference(DateTime(value.year, value.month, value.day)).inDays >
          goneAfterDays)
        key,
  };
}
