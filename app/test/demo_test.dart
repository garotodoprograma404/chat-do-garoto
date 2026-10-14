import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:chat_do_garoto/src/demo/demo_app.dart';
import 'package:chat_do_garoto/src/demo/demo_core_bridge.dart';
import 'package:chat_do_garoto/src/intro/intro_screen.dart';
import 'package:chat_do_garoto/src/sales/sale_math.dart';
import 'package:chat_do_garoto/src/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The demo: invented data, all in memory, alive conversations.
void main() {
  group('the demo WhatsApp', () {
    test('conversations come newest first, with names', () {
      final bridge = DemoCoreBridge();
      addTearDown(bridge.dispose);
      final chats = bridge.listChats();
      expect(chats, hasLength(demoChats.length));
      for (var i = 1; i < chats.length; i++) {
        expect(chats[i - 1].lastTs, greaterThanOrEqualTo(chats[i].lastTs));
      }
      expect(chats.first.name, 'Ana Paula');
      expect(bridge.listMessages(chats.first.jid), isNotEmpty);
    });

    test('my message is read and the contact answers', () async {
      final bridge = DemoCoreBridge(
        replyAfter: const Duration(milliseconds: 80),
        statusStep: const Duration(milliseconds: 10),
      );
      addTearDown(bridge.dispose);
      final events = <CoreEvent>[];
      final sub = bridge.events.listen(events.add);
      addTearDown(sub.cancel);
      const chat = '5511900000101@s.whatsapp.net';

      final sent = bridge.sendText(chat, 'Separei aqui!');
      expect(sent.status, 'sending');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        [
          for (final e in events)
            if (e.type == 'wa_message_status') e.data['status'],
        ],
        ['sent', 'delivered', 'read'],
      );
      final answer = events.singleWhere((e) => e.type == 'wa_message');
      expect(answer.data['chat'], chat);
      expect(answer.data['from_me'], false);
      final last = bridge.listMessages(chat).last;
      expect(last.fromMe, false);
      expect(bridge.listChats().first.jid, chat);
    });

    test('nothing to send is refused; search ignores accents', () {
      final bridge = DemoCoreBridge();
      addTearDown(bridge.dispose);
      expect(() => bridge.sendText('x', '  '), throwsA(isA<CoreException>()));
      expect(bridge.searchMessages('MAQUINA'), isNotEmpty);
    });
  });

  group('the demo store', () {
    test('clients, products and sales, with the cases that matter', () async {
      final session = await DemoSession.open();
      addTearDown(session.close);
      final now = DateTime.now();

      expect(await session.clients.list(), hasLength(7));
      final products = await session.products.list();
      expect(products, hasLength(7));
      final sales = await session.sales.list();
      expect(sales, hasLength(7));

      final statuses = {for (final s in sales) s.status(now)};
      expect(statuses, containsAll([SaleStatus.paid, SaleStatus.overdue]));
      expect(statuses, contains(SaleStatus.open));
      // Every client of a conversation is linked by the phone.
      for (final c in demoChats.where((c) => c.jid.endsWith('.net'))) {
        final phone = c.jid.split('@').first;
        if (phone.endsWith('199')) continue; // the new contact
        expect(
          (await session.clients.list()).any((x) => x.phone == phone),
          isTrue,
          reason: c.name,
        );
      }
    });

    // The demo runs where neither the files folder (path_provider)
    // nor the system vault (secure storage) exist, as in tests: had it
    // touched them, opening would fail.
    test('opens and closes without the disk or the vault', () async {
      final session = await DemoSession.open();
      session.bridge.sendText('5511900000104@s.whatsapp.net', 'Valeu!');
      await session.close();
    });
  });

  group('the way in and out', () {
    testWidgets('the first screen offers the demo only with a launcher', (
      tester,
    ) async {
      var entered = 0;
      await tester.pumpWidget(
        const MaterialApp(home: IntroScreen(mode: IntroMode.newInstall)),
      );
      expect(find.text('Explorar sem conectar'), findsNothing);

      await tester.pumpWidget(
        DemoLauncher(
          enter: () => entered++,
          child: const MaterialApp(
            home: IntroScreen(mode: IntroMode.newInstall),
          ),
        ),
      );
      await tester.tap(find.text('Explorar sem conectar'));
      expect(entered, 1);
    });

    testWidgets('the demo shows its strip, data in every section, and leaves', (
      tester,
    ) async {
      final session = (await tester.runAsync(DemoSession.open))!;
      var left = false;
      await tester.pumpWidget(
        DemoApp(
          session: session,
          theme: ThemeController(store: MemoryKeyVault())
            ..mode = ThemeMode.dark,
          onExit: () => left = true,
        ),
      );
      // Each section reads the in-memory database when it opens.
      Future<void> settle() async {
        for (var i = 0; i < 2; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump(const Duration(milliseconds: 400));
        }
      }

      await settle();
      expect(find.text('Modo demonstração: nada aqui é real'), findsOneWidget);

      await tester.tap(find.text('Conversas').last);
      await settle();
      expect(find.text('Ana Paula'), findsWidgets);

      await tester.tap(find.text('Clientes').last);
      await settle();
      expect(find.text('Bruno Costa'), findsWidgets);

      await tester.tap(find.text('Produtos').last);
      await settle();
      expect(find.textContaining('git push --force'), findsWidgets);

      await tester.tap(find.text('Vendas').last);
      await settle();
      // Today's sale, at the top of the list.
      expect(find.text('Diego Rocha'), findsWidgets);
      expect(find.text('Vencida'), findsWidgets);

      await tester.tap(find.text('Sair'));
      expect(left, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(session.close);
    });
  });
}
