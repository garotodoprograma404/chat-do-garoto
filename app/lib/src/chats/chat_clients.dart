import 'package:flutter/foundation.dart';

import '../clients/clients_repository.dart';
import '../core_bridge/core_bridge.dart';
import '../sales/sales_repository.dart';
import 'chat_prefs.dart';

/// What a client owes: the open amount and whether part of it is overdue.
typedef Debt = ({int open, bool overdue});

/// Which conversations belong to clients: by the chat a
/// client was saved from, or by phone, also for chats under a private ID
/// (LID). Also what each client owes and the contacts marked "Ignorar",
/// for the filters and the panel.
class ChatClients extends ChangeNotifier {
  ChatClients({
    required this._bridge,
    required this._repo,
    this.sales,
    this.prefs,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final CoreBridge _bridge;
  final ClientsRepository _repo;

  /// Null without the sales (the debts stay empty).
  final SalesRepository? sales;

  /// Null without app.db's preferences (nothing is ignored).
  final ChatPrefs? prefs;
  final DateTime Function() _clock;

  var _byJid = <String, Client>{};
  var _byPhone = <String, Client>{};
  final _lidPhones = <String, String>{};
  var _debts = <int, Debt>{};
  var _ignored = <String>{};

  Future<void> load() async {
    final clients = await _repo.list();
    final debts = switch (sales) {
      final s? => debtsByClient(await s.list(), _clock()),
      null => <int, Debt>{},
    };
    final ignored = await prefs?.ignored() ?? <String>{};
    _byJid = {for (final c in clients) ?c.chatJid: c};
    _byPhone = {for (final c in clients) c.phone: c};
    _debts = debts;
    _ignored = ignored;
    if (!_disposed) notifyListeners();
  }

  // load() may end after the screen that owns this is gone.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// The client of the chat [jid], or null when it is not a client's.
  Client? clientOfJid(String jid) {
    if (_byJid[jid] case final client?) return client;
    final phone = phoneOf(jid);
    return phone.isEmpty ? null : _byPhone[phone];
  }

  /// The client of [chat], or null.
  Client? clientOf(ChatSummary chat) => clientOfJid(chat.jid);

  /// The client's name for [chat], or null when it is not a client's.
  String? of(ChatSummary chat) => clientOf(chat)?.name;

  /// The phone behind a chat: the number of a phone chat, the one WhatsApp
  /// told for a private ID, or "" (groups, unknown).
  String phoneOf(String jid) {
    final [user, server] = jid.contains('@') ? jid.split('@') : [jid, ''];
    return switch (server) {
      's.whatsapp.net' => user,
      'lid' => _lidPhones.putIfAbsent(jid, () {
        try {
          return _bridge.chatPhone(jid);
        } on CoreException {
          return '';
        }
      }),
      _ => '',
    };
  }

  /// What the client of [chat] owes, or null when nothing (or no client).
  Debt? debtOf(ChatSummary chat) => switch (clientOf(chat)?.id) {
    final id? => _debts[id],
    null => null,
  };

  /// Whether the "contato novo" strip of [jid] was dismissed.
  bool isIgnored(String jid) => _ignored.contains(jid);

  /// Marks [jid] as "Ignorar", or undoes it.
  Future<void> setIgnored(String jid, {required bool ignored}) async {
    ignored ? _ignored.add(jid) : _ignored.remove(jid);
    notifyListeners();
    await prefs?.setIgnored(jid, ignored: ignored);
  }
}

/// The client of the chat [jid]: saved from it, or with its phone, also
/// the one WhatsApp told for a private ID. Null for groups
/// and non-clients.
Future<Client?> findChatClient(
  ClientsRepository repo,
  CoreBridge bridge,
  String jid,
) async {
  if (jid.endsWith('@g.us')) return null;
  if (await repo.byChat(jid) case final client?) return client;
  if (!jid.endsWith('@lid')) return null;
  final String phone;
  try {
    phone = bridge.chatPhone(jid);
  } on CoreException {
    return null;
  }
  return phone.isEmpty ? null : repo.byChat('$phone@s.whatsapp.net');
}
