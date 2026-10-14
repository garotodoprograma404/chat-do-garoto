import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'chatcore.g.dart' as native;

/// The bridge protocol version this app understands (see chatcore.h).
const bridgeProtocolVersion = 1;

/// A failure reported by the Go core. [code] is stable and safe to branch on.
class CoreException implements Exception {
  const CoreException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'CoreException($code): $message';
}

/// Versions reported by the Go core.
class CoreVersion {
  const CoreVersion({required this.core, required this.go});

  final String core;
  final String go;
}

/// An event pushed by the Go core.
class CoreEvent {
  const CoreEvent(this.type, this.data);

  final String type;
  final Map<String, Object?> data;

  @override
  String toString() => 'CoreEvent($type, $data)';
}

/// A conversation in the chat list.
class ChatSummary {
  const ChatSummary({
    required this.jid,
    required this.name,
    required this.lastText,
    required this.lastTs,
    this.lastFromMe = true,
  });

  factory ChatSummary.fromJson(Map<String, Object?> json) => ChatSummary(
    jid: json['jid'] as String,
    name: json['name'] as String,
    lastText: json['last_text'] as String,
    lastTs: json['last_ts'] as int,
    lastFromMe: json['last_from_me'] as bool? ?? true,
  );

  final String jid;
  final String name;
  final String lastText;

  /// Unix milliseconds.
  final int lastTs;

  /// Whether the newest message is mine (or there is none left): nothing
  /// to reply to.
  final bool lastFromMe;
}

/// One WhatsApp message. [kind] is "text", "image", "audio",
/// "video", "document", "sticker" or "other".
class ChatMessage {
  const ChatMessage({
    required this.chat,
    required this.id,
    required this.fromMe,
    required this.senderName,
    required this.kind,
    required this.text,
    required this.ts,
    this.status = '',
    this.media = '',
    this.thumb = false,
    this.fileName = '',
    this.mime = '',
    this.size = 0,
    this.seconds = 0,
    this.ptt = false,
    this.forwarded = false,
  });

  factory ChatMessage.fromJson(Map<String, Object?> json) => ChatMessage(
    chat: json['chat'] as String,
    id: json['id'] as String,
    fromMe: json['from_me'] as bool,
    senderName: json['sender_name'] as String,
    kind: json['kind'] as String,
    text: json['text'] as String,
    ts: json['ts'] as int,
    status: json['status'] as String? ?? '',
    media: json['media'] as String? ?? '',
    thumb: json['thumb'] as bool? ?? false,
    fileName: json['file_name'] as String? ?? '',
    mime: json['mime'] as String? ?? '',
    size: json['size'] as int? ?? 0,
    seconds: json['seconds'] as int? ?? 0,
    ptt: json['ptt'] as bool? ?? false,
    forwarded: json['forwarded'] as bool? ?? false,
  );

  final String chat;
  final String id;
  final bool fromMe;
  final String senderName;
  final String kind;
  final String text;

  /// Unix milliseconds.
  final int ts;

  /// Delivery status of my messages: "sending", "sent",
  /// "delivered", "read" or "failed"; "" for received ones.
  final String status;

  /// Media state: "thumb", "remote", "downloaded",
  /// "failed", "expired"; "" without a stored media.
  final String media;

  /// Whether a thumbnail is in the vault.
  final bool thumb;

  /// Media details: a document's name, the type, the size in
  /// bytes, the length of audio and video, and whether an audio is a voice
  /// message.
  final String fileName;
  final String mime;
  final int size;
  final int seconds;
  final bool ptt;

  /// A forwarded message, received or sent.
  final bool forwarded;

  ChatMessage withMedia(String media) => _copy(media: media);

  ChatMessage withStatus(String status) => _copy(status: status);

  ChatMessage _copy({String? media, String? status}) => ChatMessage(
    chat: chat,
    id: id,
    fromMe: fromMe,
    senderName: senderName,
    kind: kind,
    text: text,
    ts: ts,
    status: status ?? this.status,
    media: media ?? this.media,
    thumb: thumb,
    fileName: fileName,
    mime: mime,
    size: size,
    seconds: seconds,
    ptt: ptt,
    forwarded: forwarded,
  );
}

