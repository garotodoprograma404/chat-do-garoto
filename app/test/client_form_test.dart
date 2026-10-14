// The short client form.
import 'package:chat_do_garoto/src/clients/client_form_screen.dart';
import 'package:chat_do_garoto/src/clients/contact_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';

class _Picker implements ContactPicker {
  @override
  Future<PickedContact?> pick() async => null;
}

void main() {
  tearDown(() => contactPicker = null);

  testWidgets('name, phone and the address book; the rest closed; '
      'masks while typing', (tester) async {
    contactPicker = _Picker();
    final repo = FakeClientsRepository();
    await tester.pumpWidget(MaterialApp(home: ClientFormScreen(repo: repo)));
    expect(find.text('Escolher da agenda'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Mais detalhes'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Telefone (com DDD)'),
      '5511987654321',
    );
    await tester.pump();
    expect(find.text('+55 11 98765-4321'), findsOneWidget);

    await tester.tap(find.text('Mais detalhes'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'CPF ou CNPJ'),
      '52998224725',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Aniversário'),
      '0503',
    );
    await tester.pump();
    expect(find.text('529.982.247-25'), findsOneWidget);
    expect(find.text('05/03'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Ana');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final saved = repo.clients.values.single;
    expect(saved.phone, '5511987654321');
    expect(saved.document, '52998224725');
    expect(saved.birthday, '--03-05');
  });
}
