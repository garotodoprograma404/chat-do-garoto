import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'app_database.dart';

/// Where `app.db` lives: the app's private support directory.
Future<String> defaultDatabasePath() async {
  final dir = await getApplicationSupportDirectory();
  final sep = Platform.pathSeparator;
  return '${dir.path}${sep}app${sep}app.db';
}

/// The outcome of opening `app.db`.
sealed class StorageResult {
  const StorageResult();
}

/// The database is open and ready.
final class StorageOpened extends StorageResult {
  const StorageOpened(this.database);
  final AppDatabase database;
}

/// The file exists but the key cannot open it.
final class StorageUnreadable extends StorageResult {
  const StorageUnreadable();
}

/// The bundled SQLite is not SQLCipher: refuse to store anything.
class NotEncryptedException implements Exception {
  const NotEncryptedException();
  @override
  String toString() => 'NotEncryptedException: SQLCipher is not loaded';
}

/// Throws [NotEncryptedException] unless [cipherVersion] (from
/// `PRAGMA cipher_version`) shows SQLCipher.
void ensureSqlCipher(String? cipherVersion) {
  if (cipherVersion == null || cipherVersion.trim().isEmpty) {
    throw const NotEncryptedException();
  }
}

/// A new random 256-bit key, in hex.
String newDatabaseKey() {
  final random = Random.secure();
  return [
    for (var i = 0; i < 32; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// Applies [hexKey] to a freshly opened SQLCipher connection. The raw key
/// form skips password derivation: the key is already random.
void applyKey(Database db, String hexKey) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hexKey)) {
    throw ArgumentError('malformed database key'); // never print the key
  }
  db.execute("PRAGMA key = \"x'$hexKey'\"");
  final rows = db.select('PRAGMA cipher_version');
  ensureSqlCipher(rows.isEmpty ? null : rows.first.values.first as String?);
  // Deleting really deletes: freed space is zeroed; and
  // deleting a client deletes its notes and tags.
  db.execute('PRAGMA secure_delete = ON');
  db.execute('PRAGMA foreign_keys = ON');
}

/// The statement that attaches the database at [path], encrypted with the
/// one-time [hexKey], as `bk`. Never print it: it holds the key.
String attachSql(String path, String hexKey) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hexKey)) {
    throw ArgumentError('malformed database key');
  }
  final quoted = path.replaceAll("'", "''");
  return "ATTACH DATABASE '$quoted' AS bk KEY \"x'$hexKey'\"";
}

/// Copies the open [db] to [path], encrypted with the one-time [hexKey], for
/// a backup: the copy never exists unencrypted.
Future<void> exportCopy(AppDatabase db, String path, String hexKey) async {
  final file = File(path);
  if (file.existsSync()) file.deleteSync();
  file.parent.createSync(recursive: true);
  await db.customStatement(attachSql(path, hexKey));
  try {
    await db.customSelect("SELECT sqlcipher_export('bk')").get();
    final version = await db
        .customSelect('PRAGMA main.user_version')
        .getSingle();
    await db.customStatement(
      'PRAGMA bk.user_version = ${version.data.values.first as int}',
    );
  } finally {
    await db.customStatement('DETACH DATABASE bk');
  }
}

/// Opens, creates or resets the encrypted `app.db`. The key
/// comes from the app lock, only after the PIN or
/// biometrics.
class AppStorage {
  AppStorage({this._path = defaultDatabasePath});

  final Future<String> Function() _path;

  Future<StorageResult> open(String key) async {
    final path = await _path();
    final file = File(path);
    file.parent.createSync(recursive: true);

    // Check the key before handing the file to Drift.
    final probe = sqlite3.open(path);
    try {
      applyKey(probe, key);
      probe.select('SELECT count(*) FROM sqlite_master');
    } on SqliteException catch (e) {
      if (e.resultCode == 26) return const StorageUnreadable(); // NOTADB
      rethrow;
    } finally {
      probe.close();
    }

    final hexKey = key;
    return StorageOpened(
      AppDatabase(
        NativeDatabase.createInBackground(
          file,
          setup: (db) => applyKey(db, hexKey),
        ),
      ),
    );
  }

  /// Deletes `app.db`, then opens a new, empty one with [key]. The
  /// WhatsApp session and messages (`wa.db`) are not touched.
  Future<StorageResult> reset(String key) async {
    await wipe();
    return open(key);
  }

  /// Replaces `app.db` with the backup copy at [copyPath], encrypted with
  /// [copyKey], re-encrypted with [key]. The new file
  /// is built aside and only then takes the old one's place, so a failure
  /// leaves the old data. Drift must be closed; opening it next runs the
  /// migrations of an older backup.
  Future<void> importCopy(String key, String copyPath, String copyKey) async {
    final path = await _path();
    final aside = '$path.restore';
    File(path).parent.createSync(recursive: true);
    _deleteDb(aside);
    final db = sqlite3.open(aside);
    try {
      applyKey(db, key);
      db.execute(attachSql(copyPath, copyKey));
      db.execute("SELECT sqlcipher_export('main', 'bk')");
      final version = db.select('PRAGMA bk.user_version').first.values.first;
      db.execute('PRAGMA main.user_version = $version');
      db.execute('DETACH DATABASE bk');
    } on Object {
      db.close();
      _deleteDb(aside);
      rethrow;
    }
    db.close();
    _deleteDb(path);
    File(aside).renameSync(path);
  }

  void _deleteDb(String path) {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('$path$suffix');
      if (f.existsSync()) f.deleteSync();
    }
  }

  /// Deletes `app.db` without opening anything (forgot the PIN).
  Future<void> wipe() async {
    final path = await _path();
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('$path$suffix');
      if (f.existsSync()) f.deleteSync();
    }
  }
}
