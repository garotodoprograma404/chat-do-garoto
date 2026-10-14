// Photos in the conversation and full screen, with a fake bridge.
import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_do_garoto/src/chats/chat_screen.dart';
import 'package:chat_do_garoto/src/chats/photo_screen.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_core_bridge.dart';

const _chat = '5511900000001@s.whatsapp.net';

// A 1x1 PNG.
final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  ),
);

ChatMessage _photo(String id, {bool thumb = true, String media = 'thumb'}) =>
    ChatMessage(
      chat: _chat,
      id: id,
      fromMe: false,
      senderName: '',
      kind: 'image',
      text: 'olha',
      ts: 1000,
      media: media,
      thumb: thumb,
    );

void main() {
  testWidgets('a photo shows its thumbnail and caption; tapping opens it', (
    tester,
  ) async {
    final bridge = FakeCoreBridge()
      ..messages[_chat] = [_photo('A1')]
      ..mediaParts['$_chat|A1|thumb'] = _png;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          bridge: bridge,
          chat: const ChatSummary(
            jid: _chat,
            name: 'Ana',
            lastText: '',
            lastTs: 0,
          ),
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('olha'), findsOneWidget);
    expect(find.text('[imagem] olha'), findsNothing);

    await tester.tap(find.byType(Image));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Baixando…'), findsOneWidget);
    expect(bridge.calls, contains('downloadMedia:A1'));

    bridge.mediaParts['$_chat|A1|full'] = _png;
    bridge.push('wa_media', {'chat': _chat, 'id': 'A1', 'state': 'downloaded'});
    await tester.pump();
    expect(find.byType(InteractiveViewer), findsOneWidget);

    // The conversation behind updated too: its bubble read the photo
    // itself (reads: photo screen before and after the download, bubble).
    Navigator.of(tester.element(find.byType(InteractiveViewer))).pop();
    await tester.pumpAndSettle();
    expect(bridge.calls.where((c) => c == 'mediaBytes:A1:full'), hasLength(3));
  });

  testWidgets('without a thumbnail there is a button', (tester) async {
    final bridge = FakeCoreBridge()
      ..messages[_chat] = [_photo('A2', thumb: false, media: 'remote')];
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          bridge: bridge,
          chat: const ChatSummary(
            jid: _chat,
            name: 'Ana',
            lastText: '',
            lastTs: 0,
          ),
        ),
      ),
    );
    expect(find.text('[imagem] ver foto'), findsOneWidget);
  });

  testWidgets('a downloaded photo opens without downloading again', (
    tester,
  ) async {
    final bridge = FakeCoreBridge()..mediaParts['$_chat|A3|full'] = _png;
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoScreen(
          bridge: bridge,
          message: _photo('A3', media: 'downloaded'),
        ),
      ),
    );
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(bridge.calls, isNot(contains('downloadMedia:A3')));
  });

  testWidgets('a failed download can be retried; an expired one cannot', (
    tester,
  ) async {
    final bridge = FakeCoreBridge();
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoScreen(bridge: bridge, message: _photo('A4')),
      ),
    );
    bridge.push('wa_media', {'chat': _chat, 'id': 'A4', 'state': 'failed'});
    await tester.pump();
    await tester.tap(find.textContaining('tentar de novo'));
    await tester.pump();
    expect(bridge.calls.where((c) => c == 'downloadMedia:A4'), hasLength(2));
    // Another photo's event changes nothing here.
    bridge.push('wa_media', {'chat': _chat, 'id': 'other', 'state': 'expired'});
    await tester.pump();
    expect(find.text('Foto não disponível'), findsNothing);

    bridge.push('wa_media', {'chat': _chat, 'id': 'A4', 'state': 'expired'});
    await tester.pump();
    expect(find.text('Foto não disponível'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoScreen(
          bridge: bridge,
          message: _photo('A5', media: 'expired'),
        ),
      ),
    );
    expect(find.text('Foto não disponível'), findsOneWidget);
    expect(bridge.calls, isNot(contains('downloadMedia:A5')));
  });
}
