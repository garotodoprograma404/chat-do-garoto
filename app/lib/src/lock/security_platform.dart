import 'dart:io';

import 'package:flutter/services.dart';

/// Why a biometric attempt did not unlock.
class BiometricException implements Exception {
  const BiometricException(this.code);

  /// "cancelled" (the user chose the PIN), "invalidated" (a new fingerprint
  /// was enrolled: the key is gone), "unavailable" or "failed".
  final String code;

  @override
  String toString() => 'BiometricException($code)';
}

/// Biometrics and key information from the platform. On Android,
/// a Keystore key that needs strong biometrics on every use wraps the
/// app.db key; elsewhere biometrics are unavailable.
abstract interface class SecurityPlatform {
  Future<bool> biometricsAvailable();

  /// Wraps [secretHex] after a biometric prompt; returns the wrapped blob.
  Future<String> enrollBiometrics(String secretHex);

  /// Unwraps [blob] after a biometric prompt; returns the secret.
  Future<String> unlockWithBiometrics(String blob);

  Future<void> disableBiometrics();

  /// Where each Keystore key lives ("strongbox", "tee", "software"), for
  /// diagnostics.
  Future<Map<String, String>> keyInfo();
}

class PlatformSecurity implements SecurityPlatform {
  const PlatformSecurity();

  static const _channel = MethodChannel('chatdogaroto/security');

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw BiometricException(e.code);
    }
  }

  @override
  Future<bool> biometricsAvailable() async =>
      Platform.isAndroid && (await _call<bool>('bioAvailable') ?? false);

  @override
  Future<String> enrollBiometrics(String secretHex) async =>
      await _call<String>('bioEnroll', secretHex) ??
      (throw const BiometricException('failed'));

  @override
  Future<String> unlockWithBiometrics(String blob) async =>
      await _call<String>('bioUnlock', blob) ??
      (throw const BiometricException('failed'));

  @override
  Future<void> disableBiometrics() async {
    if (Platform.isAndroid) await _call<void>('bioDisable');
  }

  @override
  Future<Map<String, String>> keyInfo() async {
    if (!Platform.isAndroid) return const {};
    final info = await _channel.invokeMapMethod<String, String>('keyInfo');
    return info ?? const {};
  }
}