/// A media to send: [kind] is "image", "video", "audio" or
/// "document"; [thumb] is a video's preview made by the phone.
/// What a backup needs from the app: the password, the copy of
/// `app.db` encrypted with a one-time key, and the folder to work in.
class BackupRequest {
  const BackupRequest({
    required this.password,
    required this.appCopy,
    required this.appKey,
    required this.appVersion,
    required this.appSchema,
    required this.media,
    required this.workDir,
  });

  final String password;
  final String appCopy;
  final String appKey;
  final String appVersion;
  final int appSchema;
  final bool media;
  final String workDir;

  Map<String, Object?> toJson() => {
    'password': password,
    'app_copy': appCopy,
    'app_key': appKey,
    'app_version': appVersion,
    'app_schema': appSchema,
    'media': media,
    'work_dir': workDir,
  };
}

class OutgoingMedia {
  const OutgoingMedia({
    required this.kind,
    required this.bytes,
    this.caption = '',
    this.fileName = '',
    this.mime = '',
    this.seconds = 0,
    this.ptt = false,
    this.thumb,
  });

  final String kind;
  final Uint8List bytes;
  final String caption;
  final String fileName;
  final String mime;
  final int seconds;
  final bool ptt;
  final Uint8List? thumb;
}

/// What [CoreBridge.startWhatsApp] finds: whether an account is paired and
/// whether the connection is already up.
typedef WhatsAppState = ({bool paired, bool connected, String pushName});

/// A period without connection. [cause] is "drop", "restart"
/// or "stop" (on purpose); [source] says who restarted the core.
class Outage {
  const Outage({
    required this.start,
    required this.durationMs,
    required this.cause,
    this.source = '',
    this.ongoing = false,
  });

  factory Outage.fromJson(Map<String, Object?> json) => Outage(
    start: json['start'] as int,
    durationMs: json['duration_ms'] as int,
    cause: json['cause'] as String,
    source: json['source'] as String? ?? '',
    ongoing: json['ongoing'] as bool? ?? false,
  );

  /// Unix milliseconds.
  final int start;
  final int durationMs;
  final String cause;
  final String source;
  final bool ongoing;
}

/// Summary of the connection log.
class ConnectionReport {
  const ConnectionReport({
    required this.since,
    required this.totalMs,
    required this.connectedMs,
    required this.drops,
    required this.longestMs,
    this.starts = const {},
    this.outages = const [],
  });

  factory ConnectionReport.fromJson(Map<String, Object?> json) =>
      ConnectionReport(
        since: json['since'] as int,
        totalMs: json['total_ms'] as int,
        connectedMs: json['connected_ms'] as int,
        drops: json['drops'] as int,
        longestMs: json['longest_ms'] as int,
        starts: {
          for (final MapEntry(:key, :value)
              in (json['starts'] as Map<String, Object?>? ?? {}).entries)
            key: value as int,
        },
        outages: [
          for (final o in json['outages'] as List<Object?>? ?? const [])
            Outage.fromJson(o as Map<String, Object?>),
        ],
      );

  /// When measuring began (Unix ms); 0 when there is no data yet.
  final int since;
  final int totalMs;
  final int connectedMs;

  /// Unintended outages: drops and restarts.
  final int drops;
  final int longestMs;

  /// How many times each source ("app", "system", "boot") started the core.
  final Map<String, int> starts;

  /// Newest first.
  final List<Outage> outages;
}

/// The only entry point to the Go core. Screens depend on this interface and
/// never call FFI directly.
abstract interface class CoreBridge {
  /// Versions of the core and of the Go runtime inside it.
  CoreVersion version();

  /// Sends [text] through the bridge and returns what the core sent back.
  /// [text] must not contain NUL characters.
  String echo(String text);

  /// Events pushed by the core, in the order each core task sent them.
  Stream<CoreEvent> get events;

  /// Starts the demo ticker: [workers] concurrent core tasks each push
  /// [count] "tick" events, [interval] apart, then one "ticker_done" event.
  void startTicker({
    required int count,
    Duration interval = Duration.zero,
    int workers = 1,
  });

  /// Stops the demo ticker. No tick is pushed after this returns.
  void stopTicker();

