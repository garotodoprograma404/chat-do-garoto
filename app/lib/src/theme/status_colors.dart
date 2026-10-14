import 'package:flutter/material.dart';

/// Situations with a fixed meaning across the app: color
/// always comes with text, never alone.
enum Situation {
  /// Paid, up to date.
  ok,

  /// To receive, open.
  open,

  /// Overdue.
  overdue,

  /// Cancelled, inactive.
  off,
}

/// The colors of each [Situation], light and dark.
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({required this.colors});

  /// For each situation: (text and icon, background).
  final Map<Situation, (Color, Color)> colors;

  static const _light = AppStatusColors(
    colors: {
      Situation.ok: (Color(0xFF0A7A3D), Color(0xFFD3F5E0)),
      Situation.open: (Color(0xFF7A5600), Color(0xFFFBEBC4)),
      Situation.overdue: (Color(0xFFB3261E), Color(0xFFFFDAD6)),
      Situation.off: (Color(0xFF55636A), Color(0xFFE3E9EC)),
    },
  );

  static const _dark = AppStatusColors(
    colors: {
      Situation.ok: (Color(0xFF39FF88), Color(0xFF0F3D22)),
      Situation.open: (Color(0xFFF5C542), Color(0xFF3D2F0C)),
      Situation.overdue: (Color(0xFFFF8A8A), Color(0xFF4A1B1B)),
      Situation.off: (Color(0xFF9AA4AE), Color(0xFF1F2933)),
    },
  );

  static AppStatusColors of(Brightness b) =>
      b == Brightness.dark ? _dark : _light;

  /// The colors of [s] in the current theme.
  static (Color, Color) resolve(BuildContext context, Situation s) {
    final ext =
        Theme.of(context).extension<AppStatusColors>() ??
        of(Theme.of(context).brightness);
    return ext.colors[s]!;
  }

  @override
  AppStatusColors copyWith({Map<Situation, (Color, Color)>? colors}) =>
      AppStatusColors(colors: colors ?? this.colors);

  @override
  AppStatusColors lerp(AppStatusColors? other, double t) {
    if (other == null) return this;
    return AppStatusColors(
      colors: {
        for (final s in Situation.values)
          s: (
            Color.lerp(colors[s]!.$1, other.colors[s]!.$1, t)!,
            Color.lerp(colors[s]!.$2, other.colors[s]!.$2, t)!,
          ),
      },
    );
  }
}

/// A situation as a small pill: "Paga", "A receber", "Vencida"…
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, this.situation, {super.key});

  final String label;
  final Situation situation;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = AppStatusColors.resolve(context, situation);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium!
              .copyWith(color: fg, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
