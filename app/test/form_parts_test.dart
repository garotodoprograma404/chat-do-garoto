// Masks and the "Mais detalhes" group.
import 'package:chat_do_garoto/src/products/money.dart';
import 'package:chat_do_garoto/src/theme/form_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

String _type(TextInputFormatter mask, String old, String typed) => mask
    .formatEditUpdate(
      TextEditingValue(text: old),
      TextEditingValue(text: typed),
    )
    .text;

void main() {
  test('money: the digits are cents, pushed in from the right', () {
    expect(_type(Masks.money, '', '1'), r'R$ 0,01');
    expect(_type(Masks.money, r'R$ 0,01', r'R$ 0,012'), r'R$ 0,12');
    expect(_type(Masks.money, r'R$ 0,12', r'R$ 0,129'), r'R$ 1,29');
    expect(_type(Masks.money, r'R$ 1,29', r'R$ 1,290'), r'R$ 12,90');
    expect(_type(Masks.money, '', '123456'), r'R$ 1.234,56');
    expect(_type(Masks.money, r'R$ 12,90', r'R$ 12,9'), r'R$ 1,29');
    expect(_type(Masks.money, r'R$ 0,01', ''), '');
    expect(_type(Masks.money, '', '12,90'), r'R$ 12,90'); // pasted
    expect(parseMoney(_type(Masks.money, '', '1290')), 1290);
    expect(Masks.money.apply('12,90'), r'R$ 12,90');
  });

  test('date, phone and CPF/CNPJ', () {
    expect(_type(Masks.date, '', '13102026'), '13/10/2026');
    expect(_type(Masks.date, '', '0503'), '05/03');
    expect(_type(Masks.date, '13/10/2026', '13/10/20261'), '13/10/2026');
    // Deleting the slash deletes the digit before it.
    expect(_type(Masks.date, '13/10/', '13/10'), '13/1');
    expect(_type(Masks.phone, '', '5511987654321'), '+55 11 98765-4321');
    expect(_type(Masks.phone, '', '551134567890'), '+55 11 3456-7890');
    expect(_type(Masks.phone, '', '55'), '+55');
    expect(_type(Masks.document, '', '52998224725'), '529.982.247-25');
    expect(_type(Masks.document, '', '11222333000181'), '11.222.333/0001-81');
    expect(_type(Masks.document, '', '5299'), '529.9');
  });

  testWidgets('the group shows the summary closed and the fields open', (
    tester,
  ) async {
    var open = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DetailsGroup(
              title: 'Promoção',
              summary: r'R$ 9,90 até 31/10',
              open: open,
              onToggle: () => setState(() => open = !open),
              children: const [Text('campo')],
            ),
          ),
        ),
      ),
    );
    expect(find.text(r'R$ 9,90 até 31/10'), findsOneWidget);
    expect(find.text('campo'), findsNothing);
    await tester.tap(find.text('Promoção'));
    await tester.pumpAndSettle();
    expect(find.text('campo'), findsOneWidget);
    expect(find.text(r'R$ 9,90 até 31/10'), findsNothing);
  });
}
