import '../core_bridge/core_bridge.dart';
import 'chat_clients.dart';

/// The filters above the chat list, one at a time, as in
/// WhatsApp.
enum ChatFilter {
  all,
  waiting,
  clients,
  owing,
  newContacts;

  /// Whether the filter looks at the CRM (clients, debts, ignored).
  bool get needsCrm => index >= ChatFilter.clients.index;
}

const chatFilterLabels = {
  ChatFilter.all: 'Todas',
  ChatFilter.waiting: 'Sem resposta',
  ChatFilter.clients: 'Clientes',
  ChatFilter.owing: 'Devendo',
  ChatFilter.newContacts: 'Novos contatos',
};

/// A chat with one person (not a group, a channel or a broadcast list).
bool isPersonChat(String jid) =>
    jid.endsWith('@s.whatsapp.net') || jid.endsWith('@lid');

/// How far back a message still waits for a reply: older history imported
/// at pairing would fill the filter otherwise.
const waitingWindow = Duration(days: 7);

/// Whether [chat] waits for my reply at [now]: one person, the last
/// message theirs and from the last 7 days.
bool waitingReply(ChatSummary chat, DateTime now) =>
    isPersonChat(chat.jid) &&
    !chat.lastFromMe &&
    chat.lastTs > 0 &&
    now.difference(DateTime.fromMillisecondsSinceEpoch(chat.lastTs)) <=
        waitingWindow;

/// The chats waiting for a reply, the ones waiting longest first.
List<ChatSummary> waitingChats(List<ChatSummary> chats, DateTime now) => [
  for (final c in chats)
    if (waitingReply(c, now)) c,
]..sort((a, b) => a.lastTs.compareTo(b.lastTs));

/// The chats [filter] shows, in the list's order. Without [clients] (the
/// CRM closed), only "Todas" and "Sem resposta" filter anything.
List<ChatSummary> filterChats(
  List<ChatSummary> chats,
  ChatFilter filter, {
  required DateTime now,
  ChatClients? clients,
}) {
  bool keep(ChatSummary c) => switch (filter) {
    ChatFilter.all => true,
    ChatFilter.waiting => waitingReply(c, now),
    ChatFilter.clients => clients?.clientOf(c) != null,
    ChatFilter.owing => clients?.debtOf(c) != null,
    ChatFilter.newContacts =>
      clients != null &&
          isPersonChat(c.jid) &&
          clients.clientOf(c) == null &&
          !clients.isIgnored(c.jid),
  };
  return [
    for (final c in chats)
      if (keep(c)) c,
  ];
}

/// What an empty filter says.
const chatFilterEmpty = {
  ChatFilter.waiting: (
    'Nenhuma conversa esperando resposta.',
    'Aqui aparecem as conversas em que a última mensagem é do contato, dos '
        'últimos 7 dias.',
  ),
  ChatFilter.clients: (
    'Nenhuma conversa de cliente.',
    'Toque no nome de um contato, numa conversa, para cadastrá-lo como '
        'cliente.',
  ),
  ChatFilter.owing: (
    'Nenhum cliente devendo.',
    'Aqui aparecem as conversas de clientes com valor a receber.',
  ),
  ChatFilter.newContacts: (
    'Nenhum contato novo.',
    'Aqui aparecem as conversas de quem ainda não é cliente.',
  ),
};
