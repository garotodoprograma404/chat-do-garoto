import 'package:flutter/services.dart';

/// Where a player is.
typedef PlayState = ({bool playing, int position, int duration});

/// A video opened for playing: shown with `Texture(texture)`.
typedef OpenedVideo = ({int texture, int duration, int width, int height});

/// A recording, deleted from the disk as soon as it is read.
typedef Recording = ({Uint8List bytes, int ms});

/// A picked video copied without its location (when [stripped]), with a
/// thumbnail and its length.
typedef PreparedVideo = ({
  Uint8List bytes,
  int ms,
  Uint8List? thumb,
  bool stripped,
});

/// A document read straight into memory by the system picker.
typedef PickedDocument = ({String name, String mime, Uint8List bytes});

/// The Android side failed: [code] is "too_big", "unplayable",
/// "unsupported", "record_failed" or "failed".
class MediaException implements Exception {
  const MediaException(this.code);
  final String code;
}

/// Media on the phone: play from memory, record voice,
/// prepare videos, pick, open with and save documents.
abstract interface class MediaPlatform {
  /// Plays [bytes]; returns the duration in ms. Stops the audio before.
  Future<int> audioPlay(Uint8List bytes);
  Future<void> audioPause();
  Future<void> audioResume();
  Future<void> audioSeek(int ms);
  Future<void> audioStop();
  Future<PlayState> audioState();

  Future<OpenedVideo> videoOpen(Uint8List bytes);
  Future<void> videoPlay();
  Future<void> videoPause();
  Future<void> videoSeek(int ms);
  Future<PlayState> videoState();
  Future<void> videoClose();

  /// Voice messages need Android 10 or newer.
  Future<bool> canRecord();

  /// Asks for the microphone the first time; whether it may be used.
  Future<bool> micPermission();
  Future<void> recordStart();

  /// Null when nothing was recorded.
  Future<Recording?> recordStop();
  Future<void> recordCancel();

  Future<PreparedVideo> videoPrepare(String path);

  /// Null when the user backs out.
  Future<PickedDocument?> pickDocument();

  /// False when no app opens this type.
  Future<bool> openWith(Uint8List bytes, String name, String mime);

  /// False when the user backs out.
  Future<bool> saveAs(Uint8List bytes, String name, String mime);
}

/// The app's own Kotlin code (`MediaChannel.kt`).
class ChannelMediaPlatform implements MediaPlatform {
  const ChannelMediaPlatform();

  static const _channel = MethodChannel('chatdogaroto/media');

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw MediaException(e.code);
    }
  }

  PlayState _state(Map<Object?, Object?>? m) => (
    playing: m?['playing'] as bool? ?? false,
    position: m?['position'] as int? ?? 0,
    duration: m?['duration'] as int? ?? 0,
  );

  @override
  Future<int> audioPlay(Uint8List bytes) async =>
      await _call<int>('audioPlay', {'bytes': bytes}) ?? 0;

  @override
  Future<void> audioPause() => _call<void>('audioPause');

  @override
  Future<void> audioResume() => _call<void>('audioResume');

  @override
  Future<void> audioSeek(int ms) => _call<void>('audioSeek', {'ms': ms});

  @override
  Future<void> audioStop() => _call<void>('audioStop');

  @override
  Future<PlayState> audioState() async =>
      _state(await _call<Map<Object?, Object?>>('audioState'));

  @override
  Future<OpenedVideo> videoOpen(Uint8List bytes) async {
    final m = (await _call<Map<Object?, Object?>>('videoOpen', {
      'bytes': bytes,
    }))!;
    return (
      texture: m['texture'] as int,
      duration: m['duration'] as int,
      width: m['width'] as int,
      height: m['height'] as int,
    );
  }

  @override
  Future<void> videoPlay() => _call<void>('videoPlay');

  @override
  Future<void> videoPause() => _call<void>('videoPause');

  @override
  Future<void> videoSeek(int ms) => _call<void>('videoSeek', {'ms': ms});

  @override
  Future<PlayState> videoState() async =>
      _state(await _call<Map<Object?, Object?>>('videoState'));

  @override
  Future<void> videoClose() => _call<void>('videoClose');

  @override
  Future<bool> canRecord() async => await _call<bool>('canRecord') ?? false;

  @override
  Future<bool> micPermission() async =>
      await _call<bool>('micPermission') ?? false;

  @override
  Future<void> recordStart() => _call<void>('recordStart');

  @override
  Future<Recording?> recordStop() async {
    final m = await _call<Map<Object?, Object?>>('recordStop');
    if (m == null) return null;
    return (bytes: m['bytes'] as Uint8List, ms: m['ms'] as int);
  }

  @override
  Future<void> recordCancel() => _call<void>('recordCancel');

  @override
  Future<PreparedVideo> videoPrepare(String path) async {
    final m = (await _call<Map<Object?, Object?>>('videoPrepare', {
      'path': path,
    }))!;
    return (
      bytes: m['bytes'] as Uint8List,
      ms: m['ms'] as int,
      thumb: m['thumb'] as Uint8List?,
      stripped: m['stripped'] as bool,
    );
  }

  @override
  Future<PickedDocument?> pickDocument() async {
    final m = await _call<Map<Object?, Object?>>('pickDocument');
    if (m == null) return null;
    return (
      name: m['name'] as String,
      mime: m['mime'] as String,
      bytes: m['bytes'] as Uint8List,
    );
  }

  @override
  Future<bool> openWith(Uint8List bytes, String name, String mime) async =>
      await _call<bool>('openWith', {
        'bytes': bytes,
        'name': name,
        'mime': mime,
      }) ??
      false;

  @override
  Future<bool> saveAs(Uint8List bytes, String name, String mime) async =>
      await _call<bool>('saveAs', {
        'bytes': bytes,
        'name': name,
        'mime': mime,
      }) ??
      false;
}

/// The media platform screens use; tests replace it.
MediaPlatform mediaPlatform = const ChannelMediaPlatform();
