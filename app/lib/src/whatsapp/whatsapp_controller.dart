import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core_bridge/core_bridge.dart';
import '../platform/connection_keeper.dart';
import '../platform/wa_key.dart';

/// Where the WhatsApp session lives: the app's private support directory.
Future<String> defaultSessionPath() async {
  final dir = await getApplicationSupportDirectory();
  return '${dir.path}${Platform.pathSeparator}wa${Platform.pathSeparator}wa.db';
}

/// The phases of linking the app to WhatsApp.
enum WhatsAppPhase { starting, pairing, connecting, connected, disconnecting }

/// State and actions of the WhatsApp connection.
class WhatsAppController extends ChangeNotifier {
  WhatsAppController({
    required this._bridge,
    this._sessionPath = defaultSessionPath,
    this._keeper = const PlatformConnectionKeeper(),
    this._keys = const PlatformWaKeyProvider(),
  });

  final CoreBridge _bridge;
  final Future<String> Function() _sessionPath;
  final ConnectionKeeper _keeper;
  final WaKeyProvider _keys;
  StreamSubscription<CoreEvent>? _events;

  WhatsAppPhase phase = WhatsAppPhase.starting;

  /// True while a paired session exists (even if reconnecting): the app then
  /// shows the conversations instead of the pairing screen.
  bool linked = false;

  /// Latest QR code to show (refreshes while not scanned).
  String? qrCode;

  /// The 8-character pairing code, once WhatsApp sends it.
  String? pairingCode;

  /// True while waiting for the pairing code.
  bool requestingCode = false;

  /// The account name, once connected (may be empty).
  String? pushName;

  /// A user-facing error, in Portuguese.
  String? error;

  /// A user-facing notice, such as the phone removing this device.
  String? notice;

  /// True when the pairing window ran out; generating a code or a QR
  /// again reopens it.
  bool expired = false;

  /// True right after pairing when Android restricts the app's battery: the
  /// app then shows the battery screen once.
  bool offerBattery = false;

  /// The latest connection summary, once loaded.
  ConnectionReport? report;

  /// The keep-alive service and battery settings.
  ConnectionKeeper get keeper => _keeper;

  /// Opens the session and connects. Call once at startup.
  Future<void> start() async {
    if (_events == null) {
      _events = _bridge.events.listen(_onEvent);
      // Redacted diagnostics in development builds only.
      if (kDebugMode) _bridge.setWhatsAppDiagnostics(true);
    }
    final path = await _sessionPath();
    expired = false;
    try {
      final state = _open(path, await _keys.key());
      linked = state.paired;
      if (!state.paired) {
        phase = WhatsAppPhase.pairing;
      } else if (state.connected) {
        // Already connected by the Android service.
        phase = WhatsAppPhase.connected;
        pushName = state.pushName;
      } else {
        phase = WhatsAppPhase.connecting;
      }
      if (state.paired) unawaited(_keeper.start());
    } on CoreException catch (e) {
      error = 'Não foi possível abrir a sessão do WhatsApp (${e.code}).';
    }
    notifyListeners();
  }

  WhatsAppState _open(String path, String key) {
    try {
      return _bridge.startWhatsApp(path, key);
    } on CoreException catch (e) {
      if (e.code != 'unreadable') rethrow;
      // The key no longer opens the session: delete it and
      // pair again; the history comes back from WhatsApp.
      _bridge.resetWhatsApp(path);
      notice =
          'A sessão do WhatsApp não pôde ser aberta neste aparelho. '
          'Conecte de novo.';
      return _bridge.startWhatsApp(path, key);
    }
  }

  /// Asks WhatsApp for a pairing code for [phone]. Reopens the pairing
  /// window first when it expired.
  Future<void> requestCode(String phone) async {
    if (expired) {
      notice = null;
      await start();
    }
    try {
      _bridge.requestPairingCode(phone);
      // The user is about to switch to WhatsApp: keep the connection alive.
      unawaited(_keeper.start());
      requestingCode = true;
      pairingCode = null;
      error = null;
    } on CoreException catch (e) {
      error = e.code == 'invalid_argument'
          ? 'Número inválido. Use o código do país, o DDD e o número, '
                'por exemplo 55 11 99999-0000.'
          : 'Não foi possível pedir o código (${e.code}).';
    }
    notifyListeners();
  }

