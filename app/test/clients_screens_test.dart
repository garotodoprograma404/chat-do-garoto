// Client screens with an in-memory repository.
import 'package:chat_do_garoto/src/clients/client_screen.dart';
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/clients/clients_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';

/// Types into a field of the client form, opening "Mais detalhes" when
/// the field is in it.
Future<void> _type(WidgetTester tester, String label, String text) async {
  if (find.widgetWithText(TextField, label).evaluate().isEmpty) {
    await tester.tap(find.text('Mais detalhes'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.widgetWithText(TextField, label), text);
}

void main() {
  testWidgets('a new client with every field; wrong data is refused', (
    tester,
  ) async {
    final repo = FakeClientsRepository();
    await tester.pumpWidget(MaterialApp(home: ClientsScreen(repo: repo)));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum cliente ainda.'), findsOneWidget);

    await tester.tap(find.text('Novo cliente'));
    await tester.pumpAndSettle();
    await _type(tester, 'Nome', 'Ana Souza');
    await _type(tester, 'Telefone (com DDD)', '55 11 90000-0001');
    await _type(tester, 'E-mail', 'ana@exemplo');
    await _type(tester, 'CPF ou CNPJ', '529.982.247-24');
    await _type(tester, 'Aniversário', '31/04');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('E-mail inválido.'), findsOneWidget);
    expect(find.text('CPF inválido.'), findsOneWidget);
    expect(find.text('Use dd/mm ou dd/mm/aaaa.'), findsOneWidget);
    expect(repo.clients, isEmpty);

    await _type(tester, 'E-mail', 'ana@exemplo.com');
    await _type(tester, 'CPF ou CNPJ', '529.982.247-25');
    await _type(tester, 'Aniversário', '05/03/1990');
    await _type(tester, 'Rua', 'Rua A, 1');
    await _type(tester, 'Empresa', 'Loja da Ana');
    await _type(tester, 'Etiquetas', 'VIP, atacado');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Ana Souza'), findsOneWidget);
    final saved = repo.clients.values.single;
    expect(saved.phone, '5511900000001');
    expect(saved.document, '52998224725');
    expect(saved.birthday, '1990-03-05');
    expect(saved.tags, ['vip', 'atacado']);
  });

  testWidgets('a repeated phone is refused', (tester) async {
    final repo = FakeClientsRepository();
    await repo.save(const Client(name: 'Ana', phone: '5511900000001'));
    await tester.pumpWidget(MaterialApp(home: ClientsScreen(repo: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Novo cliente'));
    await tester.pumpAndSettle();
    await _type(tester, 'Nome', 'Outra');
    await _type(tester, 'Telefone (com DDD)', '5511900000001');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Já existe um cliente com este telefone.'),
      findsOneWidget,
    );
  });

  testWidgets('notes: newest first, with date and time; one deleted', (
    tester,
  ) async {
    final repo = FakeClientsRepository();
    final id = await repo.save(
      const Client(
        name: 'Ana',
        phone: '5511900000001',
        document: '52998224725',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ClientScreen(repo: repo, id: id),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('529.982.247-25'), findsOneWidget);

    for (final text in ['primeira', 'segunda']) {
      await tester.enterText(
        find.widgetWithText(TextField, 'Nova anotação'),
        text,
      );
      await tester.tap(find.text('Anotar'));
      await tester.pumpAndSettle();
    }
    final first = tester.getTopLeft(find.text('segunda')).dy;
    final second = tester.getTopLeft(find.text('primeira')).dy;
    expect(first, lessThan(second));
    expect(find.text('02/10/2026 09:02'), findsOneWidget);

    await tester.tap(find.byTooltip('Apagar anotação').last);
    await tester.pumpAndSettle();
    expect(find.text('primeira'), findsNothing);
    expect(find.text('segunda'), findsOneWidget);
  });

  testWidgets('deleting asks first, then the client is gone', (tester) async {
    final repo = FakeClientsRepository();
    final id = await repo.save(
      const Client(name: 'Ana', phone: '5511900000001'),
    );
    await tester.pumpWidget(MaterialApp(home: ClientsScreen(repo: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Apagar cliente'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('conversa do WhatsApp continua'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.clients, contains(id));

    await tester.tap(find.byTooltip('Apagar cliente'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apagar'));
    await tester.pumpAndSettle();
    expect(repo.clients, isEmpty);
    expect(find.text('Nenhum cliente ainda.'), findsOneWidget);
  });
}
