import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core_bridge/core_bridge.dart';
import '../storage/app_storage.dart';
import '../storage/key_vault.dart';
import 'security_platform.dart';

enum AppLockState { checking, needsPin, locked, unlocked }

/// The app's own lock. While unlocked it holds the
/// app.db key, which only the PIN envelope or biometrics release.
class LockController extends ChangeNotifier {
  LockController({
    required this._bridge,
    this._security = const PlatformSecurity(),
    KeyVault Function(String name)? vault,
    DateTime Function()? clock,
    this._wipeData = _noWipe,
  }) : _vault = vault ?? SecureKeyVault.new,
       _clock = clock ?? DateTime.now;

  static const pinLength = 6;
  static const awayLimit = Duration(minutes: 1);

  /// Away while the gallery or camera the app opened is in front:
  /// long enough to take a photo without losing the form.
  static const externalAwayLimit = Duration(minutes: 5);
  static const idleLimit = Duration(minutes: 5);
  static const freeAttempts = 5;
  static const firstWait = Duration(seconds: 30);
  static const maxWait = Duration(hours: 1);

  // Vault items. app_db_key is the key without PIN from delivery 2.1.
  static const legacyItem = 'app_db_key';
  static const pinItem = 'app_key_pin';
  static const bioItem = 'app_key_bio';
  static const attemptsItem = 'pin_attempts';

  final CoreBridge _bridge;
  final SecurityPlatform _security;
  final KeyVault Function(String name) _vault;
  final DateTime Function() _clock;
  final Future<void> Function() _wipeData;

  static Future<void> _noWipe() async {}

  AppLockState state = AppLockState.checking;
  String? _key;
  bool biometricsOn = false;
  bool biometricsAvailable = false;

  /// True right after the PIN is created on a phone with biometrics: the
  /// app then asks once whether to use them.
  bool offerBiometrics = false;

  /// A user-facing message, in Portuguese.
  String? message;

  /// While set, PIN attempts are refused until then.
  DateTime? waitUntil;
  int _failures = 0;
  DateTime? _awaySince;
  Duration _awayAllowed = awayLimit;
  bool _external = false;
  DateTime _lastTouch = DateTime.fromMillisecondsSinceEpoch(0);

  /// The app.db key; only while unlocked. Never log it.
  String? get key => _key;

  bool get busy => _busy;
  bool _busy = false;

  Future<void> start() async {
    // Independent reads, at the same time: opening the app waits on them
    final (available, bio, _, pin) = await (
      _security.biometricsAvailable(),
      _vault(bioItem).read(),
      _loadAttempts(),
      _vault(pinItem).read(),
    ).wait;
    biometricsAvailable = available;
    biometricsOn = bio != null;
    final hasPin = pin != null;
    state = hasPin ? AppLockState.locked : AppLockState.needsPin;
    // Show a pending wait at once, not only on the next attempt.
    if (waitUntil case final until? when _clock().isBefore(until)) {
      message = 'PIN bloqueado por erros. ${_waitText()}';
    }
    notifyListeners();
    if (kDebugMode) {
      // Where the Keystore keys live; levels only, never keys.
      debugPrint('[keys] ${await _security.keyInfo()}');
    }
    addListener(_debugState);
    _debugState();
  }

  String? _lastDebug;

  /// Development builds only: the lock state for checking on a device whose
  /// screen cannot be captured (FLAG_SECURE). No PIN, key or count.
  void _debugState() {
    if (!kDebugMode) return;
    final line =
        '[lock] $state pin=${state != AppLockState.needsPin} '
        'bio=${biometricsOn ? 'on' : 'off'} waiting=${waitUntil != null}';
    if (line == _lastDebug) return;
    _lastDebug = line;
    debugPrint(line);
  }

  static bool validPin(String pin) =>
      pin.length == pinLength && RegExp(r'^[0-9]+$').hasMatch(pin);

  /// Creates the PIN. The app.db key of delivery 2.1, if any, is kept
  /// and sealed under it.
  Future<bool> createPin(String pin, String confirm) async {
    if (!validPin(pin)) return _fail('O PIN tem 6 números.');
    if (pin != confirm) return _fail('Os dois PINs não são iguais.');
    return _guard(() async {
      final legacy = _vault(legacyItem);
      final key = await legacy.read() ?? newDatabaseKey();
      await _vault(pinItem).write(await _bridge.sealWithPin(pin, key));
      await legacy.delete();
      offerBiometrics = biometricsAvailable;
      _unlocked(key);
      return true;
    });
  }

  Future<bool> unlock(String pin) async {
    if (_waiting()) return false;
    final envelope = await _vault(pinItem).read();
    if (envelope == null) return _fail('Crie um PIN.');
    return _guard(() async {
      try {
        final key = await _bridge.openWithPin(pin, envelope);
        await _setAttempts(0);
        _unlocked(key);
        return true;
      } on CoreException catch (e) {
        if (e.code != 'wrong_pin') rethrow;
        await _setAttempts(_failures + 1);
        return _fail(
          waitUntil == null ? 'PIN errado.' : 'PIN errado. ${_waitText()}',
        );
      }
    });
  }

