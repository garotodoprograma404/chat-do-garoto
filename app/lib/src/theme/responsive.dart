import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;

/// How much room the window has. The width decides, never
/// the operating system: a tablet and a small desktop window behave alike.
enum WindowClass {
  /// Phones, under 600: the bottom bar and one column.
  compact,

  /// Tablets standing up, 600 to 899: the side bar and one column.
  medium,

  /// Wide windows, 900 and up: the side bar, a list and its detail.
  expanded;

  static WindowClass of(double width) => width < compactMax
      ? compact
      : width < mediumMax
      ? medium
      : expanded;

  static const compactMax = 600.0;
  static const mediumMax = 900.0;
}

/// The class of the window [context] is in.
WindowClass windowClass(BuildContext context) =>
    WindowClass.of(MediaQuery.sizeOf(context).width);

/// Side margin of the content: 16 on phones, 24 on wider windows.
double pageMargin(BuildContext context) =>
    windowClass(context) == WindowClass.compact ? 16 : 24;

/// Widest a full-width reading screen goes (Início, Configurações).
const readingWidth = 760.0;

/// Widest the messages column of a conversation goes (header, bubbles and
/// message box share it); on a wider pane the extra room is left on both
/// sides, with the brand dots, and everything stays on the same edges.
const chatColumnWidth = 1040.0;

/// Widest a panel of cards goes (Configurações, Backup): bar and cards stay
/// together, centered, on a very wide window.
const panelWidth = 1280.0;

/// Widest the Início panel goes; on a wider window it stays centered and
/// the title above it moves to the same edge ([sideRoom]).
const dashboardWidth = 1680.0;

/// The room left on each side of content [max] wide in [width]: what a
/// header adds to its own margin to sit on the content's edge.
double sideRoom(double width, double max) =>
    ((width - max) / 2).clamp(0.0, double.infinity);

/// How wide a message bubble goes in a column [available] wide: most of it
/// on a phone, about two thirds on a big window, never a wall of text.
double bubbleMaxWidth(double available) =>
    available < 480 ? available * 0.86 : (available * 0.72).clamp(0, 680);

/// Widest a form or a screen opened over the others goes.
const formWidth = 640.0;

/// Tallest one goes: a form opened over a big window is a card in the
/// middle, not a strip from top to bottom.
const formHeight = 780.0;

/// Keeps [child] at most [maxWidth] wide, centered: text and forms stay
/// easy to read on big windows. Narrow windows are untouched.
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    this.maxWidth = readingWidth,
    required this.child,
  });

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// The name of the routes that use the whole window width (a conversation,
/// a photo, a video); every other page opened over the others is limited to
/// [formWidth] on big windows.
const wideRouteName = 'wide';

/// Marks a screen that uses the whole window width (a conversation).
abstract interface class WideScreen {}

/// The route for [screen] opened over the others: wide screens keep the
/// whole width, the rest stay at a readable width on big windows.
Route<T> appRoute<T>(Widget screen) => MaterialPageRoute<T>(
  settings: screen is WideScreen
      ? const RouteSettings(name: wideRouteName)
      : null,
  builder: (_) => screen,
);

/// Wraps another page transition and keeps the page at a readable width:
/// forms and detail screens stay [formWidth] wide, centered, on big
/// windows. Phones are untouched.
class WidthLimitedTransitions extends PageTransitionsBuilder {
  const WidthLimitedTransitions(this.inner);

  final PageTransitionsBuilder inner;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // The first page of a navigator (the app itself, the detail pane) is
    // never limited: only pages opened over it are.
    final limited = route.isFirst || route.settings.name == wideRouteName
        ? child
        : LayoutBuilder(
            builder: (context, box) => box.maxWidth <= formWidth + 64
                ? child
                : ColoredBox(
                    // A step darker than the page: the card stands out.
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    // The page is a card in the middle, like a dialog: no
                    // taller than [formHeight], so on a tall monitor a short
                    // form is not a long empty strip.
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: formWidth,
                            maxHeight: formHeight,
                          ),
                          // A thin edge and rounded corners, drawn over the
                          // page: the page itself is opaque.
                          child: DecoratedBox(
                            position: DecorationPosition.foreground,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          );
    return inner.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      limited,
    );
  }
}

/// Every platform's own page transition, made [WidthLimitedTransitions].
PageTransitionsTheme limitedPageTransitions() => PageTransitionsTheme(
  builders: {
    for (final platform in TargetPlatform.values)
      platform: WidthLimitedTransitions(_defaultTransition(platform)),
  },
);

PageTransitionsBuilder _defaultTransition(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.iOS ||
      TargetPlatform.macOS => const CupertinoPageTransitionsBuilder(),
      _ => const ZoomPageTransitionsBuilder(),
    };

/// A row of filter chips. Phones keep one scrolling line (a finger drags
/// it); wider windows wrap onto more lines, so nothing hides off the edge
/// where a mouse cannot reach.
class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    required this.children,
  });

  final EdgeInsetsGeometry padding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (windowClass(context) == WindowClass.compact) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(spacing: 8, children: children),
      );
    }
    // A mouse is precise: the chips are a little lower, so the lines of
    // filters take less of the list.
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Theme(
          data: theme.copyWith(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Wrap(spacing: 8, runSpacing: 8, children: children),
        ),
      ),
    );
  }
}

/// Lets a mouse or a trackpad drag scrollables, as a finger does: on the
/// desktop the default would leave them still.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
