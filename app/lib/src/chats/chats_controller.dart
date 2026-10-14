import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core_bridge/core_bridge.dart';
import 'chat_filters.dart';

/// The chat list. Reloads when the core reports a new
/// message or an imported history.
class ChatsController extends ChangeNotifier {
  ChatsController({required this._bridge});

  final CoreBridge _bridge;
  StreamSubscription<CoreEvent>? _events;

  List<ChatSummary> chats = const [];

  /// The filter above the list; kept here so the Início can
  /// open the list already filtered.
  ChatFilter filter = ChatFilter.all;

  void setFilter(ChatFilter value) {
    if (value == filter) return;
    filter = value;
    notifyListeners();
  }

  /// Called when "delete the chat and my messages for everyone" ends.
  void Function(int revoked, int failed)? onRevokeDone;

  /// Starts listening and loads the stored chats.
  void start() {
    _events ??= _bridge.events.listen((event) {
      switch (event.type) {
        case 'wa_message' || 'wa_history' || 'wa_deleted':
          load();
        case 'wa_revoke_done':
          onRevokeDone?.call(
            event.data['revoked'] as int? ?? 0,
            event.data['failed'] as int? ?? 0,
          );
        case 'wa_logged_out': // the core deleted the messages
          chats = const [];
          notifyListeners();
      }
    });
    load();
  }

  void load() {
    try {
      chats = _bridge.listChats();
    } on CoreException {
      chats = const []; // session not started yet
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }
}

/// How long after sending WhatsApp lets a message be deleted for everyone
/// (2 days and 12 hours; the core checks it again).
const revokeWindow = Duration(hours: 60);

/// Whether [m] may be deleted for everyone at [now]: mine,
/// sent, not deleted yet and recent enough.
bool canRevoke(ChatMessage m, DateTime now) =>
    m.fromMe &&
    m.kind != 'revoked' &&
    m.status != 'sending' &&
    m.status != 'failed' &&
    now.difference(DateTime.fromMillisecondsSinceEpoch(m.ts)) < revokeWindow;

/// The most messages a chat deletion deletes for everyone (the core's
/// limit too).
const maxRevokeOnDelete = 50;

/// How many of my messages in [chat] deleting it can also delete for
/// everyone.
int revocableCount(CoreBridge bridge, String chat, {DateTime? now}) {
  final at = now ?? DateTime.now();
  try {
    final n = bridge
        .listMessages(chat, limit: 200)
        .where((m) => canRevoke(m, at))
        .length;
    return n > maxRevokeOnDelete ? maxRevokeOnDelete : n;
  } on CoreException {
    return 0;
  }
}

/// One conversation: its messages, oldest first, growing live,
/// and sending text.
class ChatController extends ChangeNotifier {
  ChatController({required this._bridge, required this.chat, this.focus});

  static const pageSize = 50;

  final CoreBridge _bridge;
  final ChatSummary chat;
  StreamSubscription<CoreEvent>? _events;

  List<ChatMessage> messages = const [];

  /// False once the oldest stored message is loaded.
  bool hasOlder = false;

  /// A message found by a search: the conversation opens on it.
  final ChatMessage? focus;

  /// True while showing the past around [focus]; newer messages are one
  /// tap away ("Ir para as mais recentes").
  bool inPast = false;

  void start() {
    _events ??= _bridge.events.listen(_onEvent);
    if (focus case final f?) {
      // The page that ends on the message found.
      final page = _bridge.listMessages(
        chat.jid,
        beforeTs: f.ts + 1,
        limit: pageSize,
      );
      messages = page;
      hasOlder = page.length == pageSize;
      inPast = true;
      notifyListeners();
      return;
    }
    jumpToLatest();
  }

  /// Shows the newest messages.
  void jumpToLatest() {
    final page = _bridge.listMessages(chat.jid, limit: pageSize);
    messages = page;
    hasOlder = page.length == pageSize;
    inPast = false;
    notifyListeners();
  }

