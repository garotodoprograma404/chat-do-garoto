import 'package:flutter/material.dart';

import 'status_colors.dart';

/// The app's own look: petroleum with ipê yellow, the
/// bundled fonts, its own shapes and density, light and dark.
abstract final class AppTheme {
  /// The brand color: deep petroleum.
  static const brand = Color(0xFF0F4C5C);

  /// The rare highlight: ipê yellow.
  static const ipe = Color(0xFFE8B10C);

  /// Body text, lists and numbers.
  static const textFont = 'AtkinsonHyperlegibleNext';

  /// Titles and big amounts.
  static const displayFont = 'BricolageGrotesque';

  /// Corner radii.
  static const radiusChip = 8.0;
  static const radiusField = 12.0;
  static const radiusHighlight = 20.0;
  static const radiusSheet = 28.0;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ColorScheme scheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    // The ipê palette takes the tertiary roles, for the rare highlights.
    final ipeScheme = ColorScheme.fromSeed(
      seedColor: ipe,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    return base.copyWith(
      tertiary: ipeScheme.primary,
      onTertiary: ipeScheme.onPrimary,
      tertiaryContainer: ipeScheme.primaryContainer,
      onTertiaryContainer: ipeScheme.onPrimaryContainer,
    );
  }

  static TextTheme _text(ColorScheme c) {
    TextStyle s(
      String family,
      double size,
      double line,
      FontWeight weight, {
      double spacing = 0,
    }) => TextStyle(
      fontFamily: family,
      fontSize: size,
      height: line / size,
      fontWeight: weight,
      letterSpacing: spacing,
      color: c.onSurface,
    );
    return TextTheme(
      displayLarge: s(displayFont, 48, 54, FontWeight.w700),
      displayMedium: s(displayFont, 40, 46, FontWeight.w700),
      // The big amount of a sale, a receipt or a total.
      displaySmall: s(displayFont, 34, 40, FontWeight.w700),
      headlineLarge: s(displayFont, 30, 36, FontWeight.w700),
      headlineMedium: s(displayFont, 26, 32, const FontWeight(650)),
      headlineSmall: s(displayFont, 24, 30, const FontWeight(650)),
      titleLarge: s(displayFont, 22, 28, FontWeight.w700),
      titleMedium: s(textFont, 16, 22, FontWeight.w600),
      titleSmall: s(textFont, 14, 20, FontWeight.w600),
      bodyLarge: s(textFont, 16, 22, FontWeight.w400),
      bodyMedium: s(textFont, 14, 20, FontWeight.w400),
      bodySmall: s(textFont, 12, 16, FontWeight.w400),
      labelLarge: s(textFont, 14, 20, FontWeight.w600),
      labelMedium: s(textFont, 12, 16, FontWeight.w600),
      labelSmall: s(textFont, 11, 16, FontWeight.w600, spacing: 0.2),
    );
  }

  static ThemeData _build(Brightness brightness) {
    final c = scheme(brightness);
    final text = _text(c);
    const pill = StadiumBorder();
    final field = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusField),
      borderSide: BorderSide(color: c.outline),
    );
    final buttonPadding = const EdgeInsets.symmetric(horizontal: 20);
    const buttonSize = Size(64, 48);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: c,
      fontFamily: textFont,
      textTheme: text,
      scaffoldBackgroundColor: c.surface,
      extensions: [AppStatusColors.of(brightness)],
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: c.surfaceContainer,
        indicatorColor: c.secondaryContainer,
        indicatorShape: pill,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium!.copyWith(
            color: states.contains(WidgetState.selected)
                ? c.onSurface
                : c.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: pill,
          minimumSize: buttonSize,
          padding: buttonPadding,
          textStyle: text.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: pill,
          minimumSize: buttonSize,
          padding: buttonPadding,
          elevation: 0,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: pill,
          minimumSize: buttonSize,
          padding: buttonPadding,
          side: BorderSide(color: c.outline),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: pill,
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 2,
        extendedTextStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusChip),
        ),
        labelStyle: text.labelLarge,
        side: BorderSide(color: c.outlineVariant),
        selectedColor: c.secondaryContainer,
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: field,
        enabledBorder: field,
        focusedBorder: field.copyWith(
          borderSide: BorderSide(color: c.primary, width: 2),
        ),
        errorBorder: field.copyWith(borderSide: BorderSide(color: c.error)),
        focusedErrorBorder: field.copyWith(
          borderSide: BorderSide(color: c.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: c.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusHighlight),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 10,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodyMedium!.copyWith(color: c.onSurfaceVariant),
        leadingAndTrailingTextStyle: text.labelLarge,
        iconColor: c.onSurfaceVariant,
      ),
      dividerTheme: DividerThemeData(
        color: c.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: c.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(radiusSheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSheet),
        ),
        titleTextStyle: text.headlineSmall,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusField),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusField),
        ),
        textStyle: text.bodyLarge,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
    );
  }
}
