import 'package:chat_do_garoto/src/lock/security_platform.dart';

/// Biometrics that succeed, cancel or are invalidated on demand.
class FakeSecurity implements SecurityPlatform {
  bool available = true;

  /// What the next prompt does: null succeeds, otherwise the error code.
  String? nextError;
  final calls = <String>[];

  @override
  Future<bool> biometricsAvailable() async => available;

  @override
  Future<String> enrollBiometrics(String secretHex) async {
    calls.add('enroll');
    if (nextError case final code?) throw BiometricException(code);
    return 'bio:$secretHex';
  }

  @override
  Future<String> unlockWithBiometrics(String blob) async {
    calls.add('unlock');
    if (nextError case final code?) throw BiometricException(code);
    return blob.substring(4);
  }

  @override
  Future<void> disableBiometrics() async => calls.add('disable');

  @override
  Future<Map<String, String>> keyInfo() async => {'wa_db_wrap': 'tee'};
}
