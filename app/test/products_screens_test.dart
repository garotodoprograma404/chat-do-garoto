// Product screens with an in-memory repository and fake photos.
import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_do_garoto/src/products/product_photos.dart';
import 'package:chat_do_garoto/src/products/products_repository.dart';
import 'package:chat_do_garoto/src/products/products_screen.dart';
import 'package:chat_do_garoto/src/products/variants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_products_repository.dart';

// A 1x1 PNG.
final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  ),
);

class FakePhotoPicker implements PhotoPicker {
  final asked = <PhotoSource>[];

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    asked.add(source);
    return _png;
  }
}

final _today = DateTime(2026, 10, 2, 15);

/// The "Mais detalhes" group of each field of the product form.
const _groups = {
  'Código de barras': 'Código de barras e código interno',
  'Código interno (SKU)': 'Código de barras e código interno',
  'Preço de custo': 'Custo e lucro',
  'Preço promocional': 'Promoção',
  'Promoção até': 'Promoção',
  'A partir de (UN)': 'Atacado',
  'Estoque mínimo (UN)': 'Estoque e validade',
  'Validade': 'Estoque e validade',
  'Categoria': 'Categoria, marca e descrição',
  'Marca': 'Categoria, marca e descrição',
  'Fornecedor': 'Categoria, marca e descrição',
  'Descrição': 'Categoria, marca e descrição',
  'Adicionar atributo': 'Variações (tamanho, cor…)',
};

/// Opens the group of [label] when it is closed.
Future<void> _show(WidgetTester tester, String label) async {
  final group = _groups[label];
  if (group == null || find.text(label).evaluate().isNotEmpty) return;
  await tester.tap(find.text(group));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String label, String text) async {
  await _show(tester, label);
  await tester.enterText(find.widgetWithText(TextField, label).first, text);
}

