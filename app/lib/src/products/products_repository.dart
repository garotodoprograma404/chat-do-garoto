import 'package:drift/drift.dart';

import '../storage/app_database.dart';
import 'pricing.dart';
import 'variants.dart';

enum ProductKind { product, service }

/// A variation of a product: the unit of stock. A product
/// without attributes has one, with no options.
class Variant {
  const Variant({
    this.id,
    this.options = const [],
    this.sku,
    this.barcode,
    this.price,
    this.cost = 0,
    this.stock = 0,
    this.active = true,
  });

  final int? id;

  /// One value per attribute of the product, in order.
  final List<String> options;
  final String? sku;
  final String? barcode;

  /// Null: the product's price.
  final int? price;

  /// The average cost, in cents.
  final int cost;

  /// Thousandths. For a new variation being saved, the initial stock;
  /// afterwards only movements change it.
  final int stock;
  final bool active;

  String get label => variantLabel(options);
}

/// "Vencido há 3 dias", "Vencido ontem", "Vence hoje", "Vence em 5 dias"
///; null without an expiry.
String? expiryLabel(Product p, DateTime today) => switch (p.expiresIn(today)) {
  null => null,
  < -1 && final d => 'Vencido há ${-d} dias',
  -1 => 'Vencido ontem',
  0 => 'Vence hoje',
  1 => 'Vence amanhã',
  final d => 'Vence em $d dias',
};

/// How many days before the expiry a product shows as "Vencendo"
const expiryWarningDays = 30;

/// A product or service of the catalog.
class Product {
  const Product({
    this.id,
    this.kind = ProductKind.product,
    required this.name,
    this.sku,
    this.barcode,
    this.category = '',
    this.brand = '',
    this.supplier = '',
    this.unit = 'UN',
    this.description = '',
    required this.price,
    this.promoPrice,
    this.promoUntil,
    this.expiresOn,
    this.minStock = 0,
    this.active = true,
    this.attributes = const [],
    this.variants = const [],
    this.tiers = const [],
    this.photoIds = const [],
    this.createdAt,
  });

  final int? id;
  final ProductKind kind;
  final String name;
  final String? sku;
  final String? barcode;
  final String category;
  final String brand;
  final String supplier;
  final String unit;
  final String description;

  /// Cents.
  final int price;
  final int? promoPrice;

  /// "AAAA-MM-DD", inclusive; null for no end.
  final String? promoUntil;

  /// The current batch's expiry, "AAAA-MM-DD"; null when it does not
  /// apply.
  final String? expiresOn;

  /// Thousandths; applies to each variation.
  final int minStock;
  final bool active;
  final List<Attribute> attributes;
  final List<Variant> variants;
  final List<WholesaleTier> tiers;

  /// In order; the first is the main photo.
  final List<int> photoIds;

  /// Set by the repository.
  final DateTime? createdAt;

  bool get isService => kind == ProductKind.service;
  bool get hasVariants => attributes.isNotEmpty;
  List<Variant> get activeVariants => [
    for (final v in variants)
      if (v.active) v,
  ];

  /// The stock of the active variations.
  int get stock =>
      isService ? 0 : activeVariants.fold(0, (sum, v) => sum + v.stock);

  /// Zero or negative.
  bool get outOfStock => !isService && stock <= 0;

  /// Some active variation at the minimum or below.
  bool get lowStock =>
      !isService &&
      !outOfStock &&
      minStock > 0 &&
      activeVariants.any((v) => v.stock <= minStock);

  bool promoOn(DateTime today) => promoActive(promoPrice, promoUntil, today);

  /// Days from [today] to the expiry (negative when expired); null without
  /// one.
  int? expiresIn(DateTime today) {
    final d = expiresOn;
    if (d == null || d.isEmpty) return null;
    final [y, m, day] = d.split('-').map(int.parse).toList();
    return DateTime(
      y,
      m,
      day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
  }

  /// "Vencendo": active, and expired or expiring within
  /// [expiryWarningDays].
  bool expiringSoon(DateTime today) =>
      active &&
      (expiresIn(today) ?? expiryWarningDays + 1) <= expiryWarningDays;

  /// The price of [v] that applies.
  int priceOf(Variant v, DateTime today, {int quantity = 1000}) => priceFor(
    price: v.price ?? price,
    promoPrice: promoPrice,
    promoUntil: promoUntil,
    tiers: tiers,
    quantity: quantity,
    today: today,
  );

  /// The prices of the active variations today, lowest first.
  List<int> pricesToday(DateTime today) {
    final shown = activeVariants.isEmpty ? variants : activeVariants;
    final prices = {
      for (final v in shown) priceOf(v, today),
      if (shown.isEmpty) priceOf(const Variant(), today),
    }.toList()..sort();
    return prices;
  }
}

/// A photo in the form: one already saved, or one just picked.
class PhotoDraft {
  const PhotoDraft.saved(int this.id) : bytes = null;
  const PhotoDraft.added(Uint8List this.bytes) : id = null;
  final int? id;
  final Uint8List? bytes;
}

/// [sale] and [saleCancel] come only from sales.
enum MoveKind { initial, entry, exit, count, sale, saleCancel }

/// One change of stock.
class StockMove {
  const StockMove({
    required this.id,
    required this.variantId,
    required this.variantLabel,
    required this.kind,
    required this.quantity,
    this.unitCost,
    this.reason = '',
    this.note = '',
    required this.balance,
    required this.at,
    this.saleNumber,
  });

