// Scrolling 200 clients, 200 chats and 500 messages with photos, and
// opening a conversation, measured on the phone in profile mode. Example data only, never the user's.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chat_do_garoto/src/chats/chat_screen.dart';
import 'package:chat_do_garoto/src/chats/chats_controller.dart';
import 'package:chat_do_garoto/src/chats/chats_screen.dart';
import 'package:chat_do_garoto/src/home/crm_scope.dart';
import 'package:chat_do_garoto/src/chats/media/media_platform.dart';
import 'package:chat_do_garoto/src/clients/clients_repository.dart';
import 'package:chat_do_garoto/src/clients/clients_screen.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:chat_do_garoto/src/theme/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fake_chat_prefs.dart';
import '../test/support/fake_clients_repository.dart';
import '../test/support/fake_core_bridge.dart';
import '../test/support/fake_media_platform.dart';
import '../test/support/fake_sales_repository.dart';

const _names = [
  'Ana',
  'Bruno',
  'Carla',
  'Diego',
  'Elisa',
  'Fábio',
  'Gabriela',
  'Hugo',
  'Isabel',
  'João',
  'Karina',
  'Lucas',
  'Marina',
  'Nícolas',
  'Olívia',
  'Paulo',
];

/// With `--dart-define=PERF_TRACE=true`, the run waits for the computer to
/// record the timeline through the VM service, to find what costs (a
/// diagnosis run; its numbers are not the ones to report).
/// `PERF_ONLY=<clients|chat|chats>` runs one measure.
const _trace = bool.fromEnvironment('PERF_TRACE');

/// One timeline event per widget build (heavy: inflates the times).
const _traceBuilds = bool.fromEnvironment('PERF_TRACE_BUILDS');
const _only = String.fromEnvironment('PERF_ONLY');

/// `testWidgets` builds the accessibility tree by default, which a phone
/// only does with an accessibility service on (TalkBack, a password
/// manager…): it cost 5 to 23 ms in the slow frames of the conversation.
/// The numbers were taken with it; `PERF_SEMANTICS=false`
/// measures as the user's Redmi runs (accessibility off).
const _semantics = bool.fromEnvironment('PERF_SEMANTICS', defaultValue: true);
bool _skip(String key) => _only.isNotEmpty && _only != key;

Future<void> _fling(WidgetTester tester, Finder list, {bool up = false}) async {
  for (var i = 0; i < 6; i++) {
    await tester.fling(list, Offset(0, up ? 900 : -900), 4000);
    await tester.pumpAndSettle();
  }
}

/// Build and raster times of the frames drawn while [action] runs, in
/// milliseconds: average, 90th percentile, worst, and the share over the
/// 16.7 ms budget of 60 Hz.
Future<Map<String, Object>> _measure(Future<void> Function() action) async {
  final timings = <FrameTiming>[];
  void collect(List<FrameTiming> t) => timings.addAll(t);
  SchedulerBinding.instance.addTimingsCallback(collect);
  await action();
  await Future<void>.delayed(const Duration(seconds: 1)); // last reports
  SchedulerBinding.instance.removeTimingsCallback(collect);
  double ms(Duration d) => d.inMicroseconds / 1000;
  Map<String, Object> stats(List<double> v) {
    v.sort();
    return {
      'avg': (v.reduce((a, b) => a + b) / v.length).toStringAsFixed(2),
      'p90': v[(v.length * 0.9).floor().clamp(0, v.length - 1)].toStringAsFixed(
        2,
      ),
      'worst': v.last.toStringAsFixed(2),
    };
  }

  final build = [for (final t in timings) ms(t.buildDuration)];
  final raster = [for (final t in timings) ms(t.rasterDuration)];
  final total = [for (final t in timings) ms(t.totalSpan)];
  // Flutter's own measure: a frame misses when its build or its raster
  // takes longer than the budget (16.7 ms at 60 Hz).
  var missed = 0, missedBuild = 0, missedRaster = 0;
  for (var i = 0; i < timings.length; i++) {
    if (build[i] > 16.7 || raster[i] > 16.7) missed++;
    if (build[i] > 16.7) missedBuild++;
    if (raster[i] > 16.7) missedRaster++;
  }
  // The first frame: what opening a screen costs.
  final first = timings.isEmpty
      ? <String, String>{}
      : {
          'build': build.first.toStringAsFixed(2),
          'raster': raster.first.toStringAsFixed(2),
          'span': total.first.toStringAsFixed(2),
        };
  String worst(List<double> v) => ([...v]..sort((a, b) => b.compareTo(a)))
      .take(5)
      .map((x) => x.toStringAsFixed(1))
      .join(' ');
  return {
    'frames': timings.length,
    'first_frame_ms': first,
    'worst5_build': worst(build),
    'worst5_raster': worst(raster),
    'build_ms': stats(build),
    'raster_ms': stats(raster),
    'span_over_budget': total.where((v) => v > 16.7).length,
    'missed_60hz': missed,
    'missed_build': missedBuild,
    'missed_raster': missedRaster,
    'missed_pct': (100 * missed / timings.length).toStringAsFixed(2),
  };
}

