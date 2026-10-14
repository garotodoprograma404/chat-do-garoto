import 'dart:async';
import 'dart:typed_data';

import '../core_bridge/core_bridge.dart';
import '../search/text.dart';

/// A one-to-one conversation of the demo: who, and what was said.
class DemoChat {
  const DemoChat(this.jid, this.name, this.lines);

  final String jid;
  final String name;

  /// Oldest first: (minutes ago, from me, text).
  final List<(int, bool, String)> lines;
}

/// The WhatsApp of the demo: conversations kept in memory, never
/// connected to anything. Sending works: my message goes "sent", "delivered"
/// and "read", and the contact answers a few seconds later with a canned
/// line, so the conversation looks alive.
class DemoCoreBridge implements CoreBridge {
  DemoCoreBridge({
    List<DemoChat> chats = demoChats,
    this._now = DateTime.now,
    this.replyAfter = const Duration(seconds: 3),
    this.statusStep = const Duration(milliseconds: 600),
  }) {
    final t = _now().millisecondsSinceEpoch;
    for (final c in chats) {
      _names[c.jid] = c.name;
      _messages[c.jid] = [
        for (final (i, (minutes, mine, text)) in c.lines.indexed)
          ChatMessage(
            chat: c.jid,
            id: '${c.jid}#$i',
            fromMe: mine,
            // In the group, the members take turns.
            senderName: mine
                ? ''
                : c.jid.endsWith('@g.us')
                ? _groupMembers[i % _groupMembers.length]
                : c.name,
            kind: 'text',
            text: text,
            ts: t - minutes * 60000,
            status: mine ? 'read' : '',
          ),
      ];
    }
  }

  final DateTime Function() _now;

  /// How long the contact takes to answer.
  final Duration replyAfter;

  /// The time between "sent", "delivered" and "read".
  final Duration statusStep;

  final _names = <String, String>{};
  final _messages = <String, List<ChatMessage>>{};
  final _media = <String, Uint8List>{};
  final _timers = <Timer>[];
  final _events = StreamController<CoreEvent>.broadcast();
  var _sent = 0;
  var _replies = 0;

  static const _groupMembers = ['Bruno Costa', 'Carla Mendes'];

  static const _answers = [
    'Opa! Vou ver aqui e já te falo ;)',
    'Fechado então, pode separar!',
    'Me manda o Pix que eu já confirmo.',
    'Kkkkk valeu, irmão!',
    'Funciona na minha máquina também. Brincadeira, chegou certinho!',
    'Show! Amanhã passo aí pra pegar.',
  ];

  void _push(String type, Map<String, Object?> data) {
    if (!_events.isClosed) _events.add(CoreEvent(type, data));
  }

  void _later(Duration after, void Function() run) =>
      _timers.add(Timer(after, run));

  static Map<String, Object?> _json(ChatMessage m) => {
    'chat': m.chat,
    'id': m.id,
    'from_me': m.fromMe,
    'sender_name': m.senderName,
    'kind': m.kind,
    'text': m.text,
    'ts': m.ts,
    'status': m.status,
    'media': m.media,
    'thumb': m.thumb,
    'file_name': m.fileName,
    'mime': m.mime,
    'size': m.size,
    'seconds': m.seconds,
    'ptt': m.ptt,
    'forwarded': m.forwarded,
  };

  void _setStatus(String chat, String id, String status) {
    final list = _messages[chat];
    if (list == null) return;
    final i = list.indexWhere((m) => m.id == id);
    if (i < 0) return;
    list[i] = list[i].withStatus(status);
    _push('wa_message_status', {'chat': chat, 'id': id, 'status': status});
  }

  /// Stores my [message] and plays the rest: statuses, then an answer.
  ChatMessage _send(ChatMessage message) {
    _messages.putIfAbsent(message.chat, () => []).add(message);
    final chat = message.chat, id = message.id;
    _later(statusStep, () => _setStatus(chat, id, 'sent'));
    _later(statusStep * 2, () => _setStatus(chat, id, 'delivered'));
    _later(statusStep * 3, () => _setStatus(chat, id, 'read'));
    if (!chat.endsWith('@g.us')) {
      _later(replyAfter, () {
        final answer = ChatMessage(
          chat: chat,
          id: 'reply${++_replies}',
          fromMe: false,
          senderName: _names[chat] ?? '',
          kind: 'text',
          text: _answers[(_replies - 1) % _answers.length],
          ts: _now().millisecondsSinceEpoch,
        );
        _messages[chat]!.add(answer);
        _push('wa_message', _json(answer));
      });
    }
    return message;
  }

  ChatMessage _mine(String chat, String kind, String text) => ChatMessage(
    chat: chat,
    id: 'demo${++_sent}',
    fromMe: true,
    senderName: '',
    kind: kind,
    text: text,
    ts: _now().millisecondsSinceEpoch,
    status: 'sending',
  );

