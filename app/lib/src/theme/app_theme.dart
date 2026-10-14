import 'package:flutter/material.dart';

import 'status_colors.dart';

/// The app's own look: the Garoto do Programa brand (neon green and pink on
/// the channel's dark background), the bundled fonts, its own shapes and
/// density. Dark first; the light theme keeps the same colors, darkened to
/// keep the contrast. Colors with a meaning (overdue, paid) live in
/// `status_colors.dart` and may leave the brand palette.
abstract final class AppTheme {
  /// Body text, lists and numbers.
  static const textFont = 'AtkinsonHyperlegibleNext';

  /// Titles and big amounts: the channel's mono font.
  static const displayFont = 'UbuntuSansMono';

  /// Corner radii.
  static const radiusChip = 8.0;
  static const radiusField = 12.0;
  static const radiusHighlight = 20.0;
  static const radiusSheet = 28.0;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ColorScheme scheme(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  // Green leads (buttons, active item, amounts); pink is the signature
  // accent (tertiary); the secondary roles are the quiet green tint used
  // for selected chips and the active tab.
  static const _dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF39FF88),
    onPrimary: Color(0xFF04210F),
    primaryContainer: Color(0xFF0F3D22),
    onPrimaryContainer: Color(0xFFB9FFD6),
    secondary: Color(0xFF8FD9AD),
    onSecondary: Color(0xFF06210F),
    secondaryContainer: Color(0xFF16301F),
    onSecondaryContainer: Color(0xFFE6EDF3),
    tertiary: Color(0xFFFF2E88),
    onTertiary: Color(0xFF2A0016),
    tertiaryContainer: Color(0xFF3A1226),
    onTertiaryContainer: Color(0xFFFFC2DC),
    error: Color(0xFFFF6B6B),
    onError: Color(0xFF2A0606),
    errorContainer: Color(0xFF4A1B1B),
    onErrorContainer: Color(0xFFFFC9C9),
    surface: Color(0xFF0D1117),
    onSurface: Color(0xFFE6EDF3),
    onSurfaceVariant: Color(0xFF9AA4AE),
    surfaceDim: Color(0xFF0A0E13),
    surfaceBright: Color(0xFF212C3A),
    surfaceContainerLowest: Color(0xFF0A0E13),
    surfaceContainerLow: Color(0xFF111821),
    surfaceContainer: Color(0xFF151D28),
    surfaceContainerHigh: Color(0xFF1A2330),
    surfaceContainerHighest: Color(0xFF212C3A),
    outline: Color(0xFF4A5666),
    outlineVariant: Color(0xFF26303D),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE6EDF3),
    onInverseSurface: Color(0xFF0D1117),
    inversePrimary: Color(0xFF0A7A3D),
    surfaceTint: Color(0xFF39FF88),
  );

  static const _light = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF0A7A3D),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFBDF9D4),
    onPrimaryContainer: Color(0xFF04301A),
    secondary: Color(0xFF2F6B49),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFDDF3E6),
    onSecondaryContainer: Color(0xFF0D1117),
    tertiary: Color(0xFFD6006E),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFFDCEA),
    onTertiaryContainer: Color(0xFF4A0027),
    error: Color(0xFFC62828),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFF6F8FA),
    onSurface: Color(0xFF0D1117),
    onSurfaceVariant: Color(0xFF4A5562),
    surfaceDim: Color(0xFFDCE2E8),
    surfaceBright: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFEDF1F5),
    surfaceContainerHigh: Color(0xFFE6EBF0),
    surfaceContainerHighest: Color(0xFFDEE4EA),
    outline: Color(0xFF6B7785),
    outlineVariant: Color(0xFFD0D7DE),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF0D1117),
    onInverseSurface: Color(0xFFE6EDF3),
    inversePrimary: Color(0xFF39FF88),
    surfaceTint: Color(0xFF0A7A3D),
  );

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
      displayLarge: s(displayFont, 48, 54, FontWeight.w800),
      displayMedium: s(displayFont, 40, 46, FontWeight.w800),
      // The big amount of a sale, a receipt or a total.
      displaySmall: s(displayFont, 34, 40, FontWeight.w800),
      headlineLarge: s(displayFont, 30, 36, FontWeight.w800),
      headlineMedium: s(displayFont, 26, 32, FontWeight.w800),
      headlineSmall: s(displayFont, 24, 30, FontWeight.w800),
      titleLarge: s(displayFont, 22, 28, FontWeight.w800),
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
