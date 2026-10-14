/// Product variations in a grid.
library;

const maxAttributes = 3;
const maxVariants = 100;

/// An attribute such as Cor (Azul, Preto).
class Attribute {
  const Attribute(this.name, this.values);
  final String name;
  final List<String> values;
}

/// Values from "Azul, Preto, azul ": trimmed, no blanks, no repeats.
List<String> parseValues(String input) => [
  ...{
    for (final v in input.split(','))
      if (v.trim().isNotEmpty) v.trim(),
  },
];

/// Every combination of the attributes' values, in order: [Azul, P],
/// [Azul, M]… One empty combination without attributes.
List<List<String>> combinations(List<Attribute> attributes) {
  var out = <List<String>>[[]];
  for (final a in attributes) {
    out = [
      for (final o in out)
        for (final v in a.values) [...o, v],
    ];
  }
  return out;
}

/// The number of combinations, without building them.
int combinationCount(List<Attribute> attributes) =>
    attributes.fold(1, (n, a) => n * a.values.length);

/// "Azul / M"; empty for the default variation.
String variantLabel(List<String> options) =>
    options.where((o) => o.isNotEmpty).join(' / ');

/// A key for a combination, to compare old and new grids.
String optionsKey(List<String> options) => options.join('\u0000');

/// What changing the attributes does to the existing variations:
/// [kept] stay with their stock, [removed] are deleted, [added] are new.
({List<T> kept, List<T> removed, List<List<String>> added}) reconcile<T>(
  List<T> existing,
  List<String> Function(T) optionsOf,
  List<List<String>> wanted,
) {
  final wantedKeys = {for (final w in wanted) optionsKey(w)};
  final existingKeys = {for (final e in existing) optionsKey(optionsOf(e))};
  return (
    kept: [
      for (final e in existing)
        if (wantedKeys.contains(optionsKey(optionsOf(e)))) e,
    ],
    removed: [
      for (final e in existing)
        if (!wantedKeys.contains(optionsKey(optionsOf(e)))) e,
    ],
    added: [
      for (final w in wanted)
        if (!existingKeys.contains(optionsKey(w))) w,
    ],
  );
}
