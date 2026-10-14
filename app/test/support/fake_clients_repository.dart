import 'package:chat_do_garoto/src/clients/clients_repository.dart';

/// In-memory [ClientsRepository] for screen tests.
class FakeClientsRepository implements ClientsRepository {
  final clients = <int, Client>{};
  final _notes = <int, List<ClientNote>>{};
  var _next = 1;
  var _noteId = 1;
  DateTime now = DateTime(2026, 10, 2, 9);

  @override
  Future<List<Client>> list() async =>
      clients.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<Client?> byId(int id) async => clients[id];

  @override
  Future<Client?> byChat(String jid) async {
    final user = jid.split('@').first;
    for (final c in clients.values) {
      if (c.chatJid == jid || c.phone == user) return c;
    }
    return null;
  }

  @override
  Future<int> save(Client c) async {
    for (final other in clients.values) {
      if (other.phone == c.phone && other.id != c.id) {
        throw const DuplicatePhone();
      }
    }
    final id = c.id ?? _next++;
    clients[id] = Client(
      id: id,
      name: c.name,
      phone: c.phone,
      chatJid: c.chatJid,
      email: c.email,
      address: c.address,
      cep: c.cep,
      number: c.number,
      complement: c.complement,
      district: c.district,
      city: c.city,
      state: c.state,
      document: c.document,
      birthday: c.birthday,
      company: c.company,
      tags: c.tags,
      createdAt:
          clients[id]?.createdAt ??
          DateTime(2026, 1, 1).add(Duration(hours: id)),
    );
    return id;
  }

  /// When set, [delete] throws it.
  Object? deleteError;

  @override
  Future<void> delete(int id) async {
    if (deleteError case final e?) throw e;
    clients.remove(id);
    _notes.remove(id);
  }

  @override
  Future<List<ClientNote>> notes(int clientId) async =>
      (_notes[clientId] ?? []).reversed.toList();

  @override
  Future<Map<int, String>> noteTexts() async => {
    for (final MapEntry(:key, :value) in _notes.entries)
      key: value.map((n) => n.body).join(' '),
  };

  @override
  Future<void> addNote(int clientId, String body) async {
    now = now.add(const Duration(minutes: 1));
    (_notes[clientId] ??= []).add(
      ClientNote(id: _noteId++, body: body, at: now),
    );
  }

  @override
  Future<void> deleteNote(int noteId) async {
    for (final list in _notes.values) {
      list.removeWhere((n) => n.id == noteId);
    }
  }
}
