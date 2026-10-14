// The Vendas panel redone, measured with the
// app's own fonts: the test font is wider and would not show the layout
// of the phone.
import 'dart:io';

import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/sales/sale_math.dart';
import 'package:chat_do_garoto/src/sales/sales_controller.dart';
import 'package:chat_do_garoto/src/sales/sales_repository.dart';
import 'package:chat_do_garoto/src/sales/sales_screen.dart';
import 'package:chat_do_garoto/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';
import 'support/fake_products_repository.dart';
import 'support/fake_sales_repository.dart';

final _today = DateTime(2026, 10, 3, 10);

SaleItem _item(String name, int cents) =>
    SaleItem(variantId: 1, description: name, quantity: 1000, unitPrice: cents);

Sale _paid(String name, int cents, {DateTime? at}) => Sale(
  soldAt: at ?? _today,
  items: [_item(name, cents)],
  payments: [
    SalePayment(method: PayMethod.pix, amount: cents, at: at ?? _today),
  ],
);

Future<void> _fonts(WidgetTester tester) => tester.runAsync(() async {
  for (final family in [AppTheme.textFont, AppTheme.displayFont]) {
    final bytes = File('assets/fonts/$family.ttf').readAsBytesSync();
    await (FontLoader(
      family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
});

/// The Redmi width.
Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(720, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: home));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the Vendas panel: compact top, one row of filters, '
      'search, groups and the buttons side by side', (tester) async {
    await _fonts(tester);
    final sales = FakeSalesRepository()..now = _today;
    final clients = FakeClientsRepository();
    final bruno = await clients.save(
      const Client(name: 'Bruno Lima', phone: '5511900000002'),
    );
    sales.names[bruno] = 'Bruno Lima';
    await sales.conclude(_paid('Caneca', 2500));
    await sales.conclude(_paid('Camiseta', 5000, at: DateTime(2026, 8, 10)));
    await sales.conclude(
      Sale(
        clientId: bruno,
        soldAt: DateTime(2026, 9, 2),
        items: [_item('Bolsa', 9000)],
        installments: const [
          Installment(number: 1, due: '2026-09-30', amount: 4500),
          Installment(number: 2, due: '2026-10-30', amount: 4500),
        ],
      ),
    );
    final ctx = SaleContext(
      sales: sales,
      products: FakeProductsRepository(),
      clients: clients,
      clock: () => _today,
    );
    await _pump(tester, SalesScreen(ctx: ctx));

    // The list starts right under the tabs, the filters and the totals.
    expect(tester.getTopLeft(find.text('Hoje').last).dy, lessThan(320));
    expect(find.text('Vendido · 3 vendas'), findsOneWidget);
    // One row of filters.
    expect(
      tester.getCenter(find.text('Todo o período')).dy,
      moreOrLessEquals(
        tester
            .getCenter(
              find.descendant(
                of: find.widgetWithText(FilterChip, 'Paga'),
                matching: find.text('Paga'),
              ),
            )
            .dy,
        epsilon: 2,
      ),
    );
    // Side by side.
    expect(
      tester.getTopLeft(find.text('Venda rápida')).dy,
      tester.getTopLeft(find.text('Nova venda')).dy,
    );

    // The period opens its choices.
    await tester.tap(find.text('Todo o período'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckedPopupMenuItem<SalePeriod>), findsNWidgets(5));
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<SalePeriod>, 'Este mês'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Este mês'), findsOneWidget);
    expect(find.text('Vendido · 1 venda'), findsOneWidget);
    await tester.tap(find.text('Este mês'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<SalePeriod>, 'Todo o período'),
    );
    await tester.pumpAndSettle();

    // A situation, further along the row.
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'Vencida'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Vencida'));
    await tester.pumpAndSettle();
    expect(find.text('Vendido · 1 venda'), findsOneWidget);
    expect(find.text('Bruno Lima'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Vencida'));
    await tester.pumpAndSettle();

    // The search behind the icon.
    await tester.tap(find.byTooltip('Buscar vendas'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bolsa');
    await tester.pumpAndSettle();
    expect(find.text('Vendido · 1 venda'), findsOneWidget);
    await tester.tap(find.byTooltip('Fechar busca'));
    await tester.pumpAndSettle();
    expect(find.text('Vendido · 3 vendas'), findsOneWidget);

    // A receber: the card and the groups.
    await tester.tap(find.widgetWithText(Tab, 'A receber'));
    await tester.pumpAndSettle();
    expect(find.text('A receber · 2 parcelas'), findsOneWidget);
    expect(find.text('Vencidas'), findsOneWidget);
    expect(find.text('A vencer'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Vencidas')).dy,
      lessThan(tester.getTopLeft(find.text('A vencer')).dy),
    );
  });
}
