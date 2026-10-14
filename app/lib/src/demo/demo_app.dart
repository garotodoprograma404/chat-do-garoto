import 'package:drift/native.dart';
import 'package:flutter/material.dart';

import '../backup/backup_controller.dart';
import '../backup/backup_platform.dart';
import '../backup/backup_screen.dart';
import '../lock/lock_controller.dart';
import '../lock/security_platform.dart';
import '../settings/settings_screen.dart';
import '../chats/chat_prefs.dart';
import '../chats/chats_controller.dart';
import '../clients/clients_repository.dart';
import '../home/crm_scope.dart';
import '../home/home_shell.dart';
import '../platform/connection_keeper.dart';
import '../platform/wa_key.dart';
import '../products/product_photos.dart';
import '../products/products_repository.dart';
import '../sales/sales_repository.dart';
import '../storage/app_database.dart';
import '../storage/form_drafts.dart';
import '../storage/key_vault.dart';
import '../theme/app_theme.dart';
import '../theme/brand_mark.dart';
import '../theme/responsive.dart';
import '../theme/theme_controller.dart';
import '../whatsapp/whatsapp_controller.dart';
import 'demo_core_bridge.dart';
import 'demo_seed.dart';

/// Lets the first screens open the demo. Present above the real
/// app only; screens without it simply do not show the button.
class DemoLauncher extends InheritedWidget {
  const DemoLauncher({super.key, required this.enter, required super.child});

  /// Leaves the real app's screens and opens the demo.
  final VoidCallback enter;

  static DemoLauncher? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoLauncher>();

  @override
  bool updateShouldNotify(DemoLauncher old) => old.enter != enter;
}

/// "Explorar sem conectar": the button that opens the demo, shown only
/// where a [DemoLauncher] exists.
class DemoButton extends StatelessWidget {
  const DemoButton({super.key});

  @override
  Widget build(BuildContext context) {
    final launcher = DemoLauncher.maybeOf(context);
    if (launcher == null) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: launcher.enter,
      icon: const BrandMark(size: 20),
      label: const Text('Explorar sem conectar'),
    );
  }
}

/// Everything the demo runs on, all in memory: its own
/// WhatsApp, its own app.db and repositories. The real app's files, vault
/// and connection are never opened by it.
class DemoSession {
  DemoSession._(this.bridge, this.db)
    : clients = DriftClientsRepository(db),
      products = DriftProductsRepository(db),
      sales = DriftSalesRepository(db),
      chatPrefs = DriftChatPrefs(db),
      drafts = DriftFormDrafts(db) {
    whatsapp = WhatsAppController(
      bridge: bridge,
      sessionPath: () async => '',
      keeper: const _NoKeeper(),
      keys: const _NoKey(),
    );
    chats = ChatsController(bridge: bridge);
    lock = LockController(
      bridge: bridge,
      security: const _NoBiometrics(),
      vault: (_) => MemoryKeyVault(),
    );
    backup = BackupController(
      bridge: bridge,
      platform: const _NoBackupPlatform(),
      workDir: () async => '',
      copyAppDb: (path, key) async {},
      restoreAppDb: (path, key) async {},
      appSchema: () => AppDatabase.currentVersion,
      lastStore: MemoryKeyVault(),
      intervalStore: MemoryKeyVault(),
    );
  }

  final DemoCoreBridge bridge;
  final AppDatabase db;
  final ClientsRepository clients;
  final ProductsRepository products;
  final SalesRepository sales;
  final ChatPrefs chatPrefs;
  final FormDrafts drafts;
  late final WhatsAppController whatsapp;
  late final ChatsController chats;

  /// A PIN lock that never asks (the demo opens already unlocked), so the
  /// real Configurações screen works.
  late final LockController lock;

  /// A backup that goes nowhere: the screen is the real one.
  late final BackupController backup;
  final photos = DevicePhotoPicker();

