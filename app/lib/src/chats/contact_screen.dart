import 'package:flutter/material.dart';

import '../clients/validation.dart';
import '../core_bridge/core_bridge.dart';
import 'chats_screen.dart';

/// "Dados do contato", opened by tapping the name of a group, or of any
/// conversation while app.db is closed. A one-person
/// conversation opens the client panel instead. Groups
/// never become clients.
class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key, required this.bridge, required this.chat});

  final CoreBridge bridge;
  final ChatSummary chat;

  bool get _group => chat.jid.endsWith('@g.us');

  /// The phone behind the chat; "" when WhatsApp did not tell it.
  String _phone() {
    if (_group) return '';
    try {
      return bridge.chatPhone(chat.jid);
    } on CoreException {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = _phone();
    return Scaffold(
      appBar: AppBar(title: const Text('Dados do contato')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(chatTitle(chat), style: Theme.of(context).textTheme.titleLarge),
          if (phone.isNotEmpty) Text(formatPhone(phone)),
          if (_group) const Text('Grupo'),
        ],
      ),
    );
  }
}
