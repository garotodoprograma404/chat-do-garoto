// Money, codes, variations and prices of products.
import 'dart:io';

import 'package:chat_do_garoto/src/products/barcode.dart';
import 'package:chat_do_garoto/src/products/money.dart';
import 'package:chat_do_garoto/src/products/pricing.dart';
import 'package:chat_do_garoto/src/products/product_photos.dart';
import 'package:chat_do_garoto/src/products/variants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('money', () {
    test('reads the ways people type prices', () {
      expect(parseMoney('1.234,56'), 123456);
      expect(parseMoney('12,5'), 1250);
      expect(parseMoney('12.50'), 1250);
      expect(parseMoney('12.5'), 1250);
      expect(parseMoney('R\$ 3'), 300);
      expect(parseMoney(' 0,99 '), 99);
      expect(parseMoney('1.234'), 123400);
      expect(parseMoney('1.000.000'), 100000000);
      expect(parseMoney('12,'), 1200);
    });

    test('refuses what is not a price', () {
      for (final bad in ['', 'abc', '-5', '1,234,5', '1,999', '12.345,6.7']) {
        expect(parseMoney(bad), isNull, reason: bad);
      }
    });

    test('shows reais', () {
      expect(formatMoney(123456), 'R\$ 1.234,56');
      expect(formatMoney(5), 'R\$ 0,05');
      expect(formatMoney(100000000), 'R\$ 1.000.000,00');
      expect(formatMoney(-500), '-R\$ 5,00');
      expect(formatAmount(1250), '12,50');
    });
  });

  group('quantities', () {
    test('fractions only for KG, L, M, M² and H', () {
      expect(parseQuantity('1,250', 'KG'), 1250);
      expect(parseQuantity('1.25', 'L'), 1250);
      expect(parseQuantity('0,5', 'H'), 500);
      expect(parseQuantity('3', 'UN'), 3000);
      expect(parseQuantity('3,0', 'UN'), 3000);
      expect(parseQuantity('1,5', 'UN'), isNull);
      expect(parseQuantity('1,2345', 'KG'), isNull);
      expect(parseQuantity('-1', 'UN'), isNull);
      expect(parseQuantity('', 'UN'), isNull);
      expect(fractional('M²'), isTrue);
      expect(fractional('CX'), isFalse);
    });

    test('shows quantities without trailing zeros', () {
      expect(formatQuantity(1250), '1,25');
      expect(formatQuantity(3000), '3');
      expect(formatQuantity(-2000), '-2');
      expect(formatQuantity(1234000), '1.234');
      expect(formatQuantity(1), '0,001');
    });
  });

  group('barcode', () {
    test('checks the GTIN digit', () {
      expect(validGtin('7891000315507'), isTrue); // EAN-13
      expect(validGtin('7891000315508'), isFalse);
      expect(validGtin('96385074'), isTrue); // EAN-8
      expect(validGtin('036000291452'), isTrue); // UPC-A
      expect(validGtin('17891000315504'), isTrue); // GTIN-14
    });

    test('only EAN lengths are checked', () {
      expect(barcodeError(''), isNull);
      expect(barcodeError('7891000315507'), isNull);
      expect(barcodeError('7891000315508'), isNotNull);
      expect(barcodeError('LOJA-00042'), isNull);
      expect(barcodeError('12345'), isNull);
      expect(barcodeError('com espaço'), isNotNull);
    });
  });

  group('variations', () {
    const cor = Attribute('Cor', ['Azul', 'Preto']);
    const tamanho = Attribute('Tamanho', ['P', 'M', 'G']);

    test('every combination, in order', () {
      final all = combinations([cor, tamanho]);
      expect(all.length, 6);
      expect(all.first, ['Azul', 'P']);
      expect(all.last, ['Preto', 'G']);
      expect(combinations([]), [<String>[]]);
      expect(combinationCount([cor, tamanho]), 6);
      expect(variantLabel(['Azul', 'P']), 'Azul / P');
      expect(variantLabel([]), '');
    });

    test('values are trimmed without repeats', () {
      expect(parseValues(' Azul, Preto,, Azul '), ['Azul', 'Preto']);
    });

    test('changing attributes keeps, removes and adds', () {
      final existing = [
        (1, ['Azul', 'P']),
        (2, ['Azul', 'M']),
        (3, ['Preto', 'P']),
        (4, ['Preto', 'M']),
      ];
      final plan = reconcile(
        existing,
        (e) => e.$2,
        combinations([
          const Attribute('Cor', ['Azul', 'Verde']),
          const Attribute('Tamanho', ['P', 'M']),
        ]),
      );
      expect(plan.kept.map((e) => e.$1), [1, 2]);
      expect(plan.removed.map((e) => e.$1), [3, 4]);
      expect(plan.added, [
        ['Verde', 'P'],
        ['Verde', 'M'],
      ]);
    });
  });

  group('prices', () {
    final today = DateTime(2026, 10, 2, 15);

    test('a running promotion lowers the price; it ends by itself', () {
      expect(
        priceFor(
          price: 5000,
          promoPrice: 3990,
          promoUntil: '2026-10-02',
          today: today,
        ),
        3990,
      );
      expect(
        priceFor(
          price: 5000,
          promoPrice: 3990,
          promoUntil: '2026-10-01',
          today: today,
        ),
        5000,
      );
      expect(priceFor(price: 5000, promoPrice: 3990, today: today), 3990);
      expect(promoActive(null, null, today), isFalse);
    });

    test('wholesale tiers apply from their quantity', () {
      const tiers = [WholesaleTier(10000, 800), WholesaleTier(50000, 700)];
      int at(int units) => priceFor(
        price: 1000,
        tiers: tiers,
        quantity: units * 1000,
        today: today,
      );
      expect(at(9), 1000);
      expect(at(10), 800);
      expect(at(49), 800);
      expect(at(50), 700);
    });

    test('the lowest price wins', () {
      expect(
        priceFor(
          price: 1000,
          promoPrice: 750,
          tiers: const [WholesaleTier(10000, 800)],
          quantity: 10000,
          today: today,
        ),
        750,
      );
      // A variation's own price below the promotion.
      expect(priceFor(price: 700, promoPrice: 750, today: today), 700);
    });

    test('margin over the sale price', () {
      expect(marginPercent(1000, 600), 40);
      expect(marginPercent(1000, 1200), -20);
      expect(marginPercent(0, 100), isNull);
      expect(formatPercent(37.54), '37,5%');
    });

    test('average cost of stock and entry', () {
      // 10 at R$ 5,00 + 10 at R$ 7,00 = R$ 6,00.
      expect(
        averageCost(stock: 10000, cost: 500, quantity: 10000, unitCost: 700),
        600,
      );
      // 3 at R$ 1,00 + 1 at R$ 2,00 = R$ 1,25.
      expect(
        averageCost(stock: 3000, cost: 100, quantity: 1000, unitCost: 200),
        125,
      );
      // Rounded half up: 2 at 0,01 + 1 at 0,02 = 0,0133 -> 0,01.
      expect(averageCost(stock: 2000, cost: 1, quantity: 1000, unitCost: 2), 1);
      // No stock (or negative): the entry's cost.
      expect(
        averageCost(stock: 0, cost: 500, quantity: 5000, unitCost: 900),
        900,
      );
      expect(
        averageCost(stock: -2000, cost: 500, quantity: 5000, unitCost: 900),
        900,
      );
    });

    test('days', () {
      expect(parseDay('31/12/2026'), '2026-12-31');
      expect(parseDay('31122026'), '2026-12-31');
      expect(parseDay('31/02/2026'), isNull);
      expect(parseDay(''), '');
      expect(formatDay('2026-12-31'), '31/12/2026');
    });
  });

  test('photo leftovers in the cache are deleted, nothing else', () async {
    final cache = Directory.systemTemp.createTempSync('cache');
    addTearDown(() => cache.deleteSync(recursive: true));
    const uuid = '3f2b8c1e-9a4d-4e6f-8b7a-1c2d3e4f5a6b';
    File('${cache.path}/scaled_foto.jpg').writeAsStringSync('x');
    File('${cache.path}/${uuid}123456.jpg').writeAsStringSync('x');
    Directory('${cache.path}/$uuid').createSync();
    File('${cache.path}/$uuid/IMG_1.jpg').writeAsStringSync('x');
    File('${cache.path}/outro.txt').writeAsStringSync('x');
    Directory('${cache.path}/code_cache').createSync();
    await cleanPhotoLeftovers(cache: cache);
    expect(
      cache
          .listSync()
          .map((e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
          .toSet(),
      {'outro.txt', 'code_cache'},
    );
  });
}
