// Product search, filters and sorting.
import 'package:chat_do_garoto/src/products/products_controller.dart';
import 'package:chat_do_garoto/src/products/products_repository.dart';
import 'package:chat_do_garoto/src/products/variants.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_products_repository.dart';

final _today = DateTime(2026, 10, 2, 15);

Future<ProductsController> _world() async {
  final repo = FakeProductsRepository();
  // Ids follow the order: 1 is the oldest.
  await repo.save(
    const Product(
      name: 'Camiseta',
      category: 'Roupas',
      brand: 'Malhas Sul',
      price: 5000,
      minStock: 2000,
      attributes: [
        Attribute('Cor', ['Azul', 'Preto']),
      ],
      variants: [
        Variant(options: ['Azul'], stock: 1000, barcode: '7891000315507'),
        Variant(options: ['Preto'], stock: 9000, price: 4500),
      ],
    ),
  );
  await repo.save(
    const Product(
      name: 'Café em grãos',
      category: 'Alimentos',
      unit: 'KG',
      price: 6000,
      promoPrice: 4990,
      promoUntil: '2026-10-10',
      variants: [Variant(stock: 0)],
    ),
  );
  await repo.save(
    const Product(
      name: 'Ação de limpeza',
      kind: ProductKind.service,
      price: 15000,
      variants: [Variant()],
    ),
  );
  await repo.save(
    const Product(
      name: 'Caneca antiga',
      category: 'Alimentos',
      price: 1000,
      promoPrice: 900,
      promoUntil: '2026-09-30',
      active: false,
      variants: [Variant(stock: -2000)],
    ),
  );
  final controller = ProductsController(repo: repo, clock: () => _today);
  await controller.load();
  return controller;
}

List<String> _names(ProductsController c) => [
  for (final p in c.products) p.name,
];

void main() {
  test('inactive products are hidden unless asked for', () async {
    final c = await _world();
    expect(_names(c), ['Ação de limpeza', 'Café em grãos', 'Camiseta']);
    expect(c.counted.length, 3);
    c.toggleInactive();
    expect(c.products.length, 4);
  });

  test('search by name, code, barcode, brand and variation', () async {
    final c = await _world();
    c.search('acao');
    expect(_names(c), ['Ação de limpeza']);
    c.search('7891000');
    expect(_names(c), ['Camiseta']);
    c.search('preto');
    expect(_names(c), ['Camiseta']);
    c.search('malhas');
    expect(_names(c), ['Camiseta']);
    c.search('cafe graos');
    expect(_names(c), ['Café em grãos']);
    c.search('nada disso');
    expect(c.products, isEmpty);
  });

  test('categories, stock and promotion filters', () async {
    final c = await _world();
    expect(c.allCategories, ['Alimentos', 'Roupas']);
    c.toggleCategory('Roupas');
    expect(_names(c), ['Camiseta']);
    c.toggleCategory('Roupas');

    c.toggleLowStock();
    expect(_names(c), ['Camiseta']); // Azul at 1 with a minimum of 2
    c.toggleOutOfStock();
    expect(_names(c), ['Café em grãos', 'Camiseta']);
    c.toggleLowStock();
    expect(_names(c), ['Café em grãos']);
    c.toggleInactive();
    expect(_names(c), ['Café em grãos', 'Caneca antiga']); // negative
    c.toggleOutOfStock();

    c.togglePromo();
    // The old mug's promotion ended on 30/09.
    expect(_names(c), ['Café em grãos']);
  });

  test('five orders', () async {
    final c = await _world();
    c.sortBy(ProductSort.newest);
    expect(_names(c), ['Ação de limpeza', 'Café em grãos', 'Camiseta']);
    c.sortBy(ProductSort.priceLow);
    // Camiseta from R$ 45,00; café on promotion at R$ 49,90.
    expect(_names(c), ['Camiseta', 'Café em grãos', 'Ação de limpeza']);
    c.sortBy(ProductSort.priceHigh);
    expect(_names(c), ['Ação de limpeza', 'Café em grãos', 'Camiseta']);
    c.sortBy(ProductSort.stockLow);
    expect(_names(c), ['Café em grãos', 'Camiseta', 'Ação de limpeza']);
    c.sortBy(ProductSort.name);
    expect(_names(c), ['Ação de limpeza', 'Café em grãos', 'Camiseta']);
  });

  test('stock flags', () async {
    final c = await _world();
    final byName = {for (final p in c.all) p.name: p};
    expect(byName['Camiseta']!.stock, 10000);
    expect(byName['Camiseta']!.lowStock, isTrue);
    expect(byName['Café em grãos']!.outOfStock, isTrue);
    expect(byName['Café em grãos']!.lowStock, isFalse);
    expect(byName['Ação de limpeza']!.outOfStock, isFalse);
    expect(byName['Camiseta']!.pricesToday(_today), [4500, 5000]);
  });
}
