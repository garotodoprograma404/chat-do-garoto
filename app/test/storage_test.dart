// The encrypted app.db with the real SQLCipher.
import 'dart:io';

import 'package:chat_do_garoto/src/storage/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late String path;
  late AppStorage storage;
  final key = newDatabaseKey();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('app_db_test');
    path = '${dir.path}/app/app.db';
    storage = AppStorage(path: () async => path);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<StorageOpened> openOk([String? withKey]) async {
    final result = await storage.open(withKey ?? key);
    expect(result, isA<StorageOpened>());
    return result as StorageOpened;
  }

  Future<void> writeSomething() async {
    final opened = await openOk();
    await opened.database.setPreference('k', 'v');
    await opened.database.close();
  }

  test('keeps data across openings with the same key', () async {
    await writeSomething();
    final second = await openOk();
    expect(await second.database.preference('k'), 'v');
    expect(await second.database.preference('missing'), isNull);
    await second.database.close();
  });

  test('the file has no SQLite header: it is encrypted', () async {
    await writeSomething();
    final header = File(path).openSync().readSync(16);
    expect(String.fromCharCodes(header.take(15)), isNot('SQLite format 3'));
  });

  test('another key cannot read it, and the file is left alone', () async {
    await writeSomething();
    final size = File(path).lengthSync();
    expect(await storage.open(newDatabaseKey()), isA<StorageUnreadable>());
    expect(File(path).lengthSync(), size);
  });

  test('reset starts over with an empty database', () async {
    await writeSomething();
    final again = await storage.reset(key) as StorageOpened;
    expect(await again.database.preference('k'), isNull);
    await again.database.close();
  });

  test('wipe deletes the database', () async {
    await writeSomething();
    await storage.wipe();
    expect(File(path).existsSync(), isFalse);
  });

  test('refuses to work without SQLCipher', () {
    expect(() => ensureSqlCipher(null), throwsA(isA<NotEncryptedException>()));
    expect(() => ensureSqlCipher(''), throwsA(isA<NotEncryptedException>()));
    ensureSqlCipher('4.19.0 community');

    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    expect(() => applyKey(db, 'not hex'), throwsArgumentError);
    applyKey(db, newDatabaseKey()); // the bundled library is SQLCipher
  });

  test('keys are random', () {
    expect(newDatabaseKey(), isNot(newDatabaseKey()));
  });
}
