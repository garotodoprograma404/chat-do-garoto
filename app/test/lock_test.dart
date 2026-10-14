// The app lock with fake bridge, vault, biometrics and clock.
import 'package:chat_do_garoto/src/lock/lock_controller.dart';
import 'package:chat_do_garoto/src/storage/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_core_bridge.dart';
import 'support/fake_key_vault.dart';
import 'support/fake_security.dart';

class _World {
  _World() {
    lock = LockController(
      bridge: bridge,
      security: security,
      vault: (name) => vaults.putIfAbsent(name, FakeKeyVault.new),
      clock: () => now,
      wipeData: () async => wiped++,
    );
  }

  final bridge = FakeCoreBridge();
  final security = FakeSecurity();
  final vaults = <String, FakeKeyVault>{};
  DateTime now = DateTime(2026, 10, 1, 12);
  int wiped = 0;
  late LockController lock;

  String? item(String name) => vaults[name]?.key;

  Future<void> restart() async {
    final again = LockController(
      bridge: bridge,
      security: security,
      vault: (name) => vaults.putIfAbsent(name, FakeKeyVault.new),
      clock: () => now,
    );
    await again.start();
    lock = again;
  }

  /// A world where the PIN 123456 exists and the app is unlocked.
  static Future<_World> withPin() async {
    final w = _World();
    await w.lock.start();
    await w.lock.createPin('123456', '123456');
    return w;
  }
}