  /// Opens the WhatsApp session stored at [dbPath], encrypted with [key]
  /// (64 lowercase hex digits), and connects in the background
  ///, or reuses it when already open. Progress arrives as "wa_*"
  /// [events]. Throws [CoreException] "unreadable" when [key] does not open
  /// it; then call [resetWhatsApp].
  WhatsAppState startWhatsApp(String dbPath, String key);

  /// Deletes an unreadable session database at [dbPath].
  void resetWhatsApp(String dbPath);

  /// Requests a pairing code for an international [phone] number; it
  /// arrives as a "wa_pair_code" event. Throws [CoreException] with
  /// "invalid_argument" for an invalid number.
  void requestPairingCode(String phone);

  /// Unlinks this device from the account and deletes the session; a
  /// "wa_logged_out" event follows.
  void logoutWhatsApp();

  /// Disconnects, keeping the session saved.
  void stopWhatsApp();

  /// Stored chats, newest first.
  List<ChatSummary> listChats({int limit = 200});

  /// A page of [chat]'s messages older than [beforeTs] (0 = newest), oldest
  /// first.
  List<ChatMessage> listMessages(
    String chat, {
    int beforeTs = 0,
    int limit = 50,
  });

  /// Stores [text] to [chat] as "sending" and sends it in the background
  /// Status changes arrive as "wa_message_status" [events].
  /// Throws [CoreException] with "invalid_argument" for an empty text.
  ChatMessage sendText(String chat, String text);

  /// Sends a failed message again, with the same ID.
  ChatMessage retryMessage(String chat, String id);

  /// Sends a media: photos are turned upright and lose their
  /// metadata (location). Returns the message as "sending"; the outcome
  /// arrives as "wa_message_status". Throws [CoreException] "too_big" above
  /// the app's limit.
  ChatMessage sendMedia(String chat, OutgoingMedia media);

  /// Forwards a message to chat [to] with the "forwarded" mark;
  /// returns the copy as "sending".
  ChatMessage forwardMessage(String chat, String id, String to);

  /// Deletes a chat here and in my WhatsApp; `wa_deleted`
  /// follows. [forEveryone] also deletes for everyone my messages of the
  /// last 60 h (up to 50; needs the connection: code "offline"), ending as
  /// `wa_revoke_done`.
  void deleteChat(String chat, {bool forEveryone = false});

  /// Deletes a message for me, or for everyone (my message, under 60 h,
  /// needs the connection: code "offline"). For everyone ends as
  /// `wa_deleted` (scope "revoked") or `wa_delete_failed`.
  void deleteMessage(String chat, String id, {required bool forEveryone});

  /// Writes a backup to [fd] in the background; the core takes
  /// and closes [fd]. Ends as `backup_done` or `backup_failed`.
  void backupExport(int fd, BackupRequest request);

  /// Reads and checks the backup in [fd] in the background; the core takes
  /// and closes [fd]. Ends as `backup_ready` or `backup_failed`.
  void backupOpen(
    int fd, {
    required String password,
    required String workDir,
    required int maxAppSchema,
  });

  /// Replaces the conversations and media with the opened backup; ends as
  /// `backup_restored` or `backup_failed`.
  void backupCommit();

  /// Drops an opened backup.
  void backupDiscard();

  /// Cancels the backup task running now.
  void backupCancel();

  /// Summary of the connection log.
  ConnectionReport connectionReport();

  /// The phone (digits) behind a one-to-one chat, also under a private ID
  /// when WhatsApp told it; "" when unknown.
  String chatPhone(String chat);

  /// Messages whose text matches [query], ignoring accents and case,
  /// newest first.
  List<ChatMessage> searchMessages(String query, {int limit = 100});

  /// The stored chat of a phone (digits), also under a private ID when
  /// known; "" when there is none.
  String chatForPhone(String phone);

  /// Downloads the photo of a message; the outcome arrives as a
  /// "wa_media" event {chat, id, state}.
  void downloadMedia(String chat, String id);

  /// A part of a stored media ("thumb" or "full"), decrypted in memory; the
  /// media itself crosses the bridge as bytes. Throws
  /// [CoreException] "invalid_argument" when it is not stored.
  Uint8List mediaBytes(String chat, String id, String part);

  /// Seals [secretHex] under [pin]: Argon2id + AES-256-GCM.
  /// Slow on purpose, so it runs on another isolate. Never log the PIN.
  Future<String> sealWithPin(String pin, String secretHex);

