import 'package:chat_do_garoto/src/theme/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The three window sizes and the reading width.
void main() {
  test('the width decides the class', () {
    expect(WindowClass.of(390), WindowClass.compact);
    expect(WindowClass.of(599.9), WindowClass.compact);
    expect(WindowClass.of(600), WindowClass.medium);
    expect(WindowClass.of(800), WindowClass.medium);
    expect(WindowClass.of(899.9), WindowClass.medium);
    expect(WindowClass.of(900), WindowClass.expanded);
    expect(WindowClass.of(1440), WindowClass.expanded);
  });

  testWidgets('ContentWidth centers and limits, and leaves narrow alone', (
    tester,
  ) async {
    Future<Size> sizeIn(double width) async {
      tester.view
        ..physicalSize = Size(width, 800)
        ..devicePixelRatio = 1;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ContentWidth(
              maxWidth: 640,
              child: SizedBox.expand(key: Key('x')),
            ),
          ),
        ),
      );
      return tester.getSize(find.byKey(const Key('x')));
    }

    addTearDown(tester.view.reset);
    expect((await sizeIn(1440)).width, 640);
    expect((await sizeIn(500)).width, 500);
    tester.view.reset();
  });
}