  @override
  CoreVersion version() => const CoreVersion(core: 'demo', go: '-');

  @override
  String echo(String text) => text;

  @override
  Stream<CoreEvent> get events => _events.stream;

  @override
  void startTicker({
    required int count,
    Duration interval = Duration.zero,
    int workers = 1,
  }) {}

  @override
  void stopTicker() {}

  /// Always "connected": the demo never reaches WhatsApp.
  @override
  WhatsAppState startWhatsApp(String dbPath, String key) =>
      (paired: true, connected: true, pushName: 'Garoto do Programa');

  @override
  void resetWhatsApp(String dbPath) {}

  @override
  void requestPairingCode(String phone) {}

  @override
  void logoutWhatsApp() {}

  @override
  void stopWhatsApp() {}

  @override
  List<ChatSummary> listChats({int limit = 200}) {
    final list = [
      for (final MapEntry(key: jid, value: messages) in _messages.entries)
        if (messages.isNotEmpty)
          ChatSummary(
            jid: jid,
            name: _names[jid] ?? jid,
            lastText: messages.last.text,
            lastTs: messages.last.ts,
            lastFromMe: messages.last.fromMe,
          ),
    ]..sort((a, b) => b.lastTs.compareTo(a.lastTs));
    return list.take(limit).toList();
  }

  @override
  List<ChatMessage> listMessages(
    String chat, {
    int beforeTs = 0,
    int limit = 50,
  }) {
    final older = [
      for (final m in _messages[chat] ?? const <ChatMessage>[])
        if (beforeTs == 0 || m.ts < beforeTs) m,
    ];
    return older.length <= limit ? older : older.sublist(older.length - limit);
  }

  @override
  ChatMessage sendText(String chat, String text) {
    if (text.trim().isEmpty) {
      throw const CoreException('invalid_argument', 'empty text');
    }
    return _send(_mine(chat, 'text', text));
  }

  @override
  ChatMessage retryMessage(String chat, String id) {
    final message = _messages[chat]!.firstWhere((m) => m.id == id);
    _setStatus(chat, id, 'sending');
    _later(statusStep, () => _setStatus(chat, id, 'sent'));
    return message.withStatus('sending');
  }

  @override
  ChatMessage sendMedia(String chat, OutgoingMedia media) {
    final m = ChatMessage(
      chat: chat,
      id: 'demo${++_sent}',
      fromMe: true,
      senderName: '',
      kind: media.kind,
      text: media.caption,
      ts: _now().millisecondsSinceEpoch,
      status: 'sending',
      media: 'downloaded',
      thumb: media.kind == 'image',
      fileName: media.fileName,
      mime: media.mime,
      size: media.bytes.length,
      seconds: media.seconds,
      ptt: media.ptt,
    );
    _media['$chat|${m.id}|full'] = media.bytes;
    if (media.kind == 'image') _media['$chat|${m.id}|thumb'] = media.bytes;
    return _send(m);
  }

  @override
  ChatMessage forwardMessage(String chat, String id, String to) {
    final src = _messages[chat]!.firstWhere((m) => m.id == id);
    final copy = ChatMessage(
      chat: to,
      id: 'demo${++_sent}',
      fromMe: true,
      senderName: '',
      kind: src.kind,
      text: src.text,
      ts: _now().millisecondsSinceEpoch,
      status: 'sending',
      media: src.media,
      forwarded: true,
    );
    for (final part in ['full', 'thumb']) {
      if (_media['$chat|$id|$part'] case final bytes?) {
        _media['$to|${copy.id}|$part'] = bytes;
      }
    }
    return _send(copy);
  }

  @override
  void deleteChat(String chat, {bool forEveryone = false}) {
    _messages.remove(chat);
    _push('wa_deleted', {'chat': chat, 'scope': 'chat'});
    if (forEveryone) _push('wa_revoke_done', {'revoked': 0, 'failed': 0});
  }

  @override
  void deleteMessage(String chat, String id, {required bool forEveryone}) {
    final list = _messages[chat];
    if (list == null) return;
    final i = list.indexWhere((m) => m.id == id);
    if (i < 0) return;
    if (!forEveryone) {
      list.removeAt(i);
      _push('wa_deleted', {'chat': chat, 'scope': 'message', 'id': id});
      return;
    }
    final m = list[i];
    final revoked = ChatMessage(
      chat: chat,
      id: id,
      fromMe: m.fromMe,
      senderName: m.senderName,
      kind: 'revoked',
      text: '',
      ts: m.ts,
      status: m.status,
    );
    list[i] = revoked;
    _push('wa_deleted', {
      'chat': chat,
      'scope': 'revoked',
      'id': id,
      'message': _json(revoked),
    });
  }

  static const _noBackup = CoreException(
    'demo',
    'O backup não funciona na demonstração.',
  );

