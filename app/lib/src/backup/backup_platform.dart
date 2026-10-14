import 'package:flutter/services.dart';

/// The backup file on the device: the system picker creates or
/// opens it and hands over a file descriptor for the core, which writes or
/// reads it as a stream and closes it.
abstract interface class BackupPlatform {
  /// Asks where to save [name]; null when the user cancelled.
  Future<({int fd, String uri})?> create(String name);

  /// Asks which backup to open; null when the user cancelled.
  Future<int?> open();

  /// Deletes a file [create] made (a cancelled or failed backup).
  Future<bool> delete(String uri);
}

/// [BackupPlatform] on Android ("chatdogaroto/backup", `BackupChannel.kt`).
class ChannelBackupPlatform implements BackupPlatform {
  const ChannelBackupPlatform();

  static const _channel = MethodChannel('chatdogaroto/backup');

  @override
  Future<({int fd, String uri})?> create(String name) async {
    final r = await _channel.invokeMapMethod<String, Object?>('create', {
      'name': name,
    });
    if (r == null) return null;
    return (fd: r['fd']! as int, uri: r['uri']! as String);
  }

  @override
  Future<int?> open() => _channel.invokeMethod<int>('open');

  @override
  Future<bool> delete(String uri) async =>
      await _channel.invokeMethod<bool>('delete', {'uri': uri}) ?? false;
}
