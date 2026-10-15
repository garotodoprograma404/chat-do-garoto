import 'dart:async';

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'src/backup/backup_controller.dart';
import 'src/backup/backup_platform.dart';
import 'src/backup/backup_screen.dart';

import 'src/chats/chat_prefs.dart';
import 'src/chats/chats_controller.dart';
import 'src/chats/media/media_picker.dart';
import 'src/clients/clients_repository.dart';
import 'src/clients/contact_picker.dart';
import 'src/core_bridge/core_bridge.dart';
import 'src/demo/demo_app.dart';
import 'src/home/crm_scope.dart';
import 'src/home/home_shell.dart';
import 'src/intro/intro_controller.dart';
import 'src/intro/intro_screen.dart';
import 'src/lock/create_pin_screen.dart';
import 'src/lock/lock_controller.dart';
import 'src/lock/lock_screen.dart';
import 'src/platform/battery_screen.dart';
import 'src/products/product_photos.dart';
import 'src/scan/barcode_scanner.dart';
import 'src/products/products_repository.dart';
import 'src/sales/sales_repository.dart';
import 'src/storage/app_database.dart';
import 'src/storage/app_storage.dart';
import 'src/storage/form_drafts.dart';
import 'src/storage/key_vault.dart';
import 'src/storage/recovery_screen.dart';
import 'src/storage/storage_controller.dart';
import 'src/theme/app_theme.dart';
import 'src/theme/responsive.dart';
import 'src/theme/theme_controller.dart';
import 'src/settings/settings_screen.dart';
import 'src/whatsapp/whatsapp_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();

  final bridge = NativeCoreBridge();
  final storage = StorageController(storage: AppStorage());
  final lock = LockController(bridge: bridge, wipeData: storage.wipe)..start();
  // The look is read while the lock reads its state, in parallel. The
  // first frame (a spinner) does not wait for it.
  final theme = ThemeController(store: const SecureKeyVault('theme_mode'))
    ..load();
  // The WhatsApp connection runs whether the app is locked or not.
  final whatsapp = WhatsAppController(bridge: bridge);
  final chats = ChatsController(bridge: bridge);

  // Photos a closed app left behind in the cache.
  cleanPhotoLeftovers();
  // Backups and restores; what a stopped one left is deleted.
  final backupDir = getTemporaryDirectory().then((d) async {
    final dir = '${d.path}${Platform.pathSeparator}backup';
    await cleanBackupLeftovers(dir);
    return dir;
  });
  final backup = BackupController(
    bridge: bridge,
    platform: const ChannelBackupPlatform(),
    workDir: () async {
      final dir = await backupDir;
      Directory(dir).createSync(recursive: true);
      return dir;
    },
    copyAppDb: (path, key) => exportCopy(storage.database!, path, key),
    restoreAppDb: storage.restoreFrom,
    appSchema: () => AppDatabase.currentVersion,
    lastStore: const SecureKeyVault('backup_last'),
    intervalStore: const SecureKeyVault('backup_interval'),
    onLeave: lock.expectExternal,
    onBack: lock.externalDone,
  )..start();
  // The first-run screens.
  final intro = IntroController(store: const SecureKeyVault('intro_seen'))
    ..start();
  // The WhatsApp side starts right after the first frame, so opening the
  // app does not wait on the session. The Android service
  // keeps the connection on its own meanwhile.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => whatsapp.start().then((_) => chats.start()),
  );
  runApp(
    _Root(
      theme: theme,
      real: ChatDoGarotoApp(
        bridge: bridge,
        lock: lock,
        storage: storage,
        whatsapp: whatsapp,
        chats: chats,
        backup: backup,
        intro: intro,
        theme: theme,
      ),
    ),
  );
}

/// Shows the real app, or the demo when someone asks for it.
/// The real app's controllers stay alive while the demo runs; the demo
/// never touches them.
class _Root extends StatefulWidget {
  const _Root({required this.theme, required this.real});

  final ThemeController theme;
  final Widget real;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  DemoSession? _demo;
  bool _opening = false;

  // The demo starts with the app's look; a change made there stays there.
  late final _demoTheme = ThemeController(
    store: MemoryKeyVault(widget.theme.mode.name),
  )..load();

