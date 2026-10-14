// The short product form.
import 'package:chat_do_garoto/src/products/pricing.dart';
import 'package:chat_do_garoto/src/products/product_form_screen.dart';
import 'package:chat_do_garoto/src/products/product_photos.dart';
import 'package:chat_do_garoto/src/products/products_repository.dart';
import 'package:chat_do_garoto/src/products/variants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_products_repository.dart';

class _NoPhotos implements PhotoPicker {
  @override
  Future<Never> pick(PhotoSource source) => throw UnimplementedError();
}

final _today = DateTime(2026, 10, 3, 10);

Future<void> _form(
  WidgetTester tester,
  FakeProductsRepository repo, {
  Product? initial,
}) async {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: ProductFormScreen(
        repo: repo,
        photos: _NoPhotos(),
        initial: initial,
        clock: () => _today,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String label) => tester
    .widget<TextField>(find.widgetWithText(TextField, label))
    .controller!
    .text;

void main() {
  testWidgets('a new product shows photo, name, price and stock only', (
    tester,
  ) async {
    final repo = FakeProductsRepository();
    await _form(tester, repo);
    expect(find.text('Adicionar foto'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    for (final label in ['Nome', 'Preço de venda', 'Estoque (UN)']) {
      expect(find.widgetWithText(TextField, label), findsOneWidget);
    }
    expect(find.text('Mais detalhes'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Caneca');
    await tester.enterText(
      find.widgetWithText(TextField, 'Preço de venda'),
      '2500',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final p = repo.products.values.single;
    expect(p.name, 'Caneca');
    expect(p.price, 2500);
  });

  testWidgets('money and dates format while typing, number keyboards', (
    tester,
  ) async {
    await _form(tester, FakeProductsRepository());
    await tester.enterText(
      find.widgetWithText(TextField, 'Preço de venda'),
      '1290',
    );
    await tester.pump();
    expect(_text(tester, 'Preço de venda'), r'R$ 12,90');
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Preço de venda'))
          .keyboardType,
      TextInputType.number,
    );
    await tester.tap(find.text('Estoque e validade'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Validade'),
      '13102026',
    );
    await tester.pump();
    expect(_text(tester, 'Validade'), '13/10/2026');
  });

  testWidgets('the closed groups summarize a full product, and saving '
      'keeps everything', (tester) async {
    final repo = FakeProductsRepository();
    final id = await repo.save(
      const Product(
        name: 'Camiseta básica',
        price: 5990,
        promoPrice: 4990,
        promoUntil: '2026-10-31',
        barcode: '7891035210006',
        sku: 'CAM-01',
        category: 'Roupas',
        brand: 'Hering',
        supplier: 'Malhas SP',
        description: 'Algodão',
        expiresOn: '2027-01-31',
        minStock: 2000,
        tiers: [WholesaleTier(10000, 4500)],
        attributes: [
          Attribute('Tamanho', ['P', 'M', 'G']),
        ],
        variants: [
          Variant(options: ['P'], cost: 2500, stock: 3000),
          Variant(options: ['M'], cost: 2500, stock: 5000),
          Variant(options: ['G'], cost: 2500, stock: 1000),
        ],
      ),
    );
    final before = (await repo.byId(id))!;
    await _form(tester, repo, initial: before);
    for (final summary in [
      'cód. CAM-01 · 7891035210006',
      r'R$ 49,90 até 31/10/2026',
      r'a partir de 10: R$ 45,00',
      'mínimo 2 · validade 31/01/2027',
      '3 variações (Tamanho)',
      'Roupas · Hering · Malhas SP · com descrição',
      'Ativo',
    ]) {
      expect(find.text(summary), findsOneWidget, reason: summary);
    }
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final after = (await repo.byId(id))!;
    expect(after.price, 5990);
    expect(after.promoPrice, 4990);
    expect(after.promoUntil, '2026-10-31');
    expect(after.barcode, '7891035210006');
    expect(after.sku, 'CAM-01');
    expect(after.tiers.single.price, 4500);
    expect(after.minStock, 2000);
    expect(after.expiresOn, '2027-01-31');
    expect(after.variants.map((v) => v.stock), [3000, 5000, 1000]);
    expect(after.supplier, 'Malhas SP');
  });

  testWidgets('errors open their group and scroll to the field', (
    tester,
  ) async {
    await _form(tester, FakeProductsRepository());
    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Caneca');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Digite o valor.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Preço de venda'),
      '2500',
    );
    await tester.tap(find.text('Atacado'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'A partir de (UN)'),
      '10',
    );
    // Closing it hides the field; the error opens it again.
    await tester.tap(find.text('Atacado'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'A partir de (UN)'), findsNothing);
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'A partir de (UN)'), findsOneWidget);
    expect(find.text('Digite o valor.'), findsOneWidget);
  });
}
