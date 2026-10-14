import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:material_symbols_icons/symbols.dart';

import '../clients/client_form_screen.dart';
import '../clients/client_picker_screen.dart';
import '../clients/client_screen.dart';
import '../clients/clients_repository.dart';
import '../core_bridge/core_bridge.dart';
import '../home/crm_scope.dart';
import '../sales/charge_message.dart';
import '../sales/receive_dialog.dart';
import '../sales/sale_form_screen.dart';
import '../sales/sales_screen.dart' show SaleContext;
import '../theme/components.dart';
import '../theme/motion.dart';
import 'chat_clients.dart';
import 'chat_filters.dart';
import 'chat_notes.dart';
import 'chat_prefs.dart';
import 'chats_controller.dart';
import 'chats_screen.dart';
import 'client_panel.dart';
import 'contact_screen.dart';
import 'media/forward_screen.dart';
import 'media/media_picker.dart';
import 'media/media_platform.dart';
import 'media/media_tiles.dart';
import 'media/send_preview_screen.dart';
import 'media/voice_button.dart';
import 'new_contact_strip.dart';
import 'quick_replies.dart';
import '../settings/quick_replies_screen.dart';
import 'photo_screen.dart';

/// One conversation: read and reply with text.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.bridge,
    required this.chat,
    this.clients,
    this.focus,
    this.draft,
    this.clock,
  });

  final CoreBridge bridge;
  final ChatSummary chat;

  /// A message found by a search: the conversation opens on it.
  final ChatMessage? focus;

  /// Text already in the message box, such as a sale summary. It is only sent when the user taps "Enviar".
  final String? draft;

  /// The CRM, for the client panel and the "contato novo" strip (specs
  /// 012 and 022); null while app.db is not open.
  final ClientsRepository? clients;

  /// "Now", for the panel's numbers (tests).
  final DateTime Function()? clock;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final _controller = ChatController(
    bridge: widget.bridge,
    chat: widget.chat,
    focus: widget.focus,
  )..start();

  late final _text = TextEditingController(text: widget.draft ?? '');
  late final _audio = AudioPlayback(bridge: widget.bridge);

  /// With the box empty, the send button is the microphone.
  bool _empty = true;
  bool _canRecord = false;
  ({int seconds, bool canceling})? _recording;

  @override
  void initState() {
    super.initState();
    _empty = _text.text.trim().isEmpty;
    _text.addListener(() {
      final empty = _text.text.trim().isEmpty;
      if (empty != _empty) setState(() => _empty = empty);
      final query = quickReplyQuery(_text.text);
      if (query != _replyQuery) {
        setState(() => _replyQuery = query);
        if (query != null && _replies == null) _loadReplies();
      }
    });
    _controller.onDeleteFailed = () =>
        _say('Não foi possível apagar para todos.');
    _controller.addListener(_closeWhenDeleted);
    mediaPlatform.canRecord().then((ok) {
      if (mounted) setState(() => _canRecord = ok);
    }, onError: (_) {});
  }

  bool get _isGroup => widget.chat.jid.endsWith('@g.us');

  // The client of this conversation: the panel, the title and
  // the "contato novo" strip.
  CrmScope? _crm;
  Client? _client;
  bool _clientLoaded = false;
  bool _ignored = false;

  /// The client's notes, oldest first, shown among the messages.
  List<ClientNote> _notes = const [];

  /// Writing an internal note instead of a message: until the button
  /// is tapped again or the conversation is left.
  bool _noteMode = false;

  /// Notes just written: they come in like a new message.
  final _freshNotes = <int>{};

  /// What follows the "/" that starts the box, or null.
  String? _replyQuery;
  List<QuickReply>? _replies;

  Future<void> _loadReplies() async {
    final replies = await _crm?.chatPrefs?.quickReplies() ?? const [];
    if (mounted) setState(() => _replies = replies);
  }

  /// A quick reply tapped: its text, with the name, replaces the "/…";
  /// nothing is sent.
  void _useReply(QuickReply reply) {
    final text = fillName(reply.text, _client?.name ?? widget.chat.name);
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _manageReplies() async {
    final prefs = _crm?.chatPrefs;
    if (prefs == null) return;
    await _push(QuickRepliesScreen(prefs: prefs));
    await _loadReplies();
  }

  /// The phone behind the chat; "" when WhatsApp did not tell it.
  late final String _phone = () {
    if (_isGroup) return '';
    try {
      return widget.bridge.chatPhone(widget.chat.jid);
    } on CoreException {
      return '';
    }
  }();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final first = _crm == null;
    _crm = CrmScope.maybeOf(context);
    if (first) _loadClient();
  }

  Future<void> _loadClient() async {
    final repo = widget.clients;
    if (repo == null || !isPersonChat(widget.chat.jid)) return;
    final client = await findChatClient(repo, widget.bridge, widget.chat.jid);
    final ignored = await _crm?.chatPrefs?.ignored() ?? const <String>{};
    final notes = client?.id == null
        ? const <ClientNote>[]
        : (await repo.notes(client!.id!)).reversed.toList();
    if (!mounted) return;
    setState(() {
      _client = client;
      _notes = notes;
      _ignored = ignored.contains(widget.chat.jid);
      _clientLoaded = true;
      if (client == null) _noteMode = false;
    });
  }

  // The merged lines, recomputed only when the messages or the notes
  // change, never while scrolling.
  List<ChatEntry> _entries = const [];
  List<ChatMessage>? _mergedMessages;
  List<ClientNote>? _mergedNotes;

  List<ChatEntry> _entriesOf(List<ChatMessage> messages) {
    if (!identical(messages, _mergedMessages) ||
        !identical(_notes, _mergedNotes)) {
      _mergedMessages = messages;
      _mergedNotes = _notes;
      _entries = mergeNotes(messages, _notes, hasOlder: _controller.hasOlder);
    }
    return _entries;
  }

  /// The note button: switches between message and note, or explains that
  /// notes need a client.
  Future<void> _toggleNote() async {
    if (_client != null) {
      setState(() => _noteMode = !_noteMode);
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nota interna'),
        content: const Text(
          'As notas ficam na ficha do cliente e só você vê. Cadastre ou '
          'vincule este contato a um cliente para anotar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Agora não'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'link'),
            child: const Text('Vincular'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'register'),
            child: const Text('Cadastrar'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'register') await _register();
    if (choice == 'link') await _link();
  }

  /// "Anotar": saves the text as a note of the client. Nothing goes to
  /// WhatsApp: this never touches the conversation's controller.
  Future<void> _addNote() async {
    final text = _text.text.trim();
    final id = _client?.id;
    final repo = widget.clients;
    if (text.isEmpty || id == null || repo == null) return;
    await repo.addNote(id, text);
    final notes = (await repo.notes(id)).reversed.toList();
    if (!mounted) return;
    _text.clear();
    setState(() {
      if (notes.isNotEmpty) _freshNotes.add(notes.last.id);
      _notes = notes;
    });
  }

  /// Hold a note: "Apagar nota", with a confirmation.
  Future<void> _noteMenu(ClientNote note) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListTile(
          leading: const Icon(Symbols.delete_rounded),
          title: const Text('Apagar nota'),
          onTap: () => Navigator.pop(context, 'delete'),
        ),
      ),
    );
    if (action != 'delete' || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar esta nota?'),
        content: const Text('Ela some da conversa e da ficha do cliente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.clients?.deleteNote(note.id);
    setState(
      () => _notes = [
        for (final n in _notes)
          if (n.id != note.id) n,
      ],
    );
  }

  bool get _showStrip =>
      _clientLoaded && _client == null && !_ignored && widget.clients != null;

  /// The name tapped: the client panel for one person, the contact screen
  /// for groups or without the CRM.
  Future<void> _openPanel() async {
    final repo = widget.clients;
    if (repo == null || !isPersonChat(widget.chat.jid)) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ContactScreen(bridge: widget.bridge, chat: widget.chat),
        ),
      );
      return;
    }
    final crm = _crm;
    final action = await showClientPanel(
      context,
      title: chatTitle(widget.chat),
      phone: _phone,
      client: _client,
      repo: repo,
      sales: crm?.sales,
      canSell: crm?.sales != null && crm?.products != null,
      clock: widget.clock,
    );
    if (!mounted) return;
    switch (action) {
      case PanelAction.register:
        await _register();
      case PanelAction.link:
        await _link();
      case PanelAction.openFile:
        await _push(
          ClientScreen(repo: repo, id: _client!.id!, bridge: widget.bridge),
        );
        await _loadClient();
      case PanelAction.newSale:
        await _push(
          SaleFormScreen(
            ctx: SaleContext(
              sales: crm!.sales!,
              products: crm.products,
              clients: repo,
              bridge: widget.bridge,
              clock: widget.clock,
            ),
            client: _client,
          ),
        );
      case PanelAction.receive:
        final ok = await receiveFromClient(
          context,
          sales: crm!.sales!,
          clientId: _client!.id!,
          today: _now,
        );
        if (ok && mounted) _say('Recebimento registrado.');
      case PanelAction.charge:
        await _charge();
      case null:
        break;
    }
  }

  DateTime get _now => (widget.clock ?? DateTime.now)();

  /// "Cobrar" in the conversation: the ready text in the message box, in
  /// message mode; sending stays with the user.
  Future<void> _charge() async {
    final client = _client;
    final sales = _crm?.sales;
    if (client?.id == null || sales == null) return;
    final text = chargeMessage(
      name: client!.name,
      sales: await sales.byClient(client.id!),
      today: _now,
    );
    if (text == null || !mounted) return;
    setState(() => _noteMode = false);
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<T?> _push<T>(Widget screen) =>
      Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => screen));

  /// "Cadastrar": the form with name and phone, linked to this chat.
  Future<void> _register() async {
    await _push<int>(
      ClientFormScreen(
        repo: widget.clients!,
        initial: Client(
          name: chatTitle(widget.chat),
          phone: _phone,
          chatJid: widget.chat.jid,
        ),
      ),
    );
    await _loadClient();
  }

  /// "Vincular": pick a client and link this chat to them, asking first
  /// when they are linked to another chat.
  Future<void> _link() async {
    final repo = widget.clients!;
    final picked = await _push<Client>(ClientPickerScreen(repo: repo));
    if (picked == null || !mounted) return;
    if (picked.chatJid case final other? when other != widget.chat.jid) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Trocar a conversa?'),
          content: Text(
            '${picked.name} já está ligado a outra conversa do WhatsApp. '
            'Ligar a esta no lugar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ligar a esta'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await repo.save(picked.linkedTo(widget.chat.jid));
    await _loadClient();
  }

  /// "Ignorar": hides the strip here and in "Novos contatos".
  Future<void> _ignore({bool ignored = true}) async {
    setState(() => _ignored = ignored);
    await _crm?.chatPrefs?.setIgnored(widget.chat.jid, ignored: ignored);
    if (!ignored || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      aboveComposer(
        'Contato ignorado.',
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () => _ignore(ignored: false),
        ),
      ),
    );
  }

  bool _closed = false;

  /// The chat was deleted, here or on the phone: back to the
  /// list.
  void _closeWhenDeleted() {
    if (!_controller.deleted || _closed || !mounted) return;
    _closed = true;
    Navigator.of(context).maybePop();
  }

  Future<void> _deleteChat() async {
    final everyone = await confirmDeleteChat(
      context,
      mine: _controller.messages
          .where((m) => canRevoke(m, DateTime.now()))
          .length
          .clamp(0, maxRevokeOnDelete),
    );
    if (everyone == null || !mounted) return;
    try {
      _controller.deleteChat(forEveryone: everyone);
    } on CoreException catch (e) {
      _say(deleteChatError(e));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _audio.dispose();
    _text.dispose();
    super.dispose();
  }

  void _send() {
    try {
      if (_controller.send(_text.text)) _text.clear();
    } on CoreException {
      _say('Não foi possível enviar.');
    }
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(aboveComposer(text));

  /// Sends a media; the limits are the app's.
  void _sendMedia(OutgoingMedia media) {
    try {
      _controller.sendMedia(media);
    } on CoreException catch (e) {
      _say(
        e.code == 'too_big'
            ? 'Arquivo grande demais para enviar.'
            : 'Não foi possível enviar.',
      );
    }
  }

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (key, icon, label) in const [
              ('gallery-photo', Symbols.photo_rounded, 'Foto da galeria'),
              (
                'gallery-video',
                Symbols.video_library_rounded,
                'Vídeo da galeria',
              ),
              ('camera-photo', Symbols.photo_camera_rounded, 'Tirar foto'),
              ('camera-video', Symbols.videocam_rounded, 'Gravar vídeo'),
              ('document', Symbols.description_rounded, 'Documento'),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                onTap: () => Navigator.pop(context, key),
              ),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'gallery-photo' || 'camera-photo':
        await _sendPhoto(camera: choice == 'camera-photo');
      case 'gallery-video' || 'camera-video':
        await _sendVideo(camera: choice == 'camera-video');
      case 'document':
        await _sendDocument();
    }
  }

  Future<String?> _preview({
    required bool video,
    Uint8List? image,
    int seconds = 0,
  }) => Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) =>
          SendPreviewScreen(video: video, image: image, seconds: seconds),
    ),
  );

  Future<void> _sendPhoto({required bool camera}) async {
    final bytes = await chatMediaPicker?.photo(camera: camera);
    if (bytes == null || !mounted) return;
    if (bytes.length > 16 * 1024 * 1024) {
      _say('Fotos até 16 MB.');
      return;
    }
    final caption = await _preview(video: false, image: bytes);
    if (caption == null || !mounted) return;
    _sendMedia(OutgoingMedia(kind: 'image', bytes: bytes, caption: caption));
  }

  Future<void> _sendVideo({required bool camera}) async {
    PreparedVideo? video;
    try {
      video = await chatMediaPicker?.video(camera: camera);
    } on MediaException catch (e) {
      _say(
        e.code == 'too_big'
            ? 'Vídeos até 64 MB.'
            : 'Não foi possível preparar o vídeo.',
      );
      return;
    }
    if (video == null || !mounted) return;
    if (!video.stripped &&
        !await _confirm(
          'Enviar com a localização?',
          'Não foi possível tirar a localização gravada no vídeo. Enviar mesmo '
              'assim?',
        )) {
      return;
    }
    final seconds = (video.ms / 1000).round();
    final caption = await _preview(
      video: true,
      image: video.thumb,
      seconds: seconds,
    );
    if (caption == null || !mounted) return;
    _sendMedia(
      OutgoingMedia(
        kind: 'video',
        bytes: video.bytes,
        caption: caption,
        mime: 'video/mp4',
        seconds: seconds,
        thumb: video.thumb,
      ),
    );
  }

  Future<void> _sendDocument() async {
    PickedDocument? doc;
    try {
      doc = await chatMediaPicker?.document();
    } on MediaException catch (e) {
      _say(
        e.code == 'too_big'
            ? 'Documentos até 100 MB.'
            : 'Não foi possível ler o documento.',
      );
      return;
    }
    if (doc == null || !mounted) return;
    if (!await _confirm(
      'Enviar documento?',
      '${doc.name} (${formatSize(doc.bytes.length)})',
    )) {
      return;
    }
    _sendMedia(
      OutgoingMedia(
        kind: 'document',
        bytes: doc.bytes,
        fileName: doc.name,
        mime: doc.mime,
      ),
    );
  }

  void _sendVoice(VoiceMessage voice) => _sendMedia(
    OutgoingMedia(
      kind: 'audio',
      bytes: voice.recording.bytes,
      mime: 'audio/ogg; codecs=opus',
      seconds: voice.seconds,
      ptt: true,
    ),
  );

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  static const _forwardable = {'text', 'image', 'video', 'audio', 'document'};

  Future<void> _messageMenu(ChatMessage message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_forwardable.contains(message.kind))
              ListTile(
                leading: const Icon(Symbols.shortcut_rounded),
                title: const Text('Encaminhar'),
                onTap: () => Navigator.pop(context, 'forward'),
              ),
            ListTile(
              leading: const Icon(Symbols.delete_rounded),
              title: const Text('Apagar'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'delete') return _deleteMessage(message);
    if (action != 'forward') return;
    final to = await Navigator.of(context).push<ChatSummary>(
      MaterialPageRoute(builder: (_) => ForwardScreen(bridge: widget.bridge)),
    );
    if (to == null || !mounted) return;
    try {
      widget.bridge.forwardMessage(message.chat, message.id, to.jid);
      _say('Encaminhada para ${chatTitle(to)}.');
    } on CoreException {
      _say('Não foi possível encaminhar.');
    }
  }

  /// "Apagar para todos" (my recent messages) or "Apagar para mim", as in
  /// WhatsApp.
  Future<void> _deleteMessage(ChatMessage message) async {
    final everyone = canRevoke(message, DateTime.now());
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar mensagem?'),
        actions: [
          if (everyone)
            TextButton(
              onPressed: () => Navigator.pop(context, 'everyone'),
              child: const Text('Apagar para todos'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'me'),
            child: const Text('Apagar para mim'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    try {
      _controller.deleteMessage(message.id, forEveryone: choice == 'everyone');
    } on CoreException catch (e) {
      _say(
        e.code == 'offline'
            ? 'Sem conexão. Apagar para todos precisa de internet.'
            : 'Não foi possível apagar.',
      );
    }
  }

  void _retry(String id) {
    try {
      _controller.retry(id);
    } on CoreException {
      _say('Não foi possível tentar de novo.');
    }
  }

  /// The media part of a bubble.
  Widget? _mediaOf(ChatMessage m) {
    if (m.media.isEmpty) return null;
    final bridge = widget.bridge;
    return switch (m.kind) {
      'image' => _Photo(bridge: bridge, message: m),
      'audio' => AudioTile(playback: _audio, message: m),
      'video' => VideoTile(
        bridge: bridge,
        message: m,
        thumb: thumbOf(bridge, m),
      ),
      'document' => DocumentTile(bridge: bridge, message: m),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Tap the name for the client panel, as "Dados do contato" in
        // WhatsApp.
        title: GestureDetector(
          onTap: _openPanel,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _client?.name ?? chatTitle(widget.chat),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_client != null) ...[
                const SizedBox(width: 8),
                const ClientMark(),
              ],
            ],
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            onSelected: (_) => _deleteChat(),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete', child: Text('Excluir conversa')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showStrip)
            NewContactStrip(
              onRegister: _register,
              onLink: _link,
              onIgnore: _ignore,
            ),
          Expanded(
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final entries = _entriesOf(_controller.messages);
                // Newest at the bottom: the list is reversed so it starts there.
                return ListView.builder(
                  reverse: true,
                  // A screen of messages built ahead while idle: a fast
                  // fling starts with them ready.
                  scrollCacheExtent: const ScrollCacheExtent.viewport(1),
                  padding: const EdgeInsets.all(8),
                  itemCount: entries.length + (_controller.hasOlder ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == entries.length) {
                      return TextButton(
                        onPressed: _controller.loadOlder,
                        child: const Text('Carregar anteriores'),
                      );
                    }
                    final entry = entries[entries.length - 1 - i];
                    if (entry case NoteEntry(:final note)) {
                      final bubble = NoteBubble(
                        note: note,
                        onLongPress: () => _noteMenu(note),
                      );
                      return _freshNotes.remove(note.id)
                          ? EnterOnce(
                              key: ValueKey('note-${note.id}'),
                              child: bubble,
                            )
                          : bubble;
                    }
                    final message = (entry as MessageEntry).message;
                    final bubble = GestureDetector(
                      // Hold a message to forward it.
                      onLongPress: () => _messageMenu(message),
                      child: MessageBubble(
                        message: message,
                        showSender: _isGroup,
                        found:
                            message.id == widget.focus?.id &&
                            _controller.inPast,
                        onRetry: () => _retry(message.id),
                        // Media from before deliveries 2.5 and 3.6 have
                        // nothing to download: they keep their marker.
                        photo: _mediaOf(message),
                      ),
                    );
                    // Only messages that just arrived animate: the others
                    // cost no animation while scrolling.
                    return _controller.fresh.remove(message.id)
                        ? EnterOnce(key: ValueKey(message.id), child: bubble)
                        : bubble;
                  },
                );
              },
            ),
          ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _controller.inPast
                ? TextButton(
                    onPressed: _controller.jumpToLatest,
                    child: const Text('Ir para as mais recentes'),
                  )
                : const SizedBox.shrink(),
          ),
          if (_replyQuery case final q?)
            _QuickReplyList(
              replies: _replies,
              query: q,
              onPick: _useReply,
              onManage: _crm?.chatPrefs == null ? null : _manageReplies,
            ),
          _composer(context),
        ],
      ),
    );
  }

  /// The message box, or the note box in note mode: another color,
  /// "só você vê" and "Anotar" instead of sending.
  Widget _composer(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final note = _noteMode;
    final canNote = widget.clients != null && isPersonChat(widget.chat.jid);
    // Room under the box, clear of the system bar and of the keyboard
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
        child: Row(
          children: [
            if (chatMediaPicker != null && _recording == null && !note)
              IconButton(
                tooltip: 'Anexar',
                icon: const Icon(Symbols.attach_file_rounded),
                onPressed: _attach,
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: switch (_recording) {
                  final r? => Text(recordingText(r)),
                  null => TextField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: note ? 'Nota interna · só você vê' : 'Mensagem',
                      filled: note,
                      fillColor: note ? colors.tertiaryContainer : null,
                      suffixIcon: canNote
                          ? IconButton(
                              tooltip: note
                                  ? 'Voltar para mensagem'
                                  : 'Nota interna',
                              isSelected: note,
                              icon: const Icon(Symbols.sticky_note_2_rounded),
                              selectedIcon: const Icon(
                                Symbols.sticky_note_2_rounded,
                                fill: 1,
                              ),
                              onPressed: _toggleNote,
                            )
                          : null,
                    ),
                  ),
                },
              ),
            ),
            if (note)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.tonal(
                  onPressed: _addNote,
                  child: const Text('Anotar'),
                ),
              )
            else if (_empty && _canRecord)
              VoiceButton(
                onRecorded: _sendVoice,
                onRecording: (r) => setState(() => _recording = r),
              )
            else
              IconButton(
                tooltip: 'Enviar',
                icon: const Icon(Symbols.send_rounded),
                onPressed: _send,
              ),
          ],
        ),
      ),
    );
  }
}

