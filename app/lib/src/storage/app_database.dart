import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// App preferences: name and value.
class Preferences extends Table {
  TextColumn get name => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {name};
}

/// Clients of the CRM.
@DataClassName('ClientRow')
class Clients extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();

  /// Digits with country and area code; one client per phone.
  TextColumn get phone => text().unique()();

  /// The WhatsApp chat the client was saved from, if any.
  TextColumn get chatJid => text().nullable().unique()();
  TextColumn get email => text().withDefault(const Constant(''))();

  /// The street.
  TextColumn get address => text().withDefault(const Constant(''))();

  /// The rest of the address, from the CEP lookup or typed: CEP digits, number, complement, district, city and UF.
  TextColumn get cep => text().withDefault(const Constant(''))();
  TextColumn get addressNumber => text().withDefault(const Constant(''))();
  TextColumn get complement => text().withDefault(const Constant(''))();
  TextColumn get district => text().withDefault(const Constant(''))();
  TextColumn get city => text().withDefault(const Constant(''))();
  TextColumn get state => text().withDefault(const Constant(''))();

  /// CPF or CNPJ, digits only.
  TextColumn get document => text().withDefault(const Constant(''))();

  /// "AAAA-MM-DD", or "--MM-DD" without the year.
  TextColumn get birthday => text().withDefault(const Constant(''))();
  TextColumn get company => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}

@DataClassName('ClientTagRow')
class ClientTags extends Table {
  IntColumn get clientId =>
      integer().references(Clients, #id, onDelete: KeyAction.cascade)();
  TextColumn get tag => text()();

  @override
  Set<Column<Object>> get primaryKey => {clientId, tag};
}

@DataClassName('ClientNoteRow')
class ClientNotes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get clientId =>
      integer().references(Clients, #id, onDelete: KeyAction.cascade)();
  TextColumn get body => text()();
  IntColumn get createdAt => integer()();
}

/// Products and services. Money in cents, quantities
/// in thousandths.
@DataClassName('ProductRow')
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// "product" or "service".
  TextColumn get kind => text()();
  TextColumn get name => text()();
  TextColumn get sku => text().nullable().unique()();
  TextColumn get barcode => text().nullable().unique()();
  TextColumn get category => text().withDefault(const Constant(''))();
  TextColumn get brand => text().withDefault(const Constant(''))();
  TextColumn get supplier => text().withDefault(const Constant(''))();
  TextColumn get unit => text().withDefault(const Constant('UN'))();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get price => integer()();
  IntColumn get promoPrice => integer().nullable()();

  /// "AAAA-MM-DD", inclusive; null for no end.
  TextColumn get promoUntil => text().nullable()();

  /// The current batch's expiry, "AAAA-MM-DD"; null when it does not apply
  TextColumn get expiresOn => text().nullable()();
  IntColumn get minStock => integer().withDefault(const Constant(0))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}

/// Up to three attributes per product, such as Cor (Azul, Preto).
@DataClassName('ProductAttributeRow')
class ProductAttributes extends Table {
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  TextColumn get name => text()();

  /// The values, one per line.
  TextColumn get choices => text()();

  @override
  Set<Column<Object>> get primaryKey => {productId, position};
}

/// The unit of stock: every product has at least one.
@DataClassName('VariantRow')
class ProductVariants extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();
  TextColumn get option1 => text().withDefault(const Constant(''))();
  TextColumn get option2 => text().withDefault(const Constant(''))();
  TextColumn get option3 => text().withDefault(const Constant(''))();
  TextColumn get sku => text().nullable().unique()();
  TextColumn get barcode => text().nullable().unique()();

  /// Null: the product's price.
  IntColumn get price => integer().nullable()();

  /// The average cost.
  IntColumn get cost => integer().withDefault(const Constant(0))();

  /// Kept in step with the movements, in the same transaction.
  IntColumn get stock => integer().withDefault(const Constant(0))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

@DataClassName('WholesaleRow')
class ProductWholesale extends Table {
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();
  IntColumn get minQty => integer()();
  IntColumn get price => integer()();

  @override
  Set<Column<Object>> get primaryKey => {productId, minQty};
}

/// Every change of stock, with the balance after it.
@DataClassName('StockMoveRow')
class StockMoves extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get variantId =>
      integer().references(ProductVariants, #id, onDelete: KeyAction.cascade)();

  /// "initial", "entry", "exit" or "count".
  TextColumn get kind => text()();

  /// Signed: what the movement added or took.
  IntColumn get quantity => integer()();
  IntColumn get unitCost => integer().nullable()();
  TextColumn get reason => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get balance => integer()();
  IntColumn get createdAt => integer()();

  /// The sale that moved the stock.
  IntColumn get saleId => integer().nullable().references(Sales, #id)();
}

/// Up to five photos per product, as JPEG.
@DataClassName('ProductPhotoRow')
class ProductPhotos extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  BlobColumn get bytes => blob()();
  IntColumn get createdAt => integer()();
}

