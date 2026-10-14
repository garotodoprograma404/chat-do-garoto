import 'detail_pane.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Durations and curves of the app's motion: short, and
/// never to hide a wait.
abstract final class Motion {
  /// A tap, a color or state change.
  static const tap = Duration(milliseconds: 100);

  /// A chip, a checkbox, a switch.
  static const state = Duration(milliseconds: 150);

  /// A message or a list item coming in or going out.
  static const item = Duration(milliseconds: 250);

  /// A sheet opening; closing is faster.
  static const sheetIn = Duration(milliseconds: 300);
  static const sheetOut = Duration(milliseconds: 200);

  /// A list item growing into its page.
  static const container = Duration(milliseconds: 350);

  /// The rare highlight: a sale or a receipt registered.
  static const highlight = Duration(milliseconds: 600);

  static const standard = Easing.standard;
  static const enter = Easing.emphasizedDecelerate;
  static const exit = Easing.emphasizedAccelerate;

  /// Whether the phone asks for no animations ("Remover animações").
  static bool off(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or nothing when animations are off.
  static Duration of(BuildContext context, Duration d) =>
      off(context) ? Duration.zero : d;
}

/// Vibration only where it means something.
abstract final class Haptics {
  /// A sale or a receipt registered.
  static Future<void> success() => _safe(HapticFeedback.successNotification);

  /// Something failed.
  static Future<void> error() => _safe(HapticFeedback.errorNotification);

  /// Recording started, a long-press menu opened.
  static Future<void> start() => _safe(HapticFeedback.lightImpact);

  // A phone without a vibrator (or a test) must not break the action.
  static Future<void> _safe(Future<void> Function() vibrate) async {
    try {
      await vibrate();
    } on Object {
      // nothing to do
    }
  }
}

/// The rare highlight: [child] comes in once with a soft
/// overshoot, or at once when the phone asks for no animations.
class Highlight extends StatefulWidget {
  const Highlight({super.key, required this.child});

  final Widget child;

  @override
  State<Highlight> createState() => _HighlightState();
}

class _HighlightState extends State<Highlight>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.highlight);
  late final _scale = Tween(
    begin: 0.92,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack));
  late final _fade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 0.4, curve: Easing.standard),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isDismissed) {
      Motion.off(context) ? _c.value = 1 : _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: ScaleTransition(scale: _scale, child: widget.child),
  );
}

/// A message or a list item coming in: a short slide up and
/// fade, or nothing when the phone asks for no animations.
class EnterOnce extends StatefulWidget {
  const EnterOnce({super.key, required this.child, this.animate = true});

  final Widget child;

  /// False shows [child] at once (an item that was already there).
  final bool animate;

  @override
  State<EnterOnce> createState() => _EnterOnceState();
}

class _EnterOnceState extends State<EnterOnce>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.item);
  late final _curve = CurvedAnimation(parent: _c, curve: Motion.enter);
  late final _slide = Tween(
    begin: const Offset(0, 0.25),
    end: Offset.zero,
  ).animate(_curve);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isDismissed) {
      !widget.animate || Motion.off(context) ? _c.value = 1 : _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _curve,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}

/// A list row that grows into its page: the page opens
/// growing from where the row is. The row's place is only read on the tap,
/// so a long list pays nothing while scrolling (a container per row did,
/// measured on the Redmi). [row] gets the callback that opens the page;
/// [onClosed] runs when the page closes (to reload the list).
class OpenTile extends StatelessWidget {
  const OpenTile({
    super.key,
    required this.row,
    required this.page,
    this.onClosed,
    this.selectKey,
  });

  /// What marks this row as the open one in the detail pane ("client:5").
  final Object? selectKey;

  final Widget Function(VoidCallback open) row;
  final WidgetBuilder page;
  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context) {
    return row(() async {
      // With a pane beside the list the page opens there.
      if (DetailHost.peek(context) case final pane?) {
        pane.open(page, selected: selectKey);
        return;
      }
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null || !box.hasSize
          ? null
          : box.localToGlobal(Offset.zero) & box.size;
      await Navigator.of(context).push(
        GrowRoute<void>(
          builder: page,
          origin: origin,
          duration: Motion.of(context, Motion.container),
        ),
      );
      onClosed?.call();
    });
  }
}

/// A page that grows from [origin] (a row's place on screen) and shrinks
/// back into it: scale and fade only, no clip (cheap on the GPU).
class GrowRoute<T> extends PageRoute<T> {
  GrowRoute({required this.builder, this.origin, required this.duration});

  final WidgetBuilder builder;
  final Rect? origin;
  final Duration duration;

  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => duration * 0.8;

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final size = MediaQuery.sizeOf(context);
    final o = origin;
    // Grow from the row's center; without it, from the screen's center.
    final alignment = o == null || size.isEmpty
        ? Alignment.center
        : Alignment(
            (o.center.dx / size.width) * 2 - 1,
            (o.center.dy / size.height) * 2 - 1,
          );
    final curve = CurvedAnimation(
      parent: animation,
      curve: Motion.enter,
      reverseCurve: Motion.exit,
    );
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: const Interval(0, 0.5, curve: Easing.standard),
      ),
      child: ScaleTransition(
        alignment: alignment,
        scale: Tween(begin: 0.86, end: 1.0).animate(curve),
        child: child,
      ),
    );
  }
}
