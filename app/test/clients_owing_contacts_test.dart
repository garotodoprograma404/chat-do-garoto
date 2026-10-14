// Clientes: the "Devendo" filter and "Escolher da agenda".
import 'package:chat_do_garoto/src/clients/client_form_screen.dart';
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/clients/clients_screen.dart';
import 'package:chat_do_garoto/src/clients/contact_picker.dart';
import 'package:chat_do_garoto/src/clients/validation.dart';
import 'package:chat_do_garoto/src/home/crm_scope.dart';
import 'package:chat_do_garoto/src/sales/sale_math.dart';
import 'package:chat_do_garoto/src/sales/sales_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';
import 'support/fake_sales_repository.dart';

class _FakePicker implements ContactPicker {
  _FakePicker(this.result);
  PickedContact? result;
  Object? error;

  @override
  Future<PickedContact?> pick() async {
    if (error case final e?) throw e;
    return result;
  }
}

String _field(WidgetTester tester, String label) => tester
    .widget<TextField>(find.widgetWithText(TextField, label))
    .controller!
    .text;

void main() {
  tearDown(() => contactPicker = null);

  test('a number from the address book gets the 55 when missing', () {
    expect(normalizePhone('(11) 98765-4321'), '5511987654321');
    expect(normalizePhone('011 98765-4321'), '5511987654321');
    expect(normalizePhone('11 3456-7890'), '551134567890');
    expect(normalizePhone('+55 11 98765-4321'), '5511987654321');
    expect(normalizePhone('+1 415 555 0100'), '14155550100');
    expect(normalizePhone('98765-4321'), '987654321'); // no area: left as is
  });

  testWidgets('"Devendo" shows only who has something to receive', (
    tester,
  ) async {
    final repo = FakeClientsRepository();
    final sales = FakeSalesRepository();
    final ana = await repo.save(
      const Client(name: 'Ana', phone: '5511900000001'),
    );
    await repo.save(const Client(name: 'Bruno', phone: '5511900000002'));
    await sales.conclude(
      Sale(
        clientId: ana,
        soldAt: DateTime(2026, 9, 1),
        items: const [
          SaleItem(
            variantId: 1,
            description: 'Item',
            quantity: 1000,
            unitPrice: 5000,
          ),
        ],
        installments: const [
          Installment(number: 1, due: '2026-12-01', amount: 5000),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => CrmScope(sales: sales, child: child!),
        home: ClientsScreen(repo: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 de 2'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Devendo'));
    await tester.pumpAndSettle();
    expect(find.text('1 de 2'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Bruno'), findsNothing);
  });

  testWidgets('"Escolher da agenda" fills name and phone', (tester) async {
    final picker = _FakePicker((name: 'Carla Dias', phone: '(11) 98765-4321'));
    contactPicker = picker;
    await tester.pumpWidget(
      MaterialApp(home: ClientFormScreen(repo: FakeClientsRepository())),
    );

    await tester.tap(find.text('Escolher da agenda'));
    await tester.pumpAndSettle();
    expect(_field(tester, 'Nome'), 'Carla Dias');
    expect(_field(tester, 'Telefone (com DDD)'), '+55 11 98765-4321');

    // Cancelling keeps what is there.
    picker.result = null;
    await tester.tap(find.text('Escolher da agenda'));
    await tester.pumpAndSettle();
    expect(_field(tester, 'Nome'), 'Carla Dias');

    // A picker that fails says so.
    picker.error = PlatformException(code: 'unavailable');
    await tester.tap(find.text('Escolher da agenda'));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível abrir a agenda.'), findsOneWidget);
  });

  testWidgets('no agenda button when editing or saving from a chat', (
    tester,
  ) async {
    contactPicker = _FakePicker(null);
    await tester.pumpWidget(
      MaterialApp(
        home: ClientFormScreen(
          repo: FakeClientsRepository(),
          initial: const Client(name: 'Ana', phone: '5511900000001'),
        ),
      ),
    );
    expect(find.text('Escolher da agenda'), findsNothing);
  });

  Sale bought(int client, DateTime at, {bool canceled = false}) => Sale(
    clientId: client,
    soldAt: at,
    canceledAt: canceled ? at : null,
    items: const [
      SaleItem(
        variantId: 1,
        description: 'Item',
        quantity: 1000,
        unitPrice: 100,
      ),
    ],
    payments: [SalePayment(method: PayMethod.pix, amount: 100, at: at)],
  );

  test('"Sumidos" bought, but not for more than 60 days', () {
    final today = DateTime(2026, 10, 3, 9);
    DateTime ago(int days) => today.subtract(Duration(days: days));
    final gone = goneClients([
      bought(1, ago(61)), // gone
      bought(2, ago(59)), // still buying
      bought(3, ago(90)), bought(3, ago(10)), // came back
      bought(4, ago(200), canceled: true), // only a canceled one
    ], today);
    expect(gone, {1});
  });

  testWidgets('the "Sumidos" chip', (tester) async {
    final repo = FakeClientsRepository();
    final sales = FakeSalesRepository();
    final ana = await repo.save(
      const Client(name: 'Ana', phone: '5511900000001'),
    );
    final bia = await repo.save(
      const Client(name: 'Bia', phone: '5511900000002'),
    );
    await repo.save(const Client(name: 'Caio', phone: '5511900000003'));
    final now = DateTime.now();
    await sales.conclude(bought(ana, now.subtract(const Duration(days: 70))));
    await sales.conclude(bought(bia, now.subtract(const Duration(days: 5))));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => CrmScope(sales: sales, child: child!),
        home: ClientsScreen(repo: repo),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Sumidos'));
    await tester.pumpAndSettle();
    expect(find.text('1 de 3'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
  });
}
