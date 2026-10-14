// Validade and the photo first.
import 'package:chat_do_garoto/src/home/start_screen.dart';
import 'package:chat_do_garoto/src/products/product_form_screen.dart';
import 'package:chat_do_garoto/src/products/product_photos.dart';
import 'package:chat_do_garoto/src/products/products_repository.dart';
import 'package:chat_do_garoto/src/products/products_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';
import 'support/fake_products_repository.dart';
import 'support/fake_sales_repository.dart';

final _today = DateTime(2026, 10, 3, 10);

class _NoPhotos implements PhotoPicker {
  @override
  Future<Never> pick(PhotoSource source) => throw UnimplementedError();
}

Future<FakeProductsRepository> _catalog() async {
  final repo = FakeProductsRepository();
  for (final (name, expires, active) in [
    ('Hidratante', '2026-10-13', true), // 10 days
    ('Shampoo', '2026-10-02', true), // yesterday
    ('Perfume', '2026-12-02', true), // 60 days
    ('Sabonete antigo', '2026-09-01', false), // inactive
    ('Caneca', null, true),
  ]) {
    await repo.save(
      Product(
        name: name,
        price: 1000,
        expiresOn: expires,
        active: active,
        variants: const [Variant(stock: 5000)],
      ),
    );
  }
  return repo;
}

void main() {
  test('the expiry label', () {
    Product p(String d) => Product(name: 'x', price: 1, expiresOn: d);
    expect(expiryLabel(p('2026-10-13'), _today), 'Vence em 10 dias');
    expect(expiryLabel(p('2026-10-04'), _today), 'Vence amanhã');
    expect(expiryLabel(p('2026-10-03'), _today), 'Vence hoje');
    expect(expiryLabel(p('2026-10-02'), _today), 'Vencido ontem');
    expect(expiryLabel(p('2026-09-30'), _today), 'Vencido há 3 dias');
    expect(expiryLabel(const Product(name: 'x', price: 1), _today), isNull);
  });

  testWidgets('the list shows the expiry and filters "Vencendo"', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProductsScreen(repo: await _catalog(), clock: () => _today),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Vence em 10 dias'), findsOneWidget);
    expect(find.text('Vencido'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Vencendo'));
    await tester.pumpAndSettle();
    expect(find.text('Hidratante'), findsOneWidget);
    expect(find.text('Shampoo'), findsOneWidget);
    expect(find.text('Perfume'), findsNothing);
    expect(find.text('Caneca'), findsNothing);
    expect(find.text('Sabonete antigo'), findsNothing);
  });

  testWidgets('the Início warns of what is expiring', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: StartScreen(
          clients: FakeClientsRepository(),
          products: await _catalog(),
          sales: FakeSalesRepository(),
          clock: () => _today,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Shampoo'), findsOneWidget);
    expect(find.text('Vencido ontem'), findsOneWidget);
    expect(find.text('Hidratante'), findsOneWidget);
    expect(find.text('Vence em 10 dias'), findsOneWidget);
    expect(find.text('Perfume'), findsNothing);
    expect(find.text('Sabonete antigo'), findsNothing);
    // The soonest first.
    expect(
      tester.getTopLeft(find.text('Shampoo')).dy,
      lessThan(tester.getTopLeft(find.text('Hidratante')).dy),
    );
  });

  testWidgets('photos first; the expiry is saved', (tester) async {
    tester.view.physicalSize = const Size(1000, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeProductsRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ProductFormScreen(
          repo: repo,
          photos: _NoPhotos(),
          clock: () => _today,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Adicionar foto')).dy,
      lessThan(tester.getTopLeft(find.widgetWithText(TextField, 'Nome')).dy),
    );

    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Creme');
    await tester.enterText(
      find.widgetWithText(TextField, 'Preço de venda'),
      '30,00',
    );
    await tester.tap(find.text('Estoque e validade'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Validade'), '31/13');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Use dd/mm/aaaa.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Validade'),
      '12/10/2026',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect((await repo.list()).single.expiresOn, '2026-10-12');
  });
}
