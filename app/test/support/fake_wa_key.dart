import 'package:chat_do_garoto/src/platform/wa_key.dart';

/// A fixed session key for tests.
class FakeWaKeyProvider implements WaKeyProvider {
  static const value =
      '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

  @override
  Future<String> key() async => value;
}
