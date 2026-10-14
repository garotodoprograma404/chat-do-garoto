import '../search/text.dart';
import 'chat_prefs.dart';

/// What comes after the "/" that starts the message box, or null when the
/// box does not start with "/".
String? quickReplyQuery(String text) {
  if (!text.startsWith('/') || text.contains('\n')) return null;
  return text.substring(1);
}

/// The replies whose shortcut or text has [query] (accents and case
/// ignored); shortcuts that start with it come first.
List<QuickReply> matchReplies(List<QuickReply> all, String query) {
  final q = query.trim();
  if (q.isEmpty) return all;
  final starts = <QuickReply>[], others = <QuickReply>[];
  for (final r in all) {
    if (fold(r.shortcut).startsWith(fold(q))) {
      starts.add(r);
    } else if (textMatches(r.shortcut, q) || textMatches(r.text, q)) {
      others.add(r);
    }
  }
  return [...starts, ...others];
}

/// [text] with "{nome}" as the first word of [name]. Without a name,
/// "{nome}" leaves the text, with the space before it.
String fillName(String text, String? name) {
  final first = (name ?? '').trim().split(RegExp(r'\s+')).first;
  if (first.isNotEmpty) return text.replaceAll('{nome}', first);
  var out = text.replaceAll(RegExp(r' ?\{nome\}'), '');
  // "{nome}, tudo bem?" → "tudo bem?"
  out = out.replaceFirst(RegExp(r'^[,;:!]\s*'), '');
  return out;
}

/// A shortcut as kept: lower case, no "/" and no spaces.
String normalizeShortcut(String raw) =>
    raw.trim().replaceFirst(RegExp(r'^/+'), '').toLowerCase();

/// What is wrong with a shortcut, or null.
String? shortcutError(String shortcut, Iterable<String> others) {
  if (shortcut.isEmpty) return 'Digite um atalho.';
  if (shortcut.contains(RegExp(r'\s'))) return 'O atalho não pode ter espaço.';
  return others.contains(shortcut)
      ? 'Já existe uma resposta com /$shortcut.'
      : null;
}
