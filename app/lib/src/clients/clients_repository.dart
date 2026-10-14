import 'package:drift/drift.dart';

import '../storage/app_database.dart';

/// A client of the CRM.
class Client {
  const Client({
    this.id,
    required this.name,
    required this.phone,
    this.chatJid,
    this.email = '',
    this.address = '',
    this.cep = '',
    this.number = '',
    this.complement = '',
    this.district = '',
    this.city = '',
    this.state = '',
    this.document = '',
    this.birthday = '',
    this.company = '',
    this.tags = const [],
    this.createdAt,
  });

  final int? id;
  final String name;

  /// Digits with country and area code.
  final String phone;
  final String? chatJid;
  final String email;

  /// The street.
  final String address;

  /// CEP digits.
  final String cep;
  final String number;
  final String complement;
  final String district;
  final String city;

  /// UF, two letters.
  final String state;

  /// "Rua A, 10, ap 2 – Centro, São Paulo/SP – 01001-000"; empty without
  /// an address.
  String get fullAddress {
    final street = [
      address,
      number,
      complement,
    ].where((p) => p.trim().isNotEmpty).join(', ');
    final place = [
      district,
      [city, state].where((p) => p.trim().isNotEmpty).join('/'),
    ].where((p) => p.trim().isNotEmpty).join(', ');
    final code = cep.length == 8
        ? '${cep.substring(0, 5)}-${cep.substring(5)}'
        : cep;
    return [street, place, code].where((p) => p.trim().isNotEmpty).join(' – ');
  }

  /// CPF or CNPJ, digits only.
  final String document;

  /// "AAAA-MM-DD" or "--MM-DD".
  final String birthday;
  final String company;
  final List<String> tags;

  /// When the client was added; set by the repository.
  final DateTime? createdAt;

  /// The same client linked to the WhatsApp chat [jid].
  Client linkedTo(String jid) => Client(
    id: id,
    name: name,
    phone: phone,
    chatJid: jid,
    email: email,
    address: address,
    cep: cep,
    number: number,
    complement: complement,
    district: district,
    city: city,
    state: state,
    document: document,
    birthday: birthday,
    company: company,
    tags: tags,
    createdAt: createdAt,
  );
}

/// A dated note in a client's history.
class ClientNote {
  const ClientNote({required this.id, required this.body, required this.at});
  final int id;
  final String body;
  final DateTime at;
}

/// The client still owes [open] cents: receive or cancel before deleting
class ClientHasOpenSales implements Exception {
  const ClientHasOpenSales(this.open);
  final int open;
}

/// Another client already has this phone.
class DuplicatePhone implements Exception {
  const DuplicatePhone();
}

/// Clients and their notes, in app.db (0013).
abstract interface class ClientsRepository {
  /// All clients, by name.
  Future<List<Client>> list();
  Future<Client?> byId(int id);

  /// The client of a WhatsApp chat: saved from it, or with its phone.
  Future<Client?> byChat(String jid);

  /// Creates or updates; returns the id. Throws [DuplicatePhone].
  Future<int> save(Client client);

  /// Deletes the client with its notes and tags. Their sales stay as
  /// "Cliente apagado"; throws [ClientHasOpenSales] while they owe
  /// something.
  Future<void> delete(int id);

  /// Newest first.
  Future<List<ClientNote>> notes(int clientId);

  /// The text of every client's notes, joined, for the search.
  Future<Map<int, String>> noteTexts();
  Future<void> addNote(int clientId, String body);
  Future<void> deleteNote(int noteId);
}

class DriftClientsRepository implements ClientsRepository {
  DriftClientsRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  Future<Client> _withTags(ClientRow row) async {
    final tags =
        await (_db.select(_db.clientTags)
              ..where((t) => t.clientId.equals(row.id))
              ..orderBy([(t) => OrderingTerm(expression: t.tag)]))
            .map((t) => t.tag)
            .get();
    return Client(
      id: row.id,
      name: row.name,
      phone: row.phone,
      chatJid: row.chatJid,
      email: row.email,
      address: row.address,
      cep: row.cep,
      number: row.addressNumber,
      complement: row.complement,
      district: row.district,
      city: row.city,
      state: row.state,
      document: row.document,
      birthday: row.birthday,
      company: row.company,
      tags: tags,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    );
  }

  @override
  Future<List<Client>> list() async {
    final rows =
        await (_db.select(_db.clients)..orderBy([
              (c) => OrderingTerm(expression: c.name.collate(Collate.noCase)),
            ]))
            .get();
    return [for (final r in rows) await _withTags(r)];
  }

