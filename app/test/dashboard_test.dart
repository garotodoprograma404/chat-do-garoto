import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/home/start_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';
import 'support/fake_products_repository.dart';
import 'support/fake_sales_repository.dart';

/// The Início of a wide window is a panel of cards: at every
/// width from where it starts, nothing overflows.
void main() {
  for (final width in [900.0, 960.0, 1000.0, 1180.0, 1440.0, 1920.0]) {
    testWidgets('the panel fits at $width wide', (tester) async {
      tester.view
        ..physicalSize = Size(width, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // With one client the Início is no longer the first-run welcome.
      final clients = FakeClientsRepository();
      await clients.save(const Client(name: 'Ana', phone: '5511900000001'));
      await tester.pumpWidget(
        MaterialApp(
          home: StartScreen(
            clients: clients,
            products: FakeProductsRepository(),
            sales: FakeSalesRepository(),
            clock: () => DateTime(2026, 10, 3, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The month's numbers sit on top, in cards.
      expect(find.text('Faturamento'), findsOneWidget);
      expect(find.text('Ticket médio'), findsOneWidget);
    });
  }
}
