import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core_bridge/core_bridge.dart';
import '../../search/text.dart';
import '../chats_screen.dart' show chatTitle;

/// Picks the conversation to forward to, as in WhatsApp.
/// Pops with the chat.
class ForwardScreen extends StatefulWidget {
  const ForwardScreen({super.key, required this.bridge});

  final CoreBridge bridge;

  @override
  State<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends State<ForwardScreen> {
  late final List<ChatSummary> _chats = _load();
  String _query = '';

  List<ChatSummary> _load() {
    try {
      return widget.bridge.listChats();
    } on CoreException {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final c in _chats)
        if (textMatches(chatTitle(c), _query)) c,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Encaminhar para')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar conversa',
                prefixIcon: Icon(Symbols.search_rounded),
              ),
              onChanged: (t) => setState(() => _query = t),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (context, i) => ListTile(
                title: Text(chatTitle(shown[i])),
                onTap: () => Navigator.pop(context, shown[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
