import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../chats/chat_prefs.dart';
import '../chats/quick_replies.dart';
import '../theme/components.dart';

/// Configurações → Respostas rápidas: create, edit and
/// delete the texts typed after "/" in a conversation.
class QuickRepliesScreen extends StatefulWidget {
  const QuickRepliesScreen({super.key, required this.prefs});

  final ChatPrefs prefs;

  @override
  State<QuickRepliesScreen> createState() => _QuickRepliesScreenState();
}

class _QuickRepliesScreenState extends State<QuickRepliesScreen> {
  List<QuickReply>? _replies;

  @override
  void initState() {
    super.initState();
    widget.prefs.quickReplies().then((r) {
      if (mounted) setState(() => _replies = r);
    });
  }

  Future<void> _edit([int? index]) async {
    final all = _replies ?? const <QuickReply>[];
    final result = await showDialog<_Edit>(
      context: context,
      builder: (_) => _ReplyDialog(
        initial: index == null ? null : all[index],
        others: {
          for (final (i, r) in all.indexed)
            if (i != index) r.shortcut,
        },
      ),
    );
    if (result == null) return;
    final next = [...all];
    switch (result) {
      case _Save(:final reply) when index == null:
        next.add(reply);
      case _Save(:final reply):
        next[index!] = reply;
      case _Delete():
        next.removeAt(index!);
    }
    next.sort((a, b) => a.shortcut.compareTo(b.shortcut));
    await widget.prefs.saveQuickReplies(next);
    if (mounted) setState(() => _replies = next);
  }

  @override
  Widget build(BuildContext context) {
    final replies = _replies;
    return Scaffold(
      appBar: AppBar(title: const Text('Respostas rápidas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: replies == null ? null : _edit,
        icon: const Icon(Symbols.add_rounded),
        label: const Text('Nova resposta'),
      ),
      body: switch (replies) {
        null => const Center(child: CircularProgressIndicator()),
        [] => const EmptyState(
          title: 'Nenhuma resposta rápida ainda.',
          message:
              'Crie textos prontos, como a chave pix ou o horário de '
              'atendimento. Na conversa, digite / para usá-los. Use {nome} '
              'para o primeiro nome do cliente.',
        ),
        final list => ListView.builder(
          padding: EdgeInsets.only(
            bottom: listBottomPadding(context, fab: true),
          ),
          itemCount: list.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return const SectionHeader(
                'Na conversa, digite / e o atalho. {nome} vira o primeiro '
                'nome do cliente.',
              );
            }
            final r = list[i - 1];
            return AppListTile(
              title: Text('/${r.shortcut}'),
              subtitle: Text(
                r.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _edit(i - 1),
            );
          },
        ),
      },
    );
  }
}

sealed class _Edit {
  const _Edit();
}

class _Save extends _Edit {
  const _Save(this.reply);
  final QuickReply reply;
}

class _Delete extends _Edit {
  const _Delete();
}

class _ReplyDialog extends StatefulWidget {
  const _ReplyDialog({this.initial, required this.others});

  final QuickReply? initial;
  final Set<String> others;

  @override
  State<_ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends State<_ReplyDialog> {
  late final _shortcut = TextEditingController(
    text: widget.initial?.shortcut ?? '',
  );
  late final _text = TextEditingController(text: widget.initial?.text ?? '');
  String? _shortcutError, _textError;

  @override
  void dispose() {
    _shortcut.dispose();
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final shortcut = normalizeShortcut(_shortcut.text);
    final text = _text.text.trim();
    setState(() {
      _shortcutError = shortcutError(shortcut, widget.others);
      _textError = text.isEmpty ? 'Digite o texto.' : null;
    });
    if (_shortcutError != null || _textError != null) return;
    Navigator.pop(context, _Save(QuickReply(shortcut: shortcut, text: text)));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar esta resposta?'),
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
    if (ok == true && mounted) Navigator.pop(context, const _Delete());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Nova resposta' : 'Editar resposta'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _shortcut,
              autofocus: widget.initial == null,
              decoration: InputDecoration(
                labelText: 'Atalho',
                hintText: 'pix',
                prefixText: '/',
                errorText: _shortcutError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: 'Texto',
                hintText: 'Oi {nome}, a chave pix é…',
                errorText: _textError,
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.initial != null)
          TextButton(onPressed: _delete, child: const Text('Apagar')),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}