void main() {
  test('without a PIN the app asks to create one', () async {
    final w = _World();
    await w.lock.start();
    expect(w.lock.state, AppLockState.needsPin);
  });

  test('creating the PIN needs 6 digits typed twice', () async {
    final w = _World();
    await w.lock.start();
    expect(await w.lock.createPin('12345', '12345'), isFalse);
    expect(await w.lock.createPin('12345a', '12345a'), isFalse);
    expect(await w.lock.createPin('123456', '123457'), isFalse);
    expect(w.lock.message, contains('não são iguais'));
    expect(await w.lock.createPin('123456', '123456'), isTrue);
    expect(w.lock.state, AppLockState.unlocked);
    expect(w.lock.key, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(w.item(LockController.pinItem), isNotNull);
    expect(w.lock.offerBiometrics, isTrue, reason: 'asked once afterwards');
  });

  test('the app.db key of delivery 2.1 is kept under the PIN', () async {
    final w = _World();
    final old = newDatabaseKey();
    w.vaults[LockController.legacyItem] = FakeKeyVault()..key = old;
    await w.lock.start();
    await w.lock.createPin('123456', '123456');
    expect(w.lock.key, old);
    expect(w.item(LockController.legacyItem), isNull);
  });

  test(
    'a fresh start is locked; the right PIN unlocks with the same key',
    () async {
      final w = await _World.withPin();
      final key = w.lock.key;
      await w.restart();
      expect(w.lock.state, AppLockState.locked);
      expect(w.lock.key, isNull);
      expect(await w.lock.unlock('123456'), isTrue);
      expect(w.lock.key, key);
    },
  );

  test(
    'wrong PINs wait 30 s after five, doubling, and survive a restart',
    () async {
      final w = await _World.withPin();
      w.lock.lock();
      for (var i = 0; i < 4; i++) {
        expect(await w.lock.unlock('000000'), isFalse);
        expect(w.lock.waitUntil, isNull);
      }
      expect(await w.lock.unlock('000000'), isFalse);
      expect(w.lock.waitUntil, w.now.add(const Duration(seconds: 30)));

      await w.restart();
      expect(w.lock.message, contains('PIN bloqueado por erros'));
      expect(await w.lock.unlock('123456'), isFalse, reason: 'still waiting');
      expect(w.lock.message, contains('Tente de novo em'));

      w.now = w.now.add(const Duration(seconds: 31));
      expect(await w.lock.unlock('000000'), isFalse);
      expect(w.lock.waitUntil, w.now.add(const Duration(minutes: 1)));

      w.now = w.now.add(const Duration(minutes: 2));
      expect(await w.lock.unlock('123456'), isTrue);
      expect(w.item(LockController.attemptsItem), isNull);
    },
  );

  test('the wait grows up to an hour', () {
    expect(LockController.waitAfter(4), Duration.zero);
    expect(LockController.waitAfter(5), const Duration(seconds: 30));
    expect(LockController.waitAfter(7), const Duration(minutes: 2));
    expect(LockController.waitAfter(30), const Duration(hours: 1));
  });

  test('locks after more than a minute away, not less', () async {
    final w = await _World.withPin();
    w.lock.onBackground();
    w.now = w.now.add(const Duration(seconds: 50));
    w.lock.onForeground();
    expect(w.lock.state, AppLockState.unlocked);

    w.lock.onBackground();
    w.now = w.now.add(const Duration(seconds: 61));
    w.lock.onForeground();
    expect(w.lock.state, AppLockState.locked);
    expect(w.lock.key, isNull);
  });

  test('five minutes away only for the gallery or camera', () async {
    final w = await _World.withPin();
    w.lock.expectExternal();
    w.lock.onBackground();
    w.now = w.now.add(const Duration(minutes: 4));
    w.lock.externalDone(); // the photo arrives before the app shows
    w.lock.onForeground();
    expect(w.lock.state, AppLockState.unlocked);

    // Back to a minute afterwards.
    w.lock.onBackground();
    w.now = w.now.add(const Duration(seconds: 61));
    w.lock.onForeground();
    expect(w.lock.state, AppLockState.locked);
  });

  test('more than five minutes in the camera still locks', () async {
    final w = await _World.withPin();
    w.lock.expectExternal();
    w.lock.onBackground();
    w.now = w.now.add(const Duration(minutes: 5, seconds: 1));
    w.lock.onForeground();
    expect(w.lock.state, AppLockState.locked);
  });

  test('a picker that never left changes nothing', () async {
    final w = await _World.withPin();
    w.lock.expectExternal();
    w.lock.externalDone();
    w.lock.onBackground();
    w.now = w.now.add(const Duration(seconds: 61));
    w.lock.onForeground();
    expect(w.lock.state, AppLockState.locked);
  });

  test('locks after five minutes without a touch', () async {
    final w = await _World.withPin();
    w.now = w.now.add(const Duration(minutes: 4));
    w.lock.touched();
    w.now = w.now.add(const Duration(minutes: 4));
    w.lock.checkIdle();
    expect(w.lock.state, AppLockState.unlocked);
    w.now = w.now.add(const Duration(minutes: 2));
    w.lock.checkIdle();
    expect(w.lock.state, AppLockState.locked);
  });

  test('biometrics unlock; cancelling goes back to the PIN', () async {
    final w = await _World.withPin();
    final key = w.lock.key;
    expect(await w.lock.enableBiometrics(), isTrue);
    expect(w.lock.biometricsOn, isTrue);
    w.lock.lock();

    w.security.nextError = 'cancelled';
    expect(await w.lock.unlockWithBiometrics(), isFalse);
    expect(w.lock.state, AppLockState.locked);
    expect(w.lock.biometricsOn, isTrue);

    w.security.nextError = null;
    expect(await w.lock.unlockWithBiometrics(), isTrue);
    expect(w.lock.key, key);
  });

  test('a new fingerprint on the phone turns biometrics off', () async {
    final w = await _World.withPin();
    await w.lock.enableBiometrics();
    w.lock.lock();
    w.security.nextError = 'invalidated';
    expect(await w.lock.unlockWithBiometrics(), isFalse);
    expect(w.lock.biometricsOn, isFalse);
    expect(w.item(LockController.bioItem), isNull);
    expect(w.lock.message, contains('digital do celular mudou'));
  });

  test('changing the PIN needs the current one', () async {
    final w = await _World.withPin();
    final key = w.lock.key;
    expect(await w.lock.changePin('000000', '654321', '654321'), isFalse);
    expect(await w.lock.changePin('123456', '654321', '654321'), isTrue);
    w.lock.lock();
    expect(await w.lock.unlock('123456'), isFalse);
    expect(await w.lock.unlock('654321'), isTrue);
    expect(w.lock.key, key);
  });

  test(
    'forgot the PIN wipes only the app data and asks for a new one',
    () async {
      final w = await _World.withPin();
      await w.lock.enableBiometrics();
      w.lock.lock();
      await w.lock.forgotPin();
      expect(w.wiped, 1);
      expect(w.lock.state, AppLockState.needsPin);
      expect(w.item(LockController.pinItem), isNull);
      expect(w.item(LockController.bioItem), isNull);
      expect(w.security.calls, contains('disable'));
      expect(w.bridge.calls, isNot(contains('resetWhatsApp')));
    },
  );
}
