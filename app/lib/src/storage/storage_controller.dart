import 'package:flutter/foundation.dart';

import 'app_database.dart';
import 'app_storage.dart';

enum StoragePhase { opening, ready, unreadable, failed }

/// State of the encrypted `app.db`.
class StorageController extends ChangeNotifier {
  StorageController({required this._storage});

  final AppStorage _storage;
  String? _key;

  StoragePhase phase = StoragePhase.opening;
  AppDatabase? database;

  /// Opens app.db with [key], from the app lock.
  Future<void> open(String key) {
    _key = key;
    return _run(() => _storage.open(key));
  }

  /// Tries again with the same key.
  Future<void> retry() async {
    final key = _key;
    if (key != null) await open(key);
  }

  /// Deletes the app's data and starts over (after the user confirmed).
  Future<void> reset() async {
    final key = _key;
    if (key != null) await _run(() => _storage.reset(key));
  }

  /// Replaces app.db with a backup copy and opens it again. On
  /// failure the old data opens again and the error goes up.
  Future<void> restoreFrom(String copyPath, String copyKey) async {
    final key = _key;
    if (key == null) throw StateError('app.db is not open');
    final db = database;
    database = null;
    phase = StoragePhase.opening;
    notifyListeners();
    await db?.close();
    try {
      await _storage.importCopy(key, copyPath, copyKey);
    } finally {
      await _run(() => _storage.open(key));
    }
  }

  /// Closes app.db and forgets the key (the app locked).
  Future<void> close() async {
    _key = null;
    final db = database;
    database = null;
    phase = StoragePhase.opening;
    notifyListeners();
    await db?.close();
  }

  /// Deletes app.db (forgot the PIN).
  Future<void> wipe() async {
    await close();
    await _storage.wipe();
  }

  Future<void> _run(Future<StorageResult> Function() action) async {
    phase = StoragePhase.opening;
    notifyListeners();
    try {
      switch (await action()) {
        case StorageOpened(:final database):
          this.database = database;
          phase = StoragePhase.ready;
          await _noteFirstOpening(database);
        case StorageUnreadable():
          phase = StoragePhase.unreadable;
      }
    } on Object catch (e) {
      // Never log the key; the error type is enough.
      if (kDebugMode) debugPrint('[storage] open failed: ${e.runtimeType}');
      phase = StoragePhase.failed;
    }
    notifyListeners();
  }

  /// Records when this database was created; shown in debug logs to check
  /// it survives restarts.
  Future<void> _noteFirstOpening(AppDatabase db) async {
    var created = await db.preference('created_at');
    if (created == null) {
      created = DateTime.now().toIso8601String();
      await db.setPreference('created_at', created);
    }
    if (kDebugMode) debugPrint('[storage] app.db open, created $created');
  }

  @override
  void dispose() {
    database?.close();
    super.dispose();
  }
}
