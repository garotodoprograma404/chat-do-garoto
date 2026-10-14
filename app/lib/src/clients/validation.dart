/// Checks and formats for client data. Pure functions.
library;

/// Only the digits of [input].
String digitsOf(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

/// A number from the address book as the app keeps it:
/// digits only, with Brazil's 55 when the country is missing ("(11)
/// 98765-4321", "011 98765-4321"). A number written with "+" keeps its
/// own country.
String normalizePhone(String raw) {
  final digits = digitsOf(raw);
  if (raw.trim().startsWith('+')) return digits;
  final local = digits.replaceFirst(RegExp(r'^0+'), '');
  return local.length == 10 || local.length == 11 ? '55$local' : local;
}

/// "+55 11 98765-4321" from the digits kept; a number of
/// another country as "+14155552671".
String formatPhone(String digits) {
  if (digits.isEmpty) return '';
  final m = RegExp(r'^55(\d{2})(\d{4,5})(\d{4})$').firstMatch(digits);
  return m == null ? '+$digits' : '+55 ${m[1]} ${m[2]}-${m[3]}';
}

/// Error for a phone with country and area code, or null when valid.
String? phoneError(String digits) => RegExp(r'^[0-9]{10,15}$').hasMatch(digits)
    ? null
    : 'Use o código do país, o DDD e o número, por exemplo 55 11 99999-0000.';

/// Whether [email] looks like an address (empty is fine: optional).
bool validEmail(String email) =>
    email.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

bool _sameDigits(String d) => d.split('').toSet().length == 1;

int _checkDigit(String digits, List<int> weights) {
  var sum = 0;
  for (var i = 0; i < weights.length; i++) {
    sum += int.parse(digits[i]) * weights[i];
  }
  final rest = sum % 11;
  return rest < 2 ? 0 : 11 - rest;
}

/// Whether [d] (11 digits) is a CPF with valid check digits.
bool validCpf(String d) {
  if (d.length != 11 || _sameDigits(d)) return false;
  final first = _checkDigit(d, [10, 9, 8, 7, 6, 5, 4, 3, 2]);
  final second = _checkDigit(d, [11, 10, 9, 8, 7, 6, 5, 4, 3, 2]);
  return d[9] == '$first' && d[10] == '$second';
}

/// Whether [d] (14 digits) is a CNPJ with valid check digits.
bool validCnpj(String d) {
  if (d.length != 14 || _sameDigits(d)) return false;
  final first = _checkDigit(d, [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]);
  final second = _checkDigit(d, [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]);
  return d[12] == '$first' && d[13] == '$second';
}

/// Error for a CPF or CNPJ (digits), or null when valid or empty.
String? documentError(String digits) {
  if (digits.isEmpty) return null;
  if (digits.length == 11) return validCpf(digits) ? null : 'CPF inválido.';
  if (digits.length == 14) return validCnpj(digits) ? null : 'CNPJ inválido.';
  return 'O CPF tem 11 números e o CNPJ, 14.';
}

/// "123.456.789-09" or "12.345.678/0001-95" for display.
String formatDocument(String d) => switch (d.length) {
  11 =>
    '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}',
  14 =>
    '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/'
        '${d.substring(8, 12)}-${d.substring(12)}',
  _ => d,
};

/// Parses "dd/mm" or "dd/mm/aaaa" into "--MM-DD" or "AAAA-MM-DD". Also
/// takes "-", "." or spaces as separators, and digits only ("0503",
/// "05031990"). Returns null for an invalid date; "" for empty input.
String? parseBirthday(String input) {
  var text = input.trim();
  if (text.isEmpty) return '';
  if (RegExp(r'^\d{4}$|^\d{8}$').hasMatch(text)) {
    text = text.length == 4
        ? '${text.substring(0, 2)}/${text.substring(2)}'
        : '${text.substring(0, 2)}/${text.substring(2, 4)}/${text.substring(4)}';
  }
  final match = RegExp(r'^(\d{1,2})[/.\- ]+(\d{1,2})(?:[/.\- ]+(\d{4}))?$')
      .firstMatch(text);
  if (match == null) return null;
  final day = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final year = match[3] == null ? null : int.parse(match[3]!);
  // Without a year, 29/02 is allowed (a leap year is used to check).
  final check = DateTime(year ?? 2000, month, day);
  if (check.month != month || check.day != day) return null;
  if (year != null && (year < 1900 || check.isAfter(DateTime.now()))) {
    return null;
  }
  String two(int n) => n.toString().padLeft(2, '0');
  return year == null
      ? '--${two(month)}-${two(day)}'
      : '$year-${two(month)}-${two(day)}';
}

/// "05/03" or "05/03/1990" from a stored birthday.
String formatBirthday(String stored) {
  final m = RegExp(r'^(--|\d{4}-)(\d{2})-(\d{2})$').firstMatch(stored);
  if (m == null) return '';
  final year = m[1] == '--' ? '' : '/${m[1]!.substring(0, 4)}';
  return '${m[3]}/${m[2]}$year';
}

/// Tags from "VIP, atacado, vip": trimmed, lower case, no repeats.
List<String> parseTags(String input) => [
  ...{
    for (final t in input.split(','))
      if (t.trim().isNotEmpty) t.trim().toLowerCase(),
  },
];
