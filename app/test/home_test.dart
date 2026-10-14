// Sections and Configurações with fakes.
import 'package:chat_do_garoto/src/chats/chats_controller.dart';
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/home/home_shell.dart';
import 'package:chat_do_garoto/src/lock/lock_controller.dart';
import 'package:chat_do_garoto/src/settings/settings_screen.dart';
import 'package:chat_do_garoto/src/theme/theme_controller.dart';
import 'package:chat_do_garoto/src/whatsapp/whatsapp_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';
import 'support/fake_connection_keeper.dart';
import 'support/fake_core_bridge.dart';
import 'support/fake_key_vault.dart';
import 'support/fake_products_repository.dart';
import 'support/fake_sales_repository.dart';
import 'support/fake_security.dart';
import 'support/fake_wa_key.dart';

Future<(FakeCoreBridge, WhatsAppController)> _whatsapp({
  required bool paired,
}) async {
  final bridge = FakeCoreBridge(paired: paired);
  final controller = WhatsAppController(
    bridge: bridge,
    sessionPath: () async => '/tmp/test-wa.db',
    keeper: FakeConnectionKeeper(),
    keys: FakeWaKeyProvider(),
  );
  await controller.start();
  return (bridge, controller);
}

void main() {
  testWidgets('five sections, opening on Início; Configurações from '
      'Início and from the ⋮ menu', (tester) async {
    final (bridge, whatsapp) = await _whatsapp(paired: true);
    final repo = FakeClientsRepository();
    await repo.save(const Client(name: 'Ana', phone: '5511900000001'));
    var settings = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          bridge: bridge,
          whatsapp: whatsapp,
          chats: ChatsController(bridge: bridge)..start(),
          clients: repo,
          products: FakeProductsRepository(),
          sales: FakeSalesRepository(),
          onOpenSettings: () => settings++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Início first, with Configurações at the top.
    for (final tab in [
      'Início',
      'Conversas',
      'Clientes',
      'Produtos',
      'Vendas',
    ]) {
      expect(find.text(tab), findsWidgets, reason: tab);
    }
    expect(find.text('Hoje'), findsOneWidget);
    await tester.tap(find.byTooltip('Configurações'));
    await tester.pumpAndSettle();
    expect(settings, 1);

    await tester.tap(find.text('Conversas').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configurações'));
    await tester.pumpAndSettle();
    expect(settings, 2);

    await tester.tap(find.text('Clientes').last);
    await tester.pumpAndSettle();
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Novo cliente'), findsOneWidget);

    // The Produtos section, with the ⋮ menu too.
    await tester.tap(find.text('Produtos').last);
    await tester.pumpAndSettle();
    expect(find.text('Nenhum produto ainda.'), findsOneWidget);
    expect(find.text('Novo produto'), findsOneWidget);
    expect(find.byTooltip('Mais opções'), findsOneWidget);

    // The Vendas section, with its two tabs.
    await tester.tap(find.text('Vendas').last);
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma venda ainda.'), findsOneWidget);
    expect(find.text('A receber'), findsOneWidget);
    expect(find.text('Nova venda'), findsOneWidget);
  });

  testWidgets('without WhatsApp, Clientes still works', (tester) async {
    final (bridge, whatsapp) = await _whatsapp(paired: false);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          bridge: bridge,
          whatsapp: whatsapp,
          chats: ChatsController(bridge: bridge),
          clients: FakeClientsRepository(),
          onOpenSettings: () {},
        ),
      ),
    );
    // The pairing screen has an endless spinner: pump instead of settle.
    await tester.pump();
    await tester.tap(find.text('Conversas').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Conectar ao WhatsApp'), findsOneWidget);

    await tester.tap(find.text('Clientes').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nenhum cliente ainda.'), findsOneWidget);
  });

  testWidgets(
    'Configurações gathers connection, stability, battery and security',
    (tester) async {
      final (bridge, whatsapp) = await _whatsapp(paired: true);
      final lock = LockController(
        bridge: bridge,
        security: FakeSecurity(),
        vault: (name) => FakeKeyVault(),
      );
      await lock.start();
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(whatsapp: whatsapp, lock: lock),
        ),
      );
      for (final item in [
        'Conexão com o WhatsApp',
        'Estabilidade da conexão',
        'Bateria',
        'Trocar PIN',
        'Desbloquear com a digital',
      ]) {
        expect(find.text(item), findsOneWidget, reason: item);
      }
      await tester.tap(find.text('Estabilidade da conexão'));
      await tester.pumpAndSettle();
      expect(bridge.calls, contains('connectionReport'));
    },
  );

  testWidgets('Configurações in groups, each item with its '
      'icon', (tester) async {
    final (bridge, whatsapp) = await _whatsapp(paired: true);
    final lock = LockController(
      bridge: bridge,
      security: FakeSecurity(),
      vault: (name) => FakeKeyVault(),
    );
    await lock.start();
    tester.view.physicalSize = const Size(720, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          whatsapp: whatsapp,
          lock: lock,
          theme: ThemeController(store: FakeKeyVault()),
          onOpenBackup: () {},
        ),
      ),
    );
    for (final group in ['WhatsApp', 'Dados', 'Aparência', 'Segurança']) {
      expect(find.text(group), findsOneWidget, reason: group);
    }
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles.length, greaterThanOrEqualTo(7));
    for (final t in tiles) {
      expect(t.leading, isA<Icon>(), reason: '${(t.title as Text?)?.data}');
    }
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).secondary,
      isA<Icon>(),
    );
    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('WhatsApp'), lessThan(y('Bateria')));
    expect(y('Dados'), lessThan(y('Backup')));
    expect(y('Segurança'), lessThan(y('Trocar PIN')));
  });
}
