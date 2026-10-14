// The revised screens with text at 200%, light and dark, scrolled to the
// end.
import 'package:chat_do_garoto/src/chats/chat_screen.dart';
import 'package:chat_do_garoto/src/clients/client_screen.dart';
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/clients/clients_screen.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:chat_do_garoto/src/home/crm_scope.dart';
import 'package:chat_do_garoto/src/home/start_screen.dart';
import 'package:chat_do_garoto/src/lock/lock_controller.dart';
import 'package:chat_do_garoto/src/products/product_screen.dart';
import 'package:chat_do_garoto/src/products/products_repository.dart';
import 'package:chat_do_garoto/src/products/products_screen.dart';
import 'package:chat_do_garoto/src/products/variants.dart';
import 'package:chat_do_garoto/src/sales/sale_form_screen.dart';
import 'package:chat_do_garoto/src/sales/sale_math.dart';
import 'package:chat_do_garoto/src/sales/sale_screen.dart';
import 'package:chat_do_garoto/src/sales/sales_repository.dart';
import 'package:chat_do_garoto/src/sales/sales_screen.dart';
import 'package:chat_do_garoto/src/settings/settings_screen.dart';
import 'package:chat_do_garoto/src/theme/app_theme.dart';
import 'package:chat_do_garoto/src/theme/theme_controller.dart';
import 'package:chat_do_garoto/src/whatsapp/whatsapp_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_prefs.dart';
import 'support/fake_clients_repository.dart';
import 'support/fake_connection_keeper.dart';
import 'support/fake_core_bridge.dart';
import 'support/fake_key_vault.dart';
import 'support/fake_products_repository.dart';
import 'support/fake_sales_repository.dart';
import 'support/fake_security.dart';
import 'support/fake_wa_key.dart';

final _today = DateTime(2026, 10, 3, 10);
const _jid = '5511900000001@s.whatsapp.net';

