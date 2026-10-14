import 'package:chat_do_garoto/src/clients/clients_controller.dart';
import 'package:chat_do_garoto/src/products/products_controller.dart';
import 'package:chat_do_garoto/src/sales/sales_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';
import 'support/fake_products_repository.dart';
import 'support/fake_sales_repository.dart';

/// A list that is closed while the database still answers (the user
/// changed section) must not fail.
void main() {
  test(
    'the lists ignore an answer that comes after they were closed',
    () async {
      final sales = SalesController(repo: FakeSalesRepository())..load();
      final products = ProductsController(repo: FakeProductsRepository())
        ..load();
      final clients = ClientsController(repo: FakeClientsRepository())..load();
      sales.dispose();
      products.dispose();
      clients.dispose();
      // Let the pending answers arrive: with the bug, this throws.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    },
  );
}