  /// Builds the demo: an in-memory app.db filled with the demo's store,
  /// and the demo's conversations.
  static Future<DemoSession> open({DemoCoreBridge? bridge}) async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    final session = DemoSession._(bridge ?? DemoCoreBridge(), db);
    await seedDemo(
      clients: session.clients,
      products: session.products,
      sales: session.sales,
      now: DateTime.now(),
    );
    await session.whatsapp.start();
    session.chats.start();
    await session.lock.start();
    await session.lock.createPin('123456', '123456');
    return session;
  }

  /// Ends the demo: everything it built goes away with the memory.
  Future<void> close() async {
    lock.dispose();
    backup.dispose();
    chats.dispose();
    whatsapp.dispose();
    bridge.dispose();
    await db.close();
  }
}

/// A vault that lives in memory: the demo's choices never reach the
/// system vault.
class MemoryKeyVault implements KeyVault {
  MemoryKeyVault([this._value]);

  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String key) async => _value = key;

  @override
  Future<void> delete() async => _value = null;
}

class _NoBiometrics implements SecurityPlatform {
  const _NoBiometrics();

  @override
  Future<bool> biometricsAvailable() async => false;

  @override
  Future<String> enrollBiometrics(String secretHex) async => secretHex;

  @override
  Future<String> unlockWithBiometrics(String blob) async => blob;

  @override
  Future<void> disableBiometrics() async {}

  @override
  Future<Map<String, String>> keyInfo() async => const {};
}

class _NoBackupPlatform implements BackupPlatform {
  const _NoBackupPlatform();

  @override
  Future<({int fd, String uri})?> create(String name) async => null;

  @override
  Future<int?> open() async => null;

  @override
  Future<bool> delete(String uri) async => true;
}

class _NoKeeper implements ConnectionKeeper {
  const _NoKeeper();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<BatteryStatus> batteryStatus() async =>
      (unrestricted: true, xiaomi: false);

  @override
  Future<void> openBatterySettings() async {}

  @override
  Future<void> openAutostart() async {}
}

class _NoKey implements WaKeyProvider {
  const _NoKey();

  @override
  Future<String> key() async => '';
}

/// The app running on a [DemoSession]: the real screens, with a fixed strip
/// on top saying it is a demo and how to leave.
class DemoApp extends StatelessWidget {
  const DemoApp({
    super.key,
    required this.session,
    required this.theme,
    required this.onExit,
  });

  final DemoSession session;
  final ThemeController theme;
  final VoidCallback onExit;

  static final _light = AppTheme.light();
  static final _dark = AppTheme.dark();

  @override
  Widget build(BuildContext context) {
    final s = session;
    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) => MaterialApp(
        title: 'Chat do Garoto · demonstração',
        scrollBehavior: const AppScrollBehavior(),
        // The strip's "Sair" sits where the debug banner would.
        debugShowCheckedModeBanner: false,
        theme: _light,
        darkTheme: _dark,
        themeMode: theme.mode,
        builder: (context, child) => CrmScope(
          products: s.products,
          sales: s.sales,
          clients: s.clients,
          photos: s.photos,
          chatPrefs: s.chatPrefs,
          drafts: s.drafts,
          child: Column(
            children: [
              DemoStrip(onExit: onExit),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: child!,
                ),
              ),
            ],
          ),
        ),
        home: Builder(
          builder: (context) => HomeShell(
            bridge: s.bridge,
            whatsapp: s.whatsapp,
            chats: s.chats,
            clients: s.clients,
            products: s.products,
            sales: s.sales,
            photos: s.photos,
            onOpenSettings: () {},
            backup: null,
            backupBuilder: () => BackupScreen(controller: s.backup),
            settingsBuilder: (open) => SettingsScreen(
              whatsapp: s.whatsapp,
              lock: s.lock,
              theme: theme,
              onOpenBackup: () => open(BackupScreen(controller: s.backup)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The strip that never leaves the screen during the demo.
class DemoStrip extends StatelessWidget {
  const DemoStrip({super.key, required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Material(
      color: c.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Modo demonstração: nada aqui é real',
                  style: t.labelLarge!.copyWith(color: c.onTertiaryContainer),
                ),
              ),
              TextButton(
                onPressed: onExit,
                style: TextButton.styleFrom(foregroundColor: c.tertiary),
                child: const Text('Sair'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
