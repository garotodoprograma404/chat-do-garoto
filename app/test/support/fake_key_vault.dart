import 'package:chat_do_garoto/src/storage/key_vault.dart';

/// In-memory [KeyVault] for tests.
class FakeKeyVault implements KeyVault {
  String? key;

  @override
  Future<String?> read() async => key;

  @override
  Future<void> write(String value) async => key = value;

  @override
  Future<void> delete() async => key = null;
}
