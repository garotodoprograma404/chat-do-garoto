// Backups in the app: the controller, the screen and the reminder.
import 'package:chat_do_garoto/src/backup/backup_controller.dart';
import 'package:chat_do_garoto/src/backup/backup_platform.dart';
import 'package:chat_do_garoto/src/backup/backup_screen.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_core_bridge.dart';
import 'support/fake_key_vault.dart';

class _FakePlatform implements BackupPlatform {
  ({int fd, String uri})? created = (fd: 7, uri: 'content://x/1');
  int? opened = 9;
  final deleted = <String>[];
  final names = <String>[];

  @override
  Future<({int fd, String uri})?> create(String name) async {
    names.add(name);
    return created;
  }

  @override
  Future<int?> open() async => opened;

  @override
  Future<bool> delete(String uri) async {
    deleted.add(uri);
    return true;
  }
}

final _today = DateTime(2026, 10, 2, 15);

({
  BackupController c,
  FakeCoreBridge bridge,
  _FakePlatform platform,
  FakeKeyVault last,
  List<String> log,
})
_make({DateTime? now, Object? restoreError}) {
  final bridge = FakeCoreBridge();
  final platform = _FakePlatform();
  final last = FakeKeyVault();
  final log = <String>[];
  final c = BackupController(
    bridge: bridge,
    platform: platform,
    workDir: () async => '/cache/backup',
    copyAppDb: (path, key) async => log.add('copy:$path:${key.length}'),
    restoreAppDb: (path, key) async {
      log.add('restore:$path:$key');
      if (restoreError case final e?) throw e;
    },
    appSchema: () => 4,
    lastStore: last,
    intervalStore: FakeKeyVault(),
    onLeave: () => log.add('leave'),
    onBack: () => log.add('back'),
    now: () => now ?? _today,
  );
  return (c: c, bridge: bridge, platform: platform, last: last, log: log);
}

