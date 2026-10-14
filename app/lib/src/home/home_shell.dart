import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

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
import '../theme/motion.dart';
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
        setState(() => _section = 1);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Sections change with a fade through.
      body: _withReminder(
        PageTransitionSwitcher(
          duration: Motion.of(context, Motion.item),
          transitionBuilder: (child, primary, secondary) =>
              FadeThroughTransition(
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
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _section,
        onDestinationSelected: (i) => setState(() => _section = i),
        // The active section's icon is filled.
        destinations: const [
          NavigationDestination(
            icon: Icon(Symbols.home_rounded),
            selectedIcon: Icon(Symbols.home_rounded, fill: 1),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Symbols.chat_rounded),
            selectedIcon: Icon(Symbols.chat_rounded, fill: 1),
            label: 'Conversas',
          ),
          NavigationDestination(
            icon: Icon(Symbols.group_rounded),
            selectedIcon: Icon(Symbols.group_rounded, fill: 1),
            label: 'Clientes',
          ),
          NavigationDestination(
            icon: Icon(Symbols.inventory_2_rounded),
            selectedIcon: Icon(Symbols.inventory_2_rounded, fill: 1),
            label: 'Produtos',
          ),
          NavigationDestination(
            icon: Icon(Symbols.point_of_sale_rounded),
            selectedIcon: Icon(Symbols.point_of_sale_rounded, fill: 1),
            label: 'Vendas',
          ),
        ],
      ),
    );
  }
}
