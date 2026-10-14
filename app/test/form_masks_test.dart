import 'package:chat_do_garoto/src/theme/form_parts.dart';
import 'package:flutter_test/flutter_test.dart';

/// The quantity mask: digits, one comma, three decimals.
void main() {
  TextEditingValue type(String from, String to) =>
      Masks.decimal.formatEditUpdate(
        TextEditingValue(text: from),
        TextEditingValue(text: to),
      );

  test('digits and one comma, up to three decimals', () {
    expect(type('', '1').text, '1');
    expect(type('1', '1,').text, '1,');
    expect(type('1,', '1,5').text, '1,5');
    expect(type('12,25', '12,250').text, '12,250');
  });

  test('a dot becomes a comma', () {
    expect(type('2', '2.').text, '2,');
    expect(type('2,', '2.5').text, '2,5');
  });

  test('letters, a second comma and a fourth decimal are refused', () {
    expect(type('1', '1a').text, '1');
    expect(type('1,5', '1,5,').text, '1,5');
    expect(type('1,250', '1,2501').text, '1,250');
    expect(type('', '-3').text, '');
  });
}
