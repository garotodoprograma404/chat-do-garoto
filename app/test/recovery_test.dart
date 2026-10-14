// Recovery when app.db cannot be opened.
import 'dart:io';

import 'package:chat_do_garoto/src/storage/app_storage.dart';
import 'package:chat_do_garoto/src/storage/recovery_screen.dart';
import 'package:chat_do_garoto/src/storage/storage_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('controller, with the real SQLCipher', () {
    late Directory dir;
    late String path;
    late StorageController controller;
    final key = newDatabaseKey();

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('recovery_test');
      path = '${dir.path}/app/app.db';
      // A database written with a key that is then lost.
      final first = await AppStorage(
        path: () async => path,
      ).open(newDatabaseKey()) as StorageOpened;
      await first.database.setPreference('k', 'v');
      await first.database.close();
      controller = StorageController(
        storage: AppStorage(path: () async => path),
      );
    });
    tearDown(() async {
      await controller.database?.close();
      dir.deleteSync(recursive: true);
    });

    test(
      'a key that does not open it makes it unreadable, untouched',
      () async {
        await controller.open(key);
        expect(controller.phase, StoragePhase.unreadable);
        expect(File(path).existsSync(), isTrue);
      },
    );

    test('reset starts over with an empty database', () async {
      await controller.open(key);
      await controller.reset();
      expect(controller.phase, StoragePhase.ready);
      expect(await controller.database!.preference('k'), isNull);
    });

    test('close forgets the database; wipe deletes it', () async {
      await controller.open(key);
      await controller.reset();
      await controller.close();
      expect(controller.database, isNull);
      await controller.wipe();
      expect(File(path).existsSync(), isFalse);
    });
  });

  group('screen', () {
    Future<List<String>> show(
      WidgetTester tester, {
      bool unreadable = true,
    }) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: RecoveryScreen(
            unreadable: unreadable,
            onReset: () => calls.add('reset'),
            onRetry: () => calls.add('retry'),
          ),
        ),
      );
      return calls;
    }

    testWidgets('explains and asks before deleting', (tester) async {
      final calls = await show(tester);
      expect(find.textContaining('não podem ser abertos'), findsOneWidget);

      await tester.tap(find.text('Apagar dados do app e recomeçar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('A conexão com o WhatsApp'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);

      await tester.tap(find.text('Apagar dados do app e recomeçar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apagar e recomeçar'));
      await tester.pumpAndSettle();
      expect(calls, ['reset']);
    });

    testWidgets('other failures only offer to try again', (tester) async {
      final calls = await show(tester, unreadable: false);
      expect(find.text('Apagar dados do app e recomeçar'), findsNothing);
      await tester.tap(find.text('Tentar de novo'));
      expect(calls, ['retry']);
    });
  });
}
