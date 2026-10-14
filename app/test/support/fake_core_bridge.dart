import 'dart:async';
import 'dart:typed_data';

import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';

/// In-memory [CoreBridge] for widget and controller tests. Records calls and
/// lets tests push core events.
class FakeCoreBridge implements CoreBridge {
  FakeCoreBridge({this.echoFails = false, this.paired = false});

  final bool echoFails;

  /// What [startWhatsApp] reports.
  bool paired;

  /// Whether [startWhatsApp] finds the connection already up.
  bool connected = false;

  /// What [connectionReport] returns.
  ConnectionReport report = const ConnectionReport(
    since: 0,
    totalMs: 0,
    connectedMs: 0,
    drops: 0,
    longestMs: 0,
  );

  /// When set, [requestPairingCode] throws it.
  CoreException? pairingCodeError;

  final calls = <String>[];
  final _events = StreamController<CoreEvent>.broadcast(sync: true);
  bool tickerRunning = false;

  /// Pushes an event, as the core would.
  void push(String type, [Map<String, Object?> data = const {}]) =>
      _events.add(CoreEvent(type, data));

  /// Pushes a "tick" event.
  void pushTick(int n) => push('tick', {'worker': 1, 'n': n});

  @override
  CoreVersion version() => const CoreVersion(core: '9.9.9', go: 'go1.99');

  @override
  String echo(String text) {
    if (echoFails) {
      throw const CoreException('invalid_argument', 'text is null');
    }
    return text;
  }

  @override
  Stream<CoreEvent> get events => _events.stream;

  @override
  void startTicker({
    required int count,
    Duration interval = Duration.zero,
    int workers = 1,
  }) => tickerRunning = true;

  @override
  void stopTicker() => tickerRunning = false;

  @override
  WhatsAppState startWhatsApp(String dbPath, String key) {
    calls.add('startWhatsApp');
    lastKey = key;
    if (unreadable) {
      throw const CoreException('unreadable', 'the key does not open it');
    }
    return (paired: paired, connected: connected, pushName: '');
  }

  /// The key the last [startWhatsApp] received.
  String? lastKey;

  /// When true, [startWhatsApp] answers "unreadable" until [resetWhatsApp].
  bool unreadable = false;

  @override
  void resetWhatsApp(String dbPath) {
    calls.add('resetWhatsApp');
    unreadable = false;
    paired = false; // the session is gone
  }

  @override
  ConnectionReport connectionReport() {
    calls.add('connectionReport');
    return report;
  }

  @override
  void requestPairingCode(String phone) {
    calls.add('requestPairingCode');
    if (pairingCodeError case final error?) throw error;
  }

  @override
  void logoutWhatsApp() => calls.add('logoutWhatsApp');

  @override
  void stopWhatsApp() => calls.add('stopWhatsApp');

  /// What [listChats] returns.
  List<ChatSummary> chats = [];

  /// What [listMessages] returns, per chat.
  Map<String, List<ChatMessage>> messages = {};

  @override
  List<ChatSummary> listChats({int limit = 200}) {
    calls.add('listChats');
    return chats;
  }

  @override
  List<ChatMessage> listMessages(
    String chat, {
    int beforeTs = 0,
    int limit = 50,
  }) {
    calls.add('listMessages:$chat');
    return messages[chat] ?? [];
  }

  /// When set, [sendText] throws it.
  CoreException? sendError;
  var _sent = 0;

  @override
  ChatMessage sendText(String chat, String text) {
    calls.add('sendText:$chat');
    if (sendError case final error?) throw error;
    return ChatMessage(
      chat: chat,
      id: 'sent${++_sent}',
      fromMe: true,
      senderName: '',
      kind: 'text',
      text: text,
      ts: 1000000 + _sent,
      status: 'sending',
    );
  }

  @override
  ChatMessage forwardMessage(String chat, String id, String to) {
    calls.add('forward:$id:$to');
    if (sendError case final error?) throw error;
    final src = messages[chat]!.firstWhere((m) => m.id == id);
    return ChatMessage(
      chat: to,
      id: 'sent${++_sent}',
      fromMe: true,
      senderName: '',
      kind: src.kind,
      text: src.text,
      ts: 1000000 + _sent,
      status: 'sending',
      media: src.media,
      forwarded: true,
    );
  }

  /// Error thrown by the deletions.
  CoreException? deleteError;