  /// Opens an envelope from [sealWithPin]. Throws [CoreException]
  /// "wrong_pin" when the PIN does not open it.
  Future<String> openWithPin(String pin, String envelope);

  /// Development builds only: redacted whatsmeow diagnostics arrive as
  /// "wa_log" [events].
  void setWhatsAppDiagnostics(bool on);

  /// Stops listening to the core. Events still in flight are discarded.
  void dispose();
}

/// [CoreBridge] backed by libchatcore through dart:ffi.
class NativeCoreBridge implements CoreBridge {
  NativeCoreBridge();

  final _events = StreamController<CoreEvent>.broadcast();
  NativeCallable<Void Function(Pointer<Char>)>? _listener;

  @override
  CoreVersion version() {
    final data = callNative(native.cc_version);
    return CoreVersion(core: data['core'] as String, go: data['go'] as String);
  }

  @override
  String echo(String text) {
    return using((arena) {
      final input = text.toNativeUtf8(allocator: arena).cast<Char>();
      return callNative(() => native.cc_echo(input))['text'] as String;
    });
  }

  @override
  Stream<CoreEvent> get events {
    _listen();
    return _events.stream;
  }

  @override
  void startTicker({
    required int count,
    Duration interval = Duration.zero,
    int workers = 1,
  }) {
    callNative(
      () => native.cc_ticker_start(count, interval.inMilliseconds, workers),
    );
  }

  @override
  void stopTicker() {
    callNative(native.cc_ticker_stop);
  }

  @override
  WhatsAppState startWhatsApp(String dbPath, String key) {
    return using((arena) {
      final path = dbPath.toNativeUtf8(allocator: arena).cast<Char>();
      final hexKey = key.toNativeUtf8(allocator: arena).cast<Char>();
      final data = callNative(() => native.cc_wa_start(path, hexKey));
      return (
        paired: data['paired'] as bool,
        connected: data['connected'] as bool? ?? false,
        pushName: data['push_name'] as String? ?? '',
      );
    });
  }

  @override
  void resetWhatsApp(String dbPath) => using((arena) {
    final path = dbPath.toNativeUtf8(allocator: arena).cast<Char>();
    callNative(() => native.cc_wa_reset(path));
  });

  @override
  String chatPhone(String chat) => using((arena) {
    final jid = chat.toNativeUtf8(allocator: arena).cast<Char>();
    return callNative(() => native.cc_chat_phone(jid))['phone'] as String;
  });

  @override
  List<ChatMessage> searchMessages(String query, {int limit = 100}) =>
      using((arena) {
        final q = query.toNativeUtf8(allocator: arena).cast<Char>();
        final data = callNative(() => native.cc_messages_search(q, limit));
        return [
          for (final m in data['messages'] as List<Object?>)
            ChatMessage.fromJson(m as Map<String, Object?>),
        ];
      });

  @override
  String chatForPhone(String phone) => using((arena) {
    final p = phone.toNativeUtf8(allocator: arena).cast<Char>();
    return callNative(() => native.cc_chat_for_phone(p))['chat'] as String;
  });

  @override
  void downloadMedia(String chat, String id) => using((arena) {
    callNative(
      () => native.cc_media_download(
        chat.toNativeUtf8(allocator: arena).cast<Char>(),
        id.toNativeUtf8(allocator: arena).cast<Char>(),
      ),
    );
  });

  @override
  Uint8List mediaBytes(String chat, String id, String part) => using((arena) {
    final c = chat.toNativeUtf8(allocator: arena).cast<Char>();
    final i = id.toNativeUtf8(allocator: arena).cast<Char>();
    final p = part.toNativeUtf8(allocator: arena).cast<Char>();
    if (part == 'thumb') {
      final data = callNative(() => native.cc_media_get(c, i, p));
      return base64Decode(data['data'] as String);
    }
    // Media of any size come as bytes, not base64.
    final out = arena<Pointer<Uint8>>();
    final length = arena<Int64>();
    callNative(() => native.cc_media_read(c, i, p, out, length));
    try {
      return Uint8List.fromList(out.value.asTypedList(length.value));
    } finally {
      native.cc_bytes_free(out.value);
    }
  });

