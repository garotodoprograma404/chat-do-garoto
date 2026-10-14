import 'dart:io';

import 'package:flutter/services.dart';

/// Whether Android may stop the app to save battery.
typedef BatteryStatus = ({
  /// The app is exempt from battery optimization.
  bool unrestricted,

  /// Xiaomi phones also need "autostart" turned on.
  bool xiaomi,
});

/// Keeps the WhatsApp connection alive while the app is in the background
/// On Android this is a foreground service with a
/// persistent notification, plus the battery settings it depends on;
/// elsewhere it does nothing.
abstract interface class ConnectionKeeper {
  Future<void> start();
  Future<void> stop();

  Future<BatteryStatus> batteryStatus();

  /// Asks Android to stop optimizing the app's battery use.
  Future<void> openBatterySettings();

  /// Opens Xiaomi's autostart screen (or the app details elsewhere).
  Future<void> openAutostart();
}

/// [ConnectionKeeper] backed by the Android `ConnectionService`.
class PlatformConnectionKeeper implements ConnectionKeeper {
  const PlatformConnectionKeeper();

  static const _channel = MethodChannel('chatdogaroto/connection');

  @override
  Future<void> start() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('start');
  }

  @override
  Future<void> stop() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('stop');
  }

  @override
  Future<BatteryStatus> batteryStatus() async {
    if (!Platform.isAndroid) return (unrestricted: true, xiaomi: false);
    final status = await _channel.invokeMapMethod<String, Object?>(
      'batteryStatus',
    );
    return (
      unrestricted: status?['unrestricted'] as bool? ?? false,
      xiaomi: status?['xiaomi'] as bool? ?? false,
    );
  }

  @override
  Future<void> openBatterySettings() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('openBatterySettings');
    }
  }

  @override
  Future<void> openAutostart() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('openAutostart');
  }
}