  @override
  void deleteChat(String chat, {bool forEveryone = false}) {
    calls.add('deleteChat:$chat${forEveryone ? ':everyone' : ''}');
    if (deleteError case final error?) throw error;
  }

  @override
  void deleteMessage(String chat, String id, {required bool forEveryone}) {
    calls.add('deleteMessage:$id:${forEveryone ? 'everyone' : 'me'}');
    if (deleteError case final error?) throw error;
  }

  /// What [backupExport] received.
  BackupRequest? backupRequest;

  /// Error thrown by the backup calls.
  CoreException? backupError;

  @override
  void backupExport(int fd, BackupRequest request) {
    calls.add('backupExport:$fd:${request.media ? 'media' : 'no-media'}');
    if (backupError case final error?) throw error;
    backupRequest = request;
  }

  @override
  void backupOpen(
    int fd, {
    required String password,
    required String workDir,
    required int maxAppSchema,
  }) {
    calls.add('backupOpen:$fd:$maxAppSchema');
    if (backupError case final error?) throw error;
  }

  @override
  void backupCommit() {
    calls.add('backupCommit');
    if (backupError case final error?) throw error;
  }

  @override
  void backupDiscard() => calls.add('backupDiscard');

  @override
  void backupCancel() => calls.add('backupCancel');

  /// What [sendMedia] received.
  final sentMedia = <OutgoingMedia>[];

  @override
  ChatMessage sendMedia(String chat, OutgoingMedia media) {
    calls.add('sendMedia:${media.kind}');
    if (sendError case final error?) throw error;
    sentMedia.add(media);
    return ChatMessage(
      chat: chat,
      id: 'sent${++_sent}',
      fromMe: true,
      senderName: '',
      kind: media.kind,
      text: media.caption,
      ts: 1000000 + _sent,
      status: 'sending',
      media: 'downloaded',
      fileName: media.fileName,
      mime: media.mime,
      size: media.bytes.length,
      seconds: media.seconds,
      ptt: media.ptt,
    );
  }

  @override
  ChatMessage retryMessage(String chat, String id) {
    calls.add('retryMessage:$id');
    final message = messages[chat]?.firstWhere((m) => m.id == id);
    return (message ??
            ChatMessage(
              chat: chat,
              id: id,
              fromMe: true,
              senderName: '',
              kind: 'text',
              text: '',
              ts: 0,
            ))
        .withStatus('sending');
  }

  /// Stored photo parts, by "chat|id|part".
  final mediaParts = <String, Uint8List>{};

  /// What [chatPhone] answers, per chat.
  final phones = <String, String>{};

  @override
  String chatPhone(String chat) => phones[chat] ?? '';

  /// Searchable messages: [searchMessages] matches their text, folded.
  final searchable = <ChatMessage>[];

  @override
  List<ChatMessage> searchMessages(String query, {int limit = 100}) {
    calls.add('searchMessages:$query');
    final words = query.toLowerCase().split(' ').where((w) => w.isNotEmpty);
    return [
      for (final m in searchable.reversed)
        if (words.every(m.text.toLowerCase().contains)) m,
    ];
  }

  /// What [chatForPhone] answers, per phone.
  final chatsByPhone = <String, String>{};

  /// Like the core: the phone's own chat when stored, else [chatsByPhone].
  @override
  String chatForPhone(String phone) =>
      chatsByPhone[phone] ??
      (chats.any((c) => c.jid == '$phone@s.whatsapp.net')
          ? '$phone@s.whatsapp.net'
          : '');

  @override
  void downloadMedia(String chat, String id) => calls.add('downloadMedia:$id');

  @override
  Uint8List mediaBytes(String chat, String id, String part) {
    calls.add('mediaBytes:$id:$part');
    return mediaParts['$chat|$id|$part'] ??
        (throw const CoreException('invalid_argument', 'not in the vault'));
  }

  /// A fast stand-in for the real envelope: "pin|secret" reversed.
  @override
  Future<String> sealWithPin(String pin, String secretHex) async {
    calls.add('sealWithPin');
    return '$pin|$secretHex'.split('').reversed.join();
  }

  @override
  Future<String> openWithPin(String pin, String envelope) async {
    calls.add('openWithPin');
    final [sealedPin, secret] = envelope.split('').reversed.join().split('|');
    if (sealedPin != pin) {
      throw const CoreException('wrong_pin', 'the PIN does not open it');
    }
    return secret;
  }

  @override
  void setWhatsAppDiagnostics(bool on) => calls.add('diagnostics:$on');

  @override
  void dispose() => _events.close();
}
