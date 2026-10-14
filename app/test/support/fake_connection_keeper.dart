import 'package:chat_do_garoto/src/platform/connection_keeper.dart';

/// Records whether the keep-alive service would be running and what the
/// battery screen asked for.
class FakeConnectionKeeper implements ConnectionKeeper {
  bool running = false;
  BatteryStatus battery = (unrestricted: true, xiaomi: false);
  final opened = <String>[];

  @override
  Future<void> start() async => running = true;

  @override
  Future<void> stop() async => running = false;

  @override
  Future<BatteryStatus> batteryStatus() async => battery;

  @override
  Future<void> openBatterySettings() async => opened.add('battery');

  @override
  Future<void> openAutostart() async => opened.add('autostart');
}
