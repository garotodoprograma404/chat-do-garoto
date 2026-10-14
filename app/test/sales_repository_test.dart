// Sales in app.db with the real SQLCipher.
import 'dart:io';

import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/products/products_repository.dart';
import 'package:chat_do_garoto/src/products/variants.dart';
import 'package:chat_do_garoto/src/sales/sale_math.dart';
import 'package:chat_do_garoto/src/sales/sales_repository.dart';
import 'package:chat_do_garoto/src/storage/app_database.dart';
import 'package:chat_do_garoto/src/storage/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late String path;
  late AppDatabase db;
  late DriftProductsRepository products;
  late DriftClientsRepository clients;
  late DriftSalesRepository sales;
  final key = newDatabaseKey();
  var now = DateTime(2026, 10, 2, 9);

  Future<AppDatabase> openDb() async => (await AppStorage(
    path: () async => path,
  ).open(key) as StorageOpened).database;

  void repos() {
    products = DriftProductsRepository(db, clock: () => now);
    clients = DriftClientsRepository(db, clock: () => now);
    sales = DriftSalesRepository(db, clock: () => now);
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('sales_test');
    path = '${dir.path}/app/app.db';
    db = await openDb();
    repos();
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  late int ana, camiseta, consultoria;
  late List<Variant> cores;

  Future<void> world() async {
    ana = await clients.save(const Client(name: 'Ana', phone: '5511900000001'));
    camiseta = await products.save(
      const Product(
        name: 'Camiseta',
        price: 5000,
        attributes: [
          Attribute('Cor', ['Azul', 'Preto']),
        ],
        variants: [
          Variant(options: ['Azul'], cost: 2000, stock: 10000),
          Variant(options: ['Preto'], cost: 2000, stock: 10000),
        ],
      ),
    );
    consultoria = await products.save(
      const Product(
        name: 'Consultoria',
        kind: ProductKind.service,
        unit: 'H',
        price: 10000,
        variants: [Variant(cost: 3000)],
      ),
    );
    cores = (await products.byId(camiseta))!.variants;
  }

  Future<int> service() async =>
      (await products.byId(consultoria))!.variants.single.id!;

  /// 2 Azul at R$ 50 + 1 h of consultoria at R$ 100, R$ 10 off, R$ 15 of
  /// freight = R$ 205: R$ 100 by Pix, R$ 105 in 2 installments.
  Future<Sale> onCredit() async => Sale(
    clientId: ana,
    soldAt: now,
    items: [
      SaleItem(
        variantId: cores.first.id!,
        description: 'Camiseta (Azul)',
        quantity: 2000,
        unitPrice: 5000,
      ),
      SaleItem(
        variantId: await service(),
        description: 'Consultoria',
        unit: 'H',
        isService: true,
        quantity: 1000,
        unitPrice: 10000,
      ),
    ],
    discount: 1000,
    freight: 1500,
    payments: [SalePayment(method: PayMethod.pix, amount: 10000, at: now)],
    installments: splitInstallments(10500, 2, DateTime(2026, 11, 2)),
  );

  test('concluding: number, snapshot, stock and payments', () async {
    await world();
    final id = await sales.conclude(await onCredit());
    final sale = (await sales.byId(id))!;
    expect(sale.number, 1);
    expect(sale.clientLabel, 'Ana');
    expect(sale.total, 20500);
    expect(sale.items.first.unitCost, 2000);
    expect(sale.cost, 4000 + 3000);
    expect(sale.profit, 20000 - 1000 - 7000);
    expect(sale.received, 10000);
    expect(sale.open, 10500);
    expect(sale.installments.map((i) => i.amount), [5250, 5250]);
    expect(sale.status(now), SaleStatus.open);

    // The stock went down with a movement tied to the sale; the service has
    // no stock.
    final azul = (await products.byId(camiseta))!.variants.first;
    expect(azul.stock, 8000);
    final moves = await products.moves(camiseta);
    expect(moves.first.kind, MoveKind.sale);
    expect(moves.first.saleNumber, 1);
    expect(moves.first.quantity, -2000);
    expect(moves.first.balance, 8000);
    expect(await products.moves(consultoria), isEmpty);

    // A later cost does not change the sale.
    await products.move(azul.id!, MoveKind.entry, 10000, unitCost: 9000);
    expect((await sales.byId(id))!.cost, 7000);

    // Numbers follow.
    final next = await sales.conclude(
      Sale(
        soldAt: now,
        items: [
          SaleItem(
            variantId: cores.last.id!,
            description: 'Camiseta (Preto)',
            quantity: 1000,
            unitPrice: 5000,
          ),
        ],
        payments: [SalePayment(method: PayMethod.cash, amount: 5000, at: now)],
      ),
    );
    final paid = (await sales.byId(next))!;
    expect(paid.number, 2);
    expect(paid.clientLabel, 'Consumidor final');
    expect(paid.status(now), SaleStatus.paid);
    expect((await sales.list()).map((s) => s.number), [2, 1]);
    expect((await sales.byClient(ana)).map((s) => s.number), [1]);
  });

  test('a sale must add up, and credit needs a client', () async {
    await world();
    final sale = await onCredit();
    expect(
      () => sales.conclude(
        Sale(
          clientId: ana,
          soldAt: now,
          items: sale.items,
          discount: sale.discount,
          freight: sale.freight,
          payments: sale.payments,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => sales.conclude(
        Sale(
          soldAt: now,
          items: sale.items,
          discount: sale.discount,
          freight: sale.freight,
          payments: sale.payments,
          installments: sale.installments,
        ),
      ),
      throwsArgumentError,
    );
    expect(await sales.list(), isEmpty);
  });

  test('receiving: oldest installment first, partial, undo', () async {
    await world();
    final id = await sales.conclude(await onCredit());
    await sales.receive(id, PayMethod.cash, 6000, now);
    var sale = (await sales.byId(id))!;
    expect(sale.installmentPaid, [5250, 750]);
    expect(sale.open, 4500);
    expect(
      () => sales.receive(id, PayMethod.cash, 4501, now),
      throwsA(isA<InvalidReceipt>()),
    );
    expect(
      () => sales.receive(id, PayMethod.cash, 0, now),
      throwsA(isA<InvalidReceipt>()),
    );

    final receipt = sale.payments.firstWhere((p) => p.receipt);
    await sales.undoReceipt(receipt.id!);
    sale = (await sales.byId(id))!;
    expect(sale.open, 10500);
    // A payment of the sale is not a receipt.
    expect(() => sales.undoReceipt(sale.payments.single.id!), throwsStateError);

    // Overdue after the first due date.
    expect(sale.status(DateTime(2026, 11, 3)), SaleStatus.overdue);
    await sales.receive(id, PayMethod.pix, 10500, now);
    expect(
      (await sales.byId(id))!.status(DateTime(2026, 12, 3)),
      SaleStatus.paid,
    );
  });

  test('canceling: stock back, payments reversed', () async {
    await world();
    final id = await sales.conclude(await onCredit());
    await sales.receive(id, PayMethod.cash, 3000, now);
    now = now.add(const Duration(minutes: 5));
    await sales.cancel(id, reason: 'desistiu');
    final sale = (await sales.byId(id))!;
    expect(sale.canceled, isTrue);
    expect(sale.cancelReason, 'desistiu');
    expect(sale.status(now), SaleStatus.canceled);
    expect(sale.open, 0);
    expect(sale.received, 0);
    expect(sale.payments.every((p) => p.voided), isTrue);
    expect((await products.byId(camiseta))!.variants.first.stock, 10000);
    final moves = await products.moves(camiseta);
    expect(moves.first.kind, MoveKind.saleCancel);
    expect(moves.first.saleNumber, 1);
    expect(moves.first.balance, 10000);
    expect(() => sales.cancel(id), throwsStateError);
    expect(() => sales.receive(id, PayMethod.cash, 100, now), throwsStateError);
  });

  test('a sold product or variation can only be inactivated', () async {
    await world();
    await sales.conclude(await onCredit());
    expect(() => products.delete(camiseta), throwsA(isA<ProductHasSales>()));
    expect(() => products.delete(consultoria), throwsA(isA<ProductHasSales>()));
    final p = (await products.byId(camiseta))!;
    // Removing Azul (sold) is refused; Preto (not sold) can go.
    await expectLater(
      products.save(
        Product(
          id: camiseta,
          name: p.name,
          price: p.price,
          attributes: const [
            Attribute('Cor', ['Preto']),
          ],
          variants: [p.variants.last],
        ),
      ),
      throwsA(
        isA<ProductHasSales>().having((e) => e.labels, 'labels', ['Azul']),
      ),
    );
    await products.save(
      Product(
        id: camiseta,
        name: p.name,
        price: p.price,
        attributes: const [
          Attribute('Cor', ['Azul']),
        ],
        variants: [p.variants.first],
      ),
    );
    expect((await products.byId(camiseta))!.variants.length, 1);
  });

  test(
    'a client who owes cannot be deleted; then the sales lose the name',
    () async {
      await world();
      final id = await sales.conclude(await onCredit());
      expect(
        () => clients.delete(ana),
        throwsA(isA<ClientHasOpenSales>().having((e) => e.open, 'open', 10500)),
      );
      await sales.receive(id, PayMethod.pix, 10500, now);
      await clients.delete(ana);
      final sale = (await sales.byId(id))!;
      expect(sale.clientId, isNull);
      expect(sale.clientLabel, 'Cliente apagado');
      // A canceled sale does not hold the client either.
      final bia = await clients.save(
        const Client(name: 'Bia', phone: '5511900000002'),
      );
      final other = await onCredit();
      final second = await sales.conclude(
        Sale(
          clientId: bia,
          soldAt: now,
          items: other.items,
          discount: other.discount,
          freight: other.freight,
          payments: other.payments,
          installments: other.installments,
        ),
      );
      await sales.cancel(second);
      await clients.delete(bia);
    },
  );

  test(
    'an app.db from delivery 3.4 (version 3) opens without losing anything',
    () async {
      await db.close();
      File(path).deleteSync();
      final raw = sqlite3.open(path);
      applyKey(raw, key);
      raw.execute(File('test/fixtures/app_db_v3.sql').readAsStringSync());
      raw.execute('''
      INSERT INTO clients (name, phone, created_at, updated_at) VALUES ('Ana', '5511900000001', 1, 1);
      INSERT INTO products (kind, name, price, created_at, updated_at) VALUES ('product', 'Caneca', 2500, 1, 1);
      INSERT INTO product_variants (product_id, cost, stock) VALUES (1, 1000, 3000);
      INSERT INTO stock_moves (variant_id, kind, quantity, balance, created_at) VALUES (1, 'initial', 3000, 3000, 1);
      PRAGMA user_version = 3;
    ''');
      raw.close();

      db = await openDb();
      repos();
      expect((await clients.list()).single.name, 'Ana');
      final caneca = (await products.list()).single;
      expect(caneca.stock, 3000);
      expect((await products.moves(caneca.id!)).single.kind, MoveKind.initial);
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data.values.single, db.schemaVersion);

      final id = await sales.conclude(
        Sale(
          soldAt: now,
          items: [
            SaleItem(
              variantId: caneca.variants.single.id!,
              description: 'Caneca',
              quantity: 1000,
              unitPrice: 2500,
            ),
          ],
          payments: [SalePayment(method: PayMethod.pix, amount: 2500, at: now)],
        ),
      );
      expect((await sales.byId(id))!.number, 1);
      expect((await products.byId(caneca.id!))!.stock, 2000);
    },
  );

  test('a quick sale has an item without a product and moves no stock '
      '', () async {
    await world();
    final paid = await sales.conclude(
      Sale(
        soldAt: now,
        items: const [
          SaleItem(
            variantId: null,
            description: 'Conserto',
            isService: true,
            quantity: 1000,
            unitPrice: 5000,
          ),
        ],
        payments: [SalePayment(method: PayMethod.pix, amount: 5000, at: now)],
      ),
    );
    final credit = await sales.conclude(
      Sale(
        clientId: ana,
        soldAt: now,
        items: const [
          SaleItem(
            variantId: null,
            description: 'Venda rápida',
            isService: true,
            quantity: 1000,
            unitPrice: 8000,
          ),
        ],
        installments: const [
          Installment(number: 1, due: '2026-11-01', amount: 8000),
        ],
      ),
    );
    final quick = (await sales.byId(paid))!;
    expect(quick.items.single.variantId, isNull);
    expect(quick.items.single.description, 'Conserto');
    expect(quick.total, 5000);
    expect(quick.status(now), SaleStatus.paid);
    expect((await sales.byId(credit))!.open, 8000);
    // No stock moved, now or on cancelling.
    expect(await products.moves(camiseta), hasLength(2)); // the initial ones
    await sales.receive(credit, PayMethod.cash, 3000, now);
    await sales.cancel(credit, reason: 'teste');
    expect((await sales.byId(credit))!.canceled, isTrue);
    expect(await products.moves(camiseta), hasLength(2));
    expect((await products.byId(camiseta))!.variants.first.stock, 10000);
  });
}