  Future<bool> unlockWithBiometrics() async {
    final blob = await _vault(bioItem).read();
    if (blob == null) return false;
    return _guard(() async {
      try {
        final key = await _security.unlockWithBiometrics(blob);
        await _setAttempts(0);
        _unlocked(key);
        return true;
      } on BiometricException catch (e) {
        if (e.code == 'invalidated') {
          await _dropBiometrics();
          return _fail(
            'A digital do celular mudou. Use o PIN e ligue a digital de novo.',
          );
        }
        return false; // cancelled: back to the PIN
      }
    });
  }

  /// Turns biometric unlock on; needs the app unlocked.
  Future<bool> enableBiometrics() async {
    final key = _key;
    if (key == null || !biometricsAvailable) return false;
    return _guard(() async {
      try {
        await _vault(bioItem).write(await _security.enrollBiometrics(key));
        biometricsOn = true;
        return true;
      } on BiometricException {
        return false;
      }
    });
  }

  /// The biometrics question was shown.
  void biometricsOffered() => offerBiometrics = false;

  Future<void> disableBiometrics() async {
    await _dropBiometrics();
    notifyListeners();
  }

  /// Changes the PIN: the current one must open the envelope.
  Future<bool> changePin(String current, String next, String confirm) async {
    if (!validPin(next)) return _fail('O PIN tem 6 números.');
    if (next != confirm) return _fail('Os dois PINs não são iguais.');
    final envelope = await _vault(pinItem).read();
    if (envelope == null) return false;
    return _guard(() async {
      try {
        final key = await _bridge.openWithPin(current, envelope);
        await _vault(pinItem).write(await _bridge.sealWithPin(next, key));
        message = 'PIN trocado.';
        return true;
      } on CoreException catch (e) {
        if (e.code != 'wrong_pin') rethrow;
        return _fail('O PIN atual está errado.');
      }
    });
  }

  /// Forgot the PIN: deletes the app's data and its keys, then asks
  /// for a new PIN. WhatsApp and the conversations are not touched.
  Future<void> forgotPin() async {
    await _guard(() async {
      _key = null;
      await _wipeData();
      for (final item in [pinItem, bioItem, legacyItem, attemptsItem]) {
        await _vault(item).delete();
      }
      await _security.disableBiometrics();
      biometricsOn = false;
      _failures = 0;
      waitUntil = null;
      message = null;
      state = AppLockState.needsPin;
      return true;
    });
  }

  /// Locks now: the app.db key leaves memory.
  void lock() {
    if (state != AppLockState.unlocked) return;
    _key = null;
    state = AppLockState.locked;
    message = null;
    notifyListeners();
  }

  /// The app is about to open the gallery or the camera: the
  /// next time away may last [externalAwayLimit].
  void expectExternal() => _external = true;

  /// The gallery or the camera closed.
  void externalDone() => _external = false;

  /// The app went to the background. The limit is decided now: the photo
  /// may arrive before the app shows again.
  void onBackground() {
    _awaySince = _clock();
    _awayAllowed = _external ? externalAwayLimit : awayLimit;
  }

  /// The app came back: lock if it was away too long.
  void onForeground() {
    final since = _awaySince;
    _awaySince = null;
    if (since != null && _clock().difference(since) > _awayAllowed) lock();
    touched();
  }

  /// Any touch on the screen.
  void touched() => _lastTouch = _clock();

  /// Called periodically: lock after [idleLimit] without a touch.
  void checkIdle() {
    if (_clock().difference(_lastTouch) > idleLimit) lock();
  }

  void _unlocked(String key) {
    _key = key;
    state = AppLockState.unlocked;
    message = null;
    touched();
  }

  bool _waiting() {
    final until = waitUntil;
    if (until == null || !_clock().isBefore(until)) return false;
    message = _waitText();
    notifyListeners();
    return true;
  }

  String _waitText() {
    final left = waitUntil!.difference(_clock());
    final seconds = max(1, left.inSeconds);
    return seconds < 120
        ? 'Tente de novo em $seconds s.'
        : 'Tente de novo em ${(seconds / 60).ceil()} min.';
  }

  /// Wait after [failures] wrong PINs: none for the first ones, then 30 s,
  /// doubling, up to an hour.
  @visibleForTesting
  static Duration waitAfter(int failures) {
    if (failures < freeAttempts) return Duration.zero;
    final doubled = firstWait * pow(2, failures - freeAttempts).toInt();
    return doubled > maxWait ? maxWait : doubled;
  }

  Future<void> _setAttempts(int failures) async {
    _failures = failures;
    final wait = waitAfter(failures);
    waitUntil = wait == Duration.zero ? null : _clock().add(wait);
    final vault = _vault(attemptsItem);
    if (failures == 0) {
      await vault.delete();
    } else {
      await vault.write(
        jsonEncode({
          'failures': failures,
          'until': waitUntil?.millisecondsSinceEpoch ?? 0,
        }),
      );
    }
  }

  Future<void> _loadAttempts() async {
    final raw = await _vault(attemptsItem).read();
    if (raw == null) return;
    final data = jsonDecode(raw) as Map<String, Object?>;
    _failures = data['failures'] as int? ?? 0;
    final until = data['until'] as int? ?? 0;
    waitUntil = until == 0 ? null : DateTime.fromMillisecondsSinceEpoch(until);
  }

  Future<void> _dropBiometrics() async {
    await _vault(bioItem).delete();
    await _security.disableBiometrics();
    biometricsOn = false;
  }

  bool _fail(String text) {
    message = text;
    notifyListeners();
    return false;
  }

  Future<bool> _guard(Future<bool> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