void main() {
  for (final dark in [false, true]) {
    testWidgets('the revised screens at 200% '
        '(${dark ? 'escuro' : 'claro'})', (tester) async {
      final clients = FakeClientsRepository();
      final products = FakeProductsRepository();
      final sales = FakeSalesRepository()..now = _today;
      final maria = await clients.save(
        const Client(
          name: 'Maria Aparecida dos Santos Oliveira',
          phone: '5511900000001',
          chatJid: _jid,
          birthday: '--10-04',
          tags: ['revenda', 'atacado'],
        ),
      );
      sales.names[maria] = 'Maria Aparecida dos Santos Oliveira';
      final shirt = await products.save(
        const Product(
          name: 'Camiseta básica de algodão orgânico',
          price: 12990,
          promoPrice: 9990,
          promoUntil: '2026-10-31',
          category: 'Vestuário',
          brand: 'Malha Boa',
          sku: 'CAM-ORG-01',
          barcode: '7891000315507',
          minStock: 2000,
          expiresOn: '2026-10-20',
          attributes: [
            Attribute('Tamanho', ['P', 'GG']),
          ],
          variants: [
            Variant(options: ['P'], cost: 4000, stock: 1000),
            Variant(options: ['GG'], cost: 4500, price: 13990, stock: -2000),
          ],
        ),
      );
      final saleId = await sales.conclude(
        Sale(
          clientId: maria,
          soldAt: DateTime(2026, 9, 2),
          items: const [
            SaleItem(
              variantId: 1,
              description: 'Camiseta básica de algodão orgânico (GG)',
              quantity: 3000,
              unitPrice: 12990,
            ),
          ],
          installments: const [
            Installment(number: 1, due: '2026-09-29', amount: 19485),
            Installment(number: 2, due: '2026-10-29', amount: 19485),
          ],
        ),
      );
      final bridge = FakeCoreBridge(paired: true)
        ..chats = [
          ChatSummary(
            jid: _jid,
            name: 'Maria',
            lastText: 'Oi, tem a camiseta azul em M?',
            lastTs: _today.millisecondsSinceEpoch,
          ),
        ]
        ..messages[_jid] = [
          for (var i = 0; i < 6; i++)
            ChatMessage(
              chat: _jid,
              id: 'm$i',
              fromMe: i.isOdd,
              senderName: '',
              kind: 'text',
              text: 'Tenho sim! Quer que separe uma para você?',
              ts: _today.millisecondsSinceEpoch - (6 - i) * 60000,
              status: i.isOdd ? 'read' : '',
            ),
        ];
      final whatsapp = WhatsAppController(
        bridge: bridge,
        sessionPath: () async => '/tmp/test-wa.db',
        keeper: FakeConnectionKeeper(),
        keys: FakeWaKeyProvider(),
      );
      await whatsapp.start();
      final lock = LockController(
        bridge: bridge,
        security: FakeSecurity(),
        vault: (name) => FakeKeyVault(),
      );
      await lock.start();
      final ctx = SaleContext(
        sales: sales,
        products: products,
        clients: clients,
        clock: () => _today,
      );

      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      Future<void> check(
        String name,
        Widget home, [
        Future<void> Function()? setup,
      ]) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(2),
            ),
            child: MaterialApp(
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              builder: (context, child) => CrmScope(
                products: products,
                sales: sales,
                clients: clients,
                chatPrefs: FakeChatPrefs(),
                child: child!,
              ),
              home: home,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await setup?.call();
        await tester.pumpAndSettle();
        // Each vertical list to its end; found again after each drag,
        // which rebuilds them.
        for (var i = 0; ; i++) {
          final all = find.byType(Scrollable).evaluate().toList();
          if (i >= all.length) break;
          final scrollable = all[i].widget as Scrollable;
          if (scrollable.axisDirection != AxisDirection.down) continue;
          await tester.drag(
            find.byType(Scrollable).at(i),
            const Offset(0, -4000),
            warnIfMissed: false,
          );
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull, reason: name);
      }

      await check(
        'Início',
        StartScreen(
          clients: clients,
          products: products,
          sales: sales,
          bridge: bridge,
          clock: () => _today,
          onOpenSettings: () {},
          onOpenWaiting: () {},
        ),
      );
      await check(
        'Conversa',
        ChatScreen(
          bridge: bridge,
          chat: bridge.chats.single,
          clients: clients,
          clock: () => _today,
        ),
      );
      await check(
        'Clientes',
        ClientsScreen(repo: clients, clock: () => _today),
      );
      await check(
        'Ficha do cliente',
        ClientScreen(repo: clients, id: maria, clock: () => _today),
      );
      await check(
        'Produtos',
        ProductsScreen(repo: products, clock: () => _today),
      );
      await check(
        'Ficha do produto',
        ProductScreen(repo: products, id: shirt, clock: () => _today),
      );
      await check('Vendas', SalesScreen(ctx: ctx));
      await check('A receber', SalesScreen(ctx: ctx), () async {
        await tester.tap(find.widgetWithText(Tab, 'A receber'));
      });
      await check('Venda', SaleScreen(ctx: ctx, id: saleId));
      await check(
        'Nova venda',
        SaleFormScreen(
          ctx: ctx,
          item: (
            products.products[shirt]!,
            products.products[shirt]!.variants.last,
          ),
        ),
        () async {
          await tester.ensureVisible(find.text('Fiado'));
          await tester.tap(find.text('Fiado'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Parcelar'));
          await tester.tap(find.text('Parcelar'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Mais detalhes'));
          await tester.tap(find.text('Mais detalhes'));
        },
      );
      await check(
        'Configurações',
        SettingsScreen(
          whatsapp: whatsapp,
          lock: lock,
          theme: ThemeController(store: FakeKeyVault()),
          onOpenBackup: () {},
        ),
      );
    });
  }
}
