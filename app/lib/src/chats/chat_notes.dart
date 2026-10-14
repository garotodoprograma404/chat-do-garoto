import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../clients/clients_repository.dart';
import '../core_bridge/core_bridge.dart';
import 'chats_screen.dart' show shortTime;

/// One line of a conversation: a WhatsApp message or an internal note
sealed class ChatEntry {
  const ChatEntry();
}

class MessageEntry extends ChatEntry {
  const MessageEntry(this.message);
  final ChatMessage message;
}

class NoteEntry extends ChatEntry {
  const NoteEntry(this.note);
  final ClientNote note;
}

/// [messages] (oldest first) with the client's [notes] placed by time
/// Notes older than the first message shown only come in when there
/// is nothing older to load: they would jump around otherwise.
List<ChatEntry> mergeNotes(
  List<ChatMessage> messages,
  List<ClientNote> notes, {
  required bool hasOlder,
}) {
  if (notes.isEmpty) return [for (final m in messages) MessageEntry(m)];
  final from = hasOlder && messages.isNotEmpty ? messages.first.ts : null;
  final shown = [
    for (final n in notes)
      if (from == null || n.at.millisecondsSinceEpoch >= from) n,
  ]..sort((a, b) => a.at.compareTo(b.at));
  final out = <ChatEntry>[];
  var i = 0;
  for (final m in messages) {
    while (i < shown.length && shown[i].at.millisecondsSinceEpoch < m.ts) {
      out.add(NoteEntry(shown[i++]));
    }
    out.add(MessageEntry(m));
  }
  while (i < shown.length) {
    out.add(NoteEntry(shown[i++]));
  }
  return out;
}

/// An internal note in the conversation: never sent, only here and
/// in the client's file.
class NoteBubble extends StatelessWidget {
  const NoteBubble({super.key, required this.note, this.onLongPress});

  final ClientNote note;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final on = colors.onTertiaryContainer;
    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
          ),
          decoration: BoxDecoration(
            color: colors.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Symbols.sticky_note_2_rounded, size: 16, color: on),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Nota · só você vê',
                      style: t.labelMedium!.copyWith(color: on),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(note.body, style: TextStyle(color: on)),
              Text(
                shortTime(note.at.millisecondsSinceEpoch),
                style: t.labelSmall!.copyWith(color: on),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
