import 'dart:typed_data';

import 'package:chat_do_garoto/src/chats/media/media_platform.dart';

/// In-memory [MediaPlatform]: records calls, plays nothing.
class FakeMediaPlatform implements MediaPlatform {
  final calls = <String>[];

  /// What the players report.
  PlayState audio = (playing: false, position: 0, duration: 0);
  PlayState video = (playing: false, position: 0, duration: 0);
  Uint8List? played;

  bool micAllowed = true;
  Recording? recording = (bytes: Uint8List.fromList([1, 2, 3]), ms: 2500);
  PreparedVideo prepared = (
    bytes: Uint8List.fromList([9, 9]),
    ms: 4000,
    thumb: null,
    stripped: true,
  );
  PickedDocument? document = (
    name: 'contrato.pdf',
    mime: 'application/pdf',
    bytes: Uint8List.fromList([37, 80, 68, 70]),
  );
  bool openWithResult = true;
  bool saveResult = true;
  ({Uint8List bytes, String name, String mime})? opened;
  ({Uint8List bytes, String name, String mime})? saved;

  @override
  Future<int> audioPlay(Uint8List bytes) async {
    calls.add('audioPlay');
    played = bytes;
    audio = (playing: true, position: 0, duration: 7000);
    return 7000;
  }

  @override
  Future<void> audioPause() async {
    calls.add('audioPause');
    audio = (playing: false, position: audio.position, duration: 7000);
  }

  @override
  Future<void> audioResume() async {
    calls.add('audioResume');
    audio = (playing: true, position: audio.position, duration: 7000);
  }

  @override
  Future<void> audioSeek(int ms) async => calls.add('audioSeek:$ms');

  @override
  Future<void> audioStop() async => calls.add('audioStop');

  @override
  Future<PlayState> audioState() async => audio;

  @override
  Future<OpenedVideo> videoOpen(Uint8List bytes) async {
    calls.add('videoOpen:${bytes.length}');
    video = (playing: false, position: 0, duration: 12000);
    return (texture: 7, duration: 12000, width: 640, height: 360);
  }

  @override
  Future<void> videoPlay() async {
    calls.add('videoPlay');
    video = (playing: true, position: video.position, duration: 12000);
  }

  @override
  Future<void> videoPause() async {
    calls.add('videoPause');
    video = (playing: false, position: video.position, duration: 12000);
  }

  @override
  Future<void> videoSeek(int ms) async => calls.add('videoSeek:$ms');

  @override
  Future<PlayState> videoState() async => video;

  @override
  Future<void> videoClose() async => calls.add('videoClose');

  bool recordable = true;

  @override
  Future<bool> canRecord() async => recordable;

  @override
  Future<bool> micPermission() async {
    calls.add('micPermission');
    return micAllowed;
  }

  @override
  Future<void> recordStart() async => calls.add('recordStart');

  @override
  Future<Recording?> recordStop() async {
    calls.add('recordStop');
    return recording;
  }

  @override
  Future<void> recordCancel() async => calls.add('recordCancel');

  @override
  Future<PreparedVideo> videoPrepare(String path) async {
    calls.add('videoPrepare');
    return prepared;
  }

  @override
  Future<PickedDocument?> pickDocument() async {
    calls.add('pickDocument');
    return document;
  }

  @override
  Future<bool> openWith(Uint8List bytes, String name, String mime) async {
    calls.add('openWith');
    opened = (bytes: bytes, name: name, mime: mime);
    return openWithResult;
  }

  @override
  Future<bool> saveAs(Uint8List bytes, String name, String mime) async {
    calls.add('saveAs');
    saved = (bytes: bytes, name: name, mime: mime);
    return saveResult;
  }
}
