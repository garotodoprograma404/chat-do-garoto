/// Prices, margins and the average cost.
library;

/// "From [minQty] units, [price]". Quantities in thousandths, money
/// in cents.
class WholesaleTier {
  const WholesaleTier(this.minQty, this.price);
  final int minQty;
  final int price;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// "AAAA-MM-DD" for a day.
String isoDay(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// "dd/mm/aaaa" from "AAAA-MM-DD".
String formatDay(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  return m == null ? '' : '${m[3]}/${m[2]}/${m[1]}';
}

/// "AAAA-MM-DD" from "dd/mm/aaaa" (or "ddmmaaaa"); '' for blank, null when
/// invalid.
String? parseDay(String input) {
  var text = input.trim();
  if (text.isEmpty) return '';
  if (RegExp(r'^\d{8}$').hasMatch(text)) {
    text =
        '${text.substring(0, 2)}/${text.substring(2, 4)}/${text.substring(4)}';
  }
  final m = RegExp(r'^(\d{1,2})[/.\- ]+(\d{1,2})[/.\- ]+(\d{4})$')
      .firstMatch(text);
  if (m == null) return null;
  final day = int.parse(m[1]!), month = int.parse(m[2]!);
  final year = int.parse(m[3]!);
  final check = DateTime(year, month, day);
  if (check.month != month || check.day != day) return null;
  return isoDay(check);
}

/// Whether a promotion applies on [today]; [until] is "AAAA-MM-DD",
/// inclusive, or null for no end.
bool promoActive(int? promoPrice, String? until, DateTime today) =>
    promoPrice != null &&
    (until == null || isoDay(today).compareTo(until) <= 0);

/// The price that applies: the lowest among the sale price, a
/// running promotion and the wholesale tier [quantity] reaches.
int priceFor({
  required int price,
  int? promoPrice,
  String? promoUntil,
  List<WholesaleTier> tiers = const [],
  int quantity = 1000,
  required DateTime today,
}) {
  var best = price;
  if (promoActive(promoPrice, promoUntil, today) && promoPrice! < best) {
    best = promoPrice;
  }
  for (final t in tiers) {
    if (quantity >= t.minQty && t.price < best) best = t.price;
  }
  return best;
}

/// The margin in percent: profit over the sale price; null without a
/// price.
double? marginPercent(int price, int cost) =>
    price <= 0 ? null : (price - cost) * 100 / price;

/// "37,5%".
String formatPercent(double value) =>
    '${value.toStringAsFixed(1).replaceAll('.', ',')}%';

/// The cost after an entry: the weighted average of the stock and the
/// entry, rounded to the cent; the entry's cost when there was no stock.
int averageCost({
  required int stock,
  required int cost,
  required int quantity,
  required int unitCost,
}) {
  if (stock <= 0) return unitCost;
  final total =
      BigInt.from(stock) * BigInt.from(cost) +
      BigInt.from(quantity) * BigInt.from(unitCost);
  final count = BigInt.from(stock + quantity);
  // Half up: (2 * total + count) ~/ (2 * count).
  return ((total * BigInt.two + count) ~/ (count * BigInt.two)).toInt();
}
