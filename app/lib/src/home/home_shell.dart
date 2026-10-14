import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../backup/backup_controller.dart';
import '../backup/backup_screen.dart';
import '../chats/chat_filters.dart';
import '../chats/chats_controller.dart';
import '../chats/chats_screen.dart';
import '../clients/clients_repository.dart';
import '../clients/clients_screen.dart';
import '../core_bridge/core_bridge.dart';
import '../products/product_photos.dart';
import '../products/products_repository.dart';
import '../products/products_screen.dart';
import '../sales/sales_repository.dart';
import '../sales/sales_screen.dart';
import '../whatsapp/connect_screen.dart';
import '../theme/brand_nav_bar.dart';
import '../theme/detail_pane.dart';
import '../theme/motion.dart';
import '../theme/responsive.dart';
import '../whatsapp/whatsapp_controller.dart';
import 'start_screen.dart';

/// The app's sections:
/// Conversas, Clientes, Produtos and Vendas, with the ⋮ menu in each. The CRM works without WhatsApp
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.bridge,
    required this.whatsapp,
    required this.chats,
    required this.clients,
    this.products,
    this.sales,
    this.photos,
    required this.onOpenSettings,
    this.onOpenPrototype,
    this.backup,
    this.onOpenBackup,
  });

  final CoreBridge bridge;
  final WhatsAppController whatsapp;
  final ChatsController chats;

  /// Null while app.db is opening.
  final ClientsRepository? clients;

  /// Null while app.db is opening.
  final ProductsRepository? products;

  /// Null while app.db is opening.
  final SalesRepository? sales;

  /// The gallery and the camera for product photos.
  final PhotoPicker? photos;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenPrototype;

  /// The backup reminder at the top and what it opens.
  final BackupController? backup;
  final VoidCallback? onOpenBackup;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  // The app opens on Início.
  int _section = 0;

  /// The pane beside the list on wide windows.
  final _detail = DetailController()..emptyTitle = _emptyDetail[0];

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  void _select(int section) {
    if (section == _section) return;
    _detail.clear();
    _detail.emptyTitle = _emptyDetail[section];
    setState(() => _section = section);
  }

  Widget _start() => switch (widget.clients) {
    null => const Scaffold(body: Center(child: CircularProgressIndicator())),
    final clients => StartScreen(
      clients: clients,
      products: widget.products,
      sales: widget.sales,
      photos: widget.photos,
      bridge: widget.bridge,
      onOpenSettings: widget.onOpenSettings,
      // "Ver todas": Conversas with "Sem resposta".
      onOpenWaiting: () {
        widget.chats.setFilter(ChatFilter.waiting);
        _select(1);
      },
    ),
  };

  Widget _conversations() {
    final whatsapp = widget.whatsapp;
    if (!whatsapp.linked) {
      return ConnectScreen(
        controller: whatsapp,
        onOpenPrototype: widget.onOpenPrototype,
        onOpenSettings: widget.onOpenSettings,
      );
    }
    return ChatsScreen(
      bridge: widget.bridge,
      controller: widget.chats,
      status: switch (whatsapp.phase) {
        WhatsAppPhase.connected => 'Conectado',
        _ => 'Conectando…',
      },
      onOpenSettings: widget.onOpenSettings,
      clients: widget.clients,
    );
  }

  Widget _clients() => switch (widget.clients) {
    final repo? => ClientsScreen(
      repo: repo,
      onOpenSettings: widget.onOpenSettings,
      bridge: widget.bridge,
    ),
    null => const Scaffold(body: Center(child: CircularProgressIndicator())),
  };

  Widget _products() => switch (widget.products) {
    final repo? => ProductsScreen(
      repo: repo,
      photos: widget.photos,
      onOpenSettings: widget.onOpenSettings,
    ),
    null => const Scaffold(body: Center(child: CircularProgressIndicator())),
  };

  Widget _sales() => switch (widget.sales) {
    final repo? => SalesScreen(
      ctx: SaleContext(
        sales: repo,
        products: widget.products,
        clients: widget.clients,
        bridge: widget.bridge,
      ),
      onOpenSettings: widget.onOpenSettings,
    ),
    null => const Scaffold(body: Center(child: CircularProgressIndicator())),
  };

  /// The section under the backup reminder, when it shows.
  Widget _withReminder(Widget section) {
    final backup = widget.backup;
    final open = widget.onOpenBackup;
    if (backup == null || open == null) return section;
    return ListenableBuilder(
      listenable: backup,
      builder: (context, _) {
        if (!backup.reminderDue || backup.busy) return section;
        return Column(
          children: [
            BackupReminder(controller: backup, onOpen: open),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: section,
              ),
            ),
          ],
        );
      },
    );
  }

  /// The current section's screen, with the fade between sections
  Widget _sectionPage(BuildContext context) => PageTransitionSwitcher(
    duration: Motion.of(context, Motion.item),
    transitionBuilder: (child, primary, secondary) => FadeThroughTransition(
      animation: primary,
      secondaryAnimation: secondary,
      fillColor: Theme.of(context).colorScheme.surface,
      child: child,
    ),
    child: KeyedSubtree(
      key: ValueKey(_section),
      child: switch (_section) {
        0 => _start(),
        1 => _conversations(),
        2 => _clients(),
        3 => _products(),
        _ => _sales(),
      },
    ),
  );

  static const _emptyDetail = [
    '',
    'Escolha uma conversa',
    'Escolha um cliente',
    'Escolha um produto',
    'Escolha uma venda',
  ];

  @override
  Widget build(BuildContext context) {
    final size = windowClass(context);
    final width = MediaQuery.sizeOf(context).width;
    // The sections with a detail (everything but Início), on wide windows.
    // Conversas without WhatsApp linked shows the connection screen alone.
    final split =
        size == WindowClass.expanded &&
        _section != 0 &&
        (_section != 1 || widget.whatsapp.linked);
    // The list takes a third of the room beside the side bar.
    final railWidth = BrandNavRail.widthFor(
      MediaQuery.textScalerOf(context).scale(10) / 10,
    );
    final listWidth = ((width - railWidth) * 0.34).clamp(340.0, 420.0);

    Widget body;
    if (split) {
      body = DetailHost(
        controller: _detail,
        child: Row(
          children: [
            SizedBox(width: listWidth, child: _sectionPage(context)),
            VerticalDivider(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(child: DetailPane(controller: _detail)),
          ],
        ),
      );
    } else if (size != WindowClass.compact && _section == 0) {
      // Início is a single column: it stays easy to read on a big window.
      body = ContentWidth(child: _sectionPage(context));
    } else {
      body = _sectionPage(context);
    }

    if (size == WindowClass.compact) {
      return Scaffold(
        body: _withReminder(body),
        bottomNavigationBar: BrandNavBar(
          items: brandSections,
          selected: _section,
          onSelected: _select,
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          BrandNavRail(
            items: brandSections,
            selected: _section,
            onSelected: _select,
            onSettings: widget.onOpenSettings,
          ),
          Expanded(child: _withReminder(body)),
        ],
      ),
    );
  }
}
