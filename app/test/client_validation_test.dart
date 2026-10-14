// Client data checks.
import 'package:chat_do_garoto/src/clients/validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phone needs country and area code', () {
    expect(phoneError(digitsOf('+55 (11) 99999-0000')), isNull);
    expect(phoneError(digitsOf('99999-0000')), isNotNull);
    expect(phoneError(''), isNotNull);
  });

  test('e-mail is optional but checked', () {
    expect(validEmail(''), isTrue);
    expect(validEmail('ana@exemplo.com.br'), isTrue);
    expect(validEmail('ana@exemplo'), isFalse);
    expect(validEmail('ana exemplo.com'), isFalse);
  });

  test('CPF and CNPJ check digits', () {
    expect(documentError(digitsOf('529.982.247-25')), isNull);
    expect(documentError(digitsOf('529.982.247-24')), 'CPF inválido.');
    expect(documentError('11111111111'), 'CPF inválido.');
    expect(documentError(digitsOf('11.222.333/0001-81')), isNull);
    expect(documentError(digitsOf('11.222.333/0001-82')), 'CNPJ inválido.');
    expect(documentError('123'), isNotNull);
    expect(documentError(''), isNull);
    expect(formatDocument('52998224725'), '529.982.247-25');
    expect(formatDocument('11222333000181'), '11.222.333/0001-81');
  });

  test('birthday with or without year', () {
    expect(parseBirthday('5/3'), '--03-05');
    expect(parseBirthday('29/02'), '--02-29');
    expect(parseBirthday('05/03/1990'), '1990-03-05');
    expect(parseBirthday(''), '');
    expect(parseBirthday('31/04'), isNull);
    expect(parseBirthday('29/02/2023'), isNull);
    expect(parseBirthday('1/1/3000'), isNull);
    expect(parseBirthday('ontem'), isNull);
    // Whatever the phone keyboard allows.
    expect(parseBirthday('05-03-1990'), '1990-03-05');
    expect(parseBirthday('05.03.1990'), '1990-03-05');
    expect(parseBirthday('05 03 1990'), '1990-03-05');
    expect(parseBirthday('05031990'), '1990-03-05');
    expect(parseBirthday('0503'), '--03-05');
    expect(parseBirthday('050'), isNull);
    expect(formatBirthday('--03-05'), '05/03');
    expect(formatBirthday('1990-03-05'), '05/03/1990');
  });

  test('tags are trimmed, lower case and unique', () {
    expect(parseTags(' VIP, atacado,vip ,, '), ['vip', 'atacado']);
    expect(parseTags(''), isEmpty);
  });
}