/// The quick replies above the box while it starts with "/".
class _QuickReplyList extends StatelessWidget {
  const _QuickReplyList({
    required this.replies,
    required this.query,
    required this.onPick,
    required this.onManage,
  });

  /// Null while loading.
  final List<QuickReply>? replies;
  final String query;
  final ValueChanged<QuickReply> onPick;

  /// Opens Respostas rápidas; null without app.db.
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final all = replies;
    if (all == null) return const SizedBox.shrink();
    final found = matchReplies(all, query);
    final colors = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Material(
      color: colors.surfaceContainerHigh,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.3,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            if (all.isEmpty)
              ListTile(
                title: const Text('Nenhuma resposta rápida ainda.'),
                subtitle: const Text(
                  'Crie textos prontos para usar aqui com /.',
                ),
                trailing: onManage == null
                    ? null
                    : TextButton(
                        onPressed: onManage,
                        child: const Text('Criar'),
                      ),
              )
            else if (found.isEmpty)
              ListTile(title: Text('Nenhuma resposta com /$query.'))
            else
              for (final r in found)
                ListTile(
                  dense: true,
                  title: Text('/${r.shortcut}', style: t.titleSmall),
                  subtitle: Text(
                    r.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => onPick(r),
                ),
          ],
        ),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.showSender,
    required this.onRetry,
    this.photo,
    this.found = false,
  });

  final ChatMessage message;
  final bool showSender;
  final VoidCallback onRetry;

  /// The message a search opened the conversation on.
  final bool found;

  /// The media of the message: photo, audio, video or document
  final Widget? photo;

  @override
  Widget build(BuildContext context) {
    final mine = message.fromMe;
    final colors = Theme.of(context).colorScheme;
    final (bg, fg) = bubbleColors(colors, mine: mine, found: found);
    final small = Theme.of(context).textTheme.labelSmall!.copyWith(color: fg);
    // Rounded 20, with the corner next to the sender at 6.
    const big = Radius.circular(20), tail = Radius.circular(6);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: big,
            topRight: big,
            bottomLeft: mine ? big : tail,
            bottomRight: mine ? tail : big,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: fg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.forwarded) Text('↪ Encaminhada', style: small),
                if (showSender && !mine && message.senderName.isNotEmpty)
                  Text(message.senderName, style: small),
                if (photo case final photo?) ...[
                  photo,
                  if (message.text.isNotEmpty) Text(message.text),
                ] else
                  Text(messageText(message)),
                Text(
                  [
                    shortTime(message.ts),
                    if (message.kind != 'revoked') statusLabel(message.status),
                  ].where((s) => s.isNotEmpty).join('  '),
                  style: small,
                ),
                if (message.status == 'failed')
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Tentar de novo'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The background and text colors of a bubble: mine on the primary
/// container, theirs on a raised surface, the found one in ipê.
(Color, Color) bubbleColors(
  ColorScheme colors, {
  required bool mine,
  bool found = false,
}) {
  if (found) return (colors.tertiaryContainer, colors.onTertiaryContainer);
  if (mine) return (colors.primaryContainer, colors.onPrimaryContainer);
  return (colors.surfaceContainerHigh, colors.onSurface);
}

