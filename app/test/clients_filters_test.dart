// Client search, filters and sorting.
import 'package:chat_do_garoto/src/clients/clients_controller.dart';
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/clients/clients_screen.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';
import 'support/fake_core_bridge.dart';

final _today = DateTime(2026, 10, 2);

Future<(FakeClientsRepository, FakeCoreBridge)> _world() async {
  final repo = FakeClientsRepository();
  final bridge = FakeCoreBridge()
    ..chats = const [
      ChatSummary(
        jid: '5511900000002@s.whatsapp.net',
        name: '',
        lastText: '',
        lastTs: 500,
      ),
      ChatSummary(
        jid: '28175035842608@lid',
        name: '',
        lastText: '',
        lastTs: 900,
      ),
    ]
    ..chatsByPhone['5511900000003'] = '28175035842608@lid';
  // Saved in this order: createdAt grows.
  final ana = await repo.save(
    const Client(
      name: 'Ána Souza',
      phone: '5511900000001',
      birthday: '--10-20',
      tags: ['vip'],
    ),
  );
  await repo.save(
    const Client(
      name: 'bruno',
      phone: '5511900000002',
      document: '52998224725',
      birthday: '1990-10-03',
      tags: ['atacado'],
    ),
  );
  await repo.save(
    const Client(
      name: 'Caio',
      phone: '5511900000003',
      company: 'Padaria Central',
      birthday: '--01-05',
    ),
  );
  await repo.save(const Client(name: 'Duda', phone: '5511900000004'));
  await repo.addNote(ana, 'quer orçamento de cadeiras');
  return (repo, bridge);
}

Future<ClientsController> _controller() async {
  final (repo, bridge) = await _world();
  final c = ClientsController(repo: repo, bridge: bridge, clock: () => _today);
  await c.load();
  return c;
}

List<String> _names(ClientsController c) => [for (final x in c.clients) x.name];

void main() {
  test('days until the next birthday; 29/02 falls on 01/03', () {
    expect(daysUntilBirthday('--10-02', _today), 0);
    expect(daysUntilBirthday('1990-10-03', _today), 1);
    expect(daysUntilBirthday('--10-01', _today), 364);
    expect(daysUntilBirthday('--02-29', DateTime(2027, 2, 28)), 1);
    expect(daysUntilBirthday('', _today), isNull);
    expect(birthdayIn('--10-20', 10), isTrue);
    expect(birthdayIn('--01-05', 10), isFalse);
  });

  test('search in every field, notes included, accents ignored', () async {
    final c = await _controller();
    c.search('ana');
    expect(_names(c), ['Ána Souza']);
    c.search('cadeiras'); // only in a note
    expect(_names(c), ['Ána Souza']);
    c.search('padaria');
    expect(_names(c), ['Caio']);
    c.search('atacado');
    expect(_names(c), ['bruno']);
    c.search('90000-0004'); // part of a phone
    expect(_names(c), ['Duda']);
    c.search('529.982'); // part of a CPF
    expect(_names(c), ['bruno']);
    c.search('');
    expect(_names(c), hasLength(4));
  });

  test('tag and birthday-month filters add to the search', () async {
    final c = await _controller();
    c.toggleTag('vip');
    c.toggleTag('atacado');
    expect(_names(c), ['Ána Souza', 'bruno']);
    c.toggleTag('atacado');
    expect(_names(c), ['Ána Souza']);
    c.toggleTag('vip');
    c.toggleBirthdays();
    expect(_names(c), ['Ána Souza', 'bruno']);
    c.search('bru');
    expect(_names(c), ['bruno']);
  });

  test('four orders; clients without the value go last', () async {
    final c = await _controller();
    expect(_names(c), [
      'Ána Souza',
      'bruno',
      'Caio',
      'Duda',
    ], reason: 'name, accents ignored');
    c.sortBy(ClientSort.newest);
    expect(_names(c), ['Duda', 'Caio', 'bruno', 'Ána Souza']);
    c.sortBy(ClientSort.lastChat);
    // Caio's chat is under a private ID; Ana and Duda never talked.
    expect(_names(c), ['Caio', 'bruno', 'Ána Souza', 'Duda']);
    c.sortBy(ClientSort.birthday);
    expect(_names(c), ['bruno', 'Ána Souza', 'Caio', 'Duda']);
  });

  testWidgets('the screen searches, filters and counts', (tester) async {
    final (repo, bridge) = await _world();
    await tester.pumpWidget(
      MaterialApp(
        home: ClientsScreen(repo: repo, bridge: bridge),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('4 de 4'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar clientes'),
      'souza',
    );
    await tester.pumpAndSettle();
    expect(find.text('1 de 4'), findsOneWidget);
    expect(find.text('Ána Souza'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar clientes'),
      '',
    );
    await tester.tap(find.widgetWithText(FilterChip, 'atacado'));
    await tester.pumpAndSettle();
    expect(find.text('1 de 4'), findsOneWidget);
    expect(find.text('bruno'), findsOneWidget);

    await tester.tap(find.byTooltip('Ordenar'));
    await tester.pumpAndSettle();
    expect(find.text('Próximo aniversário'), findsOneWidget);
  });
}
