import 'dart:typed_data';

import 'package:chat_do_garoto/src/products/pricing.dart';
import 'package:chat_do_garoto/src/products/products_repository.dart';

/// In-memory [ProductsRepository] for screen tests.
class FakeProductsRepository implements ProductsRepository {
  final products = <int, Product>{};
  final photos = <int, Uint8List>{};
  final _moves = <StockMove>[];
  var _next = 1, _variant = 1, _photo = 1, _move = 1;
  DateTime now = DateTime(2026, 10, 2, 9);

  @override
  Future<List<Product>> list() async =>
      products.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<Product?> byId(int id) async => products[id];

  @override
  Future<int> save(Product p, {List<PhotoDraft>? photos}) async {
    final codes = <String>[];
    for (final c in [
      p.sku,
      p.barcode,
      for (final v in p.variants) ...[v.sku, v.barcode],
    ]) {
      if (c == null || c.isEmpty) continue;
      if (codes.contains(c)) throw DuplicateCode(c);
      codes.add(c);
    }
    for (final other in products.values) {
      if (other.id == p.id) continue;
      for (final c in [
        other.sku,
        other.barcode,
        for (final v in other.variants) ...[v.sku, v.barcode],
      ]) {
        if (c != null && codes.contains(c)) throw DuplicateCode(c);
      }
    }
    final id = p.id ?? _next++;
    final old = products[id];
    final variants = <Variant>[];
    for (final v in p.variants) {
      final existing = old?.variants.where((o) => o.id == v.id).firstOrNull;
      final vid = v.id ?? _variant++;
      final stock = existing?.stock ?? (p.isService ? 0 : v.stock);
      if (v.id == null && stock != 0) {
        _moves.add(
          StockMove(
            id: _move++,
            variantId: vid,
            variantLabel: v.label,
            kind: MoveKind.initial,
            quantity: stock,
            balance: stock,
            at: now,
          ),
        );
      }
      variants.add(
        Variant(
          id: vid,
          options: v.options,
          sku: v.sku,
          barcode: v.barcode,
          price: v.price,
          cost: v.cost,
          stock: stock,
          active: v.active,
        ),
      );
    }
    var photoIds = old?.photoIds ?? const <int>[];
    if (photos != null) {
      photoIds = [
        for (final ph in photos)
          if (ph.id case final pid?) pid else _addPhoto(ph.bytes!),
      ];
    }
    products[id] = _copy(
      p,
      id: id,
      variants: variants,
      photoIds: photoIds,
      createdAt:
          old?.createdAt ?? DateTime(2026, 1, 1).add(Duration(hours: id)),
    );
    return id;
  }

  int _addPhoto(Uint8List bytes) {
    final id = _photo++;
    photos[id] = bytes;
    return id;
  }

  Product _copy(
    Product p, {
    required int id,
    required List<Variant> variants,
    required List<int> photoIds,
    DateTime? createdAt,
  }) => Product(
    id: id,
    kind: p.kind,
    name: p.name,
    sku: p.sku,
    barcode: p.barcode,
    category: p.category,
    brand: p.brand,
    supplier: p.supplier,
    unit: p.unit,
    description: p.description,
    price: p.price,
    promoPrice: p.promoPrice,
    promoUntil: p.promoUntil,
    expiresOn: p.expiresOn,
    minStock: p.minStock,
    active: p.active,
    attributes: p.attributes,
    variants: variants,
    tiers: p.tiers,
    photoIds: photoIds,
    createdAt: createdAt ?? p.createdAt,
  );

  /// When set, [delete] throws it.
  Object? deleteError;

  @override
  Future<void> delete(int id) async {
    if (deleteError case final e?) throw e;
    products.remove(id);
  }

  @override
  Future<void> move(
    int variantId,
    MoveKind kind,
    int quantity, {
    int? unitCost,
    String reason = '',
    String note = '',
  }) async {
    final p = products.values.firstWhere(
      (p) => p.variants.any((v) => v.id == variantId),
    );
    final v = p.variants.firstWhere((v) => v.id == variantId);
    final delta = switch (kind) {
      MoveKind.entry => quantity,
      MoveKind.exit => -quantity,
      MoveKind.count => quantity - v.stock,
      MoveKind.initial ||
      MoveKind.sale ||
      MoveKind.saleCancel => throw ArgumentError('not by hand'),
    };
    final cost = kind == MoveKind.entry && unitCost != null
        ? averageCost(
            stock: v.stock,
            cost: v.cost,
            quantity: quantity,
            unitCost: unitCost,
          )
        : v.cost;
    now = now.add(const Duration(minutes: 1));
    _moves.add(
      StockMove(
        id: _move++,
        variantId: variantId,
        variantLabel: v.label,
        kind: kind,
        quantity: delta,
        unitCost: kind == MoveKind.entry ? unitCost : null,
        reason: reason,
        note: note,
        balance: v.stock + delta,
        at: now,
      ),
    );
    products[p.id!] = _copy(
      p,
      id: p.id!,
      photoIds: p.photoIds,
      variants: [
        for (final o in p.variants)
          o.id == variantId
              ? Variant(
                  id: o.id,
                  options: o.options,
                  sku: o.sku,
                  barcode: o.barcode,
                  price: o.price,
                  cost: cost,
                  stock: o.stock + delta,
                  active: o.active,
                )
              : o,
      ],
    );
  }

  @override
  Future<List<StockMove>> moves(int productId) async {
    final ids = {for (final v in products[productId]!.variants) v.id};
    return [
      for (final m in _moves.reversed)
        if (ids.contains(m.variantId)) m,
    ];
  }

  @override
  Future<Uint8List?> photo(int id) async => photos[id];
}
