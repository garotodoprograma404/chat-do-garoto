// Quick replies and ignored contacts in app.db with the real SQLCipher
import 'dart:io';

import 'package:chat_do_garoto/src/chats/chat_prefs.dart';
import 'package:chat_do_garoto/src/storage/app_database.dart';
import 'package:chat_do_garoto/src/storage/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late String path;
  final key = newDatabaseKey();

  Future<AppDatabase> openDb() async => (await AppStorage(
    path: () async => path,
  ).open(key) as StorageOpened).database;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('chat_prefs_test');
    path = '${dir.path}/app/app.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('quick replies and ignored chats survive closing app.db', () async {
    var db = await openDb();
    var prefs = DriftChatPrefs(db);
    expect(await prefs.quickReplies(), isEmpty);
    expect(await prefs.ignored(), isEmpty);

    await prefs.saveQuickReplies(const [
      QuickReply(shortcut: 'pix', text: 'Oi {nome}, a chave pix é 123.'),
      QuickReply(shortcut: 'obrigado', text: 'Obrigado pela compra!'),
    ]);
    await prefs.setIgnored('5511900000005@s.whatsapp.net', ignored: true);
    await prefs.setIgnored('5511900000006@s.whatsapp.net', ignored: true);
    await prefs.setIgnored('5511900000006@s.whatsapp.net', ignored: false);
    await db.close();

    db = await openDb();
    prefs = DriftChatPrefs(db);
    final replies = await prefs.quickReplies();
    expect([for (final r in replies) r.shortcut], ['pix', 'obrigado']);
    expect(replies.first.text, 'Oi {nome}, a chave pix é 123.');
    expect(await prefs.ignored(), {'5511900000005@s.whatsapp.net'});
    await db.close();
  });

  test('a damaged value reads as empty instead of breaking', () async {
    final db = await openDb();
    await db.setPreference('quick_replies', 'not json');
    expect(await DriftChatPrefs(db).quickReplies(), isEmpty);
    await db.close();
  });
}
