// The app's own look.
import 'dart:math';

import 'package:chat_do_garoto/src/theme/app_theme.dart';
import 'package:chat_do_garoto/src/theme/components.dart';
import 'package:chat_do_garoto/src/theme/motion.dart';
import 'package:chat_do_garoto/src/theme/status_colors.dart';
import 'package:chat_do_garoto/src/theme/theme_controller.dart';
import 'package:chat_do_garoto/src/storage/key_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG contrast ratio between two colors.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  group('appearance', appearanceTests);
  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    group(name, () {
      test('the brand, the fonts and the shapes', () {
        final c = theme.colorScheme;
        // The brand green is bright on dark and darkened on light, where it
        // must still read on the background.
        if (theme.brightness == Brightness.light) {
          expect(contrast(c.primary, c.surface), greaterThanOrEqualTo(4.5));
        } else {
          expect(c.primary.computeLuminance(), greaterThan(0.3));
        }
        expect(contrast(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
        expect(contrast(c.onSurface, c.surface), greaterThanOrEqualTo(7));
        expect(theme.textTheme.displaySmall!.fontFamily, AppTheme.displayFont);
        expect(theme.textTheme.bodyMedium!.fontFamily, AppTheme.textFont);
        expect(
          theme.navigationBarTheme.labelBehavior,
          NavigationDestinationLabelBehavior.alwaysShow,
        );
        final button = theme.filledButtonTheme.style!.shape!.resolve({});
        expect(button, isA<StadiumBorder>());
        expect(
          theme.filledButtonTheme.style!.minimumSize!.resolve({})!.height,
          48,
        );
      });

      test('situations are readable: text on its background', () {
        final ext = theme.extension<AppStatusColors>()!;
        for (final s in Situation.values) {
          final (fg, bg) = ext.colors[s]!;
          expect(
            contrast(fg, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$s on $name',
          );
        }
      });
    });
  }

  testWidgets('pills, amounts and empty screens in both themes', (
    tester,
  ) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                const StatusPill('Vencida', Situation.overdue),
                const MoneyText('R\$ 1.234,56'),
                Expanded(
                  child: EmptyState(
                    title: 'Nenhuma venda ainda',
                    message: 'Registre a primeira venda.',
                    action: 'Nova venda',
                    onAction: () => tapped = true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Vencida'), findsOneWidget);
      final money = tester.widget<Text>(find.text('R\$ 1.234,56'));
      expect(
        money.style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(money.style!.fontFamily, AppTheme.displayFont);
      await tester.tap(find.text('Nova venda'));
      expect(tapped, isTrue);
    }
  });

  test('initials', () {
    expect(InitialsAvatar.initials('Ana Souza'), 'AS');
    expect(InitialsAvatar.initials('ana'), 'A');
    expect(InitialsAvatar.initials('  Maria  da Silva '), 'MS');
    expect(InitialsAvatar.initials('5511999990000'), '#');
    expect(InitialsAvatar.initials('Érica'), 'É');
    expect(InitialsAvatar.initials(''), '#');
  });

  testWidgets('no animation when the phone asks for none', (tester) async {
    late Duration on, off;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          on = Motion.of(context, Motion.item);
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            off = Motion.of(context, Motion.item);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(on, Motion.item);
    expect(off, Duration.zero);
  });
}

class _Vault implements KeyVault {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String key) async => value = key;

  @override
  Future<void> delete() async => value = null;
}

void appearanceTests() {
  test('the choice is kept in the vault', () async {
    final vault = _Vault();
    final c = ThemeController(store: vault);
    await c.load();
    // The brand is dark: that is the look until the user chooses another.
    expect(c.mode, ThemeMode.dark);
    await c.set(ThemeMode.light);
    expect(vault.value, 'light');
    final again = ThemeController(store: vault);
    await again.load();
    expect(again.mode, ThemeMode.light);
    await again.set(ThemeMode.system);
    await again.load();
    expect(again.mode, ThemeMode.system);
    vault.value = 'nonsense';
    await again.load();
    expect(again.mode, ThemeMode.dark);
  });

  testWidgets('Aparência changes the look at once', (tester) async {
    final c = ThemeController(store: _Vault());
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: c,
        builder: (context, _) => MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: c.mode,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => pickThemeMode(context, c),
                child: Text(themeModeLabel(c.mode)),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Escuro'), findsOneWidget);
    await tester.tap(find.text('Escuro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claro'));
    await tester.pumpAndSettle();
    expect(c.mode, ThemeMode.light);
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.light,
    );
  });
}