  /// Loads the page before the oldest message shown.
  void loadOlder() {
    if (messages.isEmpty) return;
    final page = _bridge.listMessages(
      chat.jid,
      beforeTs: messages.first.ts,
      limit: pageSize,
    );
    messages = [...page, ...messages];
    hasOlder = page.length == pageSize;
    notifyListeners();
  }

  /// Sends [text]; the message shows at once as "sending". Returns false
  /// when nothing was sent (blank text). Throws [CoreException] when the
  /// core refuses it.
  bool send(String text) {
    if (text.trim().isEmpty) return false;
    if (inPast) jumpToLatest();
    _add(_bridge.sendText(chat.jid, text));
    return true;
  }

  /// Sends a media. Throws [CoreException] like the bridge.
  void sendMedia(OutgoingMedia media) {
    if (inPast) jumpToLatest();
    _add(_bridge.sendMedia(chat.jid, media));
  }

  /// True once the chat was deleted, here or on the phone: the
  /// screen closes.
  bool deleted = false;

  /// Called when WhatsApp refused a "delete for everyone".
  VoidCallback? onDeleteFailed;

  /// Deletes the whole chat here and in my WhatsApp. Throws
  /// [CoreException] like the bridge.
  void deleteChat({bool forEveryone = false}) {
    _bridge.deleteChat(chat.jid, forEveryone: forEveryone);
    deleted = true;
    notifyListeners();
  }

  /// Deletes a message for me, at once, or for everyone, when WhatsApp
  /// confirms. Throws [CoreException] like the bridge
  /// ("offline" for everyone without connection).
  void deleteMessage(String id, {required bool forEveryone}) {
    _bridge.deleteMessage(chat.jid, id, forEveryone: forEveryone);
    if (!forEveryone) _remove(id);
  }

  /// Sends a failed message again (same message, no copy).
  void retry(String id) {
    final message = _bridge.retryMessage(chat.jid, id);
    _setStatus(message.id, message.status);
  }

  void _onEvent(CoreEvent event) {
    if (event.data['chat'] != chat.jid) return;
    switch (event.type) {
      case 'wa_message':
        // In the past, new messages wait behind "Ir para as mais recentes".
        if (!inPast) _add(ChatMessage.fromJson(event.data));
      case 'wa_message_status':
        _setStatus(event.data['id'] as String, event.data['status'] as String);
      case 'wa_media': // a media was downloaded
        _setMedia(event.data['id'] as String, event.data['state'] as String);
      case 'wa_deleted': // here or on the phone
        _onDeleted(event.data);
      case 'wa_delete_failed':
        onDeleteFailed?.call();
    }
  }

  void _onDeleted(Map<String, Object?> data) {
    switch (data['scope']) {
      case 'chat':
        deleted = true;
        messages = const [];
        notifyListeners();
      case 'clear':
        messages = const [];
        hasOlder = false;
        notifyListeners();
      case 'message':
        _remove(data['id'] as String);
      case 'revoked':
        final now = ChatMessage.fromJson(
          data['message'] as Map<String, Object?>,
        );
        final i = messages.indexWhere((m) => m.id == now.id);
        if (i < 0) return;
        messages = [...messages]..[i] = now;
        notifyListeners();
    }
  }

  void _remove(String id) {
    if (!messages.any((m) => m.id == id)) return;
    messages = [
      for (final m in messages)
        if (m.id != id) m,
    ];
    notifyListeners();
  }

  /// Messages that arrived or were sent while the conversation is open:
  /// they come in with a short slide.
  final fresh = <String>{};

  void _add(ChatMessage message) {
    if (messages.any((m) => m.id == message.id)) return;
    fresh.add(message.id);
    messages = [...messages, message];
    notifyListeners();
  }

  void _setMedia(String id, String state) {
    final i = messages.indexWhere((m) => m.id == id);
    if (i < 0 || messages[i].media == state) return;
    messages = [...messages]..[i] = messages[i].withMedia(state);
    notifyListeners();
  }

  void _setStatus(String id, String status) {
    final i = messages.indexWhere((m) => m.id == id);
    if (i < 0 || messages[i].status == status) return;
    messages = [...messages]..[i] = messages[i].withStatus(status);
    notifyListeners();
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }
}
