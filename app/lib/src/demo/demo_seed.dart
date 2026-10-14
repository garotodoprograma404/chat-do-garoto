import '../clients/clients_repository.dart';
import '../products/products_repository.dart';
import '../products/variants.dart';
import '../sales/sale_math.dart';
import '../sales/sales_repository.dart';

/// Fills an empty app.db with the demo's store: a store of dev
/// gear in the channel's tone, its clients and sales. Everything goes
/// through the real repositories, so stock, installments and situations
/// follow the same rules as real data. Dates are relative to [now]: there is
/// always an overdue installment, a birthday this week and low stock.
Future<void> seedDemo({
  required ClientsRepository clients,
  required ProductsRepository products,
  required SalesRepository sales,
  required DateTime now,
}) async {
  DateTime daysAgo(int d) => now.subtract(Duration(days: d));
  String two(int n) => n.toString().padLeft(2, '0');
  final birthday = now.add(const Duration(days: 3));

  // Clients: the phones match the demo's conversations.
  final ana = await clients.save(
    const Client(
      name: 'Ana Paula',
      phone: '5511900000101',
      city: 'São Paulo',
      state: 'SP',
      tags: ['vip'],
    ),
  );
  final bruno = await clients.save(
    const Client(name: 'Bruno Costa', phone: '5511900000102'),
  );
  final carla = await clients.save(
    const Client(
      name: 'Carla Mendes',
      phone: '5511900000103',
      company: 'Estudante de ADS',
      tags: ['consultoria'],
    ),
  );
  final diego = await clients.save(
    Client(
      name: 'Diego Rocha',
      phone: '5511900000104',
      birthday: '--${two(birthday.month)}-${two(birthday.day)}',
    ),
  );
  final elisa = await clients.save(
    const Client(
      name: 'Elisa Prado',
      phone: '5511900000105',
      city: 'Campinas',
      state: 'SP',
    ),
  );
  final fabio = await clients.save(
    const Client(name: 'Fábio Nunes', phone: '5511900000106'),
  );
  final gabi = await clients.save(
    const Client(name: 'Gabi Torres', phone: '5511900000107', tags: ['vip']),
  );
  await clients.addNote(bruno, 'Prefere ser lembrado da parcela na sexta.');
  await clients.addNote(carla, 'Quer focar em lógica antes de framework.');

  // Products: quantities in thousandths, money in cents.
  final camiseta = await products.save(
    const Product(
      name: 'Camiseta "Funciona na minha máquina"',
      category: 'Vestuário',
      price: 6990,
      attributes: [
        Attribute('Tamanho', ['P', 'M', 'G']),
      ],
      variants: [
        Variant(options: ['P'], cost: 2500, stock: 8000),
        Variant(options: ['M'], cost: 2500, stock: 12000),
        Variant(options: ['G'], cost: 2500, stock: 5000),
      ],
    ),
  );
  final caneca = await products.save(
    const Product(
      name: 'Caneca "git push --force"',
      category: 'Casa',
      price: 3990,
      variants: [Variant(cost: 1500, stock: 20000)],
    ),
  );
  final moletom = await products.save(
    const Product(
      name: 'Moletom "Deploy de sexta"',
      category: 'Vestuário',
      price: 14990,
      minStock: 5000,
      variants: [Variant(cost: 6000, stock: 5000)],
    ),
  );
  final adesivos = await products.save(
    const Product(
      name: 'Kit de adesivos ";)"',
      category: 'Acessórios',
      price: 1990,
      variants: [Variant(cost: 400, stock: 50000)],
    ),
  );
  final mousepad = await products.save(
    const Product(
      name: 'Mousepad "Ctrl+C Ctrl+V"',
      category: 'Acessórios',
      price: 4990,
      minStock: 2000,
      variants: [Variant(cost: 1800, stock: 1000)],
    ),
  );
  final consultoria = await products.save(
    const Product(
      name: 'Consultoria de carreira dev',
      kind: ProductKind.service,
      unit: 'H',
      price: 15000,
      variants: [Variant()],
    ),
  );
  final curso = await products.save(
    const Product(
      name: 'Curso "Lógica do zero"',
      kind: ProductKind.service,
      price: 9700,
      variants: [Variant()],
    ),
  );

  Future<List<Variant>> variants(int product) async =>
      (await products.byId(product))!.variants;
  final tamanhos = await variants(camiseta);
  Future<int> only(int product) async => (await variants(product)).single.id!;

  SaleItem item(
    int variant,
    String description,
    int units,
    int price, {
    bool service = false,
    String unit = 'UN',
  }) => SaleItem(
    variantId: variant,
    description: description,
    quantity: units * 1000,
    unitPrice: price,
    isService: service,
    unit: unit,
  );

  // Paid by Pix: a T-shirt and a mug.
  await sales.conclude(
    Sale(
      clientId: ana,
      soldAt: daysAgo(20),
      items: [
        item(
          tamanhos[1].id!,
          'Camiseta "Funciona na minha máquina" (M)',
          1,
          6990,
        ),
        item(await only(caneca), 'Caneca "git push --force"', 1, 3990),
      ],
      discount: 1090,
      payments: [
        SalePayment(method: PayMethod.pix, amount: 9890, at: daysAgo(20)),
      ],
    ),
  );
  // On credit: part by Pix, two installments, the first one overdue.
  await sales.conclude(
    Sale(
      clientId: bruno,
      soldAt: daysAgo(40),
      items: [item(await only(moletom), 'Moletom "Deploy de sexta"', 1, 14990)],
      payments: [
        SalePayment(method: PayMethod.pix, amount: 4990, at: daysAgo(40)),
      ],
      installments: splitInstallments(10000, 2, daysAgo(10)),
    ),
  );
  await sales.conclude(
    Sale(
      clientId: carla,
      soldAt: daysAgo(2),
      items: [
        item(
          await only(consultoria),
          'Consultoria de carreira dev',
          1,
          15000,
          service: true,
          unit: 'H',
        ),
      ],
      payments: [
        SalePayment(method: PayMethod.credit, amount: 15000, at: daysAgo(2)),
      ],
    ),
  );
  await sales.conclude(
    Sale(
      clientId: diego,
      soldAt: now,
      items: [item(await only(adesivos), 'Kit de adesivos ";)"', 2, 1990)],
      payments: [SalePayment(method: PayMethod.cash, amount: 3980, at: now)],
    ),
  );
  await sales.conclude(
    Sale(
      clientId: elisa,
      soldAt: daysAgo(8),
      items: [
        item(await only(mousepad), 'Mousepad "Ctrl+C Ctrl+V"', 1, 4990),
        item(await only(adesivos), 'Kit de adesivos ";)"', 1, 1990),
      ],
      freight: 1500,
      payments: [
        SalePayment(method: PayMethod.pix, amount: 8480, at: daysAgo(8)),
      ],
    ),
  );
  // To receive in ten days.
  await sales.conclude(
    Sale(
      clientId: fabio,
      soldAt: daysAgo(3),
      items: [
        item(
          await only(curso),
          'Curso "Lógica do zero"',
          1,
          9700,
          service: true,
        ),
      ],
      installments: splitInstallments(
        9700,
        1,
        now.add(const Duration(days: 10)),
      ),
    ),
  );
  await sales.conclude(
    Sale(
      clientId: gabi,
      soldAt: daysAgo(15),
      items: [
        item(
          tamanhos[2].id!,
          'Camiseta "Funciona na minha máquina" (G)',
          1,
          6990,
        ),
      ],
      payments: [
        SalePayment(method: PayMethod.debit, amount: 6990, at: daysAgo(15)),
      ],
    ),
  );
}
