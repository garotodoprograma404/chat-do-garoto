// Audio, video and documents received in the conversation.
import 'dart:typed_data';

import 'package:chat_do_garoto/src/chats/chat_screen.dart';
import 'package:chat_do_garoto/src/chats/media/media_platform.dart';
import 'package:chat_do_garoto/src/chats/media/media_tiles.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_core_bridge.dart';
import 'support/fake_media_platform.dart';

const _chat = '5511900000001@s.whatsapp.net';

ChatMessage _media(
  String id,
  String kind, {
  String media = 'remote',
  String fileName = '',
  String mime = '',
  int size = 0,
  int seconds = 0,
  bool ptt = false,
}) => ChatMessage(
  chat: _chat,
  id: id,
  fromMe: false,
  senderName: 'Ana',
  kind: kind,
  text: '',
  ts: 1000,
  media: media,
  fileName: fileName,
  mime: mime,
  size: size,
  seconds: seconds,
  ptt: ptt,
);

Future<(FakeCoreBridge, FakeMediaPlatform)> _open(
  WidgetTester tester,
  List<ChatMessage> messages,
) async {
  final bridge = FakeCoreBridge()..messages[_chat] = messages;
  final platform = FakeMediaPlatform();
  mediaPlatform = platform;
  addTearDown(() => mediaPlatform = const ChannelMediaPlatform());
  resetOpenWithWarning();
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
  await tester.pump();
  return (bridge, platform);
}

void main() {
  test('formats', () {
    expect(formatDuration(7), '0:07');
    expect(formatDuration(754), '12:34');
    expect(formatSize(1500), '2 KB');
    expect(formatSize(1258291), '1,2 MB');
    expect(documentType('application/pdf', 'a.pdf'), 'PDF');
    expect(documentType('', 'planilha.XLSX'), 'XLSX');
    expect(documentType('', 'sem-extensao'), 'Arquivo');
  });

  testWidgets('a voice message downloads on the first tap and plays', (
    tester,
  ) async {
    final (bridge, platform) = await _open(tester, [
      _media('A1', 'audio', seconds: 7, ptt: true),
    ]);
    expect(find.text('🎤 0:07'), findsOneWidget);
    await tester.tap(find.byTooltip('Tocar'));
    await tester.pump();
    expect(bridge.calls, contains('downloadMedia:A1'));

    bridge.mediaParts['$_chat|A1|full'] = Uint8List.fromList([1, 2]);
    bridge.push('wa_media', {'chat': _chat, 'id': 'A1', 'state': 'downloaded'});
    await tester.pump();
    await tester.pump();
    expect(platform.calls, contains('audioPlay'));
    expect(platform.played, [1, 2]);

    platform.audio = (playing: true, position: 3000, duration: 7000);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('🎤 0:03 / 0:07'), findsOneWidget);

    await tester.tap(find.byTooltip('Pausar'));
    await tester.pump();
    expect(platform.calls, contains('audioPause'));

    // The end: back to the length, stopped.
    await tester.tap(find.byTooltip('Tocar'));
    await tester.pump();
    platform.audio = (playing: false, position: 7000, duration: 7000);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('🎤 0:07'), findsOneWidget);
    expect(platform.calls.last, 'audioStop'); // freed from memory
  });

  testWidgets('an audio WhatsApp no longer has', (tester) async {
    final (bridge, _) = await _open(tester, [
      _media('A2', 'audio', seconds: 3),
    ]);
    await tester.tap(find.byTooltip('Tocar'));
    await tester.pump();
    bridge.push('wa_media', {'chat': _chat, 'id': 'A2', 'state': 'expired'});
    await tester.pump();
    await tester.pump();
    expect(find.text('Áudio não disponível'), findsOneWidget);
  });

  testWidgets('a failed download offers to try again', (tester) async {
    final (bridge, _) = await _open(tester, [
      _media('A3', 'audio', seconds: 3),
    ]);
    await tester.tap(find.byTooltip('Tocar'));
    await tester.pump();
    bridge.push('wa_media', {'chat': _chat, 'id': 'A3', 'state': 'failed'});
    await tester.pump();
    await tester.pump();
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  testWidgets('a document opens with another app after the warning, or is '
      'saved', (tester) async {
    final (bridge, platform) = await _open(tester, [
      _media(
        'D1',
        'document',
        media: 'downloaded',
        fileName: 'contrato.pdf',
        mime: 'application/pdf',
        size: 1258291,
      ),
    ]);
    bridge.mediaParts['$_chat|D1|full'] = Uint8List.fromList([37, 80]);
    expect(find.text('contrato.pdf'), findsOneWidget);
    expect(find.text('PDF · 1,2 MB'), findsOneWidget);

    await tester.tap(find.text('contrato.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir com outro app'));
    await tester.pumpAndSettle();
    expect(find.textContaining('O outro app vê o arquivo'), findsOneWidget);
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(platform.opened?.name, 'contrato.pdf');
    expect(platform.opened?.mime, 'application/pdf');
    expect(platform.opened?.bytes, [37, 80]);

    // The warning shows once per run.
    await tester.tap(find.text('contrato.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir com outro app'));
    await tester.pumpAndSettle();
    expect(find.textContaining('O outro app vê o arquivo'), findsNothing);
    expect(platform.calls.where((c) => c == 'openWith'), hasLength(2));

    await tester.tap(find.text('contrato.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar no aparelho'));
    await tester.pumpAndSettle();
    expect(platform.saved?.name, 'contrato.pdf');
    expect(find.text('Documento salvo.'), findsOneWidget);
  });

  testWidgets('a video plays full screen from memory', (tester) async {
    final (bridge, platform) = await _open(tester, [
      _media(
        'V1',
        'video',
        media: 'downloaded',
        seconds: 12,
        mime: 'video/mp4',
      ),
    ]);
    bridge.mediaParts['$_chat|V1|full'] = Uint8List.fromList([1, 2, 3]);
    expect(find.text('▶ 0:12'), findsOneWidget);
    await tester.tap(find.text('▶ 0:12'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(platform.calls, containsAll(['videoOpen:3', 'videoPlay']));
    expect(find.byType(Texture), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byTooltip('Pausar'));
    await tester.pump();
    expect(platform.calls, contains('videoPause'));

    Navigator.of(tester.element(find.byType(Texture))).pop();
    await tester.pumpAndSettle();
    expect(platform.calls, contains('videoClose'));
  });

  testWidgets('media from before 3.6 keep their marker', (tester) async {
    await _open(tester, [_media('O1', 'audio', media: '')]);
    expect(find.text('[áudio]'), findsOneWidget);
  });
}
