import 'package:flutter/foundation.dart';

import '../core_bridge/core_bridge.dart';
import '../search/text.dart';
import 'clients_repository.dart';
import 'validation.dart';

/// How the client list is ordered.
enum ClientSort { name, newest, lastChat, birthday }

/// Days from [today] to the next birthday stored as "AAAA-MM-DD" or
/// "--MM-DD"; null without a birthday. 29/02 falls on 01/03 in other years.
int? daysUntilBirthday(String stored, DateTime today) {
  final m = RegExp(r'(\d{2})-(\d{2})$').firstMatch(stored);
  if (stored.isEmpty || m == null) return null;
  final month = int.parse(m[1]!), day = int.parse(m[2]!);
  final start = DateTime(today.year, today.month, today.day);
  var next = DateTime(today.year, month, day);
  if (next.isBefore(start)) next = DateTime(today.year + 1, month, day);
  return next.difference(start).inDays;
}

/// Whether a stored birthday falls in [month].
bool birthdayIn(String stored, int month) {
  final m = RegExp(r'(\d{2})-\d{2}$').firstMatch(stored);
  return stored.isNotEmpty && m != null && int.parse(m[1]!) == month;
}

/// The client list with search, filters and sorting.
class ClientsController extends ChangeNotifier {
  ClientsController({
    required this._repo,
    this._bridge,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ClientsRepository _repo;
  final CoreBridge? _bridge;
  final DateTime Function() _clock;

  List<Client> all = const [];
  Map<int, String> _notes = const {};
  Map<int, int> _lastChat = const {};

  String query = '';
  final Set<String> tags = {};
  bool birthdaysThisMonth = false;
  ClientSort sort = ClientSort.name;

  /// "Devendo": only the clients in [_debtors].
  bool owingOnly = false;
  Set<int> _debtors = const {};

  /// "Sumidos": only the clients in [_gone].
  bool goneOnly = false;
  Set<int> _gone = const {};

  Future<void> load() async {
    final loaded = await _repo.list();
    final texts = await _repo.noteTexts();
    // The screen may be gone while the database answered (section changed).
    if (_disposed) return;
    all = loaded;
    _notes = texts;
    _lastChat = _lastChats();
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// When each client last talked on WhatsApp (Unix ms).
  Map<int, int> _lastChats() {
    final bridge = _bridge;
    if (bridge == null) return const {};
    try {
      final byJid = {for (final c in bridge.listChats()) c.jid: c.lastTs};
      return {
        for (final client in all)
          client.id!:
              ?byJid[client.chatJid ?? bridge.chatForPhone(client.phone)],
      };
    } on CoreException {
      return const {}; // WhatsApp not started
    }
  }

  /// Every tag in use, in order.
  List<String> get allTags => {for (final c in all) ...c.tags}.toList()..sort();

  /// The clients shown: search and filters, in the chosen order.
  List<Client> get clients {
    final today = _clock();
    final digits = digitsOf(query);
    final shown = [
      for (final c in all)
        if (_matches(c, digits) &&
            (tags.isEmpty || c.tags.any(tags.contains)) &&
            (!birthdaysThisMonth || birthdayIn(c.birthday, today.month)) &&
            (!owingOnly || _debtors.contains(c.id)) &&
            (!goneOnly || _gone.contains(c.id)))
          c,
    ];
    int byName(Client a, Client b) => fold(a.name).compareTo(fold(b.name));
    shown.sort((a, b) {
      final order = switch (sort) {
        ClientSort.name => byName(a, b),
        ClientSort.newest => _nullsLast(
          a.createdAt,
          b.createdAt,
          descending: true,
        ),
        ClientSort.lastChat => _nullsLast(
          _lastChat[a.id],
          _lastChat[b.id],
          descending: true,
        ),
        ClientSort.birthday => _nullsLast(
          daysUntilBirthday(a.birthday, today),
          daysUntilBirthday(b.birthday, today),
          descending: false,
        ),
      };
      return order != 0 ? order : byName(a, b);
    });
    return shown;
  }

  /// Clients without a value go last, whatever the direction.
  static int _nullsLast<T extends Comparable<Object>>(
    T? x,
    T? y, {
    required bool descending,
  }) => switch ((x, y)) {
    (null, null) => 0,
    (null, _) => 1,
    (_, null) => -1,
    (final a?, final b?) => descending ? b.compareTo(a) : a.compareTo(b),
  };

  bool _matches(Client c, String digits) {
    if (query.trim().isEmpty) return true;
    final text = [
      c.name,
      c.email,
      c.company,
      c.address,
      c.district,
      c.city,
      ...c.tags,
      _notes[c.id] ?? '',
    ].join(' ');
    if (textMatches(text, query)) return true;
    // Numbers: phone or CPF/CNPJ containing what was typed.
    return digits.length >= 3 &&
        digits.length == query.replaceAll(RegExp(r'[\s().\-/+]'), '').length &&
        (c.phone.contains(digits) || c.document.contains(digits));
  }

  void search(String text) {
    query = text;
    notifyListeners();
  }

  void toggleTag(String tag) {
    if (!tags.remove(tag)) tags.add(tag);
    notifyListeners();
  }

  void toggleBirthdays() {
    birthdaysThisMonth = !birthdaysThisMonth;
    notifyListeners();
  }

  void toggleOwing() {
    owingOnly = !owingOnly;
    notifyListeners();
  }

  void toggleGone() {
    goneOnly = !goneOnly;
    notifyListeners();
  }

  /// The clients with something to receive, and the ones who stopped
  /// buying, from the sales.
  void setDebtors(Set<int> ids, {Set<int> gone = const {}}) {
    _debtors = ids;
    _gone = gone;
    notifyListeners();
  }

  void sortBy(ClientSort value) {
    sort = value;
    notifyListeners();
  }
}

/// One client with the history of notes.
class ClientController extends ChangeNotifier {
  ClientController({required this._repo, required this.id});

  final ClientsRepository _repo;
  final int id;
  Client? client;
  List<ClientNote> notes = const [];
  bool loaded = false;

  Future<void> load() async {
    final found = await _repo.byId(id);
    final noted = found == null ? const <ClientNote>[] : await _repo.notes(id);
    if (_disposed) return;
    client = found;
    notes = noted;
    loaded = true;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Adds a note; blank text is ignored.
  Future<void> addNote(String text) async {
    if (text.trim().isEmpty) return;
    await _repo.addNote(id, text.trim());
    await load();
  }

  Future<void> deleteNote(int noteId) async {
    await _repo.deleteNote(noteId);
    await load();
  }

  /// Deletes the client, notes and tags for good.
  Future<void> delete() => _repo.delete(id);
}
