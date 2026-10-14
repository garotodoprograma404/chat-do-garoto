// The name of a conversation: the client panel and the "contato novo"
// strip.
import 'package:chat_do_garoto/src/chats/chat_screen.dart';
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:chat_do_garoto/src/home/crm_scope.dart';
import 'package:chat_do_garoto/src/sales/sale_math.dart';
import 'package:chat_do_garoto/src/sales/sales_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_prefs.dart';
import 'support/fake_clients_repository.dart';
import 'support/fake_core_bridge.dart';
import 'support/fake_products_repository.dart';
import 'support/fake_sales_repository.dart';

const _pn = '5511900000001@s.whatsapp.net';
final _today = DateTime(2026, 10, 2, 9);

ChatSummary _chat(String jid, String name) =>
    ChatSummary(jid: jid, name: name, lastText: '', lastTs: 0);

typedef _World = ({
  FakeCoreBridge bridge,
  FakeClientsRepository clients,
  FakeSalesRepository sales,
  FakeChatPrefs prefs,
});

_World _world() => (
  bridge: FakeCoreBridge(),
  clients: FakeClientsRepository(),
  sales: FakeSalesRepository()..now = _today,
  prefs: FakeChatPrefs(),
);

Future<void> _open(WidgetTester tester, _World w, ChatSummary chat) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => CrmScope(
        sales: w.sales,
        products: FakeProductsRepository(),
        chatPrefs: w.prefs,
        child: child!,
      ),
      home: ChatScreen(
        bridge: w.bridge,
        chat: chat,
        clients: w.clients,
        clock: () => _today,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _field(WidgetTester tester, String label) => tester
    .widget<TextField>(find.widgetWithText(TextField, label))
    .controller!
    .text;

void main() {
  testWidgets('"Cadastrar" fills name and phone and links the chat', (
    tester,
  ) async {
    final w = _world();
    w.bridge.phones[_pn] = '5511900000001';
    await _open(tester, w, _chat(_pn, 'Ana'));
    expect(find.text('Contato novo'), findsOneWidget);

    await tester.tap(find.text('Cadastrar'));
    await tester.pumpAndSettle();
    expect(_field(tester, 'Nome'), 'Ana');
    expect(_field(tester, 'Telefone (com DDD)'), '+55 11 90000-0001');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(w.clients.clients.values.single.chatJid, _pn);
    expect(find.text('Contato novo'), findsNothing);
    expect(find.text('cliente'), findsOneWidget); // the mark in the title
  });

  testWidgets('the panel of someone who is not a client', (tester) async {
    final w = _world();
    w.bridge.phones[_pn] = '5511900000001';
    await _open(tester, w, _chat(_pn, 'Ana'));

    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    expect(find.text('+55 11 90000-0001'), findsOneWidget);
    expect(find.text('Este contato ainda não é cliente.'), findsOneWidget);
    expect(find.text('Cadastrar como cliente'), findsOneWidget);
    expect(find.text('Vincular a um cliente'), findsOneWidget);

    await tester.tap(find.text('Cadastrar como cliente'));
    await tester.pumpAndSettle();
    expect(_field(tester, 'Nome'), 'Ana');
  });

  testWidgets('without the phone, it is typed by hand', (tester) async {
    final w = _world();
    await _open(tester, w, _chat('99999@lid', 'Bia'));
    await tester.tap(find.text('Cadastrar'));
    await tester.pumpAndSettle();
    expect(_field(tester, 'Telefone (com DDD)'), isEmpty);
  });

  testWidgets(
    'a chat under a private ID finds the client by the phone WhatsApp told',
    (tester) async {
      final w = _world();
      w.bridge.phones['123456789@lid'] = '5511900000009';
      await w.clients.save(
        const Client(name: 'Bia Souza', phone: '5511900000009'),
      );
      await _open(tester, w, _chat('123456789@lid', 'Bia'));
      expect(find.text('Bia Souza'), findsOneWidget);
      expect(find.text('Contato novo'), findsNothing);
    },
  );

  testWidgets('"Vincular" links a client, asking when already linked', (
    tester,
  ) async {
    final w = _world();
    await w.clients.save(
      const Client(
        name: 'Carla Dias',
        phone: '5511900000003',
        chatJid: '5511900000077@s.whatsapp.net',
      ),
    );
    await _open(tester, w, _chat(_pn, 'Carlinha'));

    await tester.tap(find.text('Vincular'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carla Dias'));
    await tester.pumpAndSettle();
    expect(find.text('Trocar a conversa?'), findsOneWidget);
    await tester.tap(find.text('Ligar a esta'));
    await tester.pumpAndSettle();

    expect(w.clients.clients.values.single.chatJid, _pn);
    expect(find.text('Carla Dias'), findsOneWidget); // the title
    expect(find.text('Contato novo'), findsNothing);
  });

  testWidgets('"Ignorar" hides the strip, "Desfazer" brings it back', (
    tester,
  ) async {
    final w = _world();
    await _open(tester, w, _chat(_pn, 'Ana'));

    await tester.tap(find.text('Ignorar'));
    await tester.pumpAndSettle();
    expect(find.text('Contato novo'), findsNothing);
    expect(w.prefs.ignoredChats, {_pn});

    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();
    expect(find.text('Contato novo'), findsOneWidget);
    expect(w.prefs.ignoredChats, isEmpty);
  });

  testWidgets('the panel of a client who owes, and "Nova venda"', (
    tester,
  ) async {
    final w = _world();
    final id = await w.clients.save(
      const Client(
        name: 'Maria Souza',
        phone: '5511900000001',
        tags: ['revenda'],
      ),
    );
    await w.clients.addNote(id, 'Prefere entrega à tarde');
    w.sales.names[id] = 'Maria Souza';
    await w.sales.conclude(
      Sale(
        clientId: id,
        soldAt: DateTime(2026, 9, 2),
        items: const [
          SaleItem(
            variantId: 1,
            description: 'Camiseta',
            quantity: 1000,
            unitPrice: 30000,
          ),
        ],
        installments: const [
          Installment(number: 1, due: '2026-09-29', amount: 15000),
          Installment(number: 2, due: '2026-10-29', amount: 15000),
        ],
      ),
    );
    await _open(tester, w, _chat(_pn, 'Maria'));
    expect(find.text('Contato novo'), findsNothing);

    await tester.tap(find.text('Maria Souza'));
    await tester.pumpAndSettle();
    expect(find.text('R\$ 300,00'), findsOneWidget); // owes
    expect(find.text('Vencido R\$ 150,00'), findsOneWidget);
    expect(
      find.text(
        'Comprou R\$ 300,00 em 1 compra · ticket médio R\$ 300,00 · última em 02/09/2026',
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.textContaining('Prefere entrega à tarde'),
      ),
      findsOneWidget,
    );
    expect(find.text('revenda'), findsOneWidget);
    for (final action in ['Receber', 'Cobrar', 'Ver ficha']) {
      expect(find.text(action), findsOneWidget);
    }

    await tester.tap(find.text('Nova venda'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Nova venda'), findsOneWidget);
    expect(find.textContaining('Maria Souza'), findsWidgets);
  });

  testWidgets('a group: the contact screen, never a client', (tester) async {
    final w = _world();
    await _open(tester, w, _chat('120363000000000001@g.us', 'Família'));
    expect(find.text('Contato novo'), findsNothing);
    await tester.tap(find.text('Família'));
    await tester.pumpAndSettle();
    expect(find.text('Dados do contato'), findsOneWidget);
    expect(find.text('Grupo'), findsOneWidget);
  });
}
