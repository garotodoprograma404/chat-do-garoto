import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../clients/clients_repository.dart';
import '../clients/validation.dart';
import '../core_bridge/core_bridge.dart';
import '../home/crm_scope.dart';
import '../settings/settings_menu.dart';
import '../theme/detail_pane.dart';
import '../theme/brand_mark.dart';
import '../theme/components.dart';
import 'chat_clients.dart';
import 'chat_filters.dart';
import 'chat_screen.dart';
import 'chat_search_screen.dart';
import 'chats_controller.dart';
import '../theme/responsive.dart';

/// The chat list. Conversations of clients show the name in
/// their file and a "cliente" mark; filters on top
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({
    super.key,
    required this.bridge,
    required this.controller,
    required this.status,
    this.onOpenSettings,
    this.clients,
    this.clock,
  });

  /// The CRM; null while app.db is not open.
  final ClientsRepository? clients;

  /// "Now", for "Sem resposta" (tests).
  final DateTime Function()? clock;

  final CoreBridge bridge;
  final ChatsController controller;

  /// Connection status shown under the title.
  final String status;

  /// Opens Configurações from the ⋮ menu.
  final VoidCallback? onOpenSettings;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  ChatClients? _names;

  CoreBridge get bridge => widget.bridge;
  ChatsController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.onRevokeDone = _revokeDone;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A client may have been saved from the conversation open beside.
    _detailReloader.attach(context, () => _names?.load());
    if (_names == null && widget.clients != null) {
      final crm = CrmScope.maybeOf(context);
      _names = ChatClients(
        bridge: bridge,
        repo: widget.clients!,
        sales: crm?.sales,
        prefs: crm?.chatPrefs,
        clock: widget.clock,
      )..load();
    }
  }

  void _filter(ChatFilter filter) {
    controller.setFilter(filter);
    // Clients and debts may have changed in the other sections.
    if (filter != ChatFilter.all && filter != ChatFilter.waiting) {
      _names?.load();
    }
  }

  final _detailReloader = DetailReloader();

  @override
  void dispose() {
    _detailReloader.dispose();
    if (controller.onRevokeDone == _revokeDone) controller.onRevokeDone = null;
    _names?.dispose();
    super.dispose();
  }

  Future<void> _chatMenu(ChatSummary chat) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListTile(
          leading: const Icon(Symbols.delete_rounded),
          title: const Text('Excluir conversa'),
          onTap: () => Navigator.pop(context, 'delete'),
        ),
      ),
    );
    if (action != 'delete' || !mounted) return;
    final everyone = await confirmDeleteChat(
      context,
      mine: revocableCount(bridge, chat.jid),
    );
    if (everyone == null || !mounted) return;
    try {
      bridge.deleteChat(chat.jid, forEveryone: everyone);
      _say(
        everyone
            ? 'Conversa excluída. Apagando para todos…'
            : 'Conversa excluída.',
      );
    } on CoreException catch (e) {
      _say(deleteChatError(e));
    }
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _revokeDone(int revoked, int failed) {
    if (!mounted) return;
    _say(
      failed == 0
          ? 'Apagadas para todos: $revoked.'
          : failed == 1
          ? '1 mensagem não foi apagada para todos.'
          : '$failed mensagens não foram apagadas para todos.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final names = _names;
    return Scaffold(
      appBar: AppBar(
        title: const SemicolonText('Conversas'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.status,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Pesquisar',
            icon: const Icon(Symbols.search_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChatSearchScreen(
                  bridge: bridge,
                  chats: controller,
                  clients: widget.clients,
                  names: _names,
                ),
              ),
            ),
          ),
          if (widget.onOpenSettings case final open?)
            SettingsMenuButton(onOpenSettings: open),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([controller, ?names]),
        builder: (context, _) {
          if (controller.chats.isEmpty) {
            return const EmptyState(
              title: 'Nenhuma conversa ainda.',
              message: 'As conversas do seu WhatsApp aparecem aqui.',
            );
          }
          final now = (widget.clock ?? DateTime.now)();
          final filter = names == null && controller.filter.needsCrm
              ? ChatFilter.all
              : controller.filter;
          final chats = filterChats(
            controller.chats,
            filter,
            now: now,
            clients: names,
          );
          final waiting = controller.chats
              .where((c) => waitingReply(c, now))
              .length;
          return Column(
            children: [
              _Filters(
                selected: filter,
                waiting: waiting,
                withCrm: names != null,
                onSelected: _filter,
              ),
              Expanded(
                child: chats.isEmpty
                    ? EmptyState(
                        title: chatFilterEmpty[filter]!.$1,
                        message: chatFilterEmpty[filter]!.$2,
                      )
                    : ListView.builder(
                        padding: EdgeInsets.only(
                          bottom: listBottomPadding(context),
                        ),
                        itemCount: chats.length,
                        itemBuilder: (context, i) => _row(chats[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(ChatSummary chat) {
    final names = _names;
    final client = names?.of(chat);
    return AppListTile(
      leading: InitialsAvatar(client ?? chatTitle(chat)),
      title: client == null
          ? Text(chatTitle(chat), maxLines: 1, overflow: TextOverflow.ellipsis)
          // The mark goes under the name when there is no room (large
          // text).
          : Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(client, maxLines: 1, overflow: TextOverflow.ellipsis),
                const ClientMark(),
              ],
            ),
      subtitle: Text(
        chat.lastText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        shortTime(chat.lastTs),
        style: Theme.of(context).textTheme.labelMedium,
      ),
      // Hold for "Excluir conversa", as in WhatsApp.
      onLongPress: () => _chatMenu(chat),
      selected: DetailHost.isSelected(context, 'chat:${chat.jid}'),
      onTap: () async {
        // With a pane beside the list, the conversation opens there.
        if (DetailHost.peek(context) case final pane?) {
          pane.open(
            (_) =>
                ChatScreen(bridge: bridge, chat: chat, clients: widget.clients),
            selected: 'chat:${chat.jid}',
            wide: true,
          );
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: wideRouteName),
            builder: (_) =>
                ChatScreen(bridge: bridge, chat: chat, clients: widget.clients),
          ),
        );
        // A client may have been saved from the conversation.
        await names?.load();
      },
    );
  }
}

/// The filter chips, one at a time. Without the CRM only
/// "Todas" and "Sem resposta" make sense.
class _Filters extends StatelessWidget {
  const _Filters({
    required this.selected,
    required this.waiting,
    required this.withCrm,
    required this.onSelected,
  });

  final ChatFilter selected;
  final int waiting;
  final bool withCrm;
  final ValueChanged<ChatFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterBar(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      children: [
        for (final f in ChatFilter.values)
          if (withCrm || !f.needsCrm)
            ChoiceChip(
              label: Text(
                f == ChatFilter.waiting && waiting > 0
                    ? '${chatFilterLabels[f]} $waiting'
                    : chatFilterLabels[f]!,
              ),
              selected: selected == f,
              showCheckmark: false,
              onSelected: (_) => onSelected(f),
            ),
      ],
    );
  }
}

/// Asks before deleting a chat. With [mine] messages of
/// mine still inside WhatsApp's window, offers to delete them for everyone
/// too. Null when cancelled; otherwise whether to delete for everyone.
Future<bool?> confirmDeleteChat(BuildContext context, {int mine = 0}) =>
    showDialog<bool>(
      context: context,
      builder: (context) => _DeleteChatDialog(mine: mine),
    );

/// What went wrong deleting a chat, for the user.
String deleteChatError(CoreException e) => e.code == 'offline'
    ? 'Sem conexão. Apagar para todos precisa de internet.'
    : 'Não foi possível excluir a conversa.';

class _DeleteChatDialog extends StatefulWidget {
  const _DeleteChatDialog({required this.mine});

  final int mine;

  @override
  State<_DeleteChatDialog> createState() => _DeleteChatDialogState();
}

class _DeleteChatDialogState extends State<_DeleteChatDialog> {
  bool _everyone = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Excluir esta conversa?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'As mensagens e mídias somem deste aparelho e do seu WhatsApp. '
            'A outra pessoa continua com a cópia dela.',
          ),
          if (widget.mine > 0)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _everyone,
              onChanged: (v) => setState(() => _everyone = v ?? false),
              title: Text(
                'Apagar também para todos as minhas mensagens das últimas '
                '60 horas (${widget.mine})',
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _everyone),
          child: const Text('Excluir'),
        ),
      ],
    );
  }
}

/// The chat's name or, when no name is known, its number, formatted for a
/// phone.
String chatTitle(ChatSummary chat) {
  if (chat.name.isNotEmpty) return chat.name;
  final user = chat.jid.split('@').first;
  return chat.jid.endsWith('@s.whatsapp.net') ? formatPhone(user) : user;
}

/// "14:05" for today, "03/10" otherwise.
String shortTime(int ms, {DateTime? now}) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  final today = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  if (t.year == today.year && t.month == today.month && t.day == today.day) {
    return '${two(t.hour)}:${two(t.minute)}';
  }
  return '${two(t.day)}/${two(t.month)}';
}
