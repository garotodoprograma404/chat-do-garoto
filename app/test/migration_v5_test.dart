// app.db v4 → v5 with the real SQLCipher: the
// sale items table is rebuilt with every row kept, products gain the
// expiry, and an item may then have no product.
import 'dart:io';

import 'package:chat_do_garoto/src/storage/app_database.dart';
import 'package:chat_do_garoto/src/storage/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

const _v4Data = '''
  INSERT INTO clients (id, name, phone, created_at, updated_at)
    VALUES (1, 'Ana', '5511900000001', 1, 1);
  INSERT INTO products (id, kind, name, price, created_at, updated_at)
    VALUES (1, 'product', 'Camiseta', 5000, 1, 1);
  INSERT INTO product_variants (id, product_id, cost, stock) VALUES (1, 1, 2000, 8000);
  INSERT INTO sales (id, number, client_id, sold_at, total, cost, created_at)
    VALUES (1, 1, 1, 100, 10000, 4000, 100);
  INSERT INTO sales (id, number, client_id, sold_at, total, cost, created_at, canceled_at, cancel_reason)
    VALUES (2, 2, NULL, 200, 5000, 2000, 200, 300, 'desistiu');
  INSERT INTO sale_items (id, sale_id, variant_id, description, unit, quantity, unit_price, discount, unit_cost)
    VALUES (1, 1, 1, 'Camiseta (Azul)', 'UN', 2000, 5000, 0, 2000);
  INSERT INTO sale_items (id, sale_id, variant_id, description, unit, quantity, unit_price, discount, unit_cost)
    VALUES (2, 2, 1, 'Camiseta (Azul)', 'UN', 1000, 5000, 100, 2000);
  INSERT INTO sale_payments (sale_id, kind, method, amount, paid_at, voided) VALUES (1, 'sale', 'pix', 4000, 100, 0);
  INSERT INTO sale_payments (sale_id, kind, method, amount, paid_at, voided) VALUES (2, 'sale', 'cash', 5000, 200, 1);
  INSERT INTO sale_installments (sale_id, number, due_date, amount) VALUES (1, 1, '2026-11-01', 6000);
  INSERT INTO stock_moves (variant_id, kind, quantity, balance, created_at, sale_id) VALUES (1, 'sale', -2000, 8000, 100, 1);
  PRAGMA user_version = 4;
''';

void main() {
  late Directory dir;
  late String path;
  final key = newDatabaseKey();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('migration_v5_test');
    path = '${dir.path}/app/app.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// A v4 app.db at [file], encrypted with [withKey].
  void writeV4(String file, String withKey) {
    File(file).parent.createSync(recursive: true);
    final raw = sqlite3.open(file);
    raw.execute("PRAGMA key = \"x'$withKey'\"");
    raw.execute(File('test/fixtures/app_db_v4.sql').readAsStringSync());
    raw.execute(_v4Data);
    raw.close();
  }

  Future<List<Map<String, Object?>>> rows(AppDatabase db, String sql) async => [
    for (final r in await db.customSelect(sql).get()) r.data,
  ];

  test('a v4 app.db opens as v5 with every row the same', () async {
    writeV4(path, key);
    final db = (await AppStorage(
      path: () async => path,
    ).open(key) as StorageOpened).database;

    expect(
      (await rows(db, 'PRAGMA user_version')).single.values.single,
      AppDatabase.currentVersion,
    );
    expect(await rows(db, 'SELECT * FROM sale_items ORDER BY id'), [
      {
        'id': 1,
        'sale_id': 1,
        'variant_id': 1,
        'description': 'Camiseta (Azul)',
        'unit': 'UN',
        'is_service': 0,
        'quantity': 2000,
        'unit_price': 5000,
        'discount': 0,
        'unit_cost': 2000,
      },
      {
        'id': 2,
        'sale_id': 2,
        'variant_id': 1,
        'description': 'Camiseta (Azul)',
        'unit': 'UN',
        'is_service': 0,
        'quantity': 1000,
        'unit_price': 5000,
        'discount': 100,
        'unit_cost': 2000,
      },
    ]);
    expect(
      await rows(db, 'SELECT number, canceled_at, cancel_reason FROM sales'),
      [
        {'number': 1, 'canceled_at': null, 'cancel_reason': ''},
        {'number': 2, 'canceled_at': 300, 'cancel_reason': 'desistiu'},
      ],
    );
    expect(await rows(db, 'SELECT count(*) AS n FROM sale_payments'), [
      {'n': 2},
    ]);
    expect(await rows(db, 'SELECT count(*) AS n FROM sale_installments'), [
      {'n': 1},
    ]);
    expect(await rows(db, 'SELECT sale_id FROM stock_moves'), [
      {'sale_id': 1},
    ]);
    // The new columns: an expiry, and an item without a product.
    expect(await rows(db, 'SELECT expires_on FROM products'), [
      {'expires_on': null},
    ]);
    await db.customStatement(
      "INSERT INTO sale_items (sale_id, variant_id, description, unit, "
      "quantity, unit_price) VALUES (1, NULL, 'Venda rápida', 'UN', 1000, 100)",
    );
    expect(
      await rows(
        db,
        'SELECT count(*) AS n FROM sale_items WHERE variant_id IS NULL',
      ),
      [
        {'n': 1},
      ],
    );
    expect(await rows(db, 'PRAGMA foreign_key_check'), isEmpty);
    await db.close();
  });

  test('a v4 backup copy restores as v5', () async {
    final copy = '${dir.path}/cache/backup/app.db';
    final copyKey = newDatabaseKey();
    writeV4(copy, copyKey);
    final storage = AppStorage(path: () async => path);
    await storage.importCopy(key, copy, copyKey);
    final db = (await storage.open(key) as StorageOpened).database;
    expect(await rows(db, 'SELECT count(*) AS n FROM sale_items'), [
      {'n': 2},
    ]);
    expect(
      (await rows(db, 'PRAGMA user_version')).single.values.single,
      AppDatabase.currentVersion,
    );
    await db.close();
  });

  test('a v5 app.db opens as v6 with the address as the '
      'street', () async {
    File(path).parent.createSync(recursive: true);
    final raw = sqlite3.open(path);
    raw.execute("PRAGMA key = \"x'$key'\"");
    raw.execute(File('test/fixtures/app_db_v5.sql').readAsStringSync());
    raw.execute('''
      INSERT INTO clients (name, phone, address, created_at, updated_at)
        VALUES ('Ana', '5511900000001', 'Rua A, 10 - Centro', 1, 1);
      PRAGMA user_version = 5;
    ''');
    raw.close();
    final db = (await AppStorage(
      path: () async => path,
    ).open(key) as StorageOpened).database;
    expect(
      await rows(
        db,
        'SELECT address, cep, address_number, district, city, state FROM clients',
      ),
      [
        {
          'address': 'Rua A, 10 - Centro',
          'cep': '',
          'address_number': '',
          'district': '',
          'city': '',
          'state': '',
        },
      ],
    );
    expect(
      (await rows(db, 'PRAGMA user_version')).single.values.single,
      AppDatabase.currentVersion,
    );
    await db.close();
  });
}