/// Sales: never deleted, only canceled. Money in
/// cents.
@DataClassName('SaleRow')
class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Sequential, never reused.
  IntColumn get number => integer().unique()();
  IntColumn get clientId => integer().nullable().references(
    Clients,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// The client was deleted: the sale stays without the name.
  BoolColumn get clientRemoved =>
      boolean().withDefault(const Constant(false))();
  IntColumn get soldAt => integer()();
  IntColumn get discount => integer().withDefault(const Constant(0))();
  IntColumn get freight => integer().withDefault(const Constant(0))();
  IntColumn get total => integer()();

  /// The cost of the items when sold.
  IntColumn get cost => integer()();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get canceledAt => integer().nullable()();
  TextColumn get cancelReason => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
}

/// A snapshot of each item when sold: later changes to the product do not
/// change the sale.
@DataClassName('SaleItemRow')
class SaleItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId =>
      integer().references(Sales, #id, onDelete: KeyAction.cascade)();

  /// No cascade: a sold variation cannot be deleted. Null for a quick
  /// sale's item, which has no product.
  IntColumn get variantId =>
      integer().nullable().references(ProductVariants, #id)();
  TextColumn get description => text()();
  TextColumn get unit => text()();
  BoolColumn get isService => boolean().withDefault(const Constant(false))();
  IntColumn get quantity => integer()();
  IntColumn get unitPrice => integer()();
  IntColumn get discount => integer().withDefault(const Constant(0))();
  IntColumn get unitCost => integer().withDefault(const Constant(0))();
}

/// Paid at the sale ("sale") or received later ("receipt").
@DataClassName('SalePaymentRow')
class SalePayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId =>
      integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text()();
  TextColumn get method => text()();
  IntColumn get amount => integer()();
  IntColumn get paidAt => integer()();

  /// Reversed when the sale was canceled.
  BoolColumn get voided => boolean().withDefault(const Constant(false))();
}

/// What is paid of each installment is calculated, never stored.
@DataClassName('InstallmentRow')
class SaleInstallments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId =>
      integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  IntColumn get number => integer()();

  /// "AAAA-MM-DD".
  TextColumn get dueDate => text()();
  IntColumn get amount => integer()();
}

/// The app's own database, `app.db`, encrypted by SQLCipher.
/// Only the Dart side opens it (architecture invariant 5).
@DriftDatabase(
  tables: [
    Preferences,
    Clients,
    ClientTags,
    ClientNotes,
    Products,
    ProductAttributes,
    ProductVariants,
    ProductWholesale,
    StockMoves,
    ProductPhotos,
    Sales,
    SaleItems,
    SalePayments,
    SaleInstallments,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => currentVersion;

  /// The version this code writes; backups from newer ones are refused.
  static const currentVersion = 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // The CRM's clients; preferences stay as they are.
        await m.createTable(clients);
        await m.createTable(clientTags);
        await m.createTable(clientNotes);
      }
      if (from < 3) {
        // Products; clients stay as they are.
        await m.createTable(products);
        await m.createTable(productAttributes);
        await m.createTable(productVariants);
        await m.createTable(productWholesale);
        await m.createTable(stockMoves);
        await m.createTable(productPhotos);
      }
      if (from < 4) {
        // Sales; the rest stays as it is.
        await m.createTable(sales);
        await m.createTable(saleItems);
        await m.createTable(salePayments);
        await m.createTable(saleInstallments);
        if (from == 3) await m.addColumn(stockMoves, stockMoves.saleId);
      }
      if (from < 5) {
        // Quick sales have an item without a product,
        // and products an expiry. Tables created above already have both.
        // SQLite cannot drop a NOT NULL, so the items table is rebuilt,
        // rows copied; nothing points at it.
        if (from >= 4) await m.alterTable(TableMigration(saleItems));
        if (from >= 3) await m.addColumn(products, products.expiresOn);
      }
      if (from >= 2 && from < 6) {
        // The address split; the old one stays as the
        // street.
        for (final column in [
          clients.cep,
          clients.addressNumber,
          clients.complement,
          clients.district,
          clients.city,
          clients.state,
        ]) {
          await m.addColumn(clients, column);
        }
      }
    },
  );

  Future<String?> preference(String name) async {
    final row = await (select(
      preferences,
    )..where((p) => p.name.equals(name))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setPreference(String name, String value) => into(preferences)
      .insertOnConflictUpdate(
        PreferencesCompanion.insert(name: name, value: value),
      );
}
