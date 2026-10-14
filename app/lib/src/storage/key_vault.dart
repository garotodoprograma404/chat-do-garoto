import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the `app.db` key lives: the system vault (Android Keystore,
/// libsecret on Linux). Never a plain file, preferences or logs.
abstract interface class KeyVault {
  Future<String?> read();
  Future<void> write(String key);
  Future<void> delete();
}

/// [KeyVault] backed by `flutter_secure_storage`, one item per [_name].
class SecureKeyVault implements KeyVault {
  const SecureKeyVault([this._name = 'app_db_key']);

  final String _name;
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _name);

  @override
  Future<void> write(String key) => _storage.write(key: _name, value: key);

  @override
  Future<void> delete() => _storage.delete(key: _name);
}
