/// Money and quantities as integers: money in cents, quantities
/// in thousandths. Never doubles.
library;

/// The units a product can be sold in.
const units = [
  'UN',
  'PC',
  'CX',
  'PCT',
  'PAR',
  'DZ',
  'KIT',
  'KG',
  'G',
  'L',
  'ML',
  'M',
  'CM',
  'M²',
  'H',
];

const _fractional = {'KG', 'L', 'M', 'M²', 'H'};

/// Whether [unit] takes quantities like 1,250.
bool fractional(String unit) => _fractional.contains(unit);

/// Cents from "1.234,56", "12,5", "12.50" or "R$ 3"; null when invalid or
/// negative.
int? parseMoney(String text) {
  var t = text.replaceAll(r'R$', '').replaceAll(RegExp(r'\s'), '');
  if (t.isEmpty) return null;
  if (RegExp(r'^\d+\.\d{1,2}$').hasMatch(t)) {
    t = t.replaceAll('.', ',');
  } else {
    // Brazilian: dots group thousands ("1.234"), the comma starts the
    // cents.
    final whole = t.split(',').first;
    if (whole.contains('.') &&
        !RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(whole)) {
      return null;
    }
    t = whole.replaceAll('.', '') + t.substring(whole.length);
  }
  final m = RegExp(r'^(\d{1,12})(?:,(\d{0,2}))?$').firstMatch(t);
  if (m == null) return null;
  final cents = (m[2] ?? '').padRight(2, '0');
  return int.parse(m[1]!) * 100 + int.parse(cents);
}

String _group(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write('.');
    out.write(s[i]);
  }
  return out.toString();
}

/// "1.234,56" from cents, for a field being edited.
String formatAmount(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  return '$sign${_group(abs ~/ 100)},${(abs % 100).toString().padLeft(2, '0')}';
}

/// "R$ 1.234,56" (or "-R$ 5,00") from cents.
String formatMoney(int cents) =>
    cents < 0 ? '-R\$ ${formatAmount(-cents)}' : 'R\$ ${formatAmount(cents)}';

/// Thousandths from "1,250" or "1.25"; whole numbers only for units
/// without fractions. Null when invalid or negative.
int? parseQuantity(String text, String unit) {
  final t = text.replaceAll(RegExp(r'\s'), '');
  final m = RegExp(r'^(\d{1,9})(?:[.,](\d{0,3}))?$').firstMatch(t);
  if (m == null) return null;
  final part = (m[2] ?? '').padRight(3, '0');
  final milli = int.parse(m[1]!) * 1000 + int.parse(part);
  if (!fractional(unit) && milli % 1000 != 0) return null;
  return milli;
}

/// "1,25", "3" or "-2" from thousandths.
String formatQuantity(int milli) {
  final sign = milli < 0 ? '-' : '';
  final abs = milli.abs();
  final whole = _group(abs ~/ 1000);
  final part = (abs % 1000)
      .toString()
      .padLeft(3, '0')
      .replaceAll(RegExp(r'0+$'), '');
  return part.isEmpty ? '$sign$whole' : '$sign$whole,$part';
}
