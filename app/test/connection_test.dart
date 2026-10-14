// Background connection, battery screen and connection summary.
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:chat_do_garoto/src/platform/battery_screen.dart';
import 'package:chat_do_garoto/src/whatsapp/stability_screen.dart';
import 'package:chat_do_garoto/src/whatsapp/connection_report_view.dart';
import 'package:chat_do_garoto/src/whatsapp/whatsapp_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_connection_keeper.dart';
import 'support/fake_core_bridge.dart';
import 'support/fake_wa_key.dart';

const _min = 60000;

Future<(FakeCoreBridge, WhatsAppController, FakeConnectionKeeper)> _start({
  bool paired = true,
  bool connected = false,
  bool unrestricted = true,
}) async {
  final keeper = FakeConnectionKeeper()
    ..battery = (unrestricted: unrestricted, xiaomi: true);
  final bridge = FakeCoreBridge(paired: paired)..connected = connected;
  final controller = WhatsAppController(
    bridge: bridge,
    sessionPath: () async => '/tmp/test-wa.db',
    keeper: keeper,
    keys: FakeWaKeyProvider(),
  );
  await controller.start();
  return (bridge, controller, keeper);
}

void main() {
  test('opening with the connection already up shows it connected', () async {
    final (_, controller, keeper) = await _start(connected: true);
    expect(controller.phase, WhatsAppPhase.connected);
    expect(controller.linked, isTrue);
    expect(keeper.running, isTrue);
  });

  test('right after pairing, a restricted battery is offered once', () async {
    final (bridge, controller, _) = await _start(
      paired: false,
      unrestricted: false,
    );
    expect(controller.offerBattery, isFalse);

    bridge.push('wa_paired');
    await Future<void>.delayed(Duration.zero);
    expect(controller.offerBattery, isTrue);

    controller.batteryOffered();
    expect(controller.offerBattery, isFalse);
  });

  test('an unrestricted battery is not offered after pairing', () async {
    final (bridge, controller, _) = await _start(paired: false);
    bridge.push('wa_paired');
    await Future<void>.delayed(Duration.zero);
    expect(controller.offerBattery, isFalse);
  });

  testWidgets('the stability screen shows the connection summary', (
    tester,
  ) async {
    final (bridge, controller, _) = await _start(connected: true);
    final since = DateTime(2026, 10, 1, 14, 50).millisecondsSinceEpoch;
    bridge.report = ConnectionReport(
      since: since,
      totalMs: 100 * _min,
      connectedMs: 98 * _min,
      drops: 1,
      longestMs: 2 * _min,
      starts: const {'app': 1, 'system': 1},
      outages: [
        Outage(
          start: since + 30 * _min,
          durationMs: 2 * _min,
          cause: 'restart',
          source: 'system',
        ),
      ],
    );
    // The summary lives in Configurações → Estabilidade.
    await tester.pumpWidget(
      MaterialApp(home: StabilityScreen(controller: controller)),
    );
    await tester.pump(); // the report loads after the first frame

    expect(bridge.calls, contains('connectionReport'));
    expect(find.text('Medindo desde 01/10 14:50'), findsOneWidget);
    expect(find.textContaining('Conectado 98,0% do tempo'), findsOneWidget);
    expect(find.text('Quedas: 1 · mais longa: 2 min'), findsOneWidget);
    expect(find.text('Inícios: app 1 · sistema 1'), findsOneWidget);
    expect(
      find.text('01/10 15:20 · 2 min · app reiniciado pelo sistema'),
      findsOneWidget,
    );
  });

  testWidgets('restricted battery offers both settings on Xiaomi', (
    tester,
  ) async {
    final keeper = FakeConnectionKeeper()
      ..battery = (unrestricted: false, xiaomi: true);
    await tester.pumpWidget(MaterialApp(home: BatteryScreen(keeper: keeper)));
    await tester.pump();

    expect(find.text('Economia de bateria: restrito'), findsOneWidget);
    await tester.tap(find.text('Liberar bateria'));
    await tester.tap(find.text('Abrir início automático'));
    expect(keeper.opened, ['battery', 'autostart']);
  });

  testWidgets('an unrestricted battery says so', (tester) async {
    final keeper = FakeConnectionKeeper()
      ..battery = (unrestricted: true, xiaomi: false);
    await tester.pumpWidget(MaterialApp(home: BatteryScreen(keeper: keeper)));
    await tester.pump();

    expect(find.text('Economia de bateria: liberado'), findsOneWidget);
    expect(find.text('Liberar bateria'), findsNothing);
    expect(find.text('Abrir início automático'), findsNothing);
  });

  test('duration and outage lines read naturally', () {
    expect(duration(30000), 'menos de 1 min');
    expect(duration(12 * _min), '12 min');
    expect(duration(185 * _min), '3 h 05 min');
    expect(duration((2 * 24 + 4) * 60 * _min), '2 d 4 h');
    final start = DateTime(2026, 10, 2, 9, 5).millisecondsSinceEpoch;
    expect(
      outageLine(Outage(start: start, durationMs: 5 * _min, cause: 'drop')),
      '02/10 09:05 · 5 min · caiu',
    );
    expect(
      outageLine(
        Outage(start: start, durationMs: _min, cause: 'drop', ongoing: true),
      ),
      '02/10 09:05 · 1 min · caiu (agora)',
    );
    expect(
      outageLine(Outage(start: start, durationMs: _min, cause: 'stop')),
      '02/10 09:05 · 1 min · desligado de propósito',
    );
  });

  test('the session key is fetched and passed to the core', () async {
    final (bridge, _, _) = await _start();
    expect(bridge.lastKey, FakeWaKeyProvider.value);
  });

  test('an unreadable session is reset and paired again', () async {
    final keeper = FakeConnectionKeeper();
    final bridge = FakeCoreBridge(paired: true)..unreadable = true;
    final controller = WhatsAppController(
      bridge: bridge,
      sessionPath: () async => '/tmp/test-wa.db',
      keeper: keeper,
      keys: FakeWaKeyProvider(),
    );
    await controller.start();

    expect(
      bridge.calls,
      containsAllInOrder(['startWhatsApp', 'resetWhatsApp', 'startWhatsApp']),
    );
    expect(controller.notice, contains('Conecte de novo'));
    expect(controller.phase, WhatsAppPhase.pairing);
    expect(controller.error, isNull);
  });

  test('an empty report has no data yet', () {
    expect(
      ConnectionReport.fromJson({
        'since': 0,
        'total_ms': 0,
        'connected_ms': 0,
        'drops': 0,
        'longest_ms': 0,
        'starts': <String, Object?>{},
        'outages': <Object?>[],
      }).since,
      0,
    );
  });
}