  final int id;
  final int variantId;
  final String variantLabel;
  final MoveKind kind;

  /// Signed thousandths.
  final int quantity;
  final int? unitCost;
  final String reason;
  final String note;
  final int balance;
  final DateTime at;

  /// The sale that moved the stock.
  final int? saleNumber;
}

/// The product (or the [labels] of its variations) was sold: it can only be
/// inactivated.
class ProductHasSales implements Exception {
  const ProductHasSales([this.labels = const []]);
  final List<String> labels;
}

/// A code (SKU or barcode) already used by this or another product.
class DuplicateCode implements Exception {
  const DuplicateCode(this.code);
  final String code;
}

/// Products in app.db.
/// The product, and the variation when the code is a variation's, with
/// [code] as barcode or SKU; null when none.
({Product product, Variant? variant})? productByCode(
  List<Product> products,
  String code,
) {
  final c = code.trim();
  if (c.isEmpty) return null;
  for (final p in products) {
    for (final v in p.variants) {
      if (v.barcode == c || v.sku == c) return (product: p, variant: v);
    }
  }
  for (final p in products) {
    if (p.barcode == c || p.sku == c) {
      // A product with one variation sells that one.
      final only = p.variants.length == 1 ? p.variants.single : null;
      return (product: p, variant: only);
    }
  }
  return null;
}

abstract interface class ProductsRepository {
  /// Every product, by name, without photo bytes.
  Future<List<Product>> list();
  Future<Product?> byId(int id);

  /// Creates or updates the product with its attributes, variations and
  /// tiers; returns the id. Variations missing from [Product.variants] are
  /// deleted with their history. A new variation's stock is its initial
  /// stock; an existing one's stock is left alone. [photos], when given,
  /// becomes the product's photos in that order. Throws [DuplicateCode], or
  /// [ProductHasSales] when a variation to delete was sold.
  Future<int> save(Product product, {List<PhotoDraft>? photos});

  /// Deletes the product with variations, history and photos.
  /// Throws [ProductHasSales] when it was sold.
  Future<void> delete(int id);

  /// An entry, exit or count of [quantity] thousandths. An entry
  /// with [unitCost] updates the average cost; a count sets the stock.
  Future<void> move(
    int variantId,
    MoveKind kind,
    int quantity, {
    int? unitCost,
    String reason = '',
    String note = '',
  });