void main() {
  test('a backup: the picker, the app.db copy, the core, the date', () async {
    final t = _make();
    await t.c.start();
    expect(await t.c.export(password: 'senha forte', media: true), isTrue);
    expect(t.platform.names.single, 'chatdogaroto-2026-10-02.backup');
    expect(t.log, ['leave', 'back', 'copy:/cache/backup/app.db:64']);
    expect(t.bridge.calls, contains('backupExport:7:media'));
    final r = t.bridge.backupRequest!;
    expect(r.appSchema, 4);
    expect(r.workDir, '/cache/backup');
    expect(t.c.phase, BackupPhase.exporting);

    t.bridge.push('backup_progress', {'done': 50, 'total': 200});
    expect((t.c.done, t.c.total), (50, 200));
    t.bridge.push('backup_done', {'bytes': 210});
    await pumpEventQueue();
    expect(t.c.phase, BackupPhase.done);
    expect(t.c.lastBackup, _today);
    expect(t.last.key, '${_today.millisecondsSinceEpoch}');
    expect(t.platform.deleted, isEmpty);
  });

  test('a failed or cancelled backup leaves no file', () async {
    final t = _make();
    await t.c.start();
    await t.c.export(password: 'senha forte', media: false);
    t.bridge.push('backup_failed', {'code': 'failed'});
    await pumpEventQueue();
    expect(t.c.phase, BackupPhase.failed);
    expect(t.c.error, 'Não foi possível fazer o backup.');
    expect(t.platform.deleted, ['content://x/1']);

    t.c.dismiss();
    await t.c.export(password: 'senha forte', media: false);
    t.c.cancel();
    expect(t.bridge.calls, contains('backupCancel'));
    t.bridge.push('backup_failed', {'code': 'cancelled'});
    await pumpEventQueue();
    expect(t.c.phase, BackupPhase.idle);
    expect(t.platform.deleted, hasLength(2));

    // The picker cancelled: nothing happens.
    t.platform.created = null;
    expect(await t.c.export(password: 'senha forte', media: true), isFalse);
    expect(t.c.phase, BackupPhase.idle);
  });

  test(
    'restore: the core checks, then app.db, then the core commits',
    () async {
      final t = _make();
      await t.c.start();
      expect(await t.c.restore(password: 'senha forte'), isTrue);
      expect(t.bridge.calls, contains('backupOpen:9:4'));
      expect(t.c.phase, BackupPhase.opening);
      t.bridge.push('backup_ready', {
        'app_copy': '/cache/backup/restore/app.db',
        'app_key': 'k',
        'app_schema': 3,
        'media': true,
      });
      await pumpEventQueue();
      expect(t.log.last, 'restore:/cache/backup/restore/app.db:k');
      expect(t.bridge.calls.last, 'backupCommit');
      expect(t.c.phase, BackupPhase.restoring);
      t.bridge.push('backup_restored');
      await pumpEventQueue();
      expect(t.c.phase, BackupPhase.restored);
    },
  );

  test('restore refusals and failures', () async {
    final t = _make(restoreError: StateError('x'));
    await t.c.start();
    for (final (code, text) in [
      ('wrong_password', 'Senha incorreta.'),
      ('not_a_backup', 'Este arquivo não é um backup válido.'),
      ('newer_version', 'Atualize o app para restaurar este backup.'),
    ]) {
      t.c.dismiss();
      await t.c.restore(password: 'x');
      t.bridge.push('backup_failed', {'code': code});
      await pumpEventQueue();
      expect(t.c.error, text);
    }
    // app.db could not be replaced: the opened backup is dropped.
    t.c.dismiss();
    await t.c.restore(password: 'x');
    t.bridge.push('backup_ready', {'app_copy': 'p', 'app_key': 'k'});
    await pumpEventQueue();
    expect(t.bridge.calls, contains('backupDiscard'));
    expect(t.bridge.calls, isNot(contains('backupCommit')));
    expect(t.c.error, 'Não foi possível restaurar o backup.');
  });

  test('the reminder', () async {
    final none = _make();
    await none.c.start();
    expect(none.c.reminderDue, isTrue); // never made one

    final t = _make(now: _today);
    t.last.key =
        '${_today.subtract(const Duration(days: 8)).millisecondsSinceEpoch}';
    await t.c.start();
    expect(t.c.daysSinceBackup, 8);
    expect(t.c.reminderDue, isTrue);
    await t.c.setInterval(15);
    expect(t.c.reminderDue, isFalse);
    await t.c.setInterval(0);
    expect(t.c.reminderDue, isFalse);

    t.last.key =
        '${_today.subtract(const Duration(days: 3)).millisecondsSinceEpoch}';
    await t.c.setInterval(7);
    await t.c.start();
    expect(t.c.reminderDue, isFalse);
  });

  testWidgets('the backup dialog checks the password', (tester) async {
    final t = _make();
    await t.c.start();
    await tester.pumpWidget(
      MaterialApp(
        home: BackupScreen(controller: t.c, mediaBytes: () async => 3 << 20),
      ),
    );
    expect(find.text('Você ainda não fez backup.'), findsOneWidget);
    await tester.tap(find.text('Fazer backup agora'));
    await tester.pumpAndSettle();
    expect(find.textContaining('3,0 MB'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Senha do backup'),
      'curta',
    );
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    expect(find.text('Use ao menos 8 caracteres.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Senha do backup'),
      'senha forte',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Repita a senha'),
      'outra senha',
    );
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    expect(find.text('As senhas não são iguais.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Repita a senha'),
      'senha forte',
    );
    await tester.tap(find.byType(Checkbox)); // without media
    await tester.tap(find.text('Continuar'));
    // The progress bar keeps moving: no pumpAndSettle while it shows.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(t.bridge.calls, contains('backupExport:7:no-media'));
    expect(t.bridge.backupRequest!.password, 'senha forte');
    expect(find.text('Preparando o backup…'), findsOneWidget);

    t.bridge.push('backup_done', {'bytes': 1});
    await tester.pumpAndSettle();
    expect(find.text('Backup concluído.'), findsOneWidget);
    expect(find.text('Último backup: 02/10/2026'), findsOneWidget);
  });

  testWidgets('restoring asks first; only restore where app.db is gone', (
    tester,
  ) async {
    final t = _make();
    await t.c.start();
    await tester.pumpWidget(
      MaterialApp(home: BackupScreen(controller: t.c, canExport: false)),
    );
    expect(find.text('Fazer backup agora'), findsNothing);
    await tester.tap(find.text('Restaurar backup'));
    await tester.pumpAndSettle();
    expect(find.textContaining('substitui todos os dados'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'senha forte');
    await tester.tap(find.text('Escolher o arquivo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(t.bridge.calls, contains('backupOpen:9:4'));
    expect(find.text('Conferindo o backup…'), findsOneWidget);
    t.bridge.push('backup_failed', {'code': 'wrong_password'});
    await tester.pumpAndSettle();
    expect(find.text('Senha incorreta.'), findsOneWidget);
  });

  testWidgets('the reminder banner opens Backup', (tester) async {
    final t = _make();
    await t.c.start();
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupReminder(controller: t.c, onOpen: () => opened = true),
        ),
      ),
    );
    expect(find.text('Você ainda não fez backup.'), findsOneWidget);
    await tester.tap(find.text('Fazer agora'));
    expect(opened, isTrue);
    await t.c.setInterval(0);
    await tester.pump();
    expect(find.text('Fazer agora'), findsNothing);
  });

  test('the request goes to the core as JSON', () {
    const r = BackupRequest(
      password: 'p',
      appCopy: 'a',
      appKey: 'k',
      appVersion: '1.0.0',
      appSchema: 4,
      media: true,
      workDir: 'w',
    );
    expect(r.toJson()['app_copy'], 'a');
    expect(r.toJson()['media'], isTrue);
  });
}
