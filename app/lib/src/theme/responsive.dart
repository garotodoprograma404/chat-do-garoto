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

/// Widest the messages column of a conversation goes (bubbles and the
/// message box), centered in the pane.
const chatWidth = 820.0;

/// Widest a single message bubble goes.
const bubbleWidth = 560.0;

/// Widest a form or a screen opened over the others goes.
const formWidth = 640.0;

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
            builder: (context, box) => box.maxWidth <= formWidth
                ? child
                : ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: ContentWidth(
                      maxWidth: formWidth,
                      // A thin edge on each side: the page reads as one
                      // panel, bars included.
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.symmetric(
                            vertical: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                            ),
                          ),
                        ),
                        child: child,
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
    return Padding(
      padding: padding,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(spacing: 8, runSpacing: 8, children: children),
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
