import 'dart:io';

import 'package:flutter/services.dart';

import '../storage/app_storage.dart';
import '../storage/key_vault.dart';

/// The key of `wa.db`, the Go session database. On
/// Android it is kept by Kotlin, wrapped by the Keystore, so the connection
/// service can open the database without the app on screen; elsewhere it
/// lives in the system vault. Never log it.
abstract interface class WaKeyProvider {
  Future<String> key();
}

class PlatformWaKeyProvider implements WaKeyProvider {
  const PlatformWaKeyProvider();

  static const _channel = MethodChannel('chatdogaroto/connection');
  static const _vault = SecureKeyVault('wa_db_key');

  @override
  Future<String> key() async {
    if (Platform.isAndroid) {
      final key = await _channel.invokeMethod<String>('waKey');
      if (key == null) throw StateError('no session key');
      return key;
    }
    final stored = await _vault.read();
    if (stored != null) return stored;
    final created = newDatabaseKey();
    await _vault.write(created);
    return created;
  }
}
