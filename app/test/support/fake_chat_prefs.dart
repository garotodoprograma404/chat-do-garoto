import 'package:chat_do_garoto/src/chats/chat_prefs.dart';

/// In-memory [ChatPrefs] for screen tests.
class FakeChatPrefs implements ChatPrefs {
  List<QuickReply> replies = [];
  final ignoredChats = <String>{};

  @override
  Future<List<QuickReply>> quickReplies() async => [...replies];

  @override
  Future<void> saveQuickReplies(List<QuickReply> list) async =>
      replies = [...list];

  @override
  Future<Set<String>> ignored() async => {...ignoredChats};

  @override
  Future<void> setIgnored(String jid, {required bool ignored}) async =>
      ignored ? ignoredChats.add(jid) : ignoredChats.remove(jid);
}
