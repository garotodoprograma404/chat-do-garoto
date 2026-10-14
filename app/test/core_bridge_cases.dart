// Bridge test cases against the real Go core, shared by the host tests
// (test/core_bridge_test.dart) and the on-device tests
// (integration_test/core_bridge_device_test.dart).
import 'dart:typed_data';
import 'dart:ffi';

import 'package:chat_do_garoto/src/core_bridge/chatcore.g.dart' as native;
import 'package:chat_do_garoto/src/core_bridge/core_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

/// Defines the bridge tests. The build hook provides libchatcore for the
/// platform the tests run on.
void defineCoreBridgeCases() {
  final bridge = NativeCoreBridge();

  test('reports the core and Go versions', () {
    final version = bridge.version();

    expect(version.core, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    expect(version.go, startsWith('go1.'));
  });

  test('echo returns UTF-8 text unchanged', () {
    const samples = [
      '',
      'Olá, ação! 🚀',
      '日本語 · Ελληνικά · العربية',
      'aspas "duplas", barra \\ e\nquebra de linha',
    ];
    for (final text in samples) {
      expect(bridge.echo(text), text);
    }
    final long = 'ç' * 100000;
    expect(bridge.echo(long), long);
  });

  test('a null input comes back as invalid_argument, without crashing', () {
    expect(
      () => callNative(() => native.cc_echo(nullptr)),
      throwsA(
        isA<CoreException>().having((e) => e.code, 'code', 'invalid_argument'),
      ),
    );
    expect(bridge.echo('still alive'), 'still alive');
  });

  test('10,000 calls leave no string unreleased', () {
    for (var i = 0; i < 10000; i++) {
      expect(bridge.echo('mensagem $i'), 'mensagem $i');
    }
    expect(bridge.liveAllocations, 0);
  });

  test('listing chats before the session starts is invalid_state', () {
    expect(
      () => bridge.listChats(),
      throwsA(
        isA<CoreException>().having((e) => e.code, 'code', 'invalid_state'),
      ),
    );
    expect(
      () => bridge.listMessages(''),
      throwsA(
        isA<CoreException>().having((e) => e.code, 'code', 'invalid_argument'),
      ),
    );
    expect(bridge.liveAllocations, 0);
  });

  test('the session key is checked before anything opens', () {
    expect(
      () => bridge.startWhatsApp('/nonexistent/wa.db', 'not-a-key'),
      throwsA(
        isA<CoreException>()
            .having((e) => e.code, 'code', 'invalid_argument')
            .having((e) => e.message, 'message', isNot(contains('not-a-key'))),
      ),
    );
    bridge.resetWhatsApp('/nonexistent/wa.db'); // nothing to delete: fine
    expect(bridge.liveAllocations, 0);
  });

  test('a PIN envelope opens only with the same PIN', () async {
    const secret =
        '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
    final envelope = await bridge.sealWithPin('123456', secret);
    expect(envelope, isNot(contains('123456')));
    expect(await bridge.openWithPin('123456', envelope), secret);
    await expectLater(
      bridge.openWithPin('654321', envelope),
      throwsA(isA<CoreException>().having((e) => e.code, 'code', 'wrong_pin')),
    );
    await expectLater(
      bridge.sealWithPin('12ab56', secret),
      throwsA(
        isA<CoreException>()
            .having((e) => e.code, 'code', 'invalid_argument')
            .having((e) => e.message, 'message', isNot(contains('12ab56'))),
      ),
    );
  });

  test('photos need the session', () {
    for (final call in [
      () => bridge.downloadMedia('c@s.whatsapp.net', 'x'),
      () => bridge.mediaBytes('c@s.whatsapp.net', 'x', 'thumb'),
      // The full media comes as bytes, and goes as bytes.
      () => bridge.mediaBytes('c@s.whatsapp.net', 'x', 'full'),
      () => bridge.sendMedia(
        'c@s.whatsapp.net',
        OutgoingMedia(kind: 'document', bytes: Uint8List.fromList([1, 2])),
      ),
      () => bridge.forwardMessage('c@s.whatsapp.net', 'x', 'd@s.whatsapp.net'),
      () => bridge.deleteChat('c@s.whatsapp.net'),
      () => bridge.deleteChat('c@s.whatsapp.net', forEveryone: true),
      () => bridge.deleteMessage('c@s.whatsapp.net', 'x', forEveryone: false),
      () => bridge.deleteMessage('c@s.whatsapp.net', 'x', forEveryone: true),
    ]) {
      expect(
        call,
        throwsA(
          isA<CoreException>().having((e) => e.code, 'code', 'invalid_state'),
        ),
      );
    }
    expect(bridge.liveAllocations, 0);
  });

  test('backups check their arguments and need the session', () {
    // An invalid descriptor never reaches the core's file code.
    expect(
      () => bridge.backupOpen(
        -1,
        password: 'senha do backup',
        workDir: '/tmp',
        maxAppSchema: 4,
      ),
      throwsA(
        isA<CoreException>().having((e) => e.code, 'code', 'invalid_argument'),
      ),
    );
    expect(
      () => bridge.backupCommit(),
      throwsA(
        isA<CoreException>().having((e) => e.code, 'code', 'invalid_state'),
      ),
    );
    bridge.backupDiscard();
    bridge.backupCancel();
    expect(bridge.liveAllocations, 0);
  });

  test('the connection report needs the session', () {
    expect(
      () => bridge.connectionReport(),
      throwsA(
        isA<CoreException>().having((e) => e.code, 'code', 'invalid_state'),
      ),
    );
    expect(bridge.liveAllocations, 0);
  });

  test('sending checks the text first, then the session', () {
    const chat = '5511900000001@s.whatsapp.net';
    expect(
      () => bridge.sendText(chat, '   '),
      throwsA(
        isA<CoreException>().having((e) => e.code, 'code', 'invalid_argument'),
      ),
    );
    expect(
      () => bridge.sendText(chat, 'oi'),
      throwsA(
        isA<CoreException>().having((e) => e.code, 'code', 'invalid_state'),
      ),
    );
    expect(
      () => bridge.retryMessage(chat, 'x'),
      throwsA(
        isA<CoreException>().having((e) => e.code, 'code', 'invalid_state'),
      ),
    );
    expect(bridge.liveAllocations, 0);
  });

  test('decodeEnvelope rejects an unknown protocol version', () {
    expect(
      () => decodeEnvelope('{"v":2,"ok":true,"data":{}}'),
      throwsA(
        isA<CoreException>().having(
          (e) => e.code,
          'code',
          'unsupported_protocol',
        ),
      ),
    );
  });
}
