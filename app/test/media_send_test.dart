// Sending photos, videos, documents and voice messages.
import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_do_garoto/src/chats/chat_screen.dart';
import 'package:chat_do_garoto/src/chats/media/media_picker.dart';
import 'package:chat_do_garoto/src/chats/media/media_platform.dart';
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_core_bridge.dart';
import 'support/fake_media_platform.dart';

const _chat = '5511900000001@s.whatsapp.net';

// A 1x1 PNG.
final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  ),
);

class _FakePicker implements ChatMediaPicker {
  Uint8List? photoBytes = _png;
  PreparedVideo? prepared = (
    bytes: Uint8List.fromList([9, 9, 9]),
    ms: 4000,
    thumb: _png,
    stripped: true,
  );
  PickedDocument? doc = (
    name: 'contrato.pdf',
    mime: 'application/pdf',
    bytes: Uint8List(1500),
  );
  MediaException? error;
  final asked = <String>[];

  @override
  Future<Uint8List?> photo({required bool camera}) async {
    asked.add(camera ? 'camera-photo' : 'gallery-photo');
    return photoBytes;
  }

  @override
  Future<PreparedVideo?> video({required bool camera}) async {
    asked.add(camera ? 'camera-video' : 'gallery-video');
    if (error case final e?) throw e;
    return prepared;
  }

  @override
  Future<PickedDocument?> document() async {
    asked.add('document');
    if (error case final e?) throw e;
    return doc;
  }
}

Future<(FakeCoreBridge, FakeMediaPlatform, _FakePicker)> _open(
  WidgetTester tester,
) async {
  final bridge = FakeCoreBridge()..messages[_chat] = [];
  final platform = FakeMediaPlatform();
  final picker = _FakePicker();
  mediaPlatform = platform;
  chatMediaPicker = picker;
  addTearDown(() {
    mediaPlatform = const ChannelMediaPlatform();
    chatMediaPicker = null;
  });
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
  await tester.pumpAndSettle();
  return (bridge, platform, picker);
}