  /// The battery screen was shown after pairing.
  void batteryOffered() {
    offerBattery = false;
  }

  /// Reads the connection summary from the core.
  void loadReport() {
    try {
      report = _bridge.connectionReport();
    } on CoreException {
      report = null; // session not open
    }
    notifyListeners();
  }

  Future<void> _checkBattery() async {
    final status = await _keeper.batteryStatus();
    if (status.unrestricted) return;
    offerBattery = true;
    notifyListeners();
  }

  /// Unlinks this device from WhatsApp and deletes the session.
  void logout() {
    try {
      _bridge.logoutWhatsApp();
      phase = WhatsAppPhase.disconnecting;
      error = null;
    } on CoreException catch (e) {
      error = 'Não foi possível desconectar (${e.code}).';
    }
    notifyListeners();
  }

  void _onEvent(CoreEvent event) {
    if (kDebugMode && event.type.startsWith('wa_')) {
      // Never print QR or pairing codes: they work as one-time passwords.
      // Diagnostics (wa_log) and error codes are already free of numbers.
      final detail = switch (event.type) {
        'wa_log' => '${event.data['level']}: ${event.data['msg']}',
        'wa_error' => '${event.data['code']}',
        'wa_logged_out' =>
          '${event.data['reason']} ${event.data['code'] ?? ''}',
        _ => '',
      };
      debugPrint('[wa] ${event.type} $detail');
    }
    switch (event.type) {
      case 'wa_qr':
        qrCode = event.data['code'] as String?;
      case 'wa_pair_code':
        pairingCode = event.data['code'] as String?;
        requestingCode = false;
      case 'wa_paired':
        linked = true;
        phase = WhatsAppPhase.connecting;
        qrCode = null;
        pairingCode = null;
        unawaited(_checkBattery());
      case 'wa_connected':
        linked = true;
        phase = WhatsAppPhase.connected;
        pushName = event.data['push_name'] as String?;
        error = null;
        notice = null;
      case 'wa_disconnected':
        if (phase == WhatsAppPhase.connected) {
          phase = WhatsAppPhase.connecting;
        }
      case 'wa_qr_expired':
        expired = true;
        qrCode = null;
        pairingCode = null;
        requestingCode = false;
        notice =
            'O tempo para conectar acabou. Gere um novo código ou QR Code.';
      case 'wa_logged_out':
        unawaited(_keeper.stop());
        _reset();
        if (event.data['reason'] != 'user') {
          notice = 'A conexão foi encerrada pelo celular. Conecte de novo.';
        }
        notifyListeners();
        unawaited(start());
        return;
      case 'wa_error':
        requestingCode = false;
        error = _errorMessage(event.data['code'] as String?);
      default:
        return;
    }
    notifyListeners();
  }

  void _reset() {
    linked = false;
    report = null;
    offerBattery = false;
    phase = WhatsAppPhase.starting;
    qrCode = null;
    pairingCode = null;
    requestingCode = false;
    pushName = null;
    error = null;
    notice = null;
  }

  static String _errorMessage(String? code) => switch (code) {
    'pair_failed' => 'O pareamento falhou. Tente de novo.',
    'pair_code_failed' =>
      'Não foi possível gerar o código. Confira o número e tente de novo.',
    'connect_failed' =>
      'Sem conexão com o WhatsApp. Verifique a internet e tente de novo.',
    'temporary_ban' => 'O WhatsApp bloqueou este número temporariamente.',
    'client_outdated' => 'Esta versão do app está desatualizada.',
    _ => 'Erro na conexão com o WhatsApp (${code ?? 'desconhecido'}).',
  };

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }
}