  @override
  Future<String> sealWithPin(String pin, String secretHex) => Isolate.run(
    () => _pinCall(native.cc_pin_seal, pin, secretHex, 'envelope'),
  );

  @override
  Future<String> openWithPin(String pin, String envelope) =>
      Isolate.run(() => _pinCall(native.cc_pin_open, pin, envelope, 'secret'));

  @override
  ConnectionReport connectionReport() =>
      ConnectionReport.fromJson(callNative(native.cc_connection_report));

  @override
  void requestPairingCode(String phone) {
    using((arena) {
      final number = phone.toNativeUtf8(allocator: arena).cast<Char>();
      callNative(() => native.cc_wa_pair_code(number));
    });
  }

  @override
  void logoutWhatsApp() {
    callNative(native.cc_wa_logout);
  }

  @override
  void stopWhatsApp() {
    callNative(native.cc_wa_stop);
  }

  @override
  List<ChatSummary> listChats({int limit = 200}) {
    final data = callNative(() => native.cc_chats_list(limit));
    return [
      for (final chat in data['chats'] as List<Object?>)
        ChatSummary.fromJson(chat as Map<String, Object?>),
    ];
  }

  @override
  List<ChatMessage> listMessages(
    String chat, {
    int beforeTs = 0,
    int limit = 50,
  }) {
    return using((arena) {
      final jid = chat.toNativeUtf8(allocator: arena).cast<Char>();
      final data = callNative(
        () => native.cc_messages_list(jid, beforeTs, limit),
      );
      return [
        for (final message in data['messages'] as List<Object?>)
          ChatMessage.fromJson(message as Map<String, Object?>),
      ];
    });
  }

  @override
  ChatMessage sendText(String chat, String text) => using((arena) {
    final data = callNative(
      () => native.cc_messages_send(
        chat.toNativeUtf8(allocator: arena).cast<Char>(),
        text.toNativeUtf8(allocator: arena).cast<Char>(),
      ),
    );
    return ChatMessage.fromJson(data['message'] as Map<String, Object?>);
  });

  @override
  ChatMessage sendMedia(String chat, OutgoingMedia media) => using((arena) {
    final c = chat.toNativeUtf8(allocator: arena).cast<Char>();
    final meta = jsonEncode({
      'kind': media.kind,
      'caption': media.caption,
      'file_name': media.fileName,
      'mime': media.mime,
      'seconds': media.seconds,
      'ptt': media.ptt,
      if (media.thumb case final thumb?) 'thumb': base64Encode(thumb),
    }).toNativeUtf8(allocator: arena).cast<Char>();
    // The bytes go as they are, not in base64.
    final data = arena<Uint8>(media.bytes.length);
    data.asTypedList(media.bytes.length).setAll(0, media.bytes);
    final result = callNative(
      () => native.cc_media_send(c, meta, data, media.bytes.length),
    );
    return ChatMessage.fromJson(result['message'] as Map<String, Object?>);
  });

  @override
  ChatMessage forwardMessage(String chat, String id, String to) =>
      using((arena) {
        final result = callNative(
          () => native.cc_messages_forward(
            chat.toNativeUtf8(allocator: arena).cast<Char>(),
            id.toNativeUtf8(allocator: arena).cast<Char>(),
            to.toNativeUtf8(allocator: arena).cast<Char>(),
          ),
        );
        return ChatMessage.fromJson(result['message'] as Map<String, Object?>);
      });

  @override
  void deleteChat(String chat, {bool forEveryone = false}) => using((arena) {
    callNative(
      () => native.cc_chats_delete(
        chat.toNativeUtf8(allocator: arena).cast<Char>(),
        forEveryone ? 1 : 0,
      ),
    );
  });

  @override
  void deleteMessage(String chat, String id, {required bool forEveryone}) =>
      using((arena) {
        callNative(
          () => native.cc_messages_delete(
            chat.toNativeUtf8(allocator: arena).cast<Char>(),
            id.toNativeUtf8(allocator: arena).cast<Char>(),
            forEveryone ? 1 : 0,
          ),
        );
      });

  @override
  void backupExport(int fd, BackupRequest request) => using((arena) {
    callNative(
      () => native.cc_backup_export(
        fd,
        jsonEncode(request.toJson())
            .toNativeUtf8(allocator: arena)
            .cast<Char>(),
      ),
    );
  });

