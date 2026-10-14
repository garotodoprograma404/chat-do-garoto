/// Text matching for searches: lower case, without accents, so
/// "acao" finds "Ação".
library;

const _plain = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
  'ý': 'y',
  'ÿ': 'y',
};

/// [text] in lower case and without accents.
String fold(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    out.write(_plain[ch] ?? ch);
  }
  return out.toString();
}

/// Whether every word of [query] appears in [text], accents and case
/// ignored. An empty query matches everything.
bool textMatches(String text, String query) {
  final haystack = fold(text);
  return fold(query)
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .every(haystack.contains);
}