  @override
  Future<Client?> byId(int id) async {
    final row = await (_db.select(
      _db.clients,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    return row == null ? null : _withTags(row);
  }

  @override
  Future<Client?> byChat(String jid) async {
    final [user, server] = jid.contains('@') ? jid.split('@') : [jid, ''];
    final phone = server == 's.whatsapp.net' ? user : null;
    final row =
        await (_db.select(_db.clients)
              ..where(
                (c) => phone == null
                    ? c.chatJid.equals(jid)
                    : c.chatJid.equals(jid) | c.phone.equals(phone),
              )
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _withTags(row);
  }

  @override
  Future<int> save(Client c) async {
    final now = _clock().millisecondsSinceEpoch;
    final other = await (_db.select(
      _db.clients,
    )..where((r) => r.phone.equals(c.phone))).getSingleOrNull();
    if (other != null && other.id != c.id) throw const DuplicatePhone();
    return _db.transaction(() async {
      final fields = ClientsCompanion(
        name: Value(c.name),
        phone: Value(c.phone),
        chatJid: Value(c.chatJid),
        email: Value(c.email),
        address: Value(c.address),
        cep: Value(c.cep),
        addressNumber: Value(c.number),
        complement: Value(c.complement),
        district: Value(c.district),
        city: Value(c.city),
        state: Value(c.state),
        document: Value(c.document),
        birthday: Value(c.birthday),
        company: Value(c.company),
        updatedAt: Value(now),
      );
      final int id;
      if (c.id case final existing?) {
        await (_db.update(
          _db.clients,
        )..where((r) => r.id.equals(existing))).write(fields);
        id = existing;
      } else {
        id = await _db
            .into(_db.clients)
            .insert(fields.copyWith(createdAt: Value(now)));
      }
      await (_db.delete(
        _db.clientTags,
      )..where((t) => t.clientId.equals(id))).go();
      for (final tag in c.tags) {
        await _db
            .into(_db.clientTags)
            .insert(ClientTagsCompanion.insert(clientId: id, tag: tag));
      }
      return id;
    });
  }

  @override
  Future<void> delete(int id) => _db.transaction(() async {
    final rows = await _db
        .customSelect(
          'SELECT '
          '(SELECT COALESCE(SUM(amount), 0) FROM sale_installments i '
          'WHERE i.sale_id = s.id) AS due, '
          '(SELECT COALESCE(SUM(amount), 0) FROM sale_payments p '
          "WHERE p.sale_id = s.id AND p.kind = 'receipt' AND p.voided = 0) "
          'AS got '
          'FROM sales s WHERE s.client_id = ? AND s.canceled_at IS NULL',
          variables: [Variable.withInt(id)],
          readsFrom: {_db.sales, _db.saleInstallments, _db.salePayments},
        )
        .get();
    final open = rows.fold(0, (sum, r) {
      final left = r.read<int>('due') - r.read<int>('got');
      return sum + (left > 0 ? left : 0);
    });
    if (open > 0) throw ClientHasOpenSales(open);
    // The sales stay, without the name.
    await (_db.update(_db.sales)..where((s) => s.clientId.equals(id))).write(
      const SalesCompanion(clientRemoved: Value(true)),
    );
    await (_db.delete(_db.clients)..where((c) => c.id.equals(id))).go();
  });

  @override
  Future<List<ClientNote>> notes(int clientId) async {
    final rows =
        await (_db.select(_db.clientNotes)
              ..where((n) => n.clientId.equals(clientId))
              ..orderBy([
                (n) => OrderingTerm.desc(n.createdAt),
                (n) => OrderingTerm.desc(n.id),
              ]))
            .get();
    return [
      for (final n in rows)
        ClientNote(
          id: n.id,
          body: n.body,
          at: DateTime.fromMillisecondsSinceEpoch(n.createdAt),
        ),
    ];
  }

  @override
  Future<Map<int, String>> noteTexts() async {
    final out = <int, String>{};
    for (final n in await _db.select(_db.clientNotes).get()) {
      out[n.clientId] = '${out[n.clientId] ?? ''} ${n.body}';
    }
    return out;
  }

  @override
  Future<void> addNote(int clientId, String body) => _db
      .into(_db.clientNotes)
      .insert(
        ClientNotesCompanion.insert(
          clientId: clientId,
          body: body,
          createdAt: _clock().millisecondsSinceEpoch,
        ),
      );

  @override
  Future<void> deleteNote(int noteId) =>
      (_db.delete(_db.clientNotes)..where((n) => n.id.equals(noteId))).go();
}