  /// The product's movements, newest first.
  Future<List<StockMove>> moves(int productId);
  Future<Uint8List?> photo(int id);
}

/// Changes a variation's stock by [delta] with a movement in the history,
/// for a sale or its cancellation. Run it inside the sale's
/// transaction. Services have no stock: nothing happens.
Future<void> moveForSale(
  AppDatabase db, {
  required int variantId,
  required MoveKind kind,
  required int delta,
  required int saleId,
  required int at,
}) async {
  final v = await (db.select(
    db.productVariants,
  )..where((r) => r.id.equals(variantId))).getSingle();
  final p = await (db.select(
    db.products,
  )..where((r) => r.id.equals(v.productId))).getSingle();
  if (p.kind == ProductKind.service.name) return;
  final balance = v.stock + delta;
  await (db.update(db.productVariants)..where((r) => r.id.equals(variantId)))
      .write(ProductVariantsCompanion(stock: Value(balance)));
  await db
      .into(db.stockMoves)
      .insert(
        StockMovesCompanion.insert(
          variantId: variantId,
          kind: kind.name,
          quantity: delta,
          balance: balance,
          createdAt: at,
          saleId: Value(saleId),
        ),
      );
}

String? _blank(String? code) {
  final t = code?.trim() ?? '';
  return t.isEmpty ? null : t;
}

class DriftProductsRepository implements ProductsRepository {
  DriftProductsRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  Future<List<Product>> _load({int? id}) async {
    final db = _db;
    final rows =
        await (db.select(db.products)
              ..where(
                (p) => id == null ? const Constant(true) : p.id.equals(id),
              )
              ..orderBy([
                (p) => OrderingTerm(expression: p.name.collate(Collate.noCase)),
              ]))
            .get();
    if (rows.isEmpty) return const [];
    final attributes = <int, List<Attribute>>{};
    for (final a
        in await (db.select(db.productAttributes)
              ..where(
                (a) =>
                    id == null ? const Constant(true) : a.productId.equals(id),
              )
              ..orderBy([(a) => OrderingTerm(expression: a.position)]))
            .get()) {
      (attributes[a.productId] ??= []).add(
        Attribute(a.name, a.choices.isEmpty ? const [] : a.choices.split('\n')),
      );
    }
    final variants = <int, List<Variant>>{};
    for (final v
        in await (db.select(db.productVariants)
              ..where(
                (v) =>
                    id == null ? const Constant(true) : v.productId.equals(id),
              )
              ..orderBy([(v) => OrderingTerm(expression: v.id)]))
            .get()) {
      final count = attributes[v.productId]?.length ?? 0;
      (variants[v.productId] ??= []).add(
        Variant(
          id: v.id,
          options: [v.option1, v.option2, v.option3].take(count).toList(),
          sku: v.sku,
          barcode: v.barcode,
          price: v.price,
          cost: v.cost,
          stock: v.stock,
          active: v.active,
        ),
      );
    }
    final tiers = <int, List<WholesaleTier>>{};
    for (final t
        in await (db.select(db.productWholesale)
              ..where(
                (t) =>
                    id == null ? const Constant(true) : t.productId.equals(id),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.minQty)]))
            .get()) {
      (tiers[t.productId] ??= []).add(WholesaleTier(t.minQty, t.price));
    }
    // Only the ids: the bytes are read one by one (photo).
    final photos = <int, List<int>>{};
    final ph = db.productPhotos;
    final query = db.selectOnly(ph)
      ..addColumns([ph.id, ph.productId])
      ..orderBy([
        OrderingTerm(expression: ph.position),
        OrderingTerm(expression: ph.id),
      ]);
    if (id != null) query.where(ph.productId.equals(id));
    for (final r in await query.get()) {
      final int productId = r.read(ph.productId)!, photoId = r.read(ph.id)!;
      (photos[productId] ??= []).add(photoId);
    }
    return [
      for (final r in rows)
        Product(
          id: r.id,
          kind: ProductKind.values.byName(r.kind),
          name: r.name,
          sku: r.sku,
          barcode: r.barcode,
          category: r.category,
          brand: r.brand,
          supplier: r.supplier,
          unit: r.unit,
          description: r.description,
          price: r.price,
          promoPrice: r.promoPrice,
          promoUntil: r.promoUntil,
          expiresOn: r.expiresOn,
          minStock: r.minStock,
          active: r.active,
          attributes: attributes[r.id] ?? const [],
          variants: variants[r.id] ?? const [],
          tiers: tiers[r.id] ?? const [],
          photoIds: photos[r.id] ?? const [],
          createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
        ),
    ];
  }

  @override
  Future<List<Product>> list() => _load();

  @override
  Future<Product?> byId(int id) async {
    final found = await _load(id: id);
    return found.isEmpty ? null : found.first;
  }

  /// Codes must be unique among every product and variation.
  Future<void> _checkCodes(Product p) async {
    final db = _db;
    final skus = [
      _blank(p.sku),
      for (final v in p.variants) _blank(v.sku),
    ].nonNulls.toList();
    final barcodes = [
      _blank(p.barcode),
      for (final v in p.variants) _blank(v.barcode),
    ].nonNulls.toList();
    for (final codes in [skus, barcodes]) {
      final seen = <String>{};
      for (final c in codes) {
        if (!seen.add(c)) throw DuplicateCode(c);
      }
    }
    Expression<bool> other(GeneratedColumn<int> productId) =>
        p.id == null ? const Constant(true) : productId.equals(p.id!).not();
    final products =
        await (db.select(db.products)..where(
              (r) =>
                  (r.sku.isIn(skus) | r.barcode.isIn(barcodes)) & other(r.id),
            ))
            .get();
    final variants =
        await (db.select(db.productVariants)..where(
              (r) =>
                  (r.sku.isIn(skus) | r.barcode.isIn(barcodes)) &
                  other(r.productId),
            ))
            .get();
    for (final (sku, barcode) in [
      for (final r in products) (r.sku, r.barcode),
      for (final r in variants) (r.sku, r.barcode),
    ]) {
      if (skus.contains(sku)) throw DuplicateCode(sku!);
      if (barcodes.contains(barcode)) throw DuplicateCode(barcode!);
    }
  }

  @override
  Future<int> save(Product p, {List<PhotoDraft>? photos}) {
    final db = _db;
    final now = _clock().millisecondsSinceEpoch;
    return db.transaction(() async {
      await _checkCodes(p);
      final fields = ProductsCompanion(
        kind: Value(p.kind.name),
        name: Value(p.name),
        sku: Value(_blank(p.sku)),
        barcode: Value(_blank(p.barcode)),
        category: Value(p.category),
        brand: Value(p.brand),
        supplier: Value(p.supplier),
        unit: Value(p.unit),
        description: Value(p.description),
        price: Value(p.price),
        promoPrice: Value(p.promoPrice),
        promoUntil: Value(p.promoPrice == null ? null : p.promoUntil),
        expiresOn: Value(_blank(p.expiresOn)),
        minStock: Value(p.isService ? 0 : p.minStock),
        active: Value(p.active),
        updatedAt: Value(now),
      );
      final int id;
      if (p.id case final existing?) {
        await (db.update(
          db.products,
        )..where((r) => r.id.equals(existing))).write(fields);
        id = existing;
      } else {
        id = await db
            .into(db.products)
            .insert(fields.copyWith(createdAt: Value(now)));
      }

      await (db.delete(
        db.productAttributes,
      )..where((a) => a.productId.equals(id))).go();
      for (final (i, a) in p.attributes.indexed) {
        await db
            .into(db.productAttributes)
            .insert(
              ProductAttributesCompanion.insert(
                productId: id,
                position: i,
                name: a.name,
                choices: a.values.join('\n'),
              ),
            );
      }

      await (db.delete(
        db.productWholesale,
      )..where((t) => t.productId.equals(id))).go();
      for (final t in p.tiers) {
        await db
            .into(db.productWholesale)
            .insert(
              ProductWholesaleCompanion.insert(
                productId: id,
                minQty: t.minQty,
                price: t.price,
              ),
            );
      }

      // Variations: the missing ones go with their history; codes are
      // cleared first so two variations can swap them.
      final keep = {for (final v in p.variants) ?v.id};
      final sold = await _sold(
        (v) => v.productId.equals(id) & v.id.isNotIn(keep),
      );
      if (sold.isNotEmpty) throw ProductHasSales(sold);
      await (db.delete(
        db.productVariants,
      )..where((v) => v.productId.equals(id) & v.id.isNotIn(keep))).go();
      await (db.update(
        db.productVariants,
      )..where((v) => v.productId.equals(id))).write(
        const ProductVariantsCompanion(sku: Value(null), barcode: Value(null)),
      );
      for (final v in p.variants) {
        String option(int i) => i < v.options.length ? v.options[i] : '';
        final variant = ProductVariantsCompanion(
          productId: Value(id),
          option1: Value(option(0)),
          option2: Value(option(1)),
          option3: Value(option(2)),
          sku: Value(_blank(v.sku)),
          barcode: Value(_blank(v.barcode)),
          price: Value(v.price),
          cost: Value(v.cost),
          active: Value(v.active),
        );
        if (v.id case final vid?) {
          await (db.update(
            db.productVariants,
          )..where((r) => r.id.equals(vid))).write(variant);
          continue;
        }
        final initial = p.isService ? 0 : v.stock;
        final vid = await db
            .into(db.productVariants)
            .insert(variant.copyWith(stock: Value(initial)));
        if (initial != 0) {
          await db
              .into(db.stockMoves)
              .insert(
                StockMovesCompanion.insert(
                  variantId: vid,
                  kind: MoveKind.initial.name,
                  quantity: initial,
                  balance: initial,
                  createdAt: now,
                ),
              );
        }
      }

      if (photos != null) {
        final saved = {for (final ph in photos) ?ph.id};
        await (db.delete(
          db.productPhotos,
        )..where((r) => r.productId.equals(id) & r.id.isNotIn(saved))).go();
        for (final (i, ph) in photos.indexed) {
          if (ph.id case final pid?) {
            await (db.update(db.productPhotos)
                  ..where((r) => r.id.equals(pid) & r.productId.equals(id)))
                .write(ProductPhotosCompanion(position: Value(i)));
          } else {
            await db
                .into(db.productPhotos)
                .insert(
                  ProductPhotosCompanion.insert(
                    productId: id,
                    position: i,
                    bytes: ph.bytes!,
                    createdAt: now,
                  ),
                );
          }
        }
      }
      return id;
    });
  }

  /// The labels of the matching variations that were sold.
  Future<List<String>> _sold(
    Expression<bool> Function($ProductVariantsTable) which,
  ) async {
    final db = _db;
    final v = db.productVariants;
    final rows =
        await (db.selectOnly(v, distinct: true)
              ..addColumns([v.option1, v.option2, v.option3])
              ..join([
                innerJoin(db.saleItems, db.saleItems.variantId.equalsExp(v.id)),
              ])
              ..where(which(v)))
            .get();
    return [
      for (final r in rows)
        variantLabel([
          r.read(v.option1)!,
          r.read(v.option2)!,
          r.read(v.option3)!,
        ]),
    ];
  }

  @override
  Future<void> delete(int id) => _db.transaction(() async {
    if ((await _sold((v) => v.productId.equals(id))).isNotEmpty) {
      throw const ProductHasSales();
    }
    await (_db.delete(_db.products)..where((p) => p.id.equals(id))).go();
  });

  @override
  Future<void> move(
    int variantId,
    MoveKind kind,
    int quantity, {
    int? unitCost,
    String reason = '',
    String note = '',
  }) {
    if (kind case MoveKind.initial || MoveKind.sale || MoveKind.saleCancel) {
      throw ArgumentError('this movement comes with the product or a sale');
    }
    if (quantity < 0 || (kind != MoveKind.count && quantity == 0)) {
      throw ArgumentError('quantity must be positive');
    }
    final db = _db;
    return db.transaction(() async {
      final v = await (db.select(
        db.productVariants,
      )..where((r) => r.id.equals(variantId))).getSingle();
      final p = await (db.select(
        db.products,
      )..where((r) => r.id.equals(v.productId))).getSingle();
      if (p.kind == ProductKind.service.name) {
        throw StateError('services have no stock');
      }
      final delta = switch (kind) {
        MoveKind.entry => quantity,
        MoveKind.exit => -quantity,
        MoveKind.count => quantity - v.stock,
        MoveKind.initial || MoveKind.sale || MoveKind.saleCancel => 0,
      };
      final balance = v.stock + delta;
      final cost = kind == MoveKind.entry && unitCost != null
          ? averageCost(
              stock: v.stock,
              cost: v.cost,
              quantity: quantity,
              unitCost: unitCost,
            )
          : v.cost;
      await (db.update(
        db.productVariants,
      )..where((r) => r.id.equals(variantId))).write(
        ProductVariantsCompanion(stock: Value(balance), cost: Value(cost)),
      );
      await db
          .into(db.stockMoves)
          .insert(
            StockMovesCompanion.insert(
              variantId: variantId,
              kind: kind.name,
              quantity: delta,
              unitCost: Value(kind == MoveKind.entry ? unitCost : null),
              reason: Value(reason),
              note: Value(note),
              balance: balance,
              createdAt: _clock().millisecondsSinceEpoch,
            ),
          );
    });
  }

  @override
  Future<List<StockMove>> moves(int productId) async {
    final db = _db;
    final m = db.stockMoves, v = db.productVariants;
    final count = (await (db.select(
      db.productAttributes,
    )..where((a) => a.productId.equals(productId))).get()).length;
    final sale = db.sales;
    final rows =
        await (db.select(m).join([
                innerJoin(v, v.id.equalsExp(m.variantId)),
                leftOuterJoin(sale, sale.id.equalsExp(m.saleId)),
              ])
              ..where(v.productId.equals(productId))
              ..orderBy([
                OrderingTerm.desc(m.createdAt),
                OrderingTerm.desc(m.id),
              ]))
            .get();
    return [
      for (final r in rows)
        if ((r.readTable(m), r.readTable(v)) case (final move, final variant))
          StockMove(
            id: move.id,
            variantId: move.variantId,
            variantLabel: variantLabel(
              [
                variant.option1,
                variant.option2,
                variant.option3,
              ].take(count).toList(),
            ),
            kind: MoveKind.values.byName(move.kind),
            quantity: move.quantity,
            unitCost: move.unitCost,
            reason: move.reason,
            note: move.note,
            balance: move.balance,
            at: DateTime.fromMillisecondsSinceEpoch(move.createdAt),
            saleNumber: r.readTableOrNull(sale)?.number,
          ),
    ];
  }

  @override
  Future<Uint8List?> photo(int id) async {
    final row = await (_db.select(
      _db.productPhotos,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    return row?.bytes;
  }
}
