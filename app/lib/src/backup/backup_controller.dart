import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core_bridge/core_bridge.dart';
import '../storage/app_storage.dart';
import '../storage/key_vault.dart';
import 'backup_platform.dart';

/// The app version written into backups.
const appVersion = '1.0.0';

/// The shortest backup password (the core checks it too).
const minBackupPassword = 8;

/// Reminder intervals offered, in days; 0 turns it off.
const reminderChoices = [7, 15, 30, 0];

enum BackupPhase { idle, exporting, opening, restoring, done, restored, failed }

/// Making and restoring backups, and the reminder.
/// Lives as long as the app: the core's events may arrive with no screen
/// open.
class BackupController extends ChangeNotifier {
  BackupController({
    required this.bridge,
    required this.platform,
    required this.workDir,
    required this.copyAppDb,
    required this.restoreAppDb,
    required this.appSchema,
    required this.lastStore,
    required this.intervalStore,
    this.onLeave,
    this.onBack,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final CoreBridge bridge;
  final BackupPlatform platform;

  /// The cache folder the core and the app work in.
  final Future<String> Function() workDir;

  /// Copies the open app.db to a path, encrypted with a one-time key.
  final Future<void> Function(String path, String key) copyAppDb;

  /// Replaces app.db with a copy and opens it again.
  final Future<void> Function(String path, String key) restoreAppDb;

  /// The app.db version: newer backups are refused.
  final int Function() appSchema;

  /// Where the last backup date and the interval live (system vault).
  final KeyVault lastStore;
  final KeyVault intervalStore;

  /// The lock allows time away while the system picker is open.
  final VoidCallback? onLeave;
  final VoidCallback? onBack;
  final DateTime Function() _now;

  StreamSubscription<CoreEvent>? _events;

  BackupPhase phase = BackupPhase.idle;

  /// Bytes written so far and in total, while exporting.
  int done = 0;
  int total = 0;

  /// Why the last task failed, for the user.
  String? error;

  DateTime? lastBackup;
  int intervalDays = 7;

  String? _uri; // the file being written, deleted if it fails

  bool get busy =>
      phase == BackupPhase.exporting ||
      phase == BackupPhase.opening ||
      phase == BackupPhase.restoring;

  /// Starts listening and loads the reminder settings.
  Future<void> start() async {
    _events ??= bridge.events.listen(_onEvent);
    final last = int.tryParse(await lastStore.read() ?? '');
    lastBackup = last == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(last);
    intervalDays = int.tryParse(await intervalStore.read() ?? '') ?? 7;
    notifyListeners();
  }

  /// Days since the last backup, or null when there was none.
  int? get daysSinceBackup =>
      lastBackup == null ? null : _now().difference(lastBackup!).inDays;

  /// Whether the reminder shows.
  bool get reminderDue {
    if (intervalDays <= 0) return false;
    final days = daysSinceBackup;
    return days == null || days >= intervalDays;
  }

  Future<void> setInterval(int days) async {
    intervalDays = days;
    await intervalStore.write('$days');
    notifyListeners();
  }

  /// "chatdogaroto-2026-10-02.backup".
  String fileName() {
    final d = _now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'chatdogaroto-${d.year}-${two(d.month)}-${two(d.day)}.backup';
  }

  /// Makes a backup: asks where to save it, copies app.db and
  /// hands everything to the core. Returns false when the user cancelled
  /// the picker.
  Future<bool> export({required String password, required bool media}) async {
    if (busy) return false;
    onLeave?.call();
    final ({int fd, String uri})? picked;
    try {
      picked = await platform.create(fileName());
    } finally {
      onBack?.call();
    }
    if (picked == null) return false;
    _uri = picked.uri;
    _set(BackupPhase.exporting);
    done = total = 0;
    try {
      final dir = await workDir();
      final key = newDatabaseKey();
      final copy = '$dir${Platform.pathSeparator}app.db';
      await copyAppDb(copy, key);
      bridge.backupExport(
        picked.fd,
        BackupRequest(
          password: password,
          appCopy: copy,
          appKey: key,
          appVersion: appVersion,
          appSchema: appSchema(),
          media: media,
          workDir: dir,
        ),
      );
    } on Object catch (e) {
      // Never log the password or the key; the error type is enough.
      if (kDebugMode) debugPrint('[backup] export failed: ${e.runtimeType}');
      await _dropFile();
      _fail(
        e is CoreException && e.code == 'weak_password'
            ? 'A senha precisa ter ao menos $minBackupPassword caracteres.'
            : 'Não foi possível fazer o backup.',
      );
    }
    return true;
  }

  /// Opens a backup to restore it. Returns false when the user
  /// cancelled the picker.
  Future<bool> restore({required String password}) async {
    if (busy) return false;
    onLeave?.call();
    final int? fd;
    try {
      fd = await platform.open();
    } finally {
      onBack?.call();
    }
    if (fd == null) return false;
    _set(BackupPhase.opening);
    try {
      bridge.backupOpen(
        fd,
        password: password,
        workDir: await workDir(),
        maxAppSchema: appSchema(),
      );
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[backup] open failed: ${e.runtimeType}');
      _fail('Não foi possível abrir o backup.');
    }
    return true;
  }

  /// Stops the backup or the opening running now.
  void cancel() {
    try {
      bridge.backupCancel();
    } on CoreException {
      // nothing running
    }
  }

  /// Back to idle after the user saw the result.
  void dismiss() {
    if (busy) return;
    _set(BackupPhase.idle);
  }

  Future<void> _onEvent(CoreEvent event) async {
    switch (event.type) {
      case 'backup_progress':
        done = event.data['done'] as int? ?? 0;
        total = event.data['total'] as int? ?? 0;
        notifyListeners();
      case 'backup_done':
        _uri = null;
        lastBackup = _now();
        await lastStore.write('${lastBackup!.millisecondsSinceEpoch}');
        _set(BackupPhase.done);
      case 'backup_ready':
        await _restoreApp(event.data);
      case 'backup_restored':
        _set(BackupPhase.restored);
      case 'backup_failed':
        final code = event.data['code'] as String?;
        if (phase == BackupPhase.exporting) await _dropFile();
        if (code == 'cancelled') {
          _set(BackupPhase.idle);
          return;
        }
        _fail(switch (code) {
          'wrong_password' => 'Senha incorreta.',
          'not_a_backup' => 'Este arquivo não é um backup válido.',
          'newer_version' => 'Atualize o app para restaurar este backup.',
          _ when phase == BackupPhase.exporting =>
            'Não foi possível fazer o backup.',
          _ => 'Não foi possível restaurar o backup.',
        });
    }
  }

  /// The core checked the whole file: app.db first, then the core's part.
  Future<void> _restoreApp(Map<String, Object?> data) async {
    _set(BackupPhase.restoring);
    try {
      await restoreAppDb(
        data['app_copy']! as String,
        data['app_key']! as String,
      );
      bridge.backupCommit();
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[backup] restore failed: ${e.runtimeType}');
      try {
        bridge.backupDiscard();
      } on CoreException {
        // already gone
      }
      _fail('Não foi possível restaurar o backup.');
    }
  }

  Future<void> _dropFile() async {
    final uri = _uri;
    _uri = null;
    if (uri != null) await platform.delete(uri);
  }

  void _fail(String message) {
    error = message;
    _set(BackupPhase.failed);
  }

  void _set(BackupPhase p) {
    phase = p;
    if (p != BackupPhase.failed) error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }
}

/// Deletes what a backup or a restore left in [dir] when the app stopped
/// in the middle (cache/backup).
Future<void> cleanBackupLeftovers(String dir) async {
  final d = Directory(dir);
  if (d.existsSync()) d.deleteSync(recursive: true);
}

/// Bytes of the media in the vault folder [dir], to show the size.
int folderBytes(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return 0;
  var sum = 0;
  for (final f in d.listSync().whereType<File>()) {
    sum += f.lengthSync();
  }
  return sum;
}