Future<void> _tap(WidgetTester tester, String text) async {
  await _show(tester, text);
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

/// A tall screen, so the long form is built at once.
Future<void> _open(
  WidgetTester tester,
  FakeProductsRepository repo, {
  PhotoPicker? photos,
}) async {
  tester.view.physicalSize = const Size(1000, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: ProductsScreen(repo: repo, photos: photos, clock: () => _today),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a simple product with every field; wrong data is refused', (
    tester,
  ) async {
    final repo = FakeProductsRepository();
    final photos = FakePhotoPicker();
    await _open(tester, repo, photos: photos);
    expect(find.text('Nenhum produto ainda.'), findsOneWidget);

    await _tap(tester, 'Novo produto');
    // A simple product shows no variation row.
    expect(find.textContaining('variação'), findsNothing);
    await _type(tester, 'Código de barras', '7891000315508');
    await _type(tester, 'Preço promocional', '60,00');
    await _type(tester, 'Promoção até', '31/09/2026');
    await _type(tester, 'Estoque (UN)', '1,5');
    await _tap(tester, 'Salvar');
    expect(find.text('Digite o nome.'), findsOneWidget);
    expect(find.text('Digite o valor.'), findsOneWidget);
    expect(
      find.text('Código de barras com um número errado. Confira.'),
      findsOneWidget,
    );
    expect(find.text('Use dd/mm/aaaa.'), findsOneWidget);
    expect(find.text('Só números inteiros em UN.'), findsOneWidget);
    expect(repo.products, isEmpty);

    await _type(tester, 'Nome', 'Caneca de cerâmica');
    await _type(tester, 'Código interno (SKU)', 'CAN-01');
    await _type(tester, 'Código de barras', '7891000315507');
    await _type(tester, 'Categoria', 'Cozinha');
    await _type(tester, 'Marca', 'Barro Bom');
    await _type(tester, 'Fornecedor', 'Olaria');
    await _type(tester, 'Descrição', 'Caneca de 300 ml');
    await _type(tester, 'Preço de venda', '50,00');
    await _type(tester, 'Preço de custo', '20,00');
    await tester.pump();
    expect(find.text('Lucro: R\$ 30,00 · margem 60,0%'), findsOneWidget);
    await _type(tester, 'Promoção até', '01/10/2026');
    await _tap(tester, 'Salvar');
    expect(
      find.text('Precisa ser menor que o preço de venda.'),
      findsOneWidget,
    );
    expect(find.text('Essa data já passou.'), findsOneWidget);

    await _type(tester, 'Preço promocional', '39,90');
    await _type(tester, 'Promoção até', '31/10/2026');
    await _type(tester, 'A partir de (UN)', '10');
    await tester.enterText(
      find.widgetWithText(TextField, 'Preço').last,
      '35,00',
    );
    await _type(tester, 'Estoque mínimo (UN)', '2');
    await _type(tester, 'Estoque (UN)', '12');
    await _tap(tester, 'Adicionar foto');
    await _tap(tester, 'Tirar foto');
    await _tap(tester, 'Adicionar foto');
    await _tap(tester, 'Escolher da galeria');
    expect(photos.asked, [PhotoSource.camera, PhotoSource.gallery]);
    expect(find.text('Principal'), findsOneWidget);
    await _tap(tester, 'Salvar');

    final p = repo.products.values.single;
    expect(p.name, 'Caneca de cerâmica');
    expect(p.sku, 'CAN-01');
    expect(p.barcode, '7891000315507');
    expect(p.category, 'Cozinha');
    expect(p.price, 5000);
    expect(p.promoPrice, 3990);
    expect(p.promoUntil, '2026-10-31');
    expect(p.tiers.single.minQty, 10000);
    expect(p.tiers.single.price, 3500);
    expect(p.minStock, 2000);
    expect(p.variants.single.cost, 2000);
    expect(p.variants.single.stock, 12000);
    expect(p.photoIds.length, 2);

    // The list: price of today with the promotion, stock.
    // The price on the right, with the promotion pill.
    expect(find.text('R\$ 39,90'), findsOneWidget);
    expect(find.text('Promoção'), findsOneWidget);
    expect(find.textContaining('12 UN'), findsOneWidget);
    expect(find.text('1 de 1'), findsOneWidget);

    // The page: price of today with the regular one struck,
    // cost, profit and margin; the photo.
    await _tap(tester, 'Caneca de cerâmica');
    expect(find.text('R\$ 39,90'), findsOneWidget);
    expect(find.text('R\$ 50,00'), findsOneWidget);
    expect(
      find.text('Custo R\$ 20,00 · lucro R\$ 19,90 · margem 49,9%'),
      findsOneWidget,
    );
    expect(find.text('Promoção até 31/10/2026'), findsOneWidget);
    expect(find.text('R\$ 39,90 · até 31/10/2026'), findsOneWidget);
    expect(find.text('Atacado: a partir de 10 UN'), findsOneWidget);
    await tester.tap(find.byType(ProductThumb).first);
    await tester.pumpAndSettle();
    expect(find.text('Foto'), findsOneWidget);
  });

  testWidgets('variations in a grid; removing values warns', (tester) async {
    final repo = FakeProductsRepository();
    await _open(tester, repo);
    await _tap(tester, 'Novo produto');
    await _type(tester, 'Nome', 'Camiseta');
    await _type(tester, 'Preço de venda', '50,00');
    await _type(tester, 'Preço de custo', '20,00');
    await _tap(tester, 'Adicionar atributo');
    await _type(tester, 'Atributo', 'Cor');
    await _type(tester, 'Valores, separados por vírgula', 'Azul, Preto');
    await _tap(tester, 'Adicionar atributo');
    await tester.enterText(
      find.widgetWithText(TextField, 'Atributo').last,
      'Tamanho',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Valores, separados por vírgula').last,
      'P, M, G',
    );
    await tester.pumpAndSettle();
    expect(find.text('6 variações'), findsOneWidget);
    expect(find.text('Azul / P'), findsOneWidget);
    expect(find.text('Preço de custo (das variações novas)'), findsOneWidget);

    // Stock and a price of its own for one variation.
    await tester.enterText(
      find.widgetWithText(TextField, 'Estoque').first,
      '3',
    );
    await tester.tap(find.byTooltip('Editar Preto / G'));
    await tester.pumpAndSettle();
    await _type(tester, 'Preço próprio', '55,00');
    await _type(tester, 'Código', 'CAM-PG');
    await _tap(tester, 'Fechar');
    expect(find.text('cód. CAM-PG · R\$ 55,00'), findsOneWidget);
    await _tap(tester, 'Salvar');

    final p = repo.products.values.single;
    expect(p.attributes.map((a) => a.name), ['Cor', 'Tamanho']);
    expect(p.variants.length, 6);
    expect(p.variants.first.stock, 3000);
    expect(p.variants.first.cost, 2000);
    expect(p.variants.last.price, 5500);
    expect(p.variants.last.sku, 'CAM-PG');
    expect(find.text('a partir de R\$ 50,00'), findsOneWidget);
    expect(find.textContaining('3 UN'), findsOneWidget);

    // Editing: "Preto" goes away with its 3 variations.
    await _tap(tester, 'Camiseta');
    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();
    await _show(tester, 'Adicionar atributo');
    await tester.enterText(
      find.widgetWithText(TextField, 'Valores, separados por vírgula').first,
      'Azul, Verde',
    );
    await tester.pumpAndSettle();
    await _tap(tester, 'Salvar');
    expect(find.text('Apagar 3 variações?'), findsOneWidget);
    await _tap(tester, 'Apagar e salvar');
    final after = repo.products.values.single;
    expect(after.variants.map((v) => v.label), [
      'Azul / P',
      'Azul / M',
      'Azul / G',
      'Verde / P',
      'Verde / M',
      'Verde / G',
    ]);
    expect(after.variants.first.stock, 3000);
  });

  testWidgets('a repeated code is refused', (tester) async {
    final repo = FakeProductsRepository();
    await repo.save(
      const Product(
        name: 'Caneca',
        sku: 'X1',
        price: 100,
        variants: [Variant()],
      ),
    );
    await _open(tester, repo);
    await _tap(tester, 'Novo produto');
    await _type(tester, 'Nome', 'Outra');
    await _type(tester, 'Código interno (SKU)', 'X1');
    await _type(tester, 'Preço de venda', '10,00');
    await _tap(tester, 'Salvar');
    expect(find.text('Este código já está em uso.'), findsOneWidget);
    expect(repo.products.length, 1);
  });

  testWidgets('stock: entry with average cost, negative exit, count, history', (
    tester,
  ) async {
    final repo = FakeProductsRepository();
    await repo.save(
      const Product(
        name: 'Camiseta',
        price: 5000,
        attributes: [
          Attribute('Cor', ['Azul', 'Preto']),
        ],
        variants: [
          Variant(options: ['Azul'], cost: 500, stock: 10000),
          Variant(options: ['Preto'], cost: 500, stock: 1000),
        ],
      ),
    );
    await _open(tester, repo);
    await _tap(tester, 'Camiseta');

    // Entry with cost: 10 at R$ 5,00 + 10 at R$ 7,00.
    await _tap(tester, 'Movimentar estoque');
    await _type(tester, 'Quantidade (UN)', '10');
    await _type(tester, 'Custo unitário (opcional)', '7,00');
    await tester.pump();
    expect(
      find.text('Estoque depois: 20 UN · custo médio R\$ 6,00'),
      findsOneWidget,
    );
    await _tap(tester, 'Registrar');
    var azul = repo.products.values.single.variants.first;
    expect(azul.stock, 20000);
    expect(azul.cost, 600);

    // Exit of Preto beyond its stock: reason required, then a warning.
    await _tap(tester, 'Movimentar estoque');
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await _tap(tester, 'Preto (1 UN)');
    await _tap(tester, 'Saída');
    await _type(tester, 'Quantidade (UN)', '3');
    await _tap(tester, 'Registrar');
    expect(find.text('Escolha o motivo.'), findsOneWidget);
    await _tap(tester, 'Perda');
    await _type(tester, 'Observação', 'caiu');
    await _tap(tester, 'Registrar');
    expect(find.text('Estoque negativo'), findsOneWidget);
    expect(find.textContaining('-2 UN'), findsWidgets);
    await _tap(tester, 'Registrar mesmo assim');
    final preto = repo.products.values.single.variants.last;
    expect(preto.stock, -2000);
    expect(find.text('-2 UN'), findsWidgets);
    expect(
      find.text('R\$ 50,00 · Custo R\$ 5,00 · lucro R\$ 45,00 · margem 90,0%'),
      findsOneWidget,
    );

    // Count of Azul: counted 18, the difference is recorded.
    await _tap(tester, 'Movimentar estoque');
    await _tap(tester, 'Balanço');
    await _type(tester, 'Quantidade contada (UN)', '18');
    await _tap(tester, 'Registrar');
    azul = repo.products.values.single.variants.first;
    expect(azul.stock, 18000);

    await _tap(tester, 'Ver histórico do estoque');
    expect(find.text('Balanço -2 UN'), findsOneWidget);
    expect(find.text('Saída -3 UN'), findsOneWidget);
    expect(find.text('Entrada +10 UN'), findsOneWidget);
    expect(find.text('Estoque inicial +10 UN'), findsOneWidget);
    expect(find.textContaining('Perda · caiu · saldo -2 UN'), findsOneWidget);
    expect(find.textContaining('custo R\$ 7,00 · saldo 20 UN'), findsOneWidget);
  });

  testWidgets('deleting asks first', (tester) async {
    final repo = FakeProductsRepository();
    await repo.save(
      const Product(name: 'Caneca', price: 100, variants: [Variant()]),
    );
    await _open(tester, repo);
    await _tap(tester, 'Caneca');
    await tester.tap(find.byTooltip('Apagar produto'));
    await tester.pumpAndSettle();
    await _tap(tester, 'Cancelar');
    expect(repo.products.length, 1);
    await tester.tap(find.byTooltip('Apagar produto'));
    await tester.pumpAndSettle();
    await _tap(tester, 'Apagar');
    expect(repo.products, isEmpty);
    expect(find.text('Nenhum produto ainda.'), findsOneWidget);
  });

  testWidgets('a service has no stock fields', (tester) async {
    final repo = FakeProductsRepository();
    await _open(tester, repo);
    await _tap(tester, 'Novo produto');
    await tester.tap(find.text('Produto ou serviço'));
    await tester.pumpAndSettle();
    await _tap(tester, 'Serviço');
    expect(find.text('Estoque (UN)'), findsNothing);
    expect(find.text('Estoque e validade'), findsNothing);
    expect(find.text('Variações (tamanho, cor…)'), findsNothing);
    await _type(tester, 'Nome', 'Consultoria');
    await _type(tester, 'Preço de venda', '200,00');
    await _tap(tester, 'Salvar');
    final p = repo.products.values.single;
    expect(p.isService, isTrue);
    expect(find.text('R\$ 200,00'), findsOneWidget);
    await _tap(tester, 'Consultoria');
    expect(find.text('Movimentar estoque'), findsNothing);
  });

  testWidgets('the last buttons scroll above the system navigation bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(bottom: 94);
    addTearDown(tester.view.reset);
    final repo = FakeProductsRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ProductsScreen(
          repo: repo,
          photos: FakePhotoPicker(),
          clock: () => _today,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, 'Novo produto');
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -3000),
    );
    await tester.pumpAndSettle();
    // The last group of "Mais detalhes".
    final bottom = tester.getRect(find.text('Produto ou serviço')).bottom;
    expect(bottom, lessThanOrEqualTo(800 - 47));
  });
}
