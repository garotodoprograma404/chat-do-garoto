// The screen review: defects and the points out of the layout
// research.
import 'package:chat_do_garoto/src/chats/chat_screen.dart';
import 'package:chat_do_garoto/src/clients/client_hint.dart';
import 'package:chat_do_garoto/src/clients/client_summary.dart';
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/clients/clients_screen.dart';
import 'package:chat_do_garoto/src/clients/validation.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:chat_do_garoto/src/home/crm_scope.dart';
import 'package:chat_do_garoto/src/home/start_screen.dart';
import 'package:chat_do_garoto/src/products/product_screen.dart';
import 'package:chat_do_garoto/src/products/products_repository.dart';
import 'package:chat_do_garoto/src/products/products_screen.dart';
import 'package:chat_do_garoto/src/products/variants.dart';
import 'package:chat_do_garoto/src/sales/sale_form_screen.dart';
import 'package:chat_do_garoto/src/sales/sale_math.dart';
import 'package:chat_do_garoto/src/sales/sales_repository.dart';
import 'package:chat_do_garoto/src/sales/sales_screen.dart';
import 'package:chat_do_garoto/src/theme/app_theme.dart';
import 'package:chat_do_garoto/src/theme/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';
import 'support/fake_products_repository.dart';
import 'support/fake_sales_repository.dart';

final _today = DateTime(2026, 10, 3, 10);

SaleItem _item(String name, int cents, {int qty = 1000}) => SaleItem(
  variantId: 1,
  description: name,
  quantity: qty,
  unitPrice: cents,
  unitCost: cents ~/ 2,
);

Sale _paid(String name, int cents, {DateTime? at, int? clientId}) => Sale(
  clientId: clientId,
  soldAt: at ?? _today,
  items: [_item(name, cents)],
  payments: [
    SalePayment(method: PayMethod.pix, amount: cents, at: at ?? _today),
  ],
);

/// WCAG contrast between two colors.
double _contrast(Color a, Color b) {
  final (la, lb) = (a.computeLuminance(), b.computeLuminance());
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

/// The Redmi width (360 dp) and, when [large], the font at 200%.
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  bool large = false,
  bool dark = false,
  FakeProductsRepository? products,
  FakeSalesRepository? sales,
  FakeClientsRepository? clients,
  double height = 800,
}) async {
  tester.view.physicalSize = Size(720, height * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox()); // a new navigator
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: Size(360, height),
        textScaler: TextScaler.linear(large ? 2 : 1),
      ),
      child: MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        builder: (context, child) => CrmScope(
          products: products ?? FakeProductsRepository(),
          sales: sales ?? FakeSalesRepository(),
          clients: clients,
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A client owing an installment overdue for 3 days, and one sale paid.
Future<({FakeSalesRepository sales, FakeClientsRepository clients})>
_owing() async {
  final sales = FakeSalesRepository()..now = _today;
  final clients = FakeClientsRepository();
  final carla = await clients.save(
    const Client(name: 'Carla Dias', phone: '5511900000001'),
  );
  sales.names[carla] = 'Carla Dias';
  await sales.conclude(
    Sale(
      clientId: carla,
      soldAt: DateTime(2026, 9, 2),
      items: [_item('Camiseta básica de algodão', 9000)],
      installments: const [
        Installment(number: 1, due: '2026-09-30', amount: 4500),
        Installment(number: 2, due: '2026-10-30', amount: 4500),
      ],
    ),
  );
  await sales.conclude(_paid('Caneca', 2500));
  return (sales: sales, clients: clients);
}

/// The paragraph of the text containing [text] was not cut.
void _notCut(WidgetTester tester, String text) {
  final f = find.textContaining(text);
  expect(f, findsWidgets, reason: text);
  for (final e in f.evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: text);
  }
}

