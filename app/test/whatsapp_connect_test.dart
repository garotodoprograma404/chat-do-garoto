// Connection screen and controller states with a fake bridge.
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:chat_do_garoto/src/whatsapp/connect_screen.dart';
import 'package:chat_do_garoto/src/whatsapp/whatsapp_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'support/fake_connection_keeper.dart';
import 'support/fake_core_bridge.dart';
import 'support/fake_wa_key.dart';

final keeper = FakeConnectionKeeper();

Future<(FakeCoreBridge, WhatsAppController)> _open(
  WidgetTester tester, {
  bool paired = false,
}) async {
  keeper.running = false;
  final bridge = FakeCoreBridge(paired: paired);
  final controller = WhatsAppController(
    bridge: bridge,
    sessionPath: () async => '/tmp/test-wa.db',
    keeper: keeper,
    keys: FakeWaKeyProvider(),
  );
  await controller.start();
  await tester.pumpWidget(
    MaterialApp(home: ConnectScreen(controller: controller)),
  );
  return (bridge, controller);
}

Future<void> _chooseCode(WidgetTester tester) async {
  await tester.tap(find.text('Com código'));
  await tester.pump();
}

void main() {
  testWidgets('without a saved session, offers code and QR', (tester) async {
    final (bridge, _) = await _open(tester);

    expect(bridge.calls, ['diagnostics:true', 'startWhatsApp']);
    expect(find.text('Conectar ao WhatsApp'), findsOneWidget);
    expect(find.text('Com código'), findsOneWidget);
    expect(find.text('Com QR Code'), findsOneWidget);
  });

  testWidgets('with a saved session, connects without pairing', (tester) async {
    final (bridge, _) = await _open(tester, paired: true);

    expect(find.text('Conectando ao WhatsApp…'), findsOneWidget);
    bridge.push('wa_connected', {'push_name': 'Rafael'});
    await tester.pump();
    expect(find.text('Conectado como Rafael'), findsOneWidget);
  });

  testWidgets('an invalid number shows a validation error', (tester) async {
    final (bridge, _) = await _open(tester);
    bridge.pairingCodeError = const CoreException(
      'invalid_argument',
      'phone number too short',
    );
    await _chooseCode(tester);

    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('Gerar código'));
    await tester.pump();

    expect(find.textContaining('Número inválido'), findsOneWidget);
  });

  testWidgets('shows the pairing code sent by WhatsApp', (tester) async {
    final (bridge, _) = await _open(tester);
    await _chooseCode(tester);

    await tester.enterText(find.byType(TextField), '55 11 99999-0000');
    await tester.tap(find.text('Gerar código'));
    await tester.pump();
    expect(bridge.calls, contains('requestPairingCode'));
    expect(find.text('Pedindo o código ao WhatsApp…'), findsOneWidget);

    bridge.push('wa_pair_code', {'code': 'ABCD-EFGH'});
    await tester.pump();
    expect(find.text('ABCD-EFGH'), findsOneWidget);
    expect(
      find.textContaining('Conectar com número de telefone'),
      findsOneWidget,
    );
  });

  testWidgets('shows the QR code sent by WhatsApp', (tester) async {
    final (bridge, _) = await _open(tester);
    await tester.tap(find.text('Com QR Code'));
    await tester.pump();

    bridge.push('wa_qr', {'code': '2@abc,def,ghi', 'timeout_ms': 60000});
    await tester.pump();
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('pairing then connecting shows the account', (tester) async {
    final (bridge, _) = await _open(tester);

    bridge.push('wa_paired');
    await tester.pump();
    expect(find.text('Conectando ao WhatsApp…'), findsOneWidget);

    bridge.push('wa_connected', {'push_name': ''});
    await tester.pump();
    expect(find.text('Conectado ao WhatsApp'), findsOneWidget);
  });

  testWidgets('Desconectar asks the core to log out', (tester) async {
    final (bridge, _) = await _open(tester, paired: true);
    bridge.push('wa_connected', {'push_name': 'Rafael'});
    await tester.pump();

    await tester.tap(find.text('Desconectar'));
    await tester.pump();
    expect(bridge.calls, contains('logoutWhatsApp'));
    expect(find.text('Desconectando…'), findsOneWidget);
  });

  testWidgets('removed by the phone: notice and pairing again', (tester) async {
    final (bridge, _) = await _open(tester, paired: true);
    bridge.push('wa_connected', {'push_name': 'Rafael'});
    await tester.pump();

    bridge.paired = false;
    bridge.push('wa_logged_out', {'reason': 'removed_by_phone'});
    await tester.pump(); // start() runs again
    await tester.pump();

    expect(find.textContaining('encerrada pelo celular'), findsOneWidget);
    expect(find.text('Conectar ao WhatsApp'), findsOneWidget);
    expect(bridge.calls.where((c) => c == 'startWhatsApp'), hasLength(2));
  });

  testWidgets('connection errors become readable messages', (tester) async {
    final (bridge, _) = await _open(tester);

    bridge.push('wa_error', {'code': 'connect_failed'});
    await tester.pump();
    expect(find.textContaining('Verifique a internet'), findsOneWidget);
  });

  testWidgets('keep-alive runs while pairing and stops on logout', (
    tester,
  ) async {
    final (bridge, _) = await _open(tester);
    expect(keeper.running, isFalse);
    await _chooseCode(tester);

    await tester.enterText(find.byType(TextField), '55 11 99999-0000');
    await tester.tap(find.text('Gerar código'));
    await tester.pump();
    expect(keeper.running, isTrue);

    bridge.push('wa_logged_out', {'reason': 'user'});
    await tester.pump();
    expect(keeper.running, isFalse);
  });

  testWidgets('a saved session starts the keep-alive', (tester) async {
    await _open(tester, paired: true);
    expect(keeper.running, isTrue);
  });

  testWidgets('expired pairing window warns and code reopens it', (
    tester,
  ) async {
    final (bridge, _) = await _open(tester);
    await _chooseCode(tester);

    bridge.push('wa_qr_expired');
    await tester.pump();
    expect(find.textContaining('O tempo para conectar acabou'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '55 11 99999-0000');
    await tester.tap(find.text('Gerar código'));
    await tester.pump();
    await tester.pump();

    expect(bridge.calls.where((c) => c == 'startWhatsApp'), hasLength(2));
    expect(bridge.calls.last, 'requestPairingCode');
    expect(find.textContaining('O tempo para conectar acabou'), findsNothing);
  });

  testWidgets('expired QR offers a new one', (tester) async {
    final (bridge, _) = await _open(tester);
    await tester.tap(find.text('Com QR Code'));
    await tester.pump();

    bridge.push('wa_qr_expired');
    await tester.pump();
    await tester.tap(find.text('Gerar novo QR Code'));
    await tester.pump();
    await tester.pump();

    expect(bridge.calls.where((c) => c == 'startWhatsApp'), hasLength(2));
  });
}