Future<void> _choose(WidgetTester tester, String option) async {
  await tester.tap(find.byTooltip('Anexar'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a photo with a caption', (tester) async {
    final (bridge, _, picker) = await _open(tester);
    await _choose(tester, 'Tirar foto');
    expect(picker.asked, ['camera-photo']);
    expect(find.text('Enviar foto'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Legenda'), 'olha');
    await tester.tap(find.byTooltip('Enviar').last);
    await tester.pumpAndSettle();
    final sent = bridge.sentMedia.single;
    expect(sent.kind, 'image');
    expect(sent.caption, 'olha');
    expect(sent.bytes, _png);
    // The message shows at once, as "sending".
    expect(find.text('olha'), findsOneWidget);
  });

  testWidgets('a document is confirmed; too big is explained', (tester) async {
    final (bridge, _, picker) = await _open(tester);
    await _choose(tester, 'Documento');
    expect(find.text('contrato.pdf (2 KB)'), findsOneWidget);
    await tester.tap(find.text('Enviar').last);
    await tester.pumpAndSettle();
    final sent = bridge.sentMedia.single;
    expect(sent.kind, 'document');
    expect(sent.fileName, 'contrato.pdf');
    expect(sent.mime, 'application/pdf');

    picker.error = const MediaException('too_big');
    await _choose(tester, 'Documento');
    expect(find.text('Documentos até 100 MB.'), findsOneWidget);
    expect(bridge.sentMedia, hasLength(1));
  });

  testWidgets('a video without its location, or with it after asking', (
    tester,
  ) async {
    final (bridge, _, picker) = await _open(tester);
    picker.prepared = (
      bytes: Uint8List.fromList([7]),
      ms: 4000,
      thumb: _png,
      stripped: false,
    );
    await _choose(tester, 'Vídeo da galeria');
    expect(find.text('Enviar com a localização?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Enviar vídeo'), findsNothing);

    await _choose(tester, 'Vídeo da galeria');
    await tester.tap(find.text('Enviar').last);
    await tester.pumpAndSettle();
    expect(find.text('Enviar vídeo'), findsOneWidget);
    expect(find.text('▶ 0:04'), findsOneWidget);
    await tester.tap(find.byTooltip('Enviar').last);
    await tester.pumpAndSettle();
    final sent = bridge.sentMedia.single;
    expect(sent.kind, 'video');
    expect(sent.seconds, 4);
    expect(sent.thumb, _png);
  });

  testWidgets('the app limit from the core is explained', (tester) async {
    final (bridge, _, _) = await _open(tester);
    bridge.sendError = const CoreException('too_big', 'media is too big');
    await _choose(tester, 'Foto da galeria');
    await tester.tap(find.byTooltip('Enviar').last);
    await tester.pumpAndSettle();
    expect(find.text('Arquivo grande demais para enviar.'), findsOneWidget);
  });

  group('voice', () {
    Future<TestGesture> hold(WidgetTester tester) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('Gravar mensagem de voz')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump();
      return gesture;
    }

    testWidgets('the microphone replaces send while the box is empty', (
      tester,
    ) async {
      await _open(tester);
      expect(find.bySemanticsLabel('Gravar mensagem de voz'), findsOneWidget);
      expect(find.byTooltip('Enviar'), findsNothing);
      await tester.enterText(find.byType(TextField), 'oi');
      await tester.pump();
      expect(find.byTooltip('Enviar'), findsOneWidget);
    });

    testWidgets('hold, release: sent as a voice message', (tester) async {
      final (bridge, platform, _) = await _open(tester);
      final gesture = await hold(tester);
      expect(platform.calls, containsAll(['micPermission', 'recordStart']));
      expect(find.textContaining('Gravando 0:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('Gravando 0:02'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(platform.calls, contains('recordStop'));
      final sent = bridge.sentMedia.single;
      expect(sent.kind, 'audio');
      expect(sent.ptt, isTrue);
      expect(sent.seconds, 3); // 2,5 s
      expect(sent.mime, 'audio/ogg; codecs=opus');
    });

    testWidgets('drag left to cancel', (tester) async {
      final (bridge, platform, _) = await _open(tester);
      final gesture = await hold(tester);
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump();
      expect(find.text('Solte para cancelar'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(platform.calls, contains('recordCancel'));
      expect(bridge.sentMedia, isEmpty);
    });

    testWidgets('too short, and without the microphone', (tester) async {
      final (bridge, platform, _) = await _open(tester);
      platform.recording = (bytes: Uint8List.fromList([1]), ms: 500);
      var gesture = await hold(tester);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Áudio curto demais.'), findsOneWidget);
      expect(bridge.sentMedia, isEmpty);

      platform.micAllowed = false;
      ScaffoldMessenger.of(tester.element(find.byType(ChatScreen)))
          .clearSnackBars();
      await tester.pumpAndSettle(); // the snack bar covered the microphone
      gesture = await hold(tester);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        find.text('Sem a permissão do microfone não dá para gravar.'),
        findsOneWidget,
      );
    });

    testWidgets('Android older than 10 shows no microphone', (tester) async {
      final bridge = FakeCoreBridge()..messages[_chat] = [];
      mediaPlatform = FakeMediaPlatform()..recordable = false;
      addTearDown(() => mediaPlatform = const ChannelMediaPlatform());
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
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Gravar mensagem de voz'), findsNothing);
      expect(find.byTooltip('Enviar'), findsOneWidget);
    });
  });

  testWidgets('hold a message to forward it; forwarded ones say so', (
    tester,
  ) async {
    const bia = '5511900000002@s.whatsapp.net';
    final bridge = FakeCoreBridge()
      ..chats = const [
        ChatSummary(jid: bia, name: 'Bia', lastText: '', lastTs: 2),
        ChatSummary(jid: _chat, name: 'Ana', lastText: '', lastTs: 1),
      ]
      ..messages[_chat] = const [
        ChatMessage(
          chat: _chat,
          id: 'T1',
          fromMe: false,
          senderName: 'Ana',
          kind: 'text',
          text: 'bom dia',
          ts: 1,
        ),
        ChatMessage(
          chat: _chat,
          id: 'T2',
          fromMe: false,
          senderName: 'Ana',
          kind: 'text',
          text: 'veio de outro lugar',
          ts: 2,
          forwarded: true,
        ),
      ];
    mediaPlatform = FakeMediaPlatform();
    addTearDown(() => mediaPlatform = const ChannelMediaPlatform());
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
    await tester.pumpAndSettle();
    expect(find.text('↪ Encaminhada'), findsOneWidget);

    await tester.longPress(find.text('bom dia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encaminhar'));
    await tester.pumpAndSettle();
    expect(find.text('Encaminhar para'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'bi');
    await tester.pump();
    expect(find.text('Ana'), findsNothing);
    await tester.tap(find.text('Bia'));
    await tester.pumpAndSettle();
    expect(bridge.calls, contains('forward:T1:$bia'));
    expect(find.text('Encaminhada para Bia.'), findsOneWidget);
  });
}
