// Lock screens with fakes.
import 'package:chat_do_garoto/src/lock/change_pin_screen.dart';
import 'package:chat_do_garoto/src/lock/create_pin_screen.dart';
import 'package:chat_do_garoto/src/lock/lock_controller.dart';
import 'package:chat_do_garoto/src/lock/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_core_bridge.dart';
import 'support/fake_key_vault.dart';
import 'support/fake_security.dart';

Future<(LockController, FakeSecurity)> _lock({bool withPin = false}) async {
  final vaults = <String, FakeKeyVault>{};
  final security = FakeSecurity();
  final lock = LockController(
    bridge: FakeCoreBridge(),
    security: security,
    vault: (name) => vaults.putIfAbsent(name, FakeKeyVault.new),
  );
  await lock.start();
  if (withPin) {
    await lock.createPin('123456', '123456');
    await lock.enableBiometrics();
    lock.lock();
    security.calls.clear();
  }
  return (lock, security);
}

Future<void> _typePin(WidgetTester tester, String pin) async {
  await tester.enterText(find.byType(TextField), pin);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('creating the PIN: twice, then biometrics are offered', (
    tester,
  ) async {
    final (lock, security) = await _lock();
    // As in the app: the home switches screens as soon as the PIN exists,
    // and the question is asked from there.
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: lock,
          builder: (context, _) {
            if (lock.state != AppLockState.unlocked) {
              return CreatePinScreen(controller: lock);
            }
            if (lock.offerBiometrics) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => offerBiometricsDialog(context, lock),
              );
            }
            return const Text('conversas');
          },
        ),
      ),
    );

    await _typePin(tester, '123456');
    expect(find.text('Digite o PIN de novo'), findsOneWidget);
    await _typePin(tester, '654321');
    expect(find.textContaining('não são iguais'), findsOneWidget);
    expect(lock.state, AppLockState.needsPin);

    await _typePin(tester, '123456');
    await _typePin(tester, '123456');
    expect(lock.state, AppLockState.unlocked);
    expect(find.text('Desbloquear com a digital?'), findsOneWidget);
    await tester.tap(find.text('Usar a digital'));
    await tester.pumpAndSettle();
    expect(lock.biometricsOn, isTrue);
    expect(security.calls, ['enroll']);
  });

  testWidgets('the lock screen shows only the PIN, then unlocks', (
    tester,
  ) async {
    final (lock, security) = await _lock(withPin: true);
    security.nextError = 'cancelled'; // the user goes for the PIN
    await tester.pumpWidget(MaterialApp(home: LockScreen(controller: lock)));
    await tester.pumpAndSettle();

    expect(security.calls, ['unlock'], reason: 'biometrics offered at once');
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toSet();
    expect(texts, {
      'Chat do Garoto',
      'Digite o PIN para abrir o app.',
      'PIN',
      'Usar a digital',
      'Esqueci o PIN',
    });

    await _typePin(tester, '000000');
    expect(find.text('PIN errado.'), findsOneWidget);
    await _typePin(tester, '123456');
    expect(lock.state, AppLockState.unlocked);
  });

  testWidgets('forgot the PIN asks before wiping', (tester) async {
    final (lock, security) = await _lock(withPin: true);
    security.nextError = 'cancelled';
    await tester.pumpWidget(MaterialApp(home: LockScreen(controller: lock)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Esqueci o PIN'));
    await tester.pumpAndSettle();
    expect(find.textContaining('conversas continuam'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(lock.state, AppLockState.locked);

    await tester.tap(find.text('Esqueci o PIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar e criar PIN novo'));
    await tester.pumpAndSettle();
    expect(lock.state, AppLockState.needsPin);
  });

  testWidgets('changing the PIN asks for the current one and the new twice', (
    tester,
  ) async {
    final (lock, _) = await _lock(withPin: true);
    await lock.unlock('123456');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChangePinScreen(controller: lock),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('PIN atual'), findsOneWidget);
    await _typePin(tester, '123456');
    await _typePin(tester, '111111');
    await _typePin(tester, '111111');
    expect(find.text('abrir'), findsOneWidget, reason: 'closed after changing');

    lock.lock();
    expect(await lock.unlock('111111'), isTrue);
  });
}
