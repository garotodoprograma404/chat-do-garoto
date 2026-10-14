// Clients in app.db with the real SQLCipher.
import 'dart:io';

import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/storage/app_database.dart';
import 'package:chat_do_garoto/src/storage/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late String path;
  late AppDatabase db;
  late DriftClientsRepository repo;
  final key = newDatabaseKey();
  var now = DateTime(2026, 10, 2, 9);

  Future<AppDatabase> openDb() async => (await AppStorage(
    path: () async => path,
  ).open(key) as StorageOpened).database;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('clients_test');
    path = '${dir.path}/app/app.db';
    db = await openDb();
    repo = DriftClientsRepository(db, clock: () => now);
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  const ana = Client(
    name: 'Ana Souza',
    phone: '5511900000001',
    chatJid: '5511900000001@s.whatsapp.net',
    email: 'ana@exemplo.com',
    address: 'Rua A, 1',
    document: '52998224725',
    birthday: '--03-05',
    company: 'Loja da Ana',
    tags: ['atacado', 'vip'],
  );

  test('creates, reads and edits a client with every field', () async {
    final id = await repo.save(ana);
    final read = (await repo.byId(id))!;
    expect(read.name, 'Ana Souza');
    expect(read.document, '52998224725');
    expect(read.birthday, '--03-05');
    expect(read.tags, ['atacado', 'vip']);

    await repo.save(
      Client(id: id, name: 'Ana S.', phone: ana.phone, tags: const ['vip']),
    );
    final edited = (await repo.byId(id))!;
    expect(edited.name, 'Ana S.');
    expect(edited.email, '');
    expect(edited.tags, ['vip']);
  });

  test('a phone belongs to one client only', () async {
    await repo.save(ana);
    await expectLater(
      repo.save(const Client(name: 'Outra', phone: '5511900000001')),
      throwsA(isA<DuplicatePhone>()),
    );
  });

  test(
    'the list is by name; a chat finds its client by jid or phone',
    () async {
      await repo.save(const Client(name: 'bruno', phone: '5511900000002'));
      await repo.save(ana);
      expect(
        [for (final c in await repo.list()) c.name],
        ['Ana Souza', 'bruno'],
      );

      expect(
        (await repo.byChat('5511900000002@s.whatsapp.net'))?.name,
        'bruno',
      );
      expect(
        (await repo.byChat('5511900000001@s.whatsapp.net'))?.name,
        'Ana Souza',
      );
      expect(await repo.byChat('5511900000009@s.whatsapp.net'), isNull);
      expect(await repo.byChat('123456@lid'), isNull);
    },
  );

  test('notes are newest first and can be deleted', () async {
    final id = await repo.save(ana);
    await repo.addNote(id, 'primeira');
    now = now.add(const Duration(hours: 1));
    await repo.addNote(id, 'segunda');
    final notes = await repo.notes(id);
    expect([for (final n in notes) n.body], ['segunda', 'primeira']);
    expect(notes.first.at, now);

    await repo.deleteNote(notes.last.id);
    expect([for (final n in await repo.notes(id)) n.body], ['segunda']);
  });

  test(
    'deleting a client deletes its notes and tags, and really deletes',
    () async {
      final id = await repo.save(ana);
      await repo.addNote(id, 'segredo');
      await repo.delete(id);
      expect(await repo.byId(id), isNull);
      expect(await db.select(db.clientNotes).get(), isEmpty);
      expect(await db.select(db.clientTags).get(), isEmpty);

      final secure = await db.customSelect('PRAGMA secure_delete').getSingle();
      expect(secure.data.values.first, 1);
    },
  );

  test('creation time and note texts for the search', () async {
    final id = await repo.save(ana);
    await repo.addNote(id, 'quer orçamento');
    await repo.addNote(id, 'ligar segunda');
    expect((await repo.byId(id))!.createdAt, now);
    final texts = await repo.noteTexts();
    expect(texts[id], contains('quer orçamento'));
    expect(texts[id], contains('ligar segunda'));
  });

  test('a version 1 database keeps its preferences', () async {
    await db.close();
    File(path).deleteSync();
    // app.db as delivery 2.1 left it: preferences only, schema version 1.
    final raw = sqlite3.open(path);
    applyKey(raw, key);
    raw.execute(
      'CREATE TABLE preferences (name TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
    );
    raw.execute("INSERT INTO preferences VALUES ('created_at', 'ontem')");
    raw.execute('PRAGMA user_version = 1');
    raw.close();

    db = await openDb();
    repo = DriftClientsRepository(db, clock: () => now);
    expect(await db.preference('created_at'), 'ontem');
    expect(await repo.save(ana), isPositive);
  });
}
