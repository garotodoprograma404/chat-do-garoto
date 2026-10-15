import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand_mark.dart';
import 'responsive.dart';

/// What the detail pane shows and what is selected in the list. Lists ask [open] instead of pushing a full-screen page when a pane
/// exists beside them.
class DetailController extends ChangeNotifier {
  /// The pane's own navigator: pages opened inside the pane stack here.
  final navigatorKey = GlobalKey<NavigatorState>();

  WidgetBuilder? _page;
  Object? _selected;
  bool _wide = false;

  /// What the empty pane asks ("Escolha uma conversa"); the shell sets it
  /// for each section.
  String _emptyTitle = '';
  String get emptyTitle => _emptyTitle;
  set emptyTitle(String value) {
    if (value == _emptyTitle) return;
    _emptyTitle = value;
    notifyListeners();
  }

  int _serial = 0;
  final _changes = _Ping();

  /// The page shown, or null for the empty pane.
  WidgetBuilder? get page => _page;

  /// A key the list marks as open ("client:5"), or null.
  Object? get selected => _selected;

  /// Whether the page uses the pane's whole width (a conversation); the
  /// others stay at a readable width, centered.
  bool get wide => _wide;

  /// Changes whenever the pane shows another page: tells the page apart.
  int get serial => _serial;

  /// Pinged when something inside the pane may have changed the data (a
  /// page opened by the pane closed), so the list can reload.
  Listenable get changes => _changes;

  /// Shows [page] in the pane, replacing what was there (and anything
  /// stacked on it). [selected] marks the row in the list.
  void open(WidgetBuilder page, {Object? selected, bool wide = false}) {
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    _page = page;
    _selected = selected;
    _wide = wide;
    _serial++;
    notifyListeners();
    _changes.ping();
  }

  /// Empties the pane (back to "choose one").
  void clear() {
    if (_page == null) return;
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    _page = null;
    _selected = null;
    _serial++;
    notifyListeners();
  }

  /// Something inside the pane closed: the list may be out of date.
  void dataMayHaveChanged() => _changes.ping();

  @override
  void dispose() {
    _changes.dispose();
    super.dispose();
  }
}

class _Ping extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// Widest a detail page (a client, a product, a sale) goes in the pane.
const paneWidth = 1600.0;

/// Tells the lists below it that a detail pane exists.
class DetailHost extends InheritedNotifier<DetailController> {
  const DetailHost({
    super.key,
    required DetailController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The pane's controller, or null when pages open full screen. Rebuilds
  /// the caller when the selection changes.
  static DetailController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DetailHost>()?.notifier;

  /// The pane's controller without listening to it (for taps).
  static DetailController? peek(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DetailHost>()?.notifier;

  /// Whether [key] is the row open in the pane.
  static bool isSelected(BuildContext context, Object key) =>
      maybeOf(context)?.selected == key;
}

/// For a list's State: reloads when the detail pane beside it may have
/// changed data. Call [attach] in didChangeDependencies and [dispose] in
/// dispose.
class DetailReloader {
  Listenable? _changes;
  VoidCallback? _reload;

  void attach(BuildContext context, VoidCallback reload) {
    final next = DetailHost.maybeOf(context)?.changes;
    _reload = reload;
    if (identical(next, _changes)) return;
    _changes?.removeListener(_fire);
    _changes = next;
    next?.addListener(_fire);
  }

  void _fire() => _reload?.call();

  void dispose() => _changes?.removeListener(_fire);
}

/// The right-hand pane: its own navigator, so the pages the detail opens
/// (a client's sale, an edit form) stack inside it with a back arrow.
class DetailPane extends StatelessWidget {
  const DetailPane({super.key, required this.controller});

  final DetailController controller;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        // Esc: back one page inside the pane, or close the detail.
        const SingleActivator(LogicalKeyboardKey.escape): () {
          final nav = controller.navigatorKey.currentState;
          if (nav != null && nav.canPop()) {
            nav.pop();
            controller.dataMayHaveChanged();
          } else {
            controller.clear();
          }
        },
      },
      child: ClipRect(
        child: Navigator(
          key: controller.navigatorKey,
          observers: [_PaneObserver(controller)],
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (context, _, _) => ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final page = controller.page;
                if (page == null) {
                  return _EmptyDetail(title: controller.emptyTitle);
                }
                // Focus on the new page, so Esc reaches the pane's shortcut.
                final shown = Focus(
                  autofocus: true,
                  skipTraversal: true,
                  child: Builder(builder: page),
                );
                return KeyedSubtree(
                  key: ValueKey(controller.serial),
                  child: controller.wide
                      ? shown
                      : ContentWidth(maxWidth: paneWidth, child: shown),
                );
              },
            ),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        ),
      ),
    );
  }
}

/// Pings the list when a page opened inside the pane closes.
class _PaneObserver extends NavigatorObserver {
  _PaneObserver(this.controller);

  final DetailController controller;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      controller.dataMayHaveChanged();
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return ColoredBox(
      color: c.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 96),
            const SizedBox(height: 24),
            SemicolonText(title, style: t.titleLarge),
          ],
        ),
      ),
    );
  }
}
