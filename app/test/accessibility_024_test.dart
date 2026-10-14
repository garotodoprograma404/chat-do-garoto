// The short forms with large text and in the dark theme, groups open
import 'package:chat_do_garoto/src/clients/client_form_screen.dart';
import 'package:chat_do_garoto/src/products/product_form_screen.dart';
import 'package:chat_do_garoto/src/products/product_photos.dart';
import 'package:chat_do_garoto/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_clients_repository.dart';
import 'support/fake_products_repository.dart';

class _NoPhotos implements PhotoPicker {
  @override
  Future<Never> pick(PhotoSource source) => throw UnimplementedError();
}

const _productGroups = [
  'Código de barras e código interno',
  'Custo e lucro',
  'Promoção',
  'Atacado',
  'Estoque e validade',
  'Variações (tamanho, cor…)',
  'Categoria, marca e descrição',
  'Produto ou serviço',
];

void main() {
  for (final dark in [false, true]) {
    testWidgets('200% text, ${dark ? 'dark' : 'light'} theme', (tester) async {
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      Future<void> pump(Widget home) async {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(2),
            ),
            child: MaterialApp(
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: home,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pump(
        ProductFormScreen(repo: FakeProductsRepository(), photos: _NoPhotos()),
      );
      expect(tester.takeException(), isNull, reason: 'produto');
      for (final group in _productGroups) {
        await tester.scrollUntilVisible(
          find.text(group),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text(group));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: group);
      }

      await pump(ClientFormScreen(repo: FakeClientsRepository()));
      await tester.tap(find.text('Mais detalhes'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'cliente');
    });
  }
}