/// A photo as large as WhatsApp's (1600 × 1200), drawn here: shapes in
/// many colors, encoded as PNG. Each message gets its own copy, so every
/// photo is decoded, as in a real conversation.
Future<Uint8List> _photo(int seed) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint();
  for (var i = 0; i < 120; i++) {
    final v = (seed * 7919 + i * 104729) & 0xFFFFFF;
    paint.color = Color(0xFF000000 | v);
    canvas.drawCircle(
      Offset(((v >> 4) % 1600).toDouble(), ((v >> 9) % 1200).toDouble()),
      40.0 + (v % 200),
      paint,
    );
  }
  final image = await recorder.endRecording().toImage(1600, 1200);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final results = <String, Object>{};
  tearDownAll(() => binding.reportData = results);
  if (_traceBuilds) debugProfileBuildsEnabled = true;

  // In a traced run, time for the computer to start recording.
  Future<Map<String, Object>> measure(
    String key,
    Future<void> Function() action,
  ) async {
    if (_trace) await Future<void>.delayed(const Duration(seconds: 8));
    return _measure(action);
  }

  testWidgets(
    'scrolling 200 clients',
    skip: _skip('clients'),
    semanticsEnabled: _semantics,
    (tester) async {
      final repo = FakeClientsRepository();
      for (var i = 0; i < 200; i++) {
        await repo.save(
          Client(
            name: '${_names[i % 16]} Exemplo ${i + 1}',
            phone: '55119000${(10000 + i).toString()}',
            tags: i.isEven ? const ['revenda'] : const [],
          ),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ClientsScreen(repo: repo),
        ),
      );
      await tester.pumpAndSettle();
      results['clients_scroll'] = await measure('clients', () async {
        final list = find.byType(Scrollable).last;
        await _fling(tester, list);
        await _fling(tester, list, up: true);
      });
    },
  );

  testWidgets(
    'scrolling 500 messages',
    skip: _skip('chat'),
    semanticsEnabled: _semantics,
    (tester) async {
      const chat = '5511900000001@s.whatsapp.net';
      mediaPlatform = FakeMediaPlatform();
      // One photo every ten messages, downloaded: the conversation shows the
      // whole photo.
      final photos = [for (var i = 0; i < 5; i++) await _photo(i)];
      final bridge = FakeCoreBridge();
      bridge.messages[chat] = [
        for (var i = 0; i < 500; i++)
          ChatMessage(
            chat: chat,
            id: 'M$i',
            fromMe: i % 3 == 0,
            senderName: 'Ana',
            kind: i % 10 == 5 ? 'image' : 'text',
            media: i % 10 == 5 ? 'downloaded' : '',
            thumb: i % 10 == 5,
            text: i % 5 == 0
                ? 'Mensagem de exemplo número $i, um pouco mais longa para '
                      'ocupar duas ou três linhas no balão.'
                : 'Exemplo $i',
            ts: 1790900000000 + i * 60000,
            status: i % 3 == 0 ? 'read' : '',
          ),
      ];
      for (var i = 5; i < 500; i += 10) {
        bridge.mediaParts['$chat|M$i|full'] = Uint8List.fromList(photos[i % 5]);
      }
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          navigatorKey: navigator,
          home: const Scaffold(body: Center(child: Text('Conversas'))),
        ),
      );
      await tester.pumpAndSettle();
      // Opening: the first frame of the conversation (under 0.3 s).
      results['chat_open'] = await _measure(() async {
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => ChatScreen(
              bridge: bridge,
              chat: const ChatSummary(
                jid: chat,
                name: 'Ana Exemplo',
                lastText: '',
                lastTs: 0,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });
      // Older pages, so the fling has all 500 messages.
      for (var i = 0; i < 9; i++) {
        final more = find.text('Carregar anteriores');
        if (more.evaluate().isEmpty) break;
        await tester.dragUntilVisible(
          more,
          find.byType(Scrollable).first,
          const Offset(0, 3000),
        );
        await tester.tap(more);
        await tester.pumpAndSettle();
      }
      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, -30000),
        20000,
      );
      await tester.pumpAndSettle();
      results['chat_scroll'] = await measure('chat', () async {
        final list = find.byType(Scrollable).first;
        await _fling(tester, list, up: true);
        await _fling(tester, list);
      });
    },
  );

  testWidgets(
    'scrolling 200 chats with the filters',
    skip: _skip('chats'),
    semanticsEnabled: _semantics,
    (tester) async {
      final clients = FakeClientsRepository();
      final now = DateTime.now();
      final chats = <ChatSummary>[];
      for (var i = 0; i < 200; i++) {
        final phone = '55119000${(10000 + i).toString()}';
        if (i.isEven) {
          await clients.save(
            Client(name: '${_names[i % 16]} Cliente ${i + 1}', phone: phone),
          );
        }
        chats.add(
          ChatSummary(
            jid: '$phone@s.whatsapp.net',
            name: '${_names[i % 16]} ${i + 1}',
            lastText: 'Última mensagem de exemplo da conversa ${i + 1}',
            lastTs: now
                .subtract(Duration(minutes: i * 30))
                .millisecondsSinceEpoch,
            lastFromMe: i % 3 == 0,
          ),
        );
      }
      final bridge = FakeCoreBridge()..chats = chats;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => CrmScope(
            sales: FakeSalesRepository(),
            chatPrefs: FakeChatPrefs(),
            child: child!,
          ),
          home: ChatsScreen(
            bridge: bridge,
            controller: ChatsController(bridge: bridge)..start(),
            status: 'Conectado',
            clients: clients,
          ),
        ),
      );
      await tester.pumpAndSettle();
      results['chats_scroll'] = await measure('chats', () async {
        final list = find.byType(Scrollable).last;
        await _fling(tester, list);
        await _fling(tester, list, up: true);
      });
    },
  );
}