  Future<void> _enter() async {
    if (_opening || _demo != null) return;
    _opening = true;
    final session = await DemoSession.open();
    _opening = false;
    if (!mounted) return session.close();
    setState(() => _demo = session);
  }

  Future<void> _exit() async {
    final session = _demo;
    if (session == null) return;
    setState(() => _demo = null);
    await session.close();
  }

  @override
  Widget build(BuildContext context) {
    if (_demo case final session?) {
      return DemoApp(session: session, theme: _demoTheme, onExit: _exit);
    }
    return DemoLauncher(enter: _enter, child: widget.real);
  }
}

/// The bundled fonts' licenses (UFL) in the app's license page.
void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (family, file) in [
      ('Ubuntu Sans', 'UFL-UbuntuSansMono.txt'),
      ('Ubuntu Sans Mono', 'UFL-UbuntuSansMono.txt'),
    ]) {
      final text = await rootBundle.loadString('assets/fonts/$file');
      yield LicenseEntryWithLineBreaks([family], text);
    }
  });
}

/// The vault's media, to show their size before a backup.
Future<int> _mediaBytes() async {
  final wa = File(await defaultSessionPath());
  return folderBytes('${wa.parent.path}${Platform.pathSeparator}media');
}

class ChatDoGarotoApp extends StatefulWidget {
  const ChatDoGarotoApp({
    super.key,
    required this.bridge,
    required this.lock,
    required this.storage,
    required this.whatsapp,
    required this.chats,
    required this.backup,
    required this.intro,
    required this.theme,
  });

  final ThemeController theme;
  final BackupController backup;
  final IntroController intro;
  final CoreBridge bridge;
  final LockController lock;
  final StorageController storage;
  final WhatsAppController whatsapp;
  final ChatsController chats;

  @override
  State<ChatDoGarotoApp> createState() => _ChatDoGarotoAppState();
}

class _ChatDoGarotoAppState extends State<ChatDoGarotoApp> {
  final _navigator = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycle;
  late final Timer _idle;
  AppLockState? _seen;
  // The lock allows five minutes away while picking a photo.
  late final _photos = DevicePhotoPicker(
    onLeave: lock.expectExternal,
    onBack: lock.externalDone,
  );

  // One set of CRM repositories per open app.db.
  AppDatabase? _crmDb;
  ProductsRepository? _products;
  SalesRepository? _sales;
  ClientsRepository? _clients;
  ChatPrefs? _chatPrefs;
  FormDrafts? _drafts;

  void _crm() {
    final db = storage.database;
    if (identical(db, _crmDb)) return;
    _crmDb = db;
    _products = db == null ? null : DriftProductsRepository(db);
    _sales = db == null ? null : DriftSalesRepository(db);
    _clients = db == null ? null : DriftClientsRepository(db);
    _chatPrefs = db == null ? null : DriftChatPrefs(db);
    _drafts = db == null ? null : DriftFormDrafts(db);
  }

  LockController get lock => widget.lock;
  StorageController get storage => widget.storage;
  WhatsAppController get whatsapp => widget.whatsapp;

  @override
  void initState() {
    super.initState();
    // Lock after a minute away and after five minutes untouched.
    _lifecycle = AppLifecycleListener(
      onHide: lock.onBackground,
      onShow: lock.onForeground,
    );
    _idle = Timer.periodic(
      const Duration(seconds: 15),
      (_) => lock.checkIdle(),
    );
    lock.addListener(_lockChanged);
    // Media to send in conversations, with the same lock care.
    chatMediaPicker = DeviceChatMediaPicker(
      onLeave: lock.expectExternal,
      onBack: lock.externalDone,
    );
    // The address book's picker exists on Android only,
    // and so does the barcode scanner.
    if (Platform.isAndroid) {
      contactPicker = ChannelContactPicker(
        onLeave: lock.expectExternal,
        onBack: lock.externalDone,
      );
      barcodeScanner = const CameraBarcodeScanner();
    }
  }