  @override
  void backupOpen(
    int fd, {
    required String password,
    required String workDir,
    required int maxAppSchema,
  }) => using((arena) {
    final request = jsonEncode({
      'password': password,
      'work_dir': workDir,
      'max_app_schema': maxAppSchema,
    });
    callNative(
      () => native.cc_backup_open(
        fd,
        request.toNativeUtf8(allocator: arena).cast<Char>(),
      ),
    );
  });

  @override
  void backupCommit() => callNative(native.cc_backup_commit);

  @override
  void backupDiscard() => callNative(native.cc_backup_discard);

  @override
  void backupCancel() => callNative(native.cc_backup_cancel);

  @override
  ChatMessage retryMessage(String chat, String id) => using((arena) {
    final data = callNative(
      () => native.cc_messages_retry(
        chat.toNativeUtf8(allocator: arena).cast<Char>(),
        id.toNativeUtf8(allocator: arena).cast<Char>(),
      ),
    );
    return ChatMessage.fromJson(data['message'] as Map<String, Object?>);
  });

  @override
  void setWhatsAppDiagnostics(bool on) => native.cc_wa_diagnostics(on ? 1 : 0);

  @override
  void dispose() {
    final listener = _listener;
    if (listener != null) {
      // Unregister first: the core waits for deliveries in progress, so the
      // listener is never called after it is closed.
      native.cc_events_listen(nullptr);
      listener.close();
      _listener = null;
    }
    _events.close();
  }

  /// How many strings the core handed out that were not released yet.
  int get liveAllocations => native.cc_live_allocs();

  void _listen() {
    if (_listener != null) return;
    final listener = NativeCallable<Void Function(Pointer<Char>)>.listener(
      _onEvent,
    );
    _listener = listener;
    native.cc_events_listen(listener.nativeFunction);
  }

  void _onEvent(Pointer<Char> event) {
    try {
      _events.add(decodeEvent(event.cast<Utf8>().toDartString()));
    } on Object catch (error, stackTrace) {
      _events.addError(error, stackTrace);
    } finally {
      native.cc_free(event);
    }
  }
}

/// Runs a PIN function of the core (on the calling isolate) and returns
/// [field] of its answer.
String _pinCall(
  Pointer<Char> Function(Pointer<Char>, Pointer<Char>) function,
  String pin,
  String argument,
  String field,
) => using((arena) {
  final data = callNative(
    () => function(
      pin.toNativeUtf8(allocator: arena).cast<Char>(),
      argument.toNativeUtf8(allocator: arena).cast<Char>(),
    ),
  );
  return data[field] as String;
});

/// Calls a core function, always releases the returned envelope and decodes
/// it. Throws [CoreException] when the core reports an error.
@visibleForTesting
Map<String, Object?> callNative(Pointer<Char> Function() function) {
  final result = function();
  try {
    return decodeEnvelope(result.cast<Utf8>().toDartString());
  } finally {
    native.cc_free(result);
  }
}

/// Decodes a bridge envelope, returning its data or throwing
/// [CoreException].
@visibleForTesting
Map<String, Object?> decodeEnvelope(String json) {
  final envelope = jsonDecode(json) as Map<String, Object?>;
  final version = envelope['v'];
  if (version != bridgeProtocolVersion) {
    throw CoreException(
      'unsupported_protocol',
      'bridge protocol $version, app expects $bridgeProtocolVersion',
    );
  }
  if (envelope['ok'] == true) {
    return (envelope['data'] as Map<String, Object?>?) ?? const {};
  }
  final error = envelope['error'] as Map<String, Object?>;
  throw CoreException(error['code'] as String, error['message'] as String);
}

/// Decodes an event envelope pushed by the core.
@visibleForTesting
CoreEvent decodeEvent(String json) {
  final event = jsonDecode(json) as Map<String, Object?>;
  final version = event['v'];
  if (version != bridgeProtocolVersion) {
    throw CoreException(
      'unsupported_protocol',
      'bridge protocol $version, app expects $bridgeProtocolVersion',
    );
  }
  return CoreEvent(
    event['type'] as String,
    (event['data'] as Map<String, Object?>?) ?? const {},
  );
}
