/// Product codes.
library;

/// Whether [digits] (8, 12, 13 or 14 digits) ends in the right GTIN check
/// digit.
bool validGtin(String digits) {
  if (!RegExp(r'^(\d{8}|\d{12,14})$').hasMatch(digits)) return false;
  var sum = 0;
  for (var i = digits.length - 2, weight = 3; i >= 0; i--) {
    sum += int.parse(digits[i]) * weight;
    weight = weight == 3 ? 1 : 3;
  }
  return (10 - sum % 10) % 10 == int.parse(digits[digits.length - 1]);
}

/// The error for a barcode, or null. Only EAN/GTIN lengths are checked:
/// stores also use their own codes.
String? barcodeError(String code) {
  if (code.isEmpty) return null;
  if (code.length > 48 || code.contains(RegExp(r'\s'))) {
    return 'Código de barras inválido.';
  }
  if (RegExp(r'^(\d{8}|\d{12,14})$').hasMatch(code) && !validGtin(code)) {
    return 'Código de barras com um número errado. Confira.';
  }
  return null;
}

/// The error for a product code (SKU), or null.
String? skuError(String code) =>
    code.length > 60 ? 'Código muito longo.' : null;
