// Opens the demo in the real app (real engine, real fonts) and saves a
// picture of each section and of a live conversation: to check
// the screens with one's own eyes and to make the README's pictures.
//   flutter test integration_test/demo_screens_test.dart -d linux \
//     --dart-define=SCREENS_OUT=<folder>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chat_do_garoto/src/demo/demo_app.dart';
import 'package:chat_do_garoto/src/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _out = String.fromEnvironment(
  'SCREENS_OUT',
  defaultValue: 'build/screens',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the demo, section by section', (tester) async {
    final shot = GlobalKey();
    final session = await DemoSession.open();
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

    Future<void> wait([int ms = 900]) async {
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

    await wait();
    await save('1-inicio');
    for (final (i, tab) in [
      'Conversas',
      'Clientes',
      'Produtos',
      'Vendas',
    ].indexed) {
      await tester.tap(find.text(tab).last);
      await wait();
      await save('${i + 2}-${tab.toLowerCase()}');
    }

    // A live conversation: my message, then the contact's answer.
    await tester.tap(find.text('Conversas').last);
    await wait();
    await tester.tap(find.text('Ana Paula').first);
    await wait();
    await tester.enterText(
      find.byType(TextField).last,
      'Separei aqui pra você!',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await wait(300);
    final send = find.byTooltip('Enviar');
    if (send.evaluate().isNotEmpty) await tester.tap(send.first);
    await wait(4500);
    await save('6-conversa');

    await session.close();
  });
}