void main() {
  test('my bubbles have contrast of 4.5:1 or more', () {
    for (final b in [Brightness.light, Brightness.dark]) {
      final c = AppTheme.scheme(b);
      for (final (mine, found) in [
        (true, false),
        (false, false),
        (true, true),
      ]) {
        final (bg, fg) = bubbleColors(c, mine: mine, found: found);
        expect(
          _contrast(bg, fg),
          greaterThanOrEqualTo(4.5),
          reason: '$b mine=$mine found=$found',
        );
      }
    }
  });

  testWidgets('the text of my bubble uses its own color', (tester) async {
    // The bubble shows the hour only for messages of the real today.
    final now = DateTime.now();
    final tenToday = DateTime(now.year, now.month, now.day, 10);
    await _pump(
      tester,
      Scaffold(
        body: MessageBubble(
          message: ChatMessage(
            chat: 'x@s.whatsapp.net',
            id: '1',
            fromMe: true,
            senderName: '',
            kind: 'text',
            text: 'Tenho sim!',
            ts: tenToday.millisecondsSinceEpoch,
            status: 'read',
          ),
          showSender: false,
          onRetry: () {},
        ),
      ),
    );
    final on = AppTheme.scheme(Brightness.light).onPrimaryContainer;
    for (final text in ['Tenho sim!', '10:00  ✓✓ lida']) {
      final style = tester.widget<RichText>(
        find.descendant(of: find.text(text), matching: find.byType(RichText)),
      );
      expect(style.text.style!.color, on, reason: text);
    }
  });

  test('plurals', () {
    expect(plural(1, 'item', 'itens'), '1 item');
    expect(plural(2, 'item', 'itens'), '2 itens');
    expect(plural(0, 'venda', 'vendas'), '0 vendas');
    expect(dueLabel('2026-10-03', _today), 'vence hoje');
    expect(dueLabel('2026-10-04', _today), 'vence amanhã');
    expect(dueLabel('2026-10-08', _today), 'vence em 5 dias');
    expect(dueLabel('2026-10-02', _today), 'venceu ontem');
    expect(dueLabel('2026-09-30', _today), 'venceu há 3 dias');
  });

  testWidgets('"1 vendido", "1 item" and "1 venda"', (tester) async {
    final sales = FakeSalesRepository()..now = _today;
    await sales.conclude(_paid('Caneca', 2500));
    final ctx = SaleContext(sales: sales, clock: () => _today);
    await _pump(tester, SalesScreen(ctx: ctx), sales: sales);
    expect(find.textContaining('1 item'), findsOneWidget);
    expect(find.text('Vendido · 1 venda'), findsOneWidget);

    await _pump(
      tester,
      StartScreen(
        clients: FakeClientsRepository(),
        products: FakeProductsRepository(),
        sales: sales,
        clock: () => _today,
      ),
      sales: sales,
    );
    await tester.scrollUntilVisible(find.text('Mais vendidos'), 200);
    expect(find.text('1 vendido'), findsOneWidget);
  });

  for (final large in [false, true]) {
    testWidgets('"venceu há 3 dias" first and not cut '
        '(${large ? '200%' : '100%'})', (tester) async {
      final w = await _owing();
      final ctx = SaleContext(
        sales: w.sales,
        clients: w.clients,
        clock: () => _today,
      );
      await _pump(
        tester,
        SalesScreen(ctx: ctx),
        large: large,
        sales: w.sales,
      );
      await tester.tap(find.widgetWithText(Tab, 'A receber'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      _notCut(tester, '1ª parcela venceu há 3 dias');
      await tester.scrollUntilVisible(
        find.textContaining('2ª parcela vence em 27 dias'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      _notCut(tester, '2ª parcela vence em 27 dias');

      await _pump(
        tester,
        StartScreen(
          clients: w.clients,
          products: FakeProductsRepository(),
          sales: w.sales,
          clock: () => _today,
        ),
        large: large,
        sales: w.sales,
      );
      expect(tester.takeException(), isNull);
      _notCut(tester, '1ª parcela venceu há 3 dias');
    });
  }

  testWidgets('"Em aberto", never "Aberta"', (tester) async {
    final w = await _owing();
    final ctx = SaleContext(sales: w.sales, clock: () => _today);
    await _pump(tester, SalesScreen(ctx: ctx), sales: w.sales);
    expect(find.text('Aberta'), findsNothing);
    await tester.tap(find.widgetWithText(Tab, 'A receber'));
    await tester.pumpAndSettle();
    expect(find.text('Aberta'), findsNothing);
    expect(find.text('Em aberto'), findsOneWidget);
  });

  testWidgets('"Venda rápida" named, the last row above the '
      'buttons', (tester) async {
    final sales = FakeSalesRepository()..now = _today;
    for (var i = 0; i < 12; i++) {
      await sales.conclude(_paid('Item $i', 1000 + i));
    }
    final ctx = SaleContext(
      sales: sales,
      products: FakeProductsRepository(),
      clock: () => _today,
    );
    await _pump(tester, SalesScreen(ctx: ctx), sales: sales);
    expect(find.text('Venda rápida'), findsOneWidget);
    expect(find.text('Nova venda'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    final last = tester.getRect(find.text('R\$ 10,00'));
    final fab = tester.getRect(
      find.widgetWithText(FloatingActionButton, 'Venda rápida'),
    );
    expect(last.bottom, lessThan(fab.top));
  });

  test('phones formatted', () {
    expect(formatPhone('5511987654321'), '+55 11 98765-4321');
    expect(formatPhone('551132654321'), '+55 11 3265-4321');
    expect(formatPhone('14155552671'), '+14155552671');
    expect(formatPhone(''), '');
  });

  test('the useful line, in order', () {
    const ana = Client(id: 1, name: 'Ana', phone: '5511900000001');
    Sale credit(String due, {int paid = 0}) => Sale(
      clientId: 1,
      soldAt: DateTime(2026, 9, 1),
      items: [_item('Camiseta', 4000)],
      installments: [
        Installment(number: 1, due: '2026-09-01', amount: 2000),
        Installment(number: 2, due: due, amount: 2000),
      ],
      payments: [
        if (paid > 0)
          SalePayment(
            receipt: true,
            method: PayMethod.pix,
            amount: paid,
            at: DateTime(2026, 9, 1),
          ),
      ],
    );
    expect(
      clientHint(ana, [credit('2026-09-30')], _today),
      '1ª parcela venceu há 32 dias',
    );
    expect(
      clientHint(ana, [credit('2026-09-30', paid: 2000)], _today),
      '2ª parcela venceu há 3 dias',
    );
    expect(
      clientHint(ana, [credit('2026-10-09', paid: 2000)], _today),
      '2ª parcela vence sexta, 09/10',
    );
    expect(
      clientHint(ana, [credit('2026-10-04', paid: 2000)], _today),
      '2ª parcela vence amanhã',
    );
    expect(
      clientHint(ana, [credit('2026-11-10', paid: 2000)], _today),
      '2ª parcela vence dia 10/11',
    );
    const birthday = Client(
      id: 1,
      name: 'Ana',
      phone: '5511900000001',
      birthday: '--10-04',
    );
    final old = _paid('Caneca', 2500, at: DateTime(2026, 9, 21), clientId: 1);
    expect(clientHint(birthday, [old], _today), 'Aniversário amanhã');
    expect(clientHint(ana, [old], _today), 'Comprou há 12 dias');
    expect(clientHint(ana, const [], _today), '+55 11 90000-0001');
  });

  testWidgets('the client list with the useful line and the '
      'groups', (tester) async {
    final clients = FakeClientsRepository();
    final sales = FakeSalesRepository()..now = _today;
    Future<int> client(String name, String phone, {String birthday = ''}) =>
        clients.save(Client(name: name, phone: phone, birthday: birthday));
    final carla = await client('Carla Dias', '5511900000001');
    final bruno = await client('Bruno Lima', '5511900000002');
    await client('Marcos Reis', '5511900000003', birthday: '--10-04');
    final ana = await client('Ana Souza', '5511900000004');
    await client('Pedro Alves', '5511900000005');
    for (final (id, due) in [(carla, '2026-09-30'), (bruno, '2026-10-09')]) {
      await sales.conclude(
        Sale(
          clientId: id,
          soldAt: DateTime(2026, 9, 1),
          items: [_item('Camiseta', 4000)],
          installments: [Installment(number: 1, due: due, amount: 4000)],
        ),
      );
    }
    await sales.conclude(
      _paid('Caneca', 2500, at: DateTime(2026, 9, 21), clientId: ana),
    );
    await _pump(
      tester,
      ClientsScreen(repo: clients, clock: () => _today),
      sales: sales,
    );
    expect(find.text('1ª parcela venceu há 3 dias'), findsOneWidget);
    expect(find.text('1ª parcela vence sexta, 09/10'), findsOneWidget);
    expect(find.text('Aniversário amanhã'), findsOneWidget);
    expect(find.text('Comprou há 12 dias'), findsOneWidget);
    expect(find.text('+55 11 90000-0005'), findsOneWidget);
    double y(String text) => tester.getTopLeft(find.text(text).last).dy;
    expect(y('Devendo'), lessThan(y('Bruno Lima')));
    expect(y('Bruno Lima'), lessThan(y('Carla Dias')));
    expect(y('Carla Dias'), lessThan(y('Em dia')));
    expect(y('Em dia'), lessThan(y('Ana Souza')));
    expect(y('Ana Souza'), lessThan(y('Marcos Reis')));
    expect(find.text('Em aberto'), findsOneWidget);
    expect(find.text('Vencido'), findsOneWidget);

    await tester.tap(find.text('Pedro Alves'));
    await tester.pumpAndSettle();
    expect(find.text('+55 11 90000-0005'), findsOneWidget);
  });

  test('the average purchase', () {
    final s = ClientSummary.of([
      _paid('Caneca', 2500),
      _paid('Camiseta', 5000),
      Sale(
        soldAt: _today,
        items: [_item('Cancelada', 9900)],
        canceledAt: _today,
      ),
    ], _today);
    expect(s.ticket, 3750);
    expect(const ClientSummary().ticket, 0);
  });

  /// A shirt on promotion with three sizes, one low and one out of stock.
  Future<(FakeProductsRepository, int, int)> catalog() async {
    final products = FakeProductsRepository();
    final shirt = await products.save(
      const Product(
        name: 'Camiseta básica',
        price: 5990,
        promoPrice: 4990,
        promoUntil: '2026-10-31',
        category: 'Roupas',
        sku: 'CAM-01',
        minStock: 1000,
        attributes: [
          Attribute('Tamanho', ['P', 'M', 'G']),
        ],
        variants: [
          Variant(options: ['P'], cost: 2500, stock: 3000),
          Variant(options: ['M'], cost: 2500, stock: 1000),
          Variant(options: ['G'], cost: 2500, stock: 0),
        ],
      ),
    );
    final mug = await products.save(
      const Product(
        name: 'Caneca',
        price: 2500,
        variants: [Variant(cost: 900, stock: 12000)],
      ),
    );
    return (products, shirt, mug);
  }

  void struck(WidgetTester tester, String text) {
    final style = tester.widget<Text>(find.text(text)).style!;
    expect(style.decoration, TextDecoration.lineThrough, reason: text);
  }

  testWidgets('the regular price struck in the list', (tester) async {
    final (products, _, _) = await catalog();
    await _pump(
      tester,
      ProductsScreen(repo: products, clock: () => _today),
      products: products,
    );
    expect(find.text('R\$ 49,90'), findsOneWidget);
    struck(tester, 'R\$ 59,90');
    expect(find.text('R\$ 25,00'), findsOneWidget);
  });

  testWidgets('the product page', (tester) async {
    final (products, shirt, mug) = await catalog();
    final sales = FakeSalesRepository()..now = _today;
    Future<void> open(int id, {bool large = false}) => _pump(
      tester,
      ProductScreen(repo: products, id: id, clock: () => _today),
      large: large,
      height: large ? 800 : 1500,
      products: products,
      sales: sales,
      clients: FakeClientsRepository(),
    );
    // With large text nothing overflows, down to the end.
    await open(shirt, large: true);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await open(shirt);
    expect(find.text('Camiseta básica'), findsOneWidget);
    expect(find.text('R\$ 49,90'), findsOneWidget);
    struck(tester, 'R\$ 59,90');
    expect(find.text('Estoque baixo'), findsNWidgets(2)); // and M
    expect(find.text('Promoção até 31/10/2026'), findsOneWidget);
    expect(find.text('Sem estoque'), findsOneWidget); // G
    expect(find.byTooltip('Editar'), findsOneWidget);
    expect(find.text('Movimentar estoque'), findsOneWidget);
    for (final (size, stock) in [('P', '3 UN'), ('M', '1 UN'), ('G', '0 UN')]) {
      expect(find.text(size), findsOneWidget);
      expect(find.text(stock), findsOneWidget);
    }
    expect(find.text('Detalhes'), findsOneWidget);
    expect(find.text('CAM-01'), findsOneWidget);

    await tester.tap(find.text('Nova venda com este produto'));
    await tester.pumpAndSettle();
    expect(find.text('Qual variação?'), findsOneWidget);
    await tester.tap(find.text('M').last);
    await tester.pumpAndSettle();
    expect(find.text('Nova venda'), findsOneWidget);
    expect(find.text('Camiseta básica (M)'), findsOneWidget);

    // One variation: straight to the sale.
    await open(mug);
    await tester.tap(find.text('Nova venda com este produto'));
    await tester.pumpAndSettle();
    expect(find.text('Nova venda'), findsOneWidget);
    expect(find.text('Caneca'), findsOneWidget);
  });

  testWidgets('Início with verbs; a product expiring and low appears '
      'once, with both pills', (tester) async {
    final products = FakeProductsRepository();
    await products.save(
      const Product(
        name: 'Hidratante',
        price: 3990,
        expiresOn: '2026-10-13',
        minStock: 5000,
        variants: [Variant(stock: 2000)],
      ),
    );
    await products.save(
      const Product(name: 'Caneca', price: 2500, variants: [Variant()]),
    );
    final clients = FakeClientsRepository();
    await clients.save(const Client(name: 'Ana', phone: '5511900000001'));
    for (final large in [false, true]) {
      await _pump(
        tester,
        StartScreen(
          clients: clients,
          products: products,
          sales: FakeSalesRepository()..now = _today,
          clock: () => _today,
        ),
        large: large,
        height: 1400,
        products: products,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Hidratante'), findsOneWidget);
      expect(find.text('Vence em 10 dias · 2 UN em estoque'), findsOneWidget);
      expect(find.text('Vencendo'), findsOneWidget);
      expect(find.text('Estoque baixo'), findsOneWidget);
      expect(find.text('Caneca'), findsOneWidget);
      expect(find.text('Sem estoque'), findsNWidgets(2)); // text and pill
      for (final verb in ['Nova venda', 'Novo cliente', 'Novo produto']) {
        expect(find.text(verb), findsOneWidget, reason: verb);
      }
    }
    // The most urgent first: out of stock before expiring.
    expect(
      tester.getTopLeft(find.text('Caneca')).dy,
      lessThan(tester.getTopLeft(find.text('Hidratante')).dy),
    );
  });

  group('the new sale in few taps', () {
    late FakeSalesRepository sales;
    late FakeProductsRepository products;
    late FakeClientsRepository clients;

    Future<void> open(WidgetTester tester, {bool large = false}) async {
      sales = FakeSalesRepository()..now = _today;
      products = FakeProductsRepository();
      clients = FakeClientsRepository();
      final ana = await clients.save(
        const Client(name: 'Ana Souza', phone: '5511900000001'),
      );
      sales.names[ana] = 'Ana Souza';
      await products.save(
        const Product(
          name: 'Kit presente com caneca, camiseta e chaveiro personalizado',
          price: 8500,
          variants: [Variant(cost: 4000, stock: 10000)],
        ),
      );
      await _pump(
        tester,
        SaleFormScreen(
          ctx: SaleContext(
            sales: sales,
            products: products,
            clients: clients,
            clock: () => _today,
          ),
        ),
        large: large,
        height: large ? 800 : 1400,
        products: products,
        sales: sales,
        clients: clients,
      );
      await tester.tap(find.text('Adicionar item'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Kit presente').last);
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text).last);
      await tester.tap(find.text(text).last);
      await tester.pumpAndSettle();
    }

    Future<void> conclude(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Concluir'));
      await tester.pumpAndSettle();
    }

    testWidgets('one item, Pix, Concluir: paid', (tester) async {
      await open(tester);
      await tap(tester, 'Pix');
      await conclude(tester);
      final sale = (await sales.list()).single;
      expect(sale.total, 8500);
      expect(sale.payments.single.method, PayMethod.pix);
      expect(sale.payments.single.amount, 8500);
      expect(sale.open, 0);
    });

    testWidgets('cash: R\$ 100,00 received, R\$ 15,00 change, R\$ 85,00 '
        'recorded', (tester) async {
      await open(tester);
      await tap(tester, 'Dinheiro');
      await tester.enterText(
        find.widgetWithText(TextField, 'Valor recebido'),
        '100,00',
      );
      await tester.pumpAndSettle();
      expect(find.text('Troco: R\$ 15,00'), findsOneWidget);
      await conclude(tester);
      final sale = (await sales.list()).single;
      expect(sale.payments.single.method, PayMethod.cash);
      expect(sale.payments.single.amount, 8500);
    });

    testWidgets('fiado asks for the client; "Parcelar" in 3 makes 3', (
      tester,
    ) async {
      await open(tester);
      await tap(tester, 'Fiado');
      await conclude(tester);
      expect(find.text('Fiado precisa de um cliente.'), findsWidgets);
      expect(await sales.list(), isEmpty);
      await tap(tester, 'Escolher cliente');
      await tap(tester, 'Ana Souza');
      await tap(tester, 'Parcelar');
      await tester.enterText(find.widgetWithText(TextField, 'Parcelas'), '3');
      await tester.pumpAndSettle();
      await conclude(tester);
      final sale = (await sales.list()).single;
      expect(sale.installments.map((i) => i.amount), [2834, 2833, 2833]);
      expect(sale.payments, isEmpty);
    });

    testWidgets('another way: transfer', (tester) async {
      await open(tester);
      await tap(tester, 'Outra forma');
      await tap(tester, 'Transferência');
      await conclude(tester);
      expect(
        (await sales.list()).single.payments.single.method,
        PayMethod.transfer,
      );
    });

    for (final large in [false, true]) {
      testWidgets('nothing overflows (${large ? '200%' : '100%'})', (
        tester,
      ) async {
        await open(tester, large: large);
        await tester.enterText(
          find.widgetWithText(TextField, 'Desconto').first,
          '10%',
        );
        await tap(tester, 'Mais detalhes');
        await tester.enterText(find.widgetWithText(TextField, 'Frete'), '1500');
        await tap(tester, 'Dinheiro');
        await tap(tester, 'Fiado');
        await tap(tester, 'Parcelar');
        await tap(tester, 'Dividir em mais de uma forma');
        await tester.enterText(
          find.widgetWithText(TextField, 'Valor').last,
          '1000',
        );
        await tap(tester, 'Adicionar');
        await tap(tester, 'Parcelar o resto');
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -3000),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Pagamento completo.'), findsOneWidget);
      });
    }
  });
}
