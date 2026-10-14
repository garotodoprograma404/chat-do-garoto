// The address by CEP in the client form.
import 'package:chat_do_garoto/src/clients/cep_lookup.dart';
import 'package:chat_do_garoto/src/clients/client_form_screen.dart';
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';

class _FakeCep implements CepLookup {
  final asked = <String>[];

  @override
  Future<CepAddress> find(String cep) async {
    asked.add(cep);
    return switch (cep) {
      '01001000' => (
        street: 'Praça da Sé',
        district: 'Sé',
        city: 'São Paulo',
        state: 'SP',
      ),
      '99999999' => throw const CepUnavailable(),
      _ => throw const CepNotFound(),
    };
  }
}

String _text(WidgetTester tester, String label) => tester
    .widget<TextField>(find.widgetWithText(TextField, label))
    .controller!
    .text;

void main() {
  late _FakeCep fake;
  setUp(() => cepLookup = fake = _FakeCep());
  tearDown(() => cepLookup = HttpCepLookup());

  test('the full address in one line', () {
    const c = Client(
      name: 'Ana',
      phone: '5511900000001',
      address: 'Praça da Sé',
      number: '10',
      complement: 'sala 2',
      district: 'Sé',
      city: 'São Paulo',
      state: 'SP',
      cep: '01001000',
    );
    expect(
      c.fullAddress,
      'Praça da Sé, 10, sala 2 – Sé, São Paulo/SP – 01001-000',
    );
    expect(const Client(name: 'x', phone: '1').fullAddress, isEmpty);
  });

  testWidgets('"Buscar CEP" fills the address; errors warn; typed '
      'fields stay', (tester) async {
    tester.view.physicalSize = const Size(720, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final repo = FakeClientsRepository();
    await tester.pumpWidget(MaterialApp(home: ClientFormScreen(repo: repo)));
    await tester.tap(find.text('Mais detalhes'));
    await tester.pumpAndSettle();
    expect(fake.asked, isEmpty, reason: 'nothing without the tap');

    await tester.enterText(find.widgetWithText(TextField, 'CEP'), '12345678');
    await tester.tap(find.text('Buscar CEP'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CEP não encontrado'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'CEP'), '99999999');
    await tester.tap(find.text('Buscar CEP'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sem conexão'), findsOneWidget);

    // The city typed by hand is kept.
    await tester.enterText(
      find.widgetWithText(TextField, 'Cidade'),
      'SP capital',
    );
    await tester.enterText(find.widgetWithText(TextField, 'CEP'), '01001000');
    expect(_text(tester, 'CEP'), '01001-000');
    await tester.tap(find.text('Buscar CEP'));
    await tester.pumpAndSettle();
    expect(fake.asked.last, '01001000');
    expect(_text(tester, 'Rua'), 'Praça da Sé');
    expect(_text(tester, 'Bairro'), 'Sé');
    expect(_text(tester, 'UF'), 'SP');
    expect(_text(tester, 'Cidade'), 'SP capital');

    await tester.enterText(find.widgetWithText(TextField, 'Número'), '10');
    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Ana');
    await tester.enterText(
      find.widgetWithText(TextField, 'Telefone (com DDD)'),
      '5511900000001',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    final c = repo.clients.values.single;
    expect(c.cep, '01001000');
    expect(c.address, 'Praça da Sé');
    expect(c.number, '10');
    expect(c.district, 'Sé');
    expect(c.city, 'SP capital');
    expect(c.state, 'SP');
  });
}
