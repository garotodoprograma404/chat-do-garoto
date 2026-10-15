// Takes pictures of every section of the demo at phone, tablet and desktop
// sizes, with the real engine and fonts: to look at spacing,
// overlaps and wasted room, and to prove the layout after each change.
//   flutter test integration_test/layout_audit_test.dart -d linux \
//     --dart-define=SCREENS_OUT=<folder>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chat_do_garoto/src/demo/demo_app.dart';
import 'package:chat_do_garoto/src/theme/brand_nav_bar.dart';
import 'package:chat_do_garoto/src/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _out = String.fromEnvironment(
  'SCREENS_OUT',
  defaultValue: 'build/screens',
);

/// The system text size: 1 normal, 2 for the 200% check.
final _textScale = double.parse(
  const String.fromEnvironment('TEXT_SCALE', defaultValue: '1'),
);

/// name: (width, height) in logical pixels.
const _sizes = {
  'celular': Size(390, 844),
  'tablet-pe': Size(800, 1180),
  'tablet-deitado': Size(1180, 820),
  'notebook': Size(1366, 768),
  'computador': Size(1440, 900),
  'monitor': Size(1920, 1030),
  'ultrawide': Size(2560, 1080),
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every section at every size', (tester) async {
    final shot = GlobalKey();
    final session = await DemoSession.open();
    addTearDown(() => tester.view.resetPhysicalSize());
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = _textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

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

    // The section's button in the bottom bar or the side bar (a filter
    // chip may carry the same word).
    Finder navItem(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is BrandNavBar || w is BrandNavRail),
      matching: find.text(label),
    );

    // The first row of each section, to open its detail.
    const details = {
      'Conversas': 'Ana Paula',
      'Clientes': 'Bruno Costa',
      'Produtos': 'Moletom',
      'Vendas': 'Diego Rocha',
    };

    for (final MapEntry(key: name, value: size) in _sizes.entries) {
      tester.view.physicalSize = size;
      // ignore: avoid_print
      print('>>> $name');
      await wait();
      await tester.tap(navItem('Início'));
      await wait();
      await save('$name-1-inicio');
      for (final (i, MapEntry(key: tab, value: row))
          in details.entries.indexed) {
        // ignore: avoid_print
        print('>>> $name / $tab');
        await tester.tap(navItem(tab));
        await wait();
        await save('$name-${i + 2}-${tab.toLowerCase()}');
        // ignore: avoid_print
        print('>>> $name / $tab aberto');
        final target = find.textContaining(row);
        if (target.evaluate().isEmpty) {
          // Large text pushes the row below the fold: scroll to it.
          await tester.dragUntilVisible(
            target,
            find.byType(ListView).first,
            const Offset(0, -200),
          );
        }
        await tester.tap(target.first);
        await wait(900);
        await save('$name-${i + 2}-${tab.toLowerCase()}-aberto');
        // Full-screen pages (compact, medium) go back; the pane stays.
        if (tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .canPop()) {
          await tester.pageBack();
          await wait();
        }
      }
    }
    await session.close();
  });
}
