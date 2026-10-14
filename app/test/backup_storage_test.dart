// The app.db copy for backups, with the real SQLCipher.
import 'dart:convert';
import 'dart:io';

import 'package:chat_do_garoto/src/storage/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late String path;
  late String copy;
  late AppStorage storage;
  final key = newDatabaseKey();
  final copyKey = newDatabaseKey();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('backup_storage_test');
    path = '${dir.path}/app/app.db';
    copy = '${dir.path}/cache/backup/app.db';
    storage = AppStorage(path: () async => path);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<StorageOpened> openOk([String? withKey]) async =>
      await storage.open(withKey ?? key) as StorageOpened;

  test('the copy is encrypted with its own key and restores', () async {
    final first = await openOk();
    await first.database.setPreference('k', 'do backup');
    await exportCopy(first.database, copy, copyKey);
    // The database keeps working after the copy.
    await first.database.setPreference('k', 'mudou depois');
    expect(await first.database.preference('k'), 'mudou depois');
    await first.database.close();

    final header = File(copy).openSync().readSync(16);
    expect(String.fromCharCodes(header.take(15)), isNot('SQLite format 3'));
    expect(
      File(copy).readAsStringSync(encoding: latin1),
      isNot(contains('do backup')),
    );
    // The app's key does not open the copy.
    final wrong = sqlite3.open(copy);
    applyKey(wrong, key);
    expect(
      () => wrong.select('SELECT count(*) FROM sqlite_master'),
      throwsA(isA<SqliteException>()),
    );
    wrong.close();

    await storage.importCopy(key, copy, copyKey);
    final restored = await openOk();
    expect(await restored.database.preference('k'), 'do backup');
    final version = await restored.database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data.values.single, restored.database.schemaVersion);
    await restored.database.close();
    expect(File('$path.restore').existsSync(), isFalse);
  });

  test('a copy from an older version is brought up to date', () async {
    File(copy).parent.createSync(recursive: true);
    final raw = sqlite3.open(copy);
    raw.execute("PRAGMA key = \"x'$copyKey'\"");
    raw.execute(File('test/fixtures/app_db_v3.sql').readAsStringSync());
    raw.execute('''
      INSERT INTO clients (name, phone, created_at, updated_at) VALUES ('Ana', '5511900000001', 1, 1);
      PRAGMA user_version = 3;
    ''');
    raw.close();
    await storage.importCopy(key, copy, copyKey);
    final restored = await openOk();
    final names = await restored.database
        .customSelect('SELECT name FROM clients')
        .get();
    expect(names.single.data['name'], 'Ana');
    final version = await restored.database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data.values.single, restored.database.schemaVersion);
    await restored.database.close();
  });

  test('a bad copy leaves the old data', () async {
    final first = await openOk();
    await first.database.setPreference('k', 'antes');
    await first.database.close();
    File(copy)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('não é um banco');
    await expectLater(
      storage.importCopy(key, copy, copyKey),
      throwsA(isA<SqliteException>()),
    );
    final again = await openOk();
    expect(await again.database.preference('k'), 'antes');
    await again.database.close();
    expect(File('$path.restore').existsSync(), isFalse);
  });

  test('keys are checked before reaching SQL', () {
    expect(() => attachSql('/x', "x'; DROP"), throwsArgumentError);
    expect(attachSql("/a'b", copyKey), contains("'/a''b'"));
  });
}
