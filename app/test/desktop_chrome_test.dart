// What changes with the window: where a list keeps its main action and who
// opens Configurações. One way to each, never two.
import 'package:chat_do_garoto/src/clients/clients_screen.dart';
import 'package:chat_do_garoto/src/theme/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';

Future<void> _clients(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      home: ClientsScreen(repo: FakeClientsRepository(), onOpenSettings: () {}),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a phone: floating button, ⋮ menu with Configurações', (
    tester,
  ) async {
    await _clients(tester, const Size(390, 844));
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byType(ListActionBar), findsNothing);
    expect(find.byTooltip('Mais opções'), findsOneWidget);
  });

  for (final size in const [
    Size(800, 1180),
    Size(1366, 768),
    Size(2560, 1080),
  ]) {
    testWidgets('a window with a side bar at $size: a bar, no floating '
        'button, no second way to Configurações', (tester) async {
      await _clients(tester, size);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(ListActionBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ListActionBar),
          matching: find.text('Novo cliente'),
        ),
        findsOneWidget,
      );
      // The side bar has the gear: the ⋮ menu would only repeat it.
      expect(find.byTooltip('Mais opções'), findsNothing);
    });
  }

  testWidgets('the bar stays as high as its buttons with large text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _clients(tester, const Size(1366, 768));
    // A bar as tall as the whole page would push the list out of sight.
    expect(tester.getSize(find.byType(ListActionBar)).height, lessThan(200));
  });
}
