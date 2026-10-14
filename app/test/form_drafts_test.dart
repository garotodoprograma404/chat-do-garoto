// Drafts of new forms and leaving without saving.
import 'dart:io';

import 'package:chat_do_garoto/src/clients/client_form_screen.dart';
import 'package:chat_do_garoto/src/home/crm_scope.dart';
import 'package:chat_do_garoto/src/products/product_form_screen.dart';
import 'package:chat_do_garoto/src/storage/app_storage.dart';
import 'package:chat_do_garoto/src/storage/form_drafts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';
import 'support/fake_form_drafts.dart';
import 'support/fake_products_repository.dart';

Future<void> _host(WidgetTester tester, FakeFormDrafts drafts, Widget form) =>
    tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => CrmScope(drafts: drafts, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => form)),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );

String _text(WidgetTester tester, String label) => tester
    .widget<TextField>(find.widgetWithText(TextField, label))
    .controller!
    .text;

void main() {
  test('the draft is kept encrypted in app.db and cleared', () async {
    final dir = Directory.systemTemp.createTempSync('drafts_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = (await AppStorage(
      path: () async => '${dir.path}/app/app.db',
    ).open(newDatabaseKey()) as StorageOpened).database;
    final drafts = DriftFormDrafts(db);
    expect(await drafts.read('product'), isNull);
    await drafts.write('product', {'name': 'Caneca', 'price': r'R$ 25,00'});
    expect((await drafts.read('product'))!['price'], r'R$ 25,00');
    await drafts.clear('product');
    expect(await drafts.read('product'), isNull);
    await db.close();
  });

  testWidgets('a product typed halfway comes back after closing', (
    tester,
  ) async {
    final drafts = FakeFormDrafts();
    final repo = FakeProductsRepository();
    await _host(tester, drafts, ProductFormScreen(repo: repo));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Caneca');
    await tester.enterText(
      find.widgetWithText(TextField, 'Preço de venda'),
      '2500',
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(drafts.saved['product']!['name'], 'Caneca');

    // The app closed: the screen is gone.
    await tester.pumpWidget(const SizedBox());
    await _host(tester, drafts, ProductFormScreen(repo: repo));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Continuar de onde parou?'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'Nome'), 'Caneca');
    expect(_text(tester, 'Preço de venda'), r'R$ 25,00');

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(repo.products, hasLength(1));
    expect(drafts.saved, isEmpty);
  });

  testWidgets('a client draft can be discarded', (tester) async {
    final drafts = FakeFormDrafts()
      ..saved['client'] = {'name': 'Ana', 'phone': '+55 11 9'};
    await _host(
      tester,
      drafts,
      ClientFormScreen(repo: FakeClientsRepository()),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'Nome'), isEmpty);
    expect(drafts.saved, isEmpty);
  });

  testWidgets('back with something typed asks first', (tester) async {
    final drafts = FakeFormDrafts();
    await _host(
      tester,
      drafts,
      ClientFormScreen(repo: FakeClientsRepository()),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Bia');
    await tester.pump(const Duration(milliseconds: 600));

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Descartar o que foi digitado?'), findsOneWidget);
    await tester.tap(find.text('Continuar editando'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'Nome'), 'Bia');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(find.text('abrir'), findsOneWidget);
    expect(drafts.saved, isEmpty);
  });
}
