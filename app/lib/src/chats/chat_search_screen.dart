import 'dart:async';

import 'package:flutter/material.dart';

import '../clients/clients_repository.dart';
import '../core_bridge/core_bridge.dart';
import '../search/text.dart';
import 'chat_screen.dart';
import 'chats_controller.dart';
import 'chats_screen.dart';
import 'chat_clients.dart';

/// Search in the conversations, as in WhatsApp:
/// chats by name (also the client's name) and messages by text.
class ChatSearchScreen extends StatefulWidget {
  const ChatSearchScreen({
    super.key,
    required this.bridge,
    required this.chats,
    this.clients,
    this.names,
  });

  final CoreBridge bridge;
  final ChatsController chats;
  final ClientsRepository? clients;

  /// Client names for the chats, when the CRM is open.
  final ChatClients? names;

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  Timer? _debounce;
  String _query = '';
  List<ChatMessage> _messages = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _typed(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(text));
  }

  void _search(String text) {
    var messages = const <ChatMessage>[];
    if (text.trim().isNotEmpty) {
      try {
        messages = widget.bridge.searchMessages(text);
      } on CoreException {
        messages = const [];
      }
    }
    setState(() {
      _query = text;
      _messages = messages;
    });
  }

  String _nameOf(ChatSummary chat) => widget.names?.of(chat) ?? chatTitle(chat);

  ChatSummary _chatOf(String jid) => widget.chats.chats.firstWhere(
    (c) => c.jid == jid,
    orElse: () => ChatSummary(jid: jid, name: '', lastText: '', lastTs: 0),
  );

  void _open(ChatSummary chat, {ChatMessage? focus}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            bridge: widget.bridge,
            chat: chat,
            clients: widget.clients,
            focus: focus,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final query = _query.trim();
    final chats = query.isEmpty
        ? const <ChatSummary>[]
        : [
            for (final c in widget.chats.chats)
              if (textMatches(_nameOf(c), query)) c,
          ];
    final heading = Theme.of(context).textTheme.titleSmall;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Pesquisar…'),
          onChanged: _typed,
        ),
      ),
      body: ListView(
        children: [
          if (chats.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Conversas', style: heading),
            ),
            for (final c in chats)
              ListTile(title: Text(_nameOf(c)), onTap: () => _open(c)),
          ],
          if (_messages.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Mensagens', style: heading),
            ),
            for (final m in _messages)
              ListTile(
                title: Text(_nameOf(_chatOf(m.chat))),
                subtitle: Text(
                  messageText(m),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(shortTime(m.ts)),
                onTap: () => _open(_chatOf(m.chat), focus: m),
              ),
          ],
          if (query.isNotEmpty && chats.isEmpty && _messages.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nada encontrado.'),
            ),
        ],
      ),
    );
  }
}