/// The text shown for a message: its text, or a marker for media.
String messageText(ChatMessage m) {
  const markers = {
    'image': '[imagem]',
    'audio': '[áudio]',
    'video': '[vídeo]',
    'document': '[documento]',
    'sticker': '[figurinha]',
    'other': '[outro]',
  };
  if (m.kind == 'text') return m.text;
  if (m.kind == 'revoked') {
    return m.fromMe ? '🚫 Você apagou esta mensagem' : '🚫 Mensagem apagada';
  }
  final marker = markers[m.kind] ?? '[outro]';
  return m.text.isEmpty ? marker : '$marker ${m.text}';
}

/// How a delivery status shows next to the time.
String statusLabel(String status) => switch (status) {
  'sending' => 'enviando',
  'sent' => '✓',
  'delivered' => '✓✓',
  'read' => '✓✓ lida',
  'failed' => 'falhou',
  _ => '',
};

/// A photo in the conversation: its thumbnail, or a button when there is
/// none; tapping opens it full screen.
class _Photo extends StatelessWidget {
  const _Photo({required this.bridge, required this.message});

  final CoreBridge bridge;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final thumb = previewOf(bridge, message);
    void open() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoScreen(bridge: bridge, message: message),
      ),
    );
    if (thumb == null) {
      return TextButton(
        onPressed: open,
        child: const Text('[imagem] ver foto'),
      );
    }
    // Decoded at the size shown, not the photo's (often 1600 px): far less
    // memory and work while scrolling.
    final px = (200 * MediaQuery.devicePixelRatioOf(context)).round();
    return GestureDetector(
      onTap: open,
      // A fixed box: the tap area exists before the image is decoded.
      child: SizedBox.square(
        dimension: 200,
        child: Image(
          image: ResizeImage(
            MemoryImage(thumb),
            width: px,
            height: px,
            policy: ResizeImagePolicy.fit,
            allowUpscaling: false,
          ),
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
