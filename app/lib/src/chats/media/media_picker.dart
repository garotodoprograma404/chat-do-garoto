import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../products/product_photos.dart' show cleanPhotoLeftovers;
import 'media_platform.dart';

/// Photos, videos and documents to send.
abstract interface class ChatMediaPicker {
  /// A photo from the camera or the gallery; null when cancelled.
  Future<Uint8List?> photo({required bool camera});

  /// A video copied without its location (when it could be), with its
  /// thumbnail and length; null when cancelled. Throws [MediaException]
  /// "too_big" above 64 MB.
  Future<PreparedVideo?> video({required bool camera});

  /// A document through the system picker; null when cancelled. Throws
  /// [MediaException] "too_big" above 100 MB.
  Future<PickedDocument?> document();
}

/// The system's camera, gallery and file picker. The temporary files are
/// deleted at once, and the lock allows five minutes away while they are on
/// screen.
class DeviceChatMediaPicker implements ChatMediaPicker {
  DeviceChatMediaPicker({this.onLeave, this.onBack, MediaPlatform? platform})
    : _platform = platform ?? mediaPlatform;

  final VoidCallback? onLeave;
  final VoidCallback? onBack;
  final MediaPlatform _platform;
  final _picker = ImagePicker();

  Future<T> _away<T>(Future<T> Function() pick) async {
    onLeave?.call();
    try {
      return await pick();
    } finally {
      onBack?.call();
    }
  }

  ImageSource _source(bool camera) =>
      camera ? ImageSource.camera : ImageSource.gallery;

  @override
  Future<Uint8List?> photo({required bool camera}) => _away(() async {
    final file = await _picker.pickImage(
      source: _source(camera),
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (file == null) return null;
    try {
      return await file.readAsBytes();
    } finally {
      await cleanPhotoLeftovers();
    }
  });

  @override
  Future<PreparedVideo?> video({required bool camera}) => _away(() async {
    final file = await _picker.pickVideo(source: _source(camera));
    if (file == null) return null;
    try {
      return await _platform.videoPrepare(file.path);
    } finally {
      await cleanPhotoLeftovers();
    }
  });

  @override
  Future<PickedDocument?> document() => _away(_platform.pickDocument);
}

/// The picker the conversation uses; set by the app with the lock's hooks,
/// replaced in tests. Null where media cannot be picked.
ChatMediaPicker? chatMediaPicker;
