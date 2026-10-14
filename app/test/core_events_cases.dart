// Event test cases against the real Go core, shared by the host
// tests (test/core_events_test.dart) and the on-device tests
// (integration_test/core_bridge_device_test.dart).
import 'dart:async';

import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

/// Defines the event tests. Each test owns one bridge and disposes it.
void defineCoreEventsCases() {
  late NativeCoreBridge bridge;

  setUp(() => bridge = NativeCoreBridge());
  tearDown(() {
    bridge.stopTicker();
    bridge.dispose();
  });

  /// Listens, runs [start] and collects events until "ticker_done".
  Future<List<CoreEvent>> collectUntilDone(void Function() start) async {
    final events = <CoreEvent>[];
    final done = Completer<void>();
    final subscription = bridge.events.listen((event) {
      events.add(event);
      if (event.type == 'ticker_done') done.complete();
    });
    start();
    await done.future.timeout(const Duration(seconds: 60));
    await subscription.cancel();
    return events;
  }

  List<(int, int)> ticksOf(List<CoreEvent> events) => [
    for (final event in events)
      if (event.type == 'tick')
        (event.data['worker'] as int, event.data['n'] as int),
  ];

  test('20 ticks arrive once each, in order', () async {
    final events = await collectUntilDone(() => bridge.startTicker(count: 20));

    expect(ticksOf(events), [for (var n = 1; n <= 20; n++) (1, n)]);
    expect(events.last.type, 'ticker_done');
  });

  test('no tick arrives after the ticker is stopped', () async {
    final ticks = <int>[];
    final subscription = bridge.events.listen((event) {
      if (event.type == 'tick') ticks.add(event.data['n'] as int);
    });
    bridge.startTicker(count: 1000, interval: const Duration(milliseconds: 10));
    while (ticks.length < 5) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    bridge.stopTicker();
    // Ticks sent before the stop may still be queued; let them drain.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final afterStop = ticks.length;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await subscription.cancel();

    expect(ticks.length, afterStop);
    expect(afterStop, lessThan(1000));
    expect(ticks, [for (var n = 1; n <= afterStop; n++) n]);
  });

  test('after the app stops listening, nothing is delivered', () async {
    bridge.events.listen((_) {});
    bridge.dispose();

    bridge.startTicker(count: 200);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(bridge.echo('ainda vivo'), 'ainda vivo');
    expect(bridge.liveAllocations, 0);
  });

  test('10,000 ticks from 4 concurrent tasks, no leak', () async {
    final events = await collectUntilDone(
      () => bridge.startTicker(count: 2500, workers: 4),
    );

    final ticks = ticksOf(events);
    expect(ticks, hasLength(10000));
    for (var worker = 1; worker <= 4; worker++) {
      expect(
        [
          for (final (w, n) in ticks)
            if (w == worker) n,
        ],
        [for (var n = 1; n <= 2500; n++) n],
        reason: 'worker $worker must deliver 1..2500 in order',
      );
    }
    expect(bridge.liveAllocations, 0);
  });

  test('decodeEvent rejects an unknown protocol version', () {
    expect(
      () => decodeEvent('{"v":2,"type":"tick"}'),
      throwsA(isA<CoreException>()),
    );
  });
}