  @override
  void backupExport(int fd, BackupRequest request) => throw _noBackup;

  @override
  void backupOpen(
    int fd, {
    required String password,
    required String workDir,
    required int maxAppSchema,
  }) => throw _noBackup;

  @override
  void backupCommit() => throw _noBackup;

  @override
  void backupDiscard() {}

  @override
  void backupCancel() {}

  @override
  ConnectionReport connectionReport() {
    final now = _now().millisecondsSinceEpoch;
    const day = 24 * 3600 * 1000;
    return ConnectionReport(
      since: now - 7 * day,
      totalMs: 7 * day,
      connectedMs: 7 * day,
      drops: 0,
      longestMs: 0,
    );
  }

  @override
  String chatPhone(String chat) =>
      chat.endsWith('@s.whatsapp.net') ? chat.split('@').first : '';

  @override
  List<ChatMessage> searchMessages(String query, {int limit = 100}) {
    final found = [
      for (final list in _messages.values)
        for (final m in list)
          if (m.kind == 'text' && textMatches(m.text, query)) m,
    ]..sort((a, b) => b.ts.compareTo(a.ts));
    return found.take(limit).toList();
  }

  @override
  String chatForPhone(String phone) {
    final jid = '$phone@s.whatsapp.net';
    return _messages.containsKey(jid) ? jid : '';
  }

  @override
  void downloadMedia(String chat, String id) {}

  @override
  Uint8List mediaBytes(String chat, String id, String part) =>
      _media['$chat|$id|$part'] ??
      (throw const CoreException('invalid_argument', 'not stored'));

  /// The demo has no PIN: nothing to seal.
  @override
  Future<String> sealWithPin(String pin, String secretHex) async => secretHex;

  @override
  Future<String> openWithPin(String pin, String envelope) async => envelope;

  @override
  void setWhatsAppDiagnostics(bool on) {}

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _events.close();
  }
}

/// The demo's conversations: invented people and a store of dev gear, in
/// the channel's tone. The phones follow the 5511900000xxx pattern, which
/// belongs to nobody.
const demoChats = [
  DemoChat('5511900000101@s.whatsapp.net', 'Ana Paula', [
    (180, false, 'Oi! A camiseta "Funciona na minha máquina" ainda tem no M?'),
    (178, true, 'Tem sim! Preta ou branca?'),
    (170, false, 'Preta. E a caneca do git push --force, quanto tá?'),
    (168, true, 'Caneca sai R\$ 39,90. Levando as duas faço R\$ 109,90.'),
    (12, false, 'Fechado! Pode separar as duas que eu passo aí amanhã.'),
  ]),
  DemoChat('5511900000102@s.whatsapp.net', 'Bruno Costa', [
    (
      3000,
      true,
      'Bruno, tudo certo? Passando pra lembrar da parcela do moletom.',
    ),
    (2990, false, 'Opa, foi mal! Pago sexta sem falta.'),
    (
      95,
      false,
      'Garoto, consegue segurar até segunda? Deploy de sexta deu ruim aqui kkk',
    ),
  ]),
  DemoChat('5511900000103@s.whatsapp.net', 'Carla Mendes', [
    (
      1500,
      false,
      'Bom dia! Vocês fazem consultoria pra quem tá começando em programação?',
    ),
    (
      1490,
      true,
      'Fazemos sim! Uma hora por chamada, a gente monta o plano de estudo junto.',
    ),
    (1480, false, 'Perfeito. Quero marcar a primeira.'),
    (1470, true, 'Marcado pra quinta, 19h ;)'),
  ]),
  DemoChat('5511900000104@s.whatsapp.net', 'Diego Rocha', [
    (40, false, 'Chegou o kit de adesivos! Ficou top no notebook'),
    (38, true, 'Boa demais! Manda foto depois que eu reposto ;)'),
  ]),
  DemoChat('5511900000105@s.whatsapp.net', 'Elisa Prado', [
    (
      6000,
      true,
      'Elisa, seu pedido saiu hoje. Código de rastreio: AB123456789BR',
    ),
    (5990, false, 'Obrigada!!'),
    (300, false, 'Tem o mousepad do Ctrl+C Ctrl+V de volta no estoque?'),
  ]),
  DemoChat('5511900000199@s.whatsapp.net', '+55 11 90000-0199', [
    (
      25,
      false,
      'Oi, vi o vídeo do Garoto no TikTok. Vocês entregam em Campinas?',
    ),
  ]),
  DemoChat('120363000000000001@g.us', 'Turma da Lógica', [
    (900, false, 'Alguém entendeu o teste de mesa da aula de ontem?'),
    (
      890,
      true,
      'Pensa comigo: lê linha por linha, igual o computador. Sem pular.',
    ),
    (880, false, 'Agora fez sentido!'),
  ]),
];
