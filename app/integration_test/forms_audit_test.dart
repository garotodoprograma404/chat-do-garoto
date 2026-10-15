// Opens every form and full-screen page of the demo at phone, tablet and
// desktop sizes and saves a picture of each: the screens the
// first layout audit did not cover.
//   flutter test integration_test/forms_audit_test.dart -d linux \
//     --dart-define=SCREENS_OUT=<folder>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chat_do_garoto/src/demo/demo_app.dart';
import 'package:chat_do_garoto/src/theme/brand_nav_bar.dart';
import 'package:chat_do_garoto/src/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _out = String.fromEnvironment(
  'SCREENS_OUT',
  defaultValue: 'build/screens',
);

const _sizes = {
  'celular': Size(390, 844),
  'tablet': Size(800, 1180),
  'computador': Size(1440, 900),
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('forms and pages', (tester) async {
    final shot = GlobalKey();
    final session = await DemoSession.open();
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;

    Future<void> wait([int ms = 700]) async {
      await Future<void>.delayed(Duration(milliseconds: ms));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }

    Future<void> save(String name) async {
      final boundary =
          shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    }

    Finder navItem(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is BrandNavBar || w is BrandNavRail),
      matching: find.text(label),
    );

    Future<void> goBack({int pages = 3}) async {
      // Back to the shell: pop what is open over it, the innermost
      // navigator first (the content one beside the side bar, or the app's
      // own on a phone).
      for (var i = 0; i < pages; i++) {
        final navs = tester
            .stateList<NavigatorState>(find.byType(Navigator))
            .toList()
            .reversed;
        final open = navs.where((n) => n.canPop());
        if (open.isEmpty) break;
        open.first.pop();
        await wait(400);
      }
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: DemoApp(
          session: session,
          theme: ThemeController(store: MemoryKeyVault())
            ..mode = ThemeMode.dark,
          onExit: () {},
        ),
      ),
    );

    // (section, button, picture name)
    const forms = [
      ('Clientes', 'Novo cliente', 'novo-cliente'),
      ('Produtos', 'Novo produto', 'novo-produto'),
      ('Vendas', 'Nova venda', 'nova-venda'),
      ('Vendas', 'Venda rápida', 'venda-rapida'),
    ];

    for (final MapEntry(key: name, value: size) in _sizes.entries) {
      tester.view.physicalSize = size;
      await wait();
      for (final (section, button, picture) in forms) {
        // ignore: avoid_print
        print('>>> $name / $picture');
        await tester.tap(navItem(section));
        await wait();
        final fab = find.text(button);
        if (fab.evaluate().isEmpty) {
          // ignore: avoid_print
          print('!!! sem botao $button em $name');
          continue;
        }
        await tester.tap(fab.last);
        await wait(900);
        await save('$name-$picture');
        // Open every group of the form (the accordions) and look again.
        for (final group in const [
          'Mais detalhes',
          'Código de barras e código interno',
          'Custo e lucro',
          'Promoção',
          'Atacado',
          'Estoque e validade',
          'Variações (tamanho, cor...)',
          'Categoria, marca e descrição',
        ]) {
          final g = find.text(group);
          if (g.evaluate().isNotEmpty) {
            await tester.ensureVisible(g.first);
            await tester.tap(g.first, warnIfMissed: false);
            await wait(250);
          }
        }
        await save('$name-$picture-grupos');
        // The lower half of a long form.
        final scroll = find.byType(Scrollable);
        if (scroll.evaluate().isNotEmpty) {
          await tester.drag(scroll.last, const Offset(0, -2000));
          await wait(400);
          await save('$name-$picture-fim');
        }
        await goBack();
      }
      // Configurações and what opens from it.
      // ignore: avoid_print
      print('>>> $name / configuracoes');
      await tester.tap(navItem('Início'));
      await wait();
      await tester.tap(find.byTooltip('Configurações').first);
      await wait(900);
      await save('$name-configuracoes');
      final settingsScroll = find.byType(Scrollable);
      if (settingsScroll.evaluate().isNotEmpty) {
        await tester.drag(settingsScroll.last, const Offset(0, -2000));
        await wait(400);
        await save('$name-configuracoes-fim');
      }
      await tester.drag(settingsScroll.last, const Offset(0, 2000));
      await wait(300);
      // ignore: avoid_print
      print('>>> $name / backup');
      await tester.tap(find.text('Backup').first);
      await wait(900);
      await save('$name-backup');
      await goBack();
      await tester.tap(navItem('Início'));
      await wait();

      // Pickers and dialogs: what opens over a form or a detail.
      Future<void> shotIf(Finder f, String picture, {int ms = 800}) async {
        if (f.evaluate().isEmpty) {
          // ignore: avoid_print
          print('!!! sem $picture em $name');
          return;
        }
        await tester.tap(f.first);
        await wait(ms);
        await save('$name-$picture');
      }

      // ignore: avoid_print
      print('>>> $name / seletores');
      await tester.tap(navItem('Vendas'));
      await wait();
      await tester.tap(find.text('Nova venda').last);
      await wait(900);
      await shotIf(find.text('Escolher cliente'), 'seletor-cliente');
      await goBack(pages: 1);
      await wait(900);
      await shotIf(find.text('Adicionar item'), 'seletor-item', ms: 1200);
      await goBack();
      await tester.tap(navItem('Vendas'));
      await wait();

      // ignore: avoid_print
      print('>>> $name / janelas');
      await tester.tap(navItem('Clientes'));
      await wait();
      await tester.tap(find.textContaining('Bruno Costa').first);
      await wait(900);
      await shotIf(find.text('Receber'), 'janela-receber');
      // A dialog is closed with Esc or the first button.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await wait(400);
      await shotIf(find.byTooltip('Apagar cliente'), 'janela-apagar-cliente');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await wait(400);
      await goBack();
      await tester.tap(navItem('Produtos'));
      await wait();
      await tester.tap(find.textContaining('Moletom').first);
      await wait(900);
      await shotIf(find.text('Movimentar estoque'), 'pagina-movimentar');
      await goBack();
      await tester.tap(navItem('Início'));
      await wait();

      // The detail pages with their own actions.
      for (final (section, row, picture) in const [
        ('Clientes', 'Bruno Costa', 'ficha-cliente'),
        ('Produtos', 'Moletom', 'ficha-produto'),
        ('Vendas', 'Carla Mendes', 'ficha-venda'),
      ]) {
        // ignore: avoid_print
        print('>>> $name / $picture');
        await tester.tap(navItem(section));
        await wait();
        await tester.tap(find.textContaining(row).first);
        await wait(900);
        final scroll = find.byType(Scrollable);
        if (scroll.evaluate().isNotEmpty) {
          await tester.drag(scroll.last, const Offset(0, -2000));
          await wait(400);
        }
        await save('$name-$picture-fim');
        await goBack();
      }
    }
    await session.close();
  });
}