  @override
  void dispose() {
    lock.removeListener(_lockChanged);
    _idle.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  /// Opens app.db on unlock; closes it and every screen on top on lock.
  void _lockChanged() {
    if (lock.state == _seen) return;
    _seen = lock.state;
    if (lock.key case final key? when lock.state == AppLockState.unlocked) {
      storage.open(key);
    } else {
      storage.close();
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Light, dark or the phone's choice.
    return ListenableBuilder(
      listenable: widget.theme,
      builder: (context, _) => MaterialApp(
        title: 'Chat do Garoto',
        scrollBehavior: const AppScrollBehavior(),
        navigatorKey: _navigator,
        theme: _light,
        darkTheme: _dark,
        themeMode: widget.theme.mode,
        // Every touch counts as activity, dialogs included. Products and
        // sales reach every route.
        builder: (context, child) => ListenableBuilder(
          listenable: storage,
          builder: (context, _) {
            _crm();
            return CrmScope(
              products: _products,
              sales: _sales,
              clients: _clients,
              photos: _photos,
              chatPrefs: _chatPrefs,
              drafts: _drafts,
              child: Listener(
                onPointerDown: (_) => lock.touched(),
                child: child,
              ),
            );
          },
        ),
        home: ListenableBuilder(
          listenable: Listenable.merge([lock, storage, whatsapp, widget.intro]),
          builder: (context, _) {
            final intro = widget.intro;
            if (lock.state == AppLockState.checking || intro.seen == null) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            switch (lock.state) {
              case AppLockState.checking:
                break; // handled above
              case AppLockState.needsPin:
                // What the app protects and the backup, before the PIN.
                if (intro.seen == false) {
                  return IntroScreen(
                    mode: IntroMode.newInstall,
                    onDone: intro.complete,
                  );
                }
                return CreatePinScreen(controller: lock);
              case AppLockState.locked:
                return LockScreen(controller: lock);
              case AppLockState.unlocked:
                break;
            }
            // The WhatsApp connection keeps running; only the screens wait
            // for app.db.
            if (storage.phase
                case StoragePhase.unreadable || StoragePhase.failed) {
              return RecoveryScreen(
                unreadable: storage.phase == StoragePhase.unreadable,
                onReset: storage.reset,
                onRetry: storage.retry,
                onRestore: () => _open(
                  context,
                  BackupScreen(controller: widget.backup, canExport: false),
                ),
              );
            }
            // Already in use: the screens once, after updating.
            if (intro.seen == false) {
              return IntroScreen(
                mode: IntroMode.existing,
                onDone: ({required restore}) => intro.complete(),
              );
            }
            if (intro.restoreWanted && storage.phase == StoragePhase.ready) {
              // A new phone: restore right after the PIN.
              intro.restoreOffered();
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _open(
                  _navigator.currentContext!,
                  BackupScreen(controller: widget.backup, canExport: false),
                ),
              );
            }
            if (lock.offerBiometrics) {
              // Once, right after the PIN is created.
              lock.biometricsOffered();
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => offerBiometricsDialog(_navigator.currentContext!, lock),
              );
            }
            if (whatsapp.offerBattery) {
              // Once, right after pairing.
              whatsapp.batteryOffered();
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _open(context, BatteryScreen(keeper: whatsapp.keeper)),
              );
            }
            return _home(context);
          },
        ),
      ),
    );
  }

  // Built once: rebuilding ThemeData on every app rebuild costs frames.
  static final _light = AppTheme.light();
  static final _dark = AppTheme.dark();

  Widget _home(BuildContext context) {
    _crm();
    return HomeShell(
      bridge: widget.bridge,
      whatsapp: whatsapp,
      chats: widget.chats,
      clients: _clients,
      products: _products,
      sales: _sales,
      photos: _photos,
      backup: widget.backup,
      onOpenBackup: () => _openBackup(context),
      // Configurações and Backup open inside the content, beside the side
      // bar.
      backupBuilder: () =>
          BackupScreen(controller: widget.backup, mediaBytes: _mediaBytes),
      settingsBuilder: (open) => SettingsScreen(
        whatsapp: whatsapp,
        lock: lock,
        onOpenBackup: () => open(
          BackupScreen(controller: widget.backup, mediaBytes: _mediaBytes),
        ),
        theme: widget.theme,
      ),
      onOpenSettings: () => _open(
        context,
        SettingsScreen(
          whatsapp: whatsapp,
          lock: lock,
          onOpenBackup: () => _openBackup(context),
          theme: widget.theme,
        ),
      ),
    );
  }

  void _openBackup(BuildContext context) => _open(
    context,
    BackupScreen(controller: widget.backup, mediaBytes: _mediaBytes),
  );

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));
}
