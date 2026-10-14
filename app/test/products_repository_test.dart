// Products in app.db with the real SQLCipher.
import 'dart:io';
import 'dart:typed_data';

import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/products/pricing.dart';
import 'package:chat_do_garoto/src/products/products_repository.dart';
import 'package:chat_do_garoto/src/products/variants.dart';
import 'package:chat_do_garoto/src/storage/app_database.dart';
import 'package:chat_do_garoto/src/storage/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late String path;
  late AppDatabase db;
  late DriftProductsRepository repo;
  final key = newDatabaseKey();
  var now = DateTime(2026, 10, 2, 9);

  Future<AppDatabase> openDb() async => (await AppStorage(
    path: () async => path,
  ).open(key) as StorageOpened).database;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('products_test');
    path = '${dir.path}/app/app.db';
    db = await openDb();
    repo = DriftProductsRepository(db, clock: () => now);
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  const cor = Attribute('Cor', ['Azul', 'Preto']);
  const tamanho = Attribute('Tamanho', ['P', 'M', 'G']);

  Product camiseta({List<Variant>? variants}) => Product(
    name: 'Camiseta básica',
    sku: 'CAM-01',
    category: 'Roupas',
    brand: 'Marca X',
    supplier: 'Fornecedor Y',
    price: 5000,
    promoPrice: 3990,
    promoUntil: '2026-10-31',
    minStock: 2000,
    attributes: const [cor, tamanho],
    tiers: const [WholesaleTier(10000, 4000), WholesaleTier(50000, 3500)],
    variants:
        variants ??
        [
          for (final (i, o) in combinations(const [cor, tamanho]).indexed)
            Variant(
              options: o,
              sku: 'CAM-01-$i',
              cost: 2000,
              stock: (i + 1) * 1000,
              price: o.last == 'G' ? 5500 : null,
            ),
        ],
  );

  test('saves a product with attributes, variations and tiers', () async {
    final id = await repo.save(camiseta());
    final p = (await repo.byId(id))!;
    expect(p.name, 'Camiseta básica');
    expect(p.attributes.map((a) => a.name), ['Cor', 'Tamanho']);
    expect(p.attributes.last.values, ['P', 'M', 'G']);
    expect(p.variants.length, 6);
    expect(p.variants.first.label, 'Azul / P');
    expect(p.variants[2].price, 5500);
    expect(p.tiers.map((t) => t.price), [4000, 3500]);
    expect(p.stock, 21000); // 1 + 2 + ... + 6
    expect(p.createdAt, now);
    // The initial stock is the first movement of each variation.
    final moves = await repo.moves(id);
    expect(moves.length, 6);
    expect(moves.every((m) => m.kind == MoveKind.initial), isTrue);
    expect(
      moves.firstWhere((m) => m.variantLabel == 'Preto / G').balance,
      6000,
    );
  });

  test('a simple product has one default variation', () async {
    final id = await repo.save(
      const Product(
        name: 'Caneca',
        barcode: '7891000315507',
        unit: 'UN',
        price: 2500,
        variants: [Variant(cost: 1000, stock: 3000)],
      ),
    );
    final p = (await repo.byId(id))!;
    expect(p.hasVariants, isFalse);
    expect(p.variants.single.options, isEmpty);
    expect(p.variants.single.label, '');
    expect(p.stock, 3000);
  });

  test('a service has no stock', () async {
    final id = await repo.save(
      const Product(
        name: 'Consultoria',
        kind: ProductKind.service,
        unit: 'H',
        price: 20000,
        variants: [Variant(stock: 5000)],
      ),
    );
    final p = (await repo.byId(id))!;
    expect(p.isService, isTrue);
    expect(p.variants.single.stock, 0);
    expect(await repo.moves(id), isEmpty);
    expect(
      () => repo.move(p.variants.single.id!, MoveKind.entry, 1000),
      throwsStateError,
    );
  });

  test('codes are unique among products and variations', () async {
    await repo.save(camiseta());
    // Another product with the SKU of a variation.
    await expectLater(
      repo.save(
        const Product(
          name: 'Outro',
          sku: 'CAM-01-3',
          price: 100,
          variants: [Variant()],
        ),
      ),
      throwsA(isA<DuplicateCode>().having((e) => e.code, 'code', 'CAM-01-3')),
    );
    // A variation with the barcode of another product.
    await repo.save(
      const Product(
        name: 'Caneca',
        barcode: '7891000315507',
        price: 2500,
        variants: [Variant()],
      ),
    );
    await expectLater(
      repo.save(
        const Product(
          name: 'Outro',
          price: 100,
          attributes: [
            Attribute('Cor', ['Azul']),
          ],
          variants: [
            Variant(options: ['Azul'], barcode: '7891000315507'),
          ],
        ),
      ),
      throwsA(isA<DuplicateCode>()),
    );
    // The same code twice in one product.
    await expectLater(
      repo.save(
        const Product(
          name: 'Outro',
          sku: 'X',
          price: 100,
          variants: [Variant(sku: 'X')],
        ),
      ),
      throwsA(isA<DuplicateCode>()),
    );
    expect((await repo.list()).length, 2);
  });

  test('editing keeps its own codes and lets variations swap them', () async {
    final id = await repo.save(camiseta());
    final p = (await repo.byId(id))!;
    final swapped = [
      for (final (i, v) in p.variants.indexed)
        Variant(
          id: v.id,
          options: v.options,
          sku: i == 0 ? 'CAM-01-1' : (i == 1 ? 'CAM-01-0' : v.sku),
          cost: v.cost,
          price: v.price,
        ),
    ];
    await repo.save(
      Product(
        id: id,
        name: p.name,
        sku: p.sku,
        price: p.price,
        attributes: p.attributes,
        variants: swapped,
      ),
    );
    final after = (await repo.byId(id))!;
    expect(after.variants.first.sku, 'CAM-01-1');
    // Saving does not touch the stock of existing variations.
    expect(after.stock, 21000);
  });

  test('movements: entry with average cost, exit, count', () async {
    final id = await repo.save(
      const Product(
        name: 'Caneca',
        price: 2500,
        variants: [Variant(cost: 500, stock: 10000)],
      ),
    );
    final vid = (await repo.byId(id))!.variants.single.id!;

    now = now.add(const Duration(minutes: 1));
    await repo.move(vid, MoveKind.entry, 10000, unitCost: 700);
    var v = (await repo.byId(id))!.variants.single;
    expect(v.stock, 20000);
    expect(v.cost, 600);

    // An entry without cost keeps the cost.
    now = now.add(const Duration(minutes: 1));
    await repo.move(vid, MoveKind.entry, 1000);
    expect((await repo.byId(id))!.variants.single.cost, 600);

    // Negative stock is allowed.
    now = now.add(const Duration(minutes: 1));
    await repo.move(vid, MoveKind.exit, 25000, reason: 'Perda', note: 'caiu');
    v = (await repo.byId(id))!.variants.single;
    expect(v.stock, -4000);

    // The next entry starts the cost again.
    now = now.add(const Duration(minutes: 1));
    await repo.move(vid, MoveKind.entry, 5000, unitCost: 900);
    expect((await repo.byId(id))!.variants.single.cost, 900);

    // A count sets the stock and records the difference.
    now = now.add(const Duration(minutes: 1));
    await repo.move(vid, MoveKind.count, 7000);
    expect((await repo.byId(id))!.variants.single.stock, 7000);

    final moves = await repo.moves(id);
    expect(moves.map((m) => m.kind), [
      MoveKind.count,
      MoveKind.entry,
      MoveKind.exit,
      MoveKind.entry,
      MoveKind.entry,
      MoveKind.initial,
    ]);
    expect(moves.map((m) => m.quantity), [
      6000,
      5000,
      -25000,
      1000,
      10000,
      10000,
    ]);
    expect(moves.map((m) => m.balance), [
      7000,
      1000,
      -4000,
      21000,
      20000,
      10000,
    ]);
    expect(moves[2].reason, 'Perda');
    expect(moves[2].note, 'caiu');
    expect(moves[1].unitCost, 900);
    expect(moves[2].unitCost, isNull);
    // The balance always matches the variation.
    expect(moves.first.balance, (await repo.byId(id))!.stock);

    expect(() => repo.move(vid, MoveKind.exit, 0), throwsArgumentError);
    expect(() => repo.move(vid, MoveKind.initial, 1), throwsArgumentError);
  });

  test('changing attributes keeps, removes and adds variations', () async {
    final id = await repo.save(camiseta());
    final p = (await repo.byId(id))!;
    const novo = [
      Attribute('Cor', ['Azul', 'Verde']),
      tamanho,
    ];
    final plan = reconcile(p.variants, (v) => v.options, combinations(novo));
    expect(plan.removed.length, 3);
    final removedIds = plan.removed.map((v) => v.id).toSet();
    await repo.save(
      Product(
        id: id,
        name: p.name,
        sku: p.sku,
        price: p.price,
        attributes: novo,
        variants: [
          ...plan.kept,
          for (final o in plan.added) Variant(options: o, cost: 2100),
        ],
      ),
    );
    final after = (await repo.byId(id))!;
    expect(after.variants.map((v) => v.label), [
      'Azul / P',
      'Azul / M',
      'Azul / G',
      'Verde / P',
      'Verde / M',
      'Verde / G',
    ]);
    expect(after.stock, 1000 + 2000 + 3000);
    final moves = await repo.moves(id);
    expect(moves.any((m) => removedIds.contains(m.variantId)), isFalse);
  });

  test('photos keep their order; only ids are listed', () async {
    final a = Uint8List.fromList([1, 2, 3]);
    final b = Uint8List.fromList([4, 5]);
    final id = await repo.save(
      const Product(name: 'Caneca', price: 2500, variants: [Variant()]),
      photos: [PhotoDraft.added(a), PhotoDraft.added(b)],
    );
    var p = (await repo.list()).single;
    expect(p.photoIds.length, 2);
    expect(await repo.photo(p.photoIds.first), a);

    // The second becomes the main photo; the first is removed.
    await repo.save(
      Product(id: id, name: p.name, price: p.price, variants: p.variants),
      photos: [PhotoDraft.saved(p.photoIds.last)],
    );
    p = (await repo.byId(id))!;
    expect(p.photoIds.length, 1);
    expect(await repo.photo(p.photoIds.single), b);

    // Saving without photos leaves them alone.
    await repo.save(
      Product(id: id, name: 'Caneca 2', price: p.price, variants: p.variants),
    );
    expect((await repo.byId(id))!.photoIds.length, 1);
  });

  test('deleting removes variations, history and photos', () async {
    final id = await repo.save(
      camiseta(),
      photos: [
        PhotoDraft.added(Uint8List.fromList([1])),
      ],
    );
    await repo.delete(id);
    expect(await repo.byId(id), isNull);
    for (final table in [
      'product_variants',
      'stock_moves',
      'product_photos',
      'product_attributes',
      'product_wholesale',
    ]) {
      final row = await db
          .customSelect('SELECT count(*) AS n FROM $table')
          .getSingle();
      expect(row.read<int>('n'), 0, reason: table);
    }
  });

  test(
    'an app.db from delivery 3.1 (version 2) opens without losing clients',
    () async {
      await db.close();
      File(path).deleteSync();
      // The schema of version 2, as delivery 3.3 left it.
      final raw = sqlite3.open(path);
      applyKey(raw, key);
      raw.execute('''
      CREATE TABLE "preferences" ("name" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("name"));
      CREATE TABLE "clients" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, "phone" TEXT NOT NULL UNIQUE, "chat_jid" TEXT NULL UNIQUE, "email" TEXT NOT NULL DEFAULT '', "address" TEXT NOT NULL DEFAULT '', "document" TEXT NOT NULL DEFAULT '', "birthday" TEXT NOT NULL DEFAULT '', "company" TEXT NOT NULL DEFAULT '', "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL);
      CREATE TABLE "client_tags" ("client_id" INTEGER NOT NULL REFERENCES clients (id) ON DELETE CASCADE, "tag" TEXT NOT NULL, PRIMARY KEY ("client_id", "tag"));
      CREATE TABLE "client_notes" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "client_id" INTEGER NOT NULL REFERENCES clients (id) ON DELETE CASCADE, "body" TEXT NOT NULL, "created_at" INTEGER NOT NULL);
      INSERT INTO preferences VALUES ('theme', 'x');
      INSERT INTO clients (name, phone, created_at, updated_at) VALUES ('Ana', '5511900000001', 1, 1);
      INSERT INTO client_tags VALUES (1, 'vip');
      INSERT INTO client_notes (client_id, body, created_at) VALUES (1, 'nota antiga', 1);
      PRAGMA user_version = 2;
    ''');
      raw.close();

      db = await openDb();
      final clients = DriftClientsRepository(db);
      final ana = (await clients.list()).single;
      expect(ana.name, 'Ana');
      expect(ana.tags, ['vip']);
      expect((await clients.notes(ana.id!)).single.body, 'nota antiga');
      expect(await db.preference('theme'), 'x');
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data.values.single, db.schemaVersion);

      repo = DriftProductsRepository(db, clock: () => now);
      final id = await repo.save(camiseta());
      expect((await repo.byId(id))!.variants.length, 6);
    },
  );

  test('the expiry is kept and "Vencendo" counts 30 days', () async {
    final id = await repo.save(
      const Product(
        name: 'Hidratante',
        price: 3000,
        barcode: '7891234567895',
        expiresOn: '2026-10-12',
        variants: [Variant(stock: 1000)],
      ),
    );
    final p = (await repo.byId(id))!;
    expect(p.expiresOn, '2026-10-12');
    final today = DateTime(2026, 10, 2, 15);
    expect(p.expiresIn(today), 10);
    expect(p.expiringSoon(today), isTrue);
    expect(p.expiringSoon(DateTime(2026, 9, 1)), isFalse); // 41 days
    expect(p.expiringSoon(DateTime(2026, 10, 13)), isTrue); // expired

    // Cleared, it is gone.
    await repo.save(
      Product(
        id: id,
        name: 'Hidratante',
        price: 3000,
        barcode: '7891234567895',
        expiresOn: '',
        variants: p.variants,
      ),
    );
    expect((await repo.byId(id))!.expiresOn, isNull);
  });

  test('a code finds the product or the variation', () async {
    await repo.save(
      const Product(
        name: 'Caneca',
        price: 2500,
        barcode: '7890000000001',
        variants: [Variant(stock: 1000)],
      ),
    );
    await repo.save(
      const Product(
        name: 'Camiseta',
        price: 5000,
        barcode: '7890000000002',
        attributes: [
          Attribute('Cor', ['Azul', 'Preto']),
        ],
        variants: [
          Variant(options: ['Azul'], barcode: '7890000000003'),
          Variant(options: ['Preto'], sku: 'CAM-PRETO'),
        ],
      ),
    );
    final all = await repo.list();
    final caneca = productByCode(all, '7890000000001')!;
    expect(caneca.product.name, 'Caneca');
    expect(caneca.variant, isNotNull); // one variation: that one
    expect(productByCode(all, '7890000000003')!.variant!.options, ['Azul']);
    expect(productByCode(all, 'CAM-PRETO')!.variant!.options, ['Preto']);
    // The product's own code with several variations: no variation.
    expect(productByCode(all, '7890000000002')!.variant, isNull);
    expect(productByCode(all, '000'), isNull);
  });
}
