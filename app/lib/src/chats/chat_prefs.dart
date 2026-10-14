import 'dart:convert';

import '../storage/app_database.dart';

/// A ready text for the conversation: typed after "/" by
/// its [shortcut], or found by its [text].
class QuickReply {
  const QuickReply({required this.shortcut, required this.text});

  final String shortcut;
  final String text;

  Map<String, Object?> toJson() => {'shortcut': shortcut, 'text': text};

  factory QuickReply.fromJson(Map<String, Object?> json) => QuickReply(
    shortcut: json['shortcut'] as String? ?? '',
    text: json['text'] as String? ?? '',
  );
}

/// What the conversations keep in app.db: the quick replies
/// and the contacts marked "Ignorar". Encrypted with the rest of app.db,
/// and so also in the backup.
abstract interface class ChatPrefs {
  Future<List<QuickReply>> quickReplies();
  Future<void> saveQuickReplies(List<QuickReply> replies);

  /// The chats whose "contato novo" strip was dismissed.
  Future<Set<String>> ignored();
  Future<void> setIgnored(String jid, {required bool ignored});
}

/// [ChatPrefs] in app.db's preferences table, as JSON: a few small lists,
/// no new table.
class DriftChatPrefs implements ChatPrefs {
  DriftChatPrefs(this._db);

  final AppDatabase _db;

  static const _replies = 'quick_replies';
  static const _ignored = 'ignored_chats';

  Future<List<Object?>> _list(String name) async {
    final raw = await _db.preference(name);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return jsonDecode(raw) as List<Object?>;
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<List<QuickReply>> quickReplies() async => [
    for (final item in await _list(_replies))
      if (item is Map<String, Object?>) QuickReply.fromJson(item),
  ];

  @override
  Future<void> saveQuickReplies(List<QuickReply> replies) => _db.setPreference(
    _replies,
    jsonEncode([for (final r in replies) r.toJson()]),
  );

  @override
  Future<Set<String>> ignored() async => {
    for (final item in await _list(_ignored))
      if (item is String) item,
  };

  @override
  Future<void> setIgnored(String jid, {required bool ignored}) async {
    final all = await this.ignored();
    ignored ? all.add(jid) : all.remove(jid);
    await _db.setPreference(_ignored, jsonEncode(all.toList()..sort()));
  }
}
