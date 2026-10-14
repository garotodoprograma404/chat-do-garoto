import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/motion.dart';
import 'media_platform.dart';
import 'media_tiles.dart';

/// A finished voice message.
typedef VoiceMessage = ({Recording recording, int seconds});

/// Hold to record, release to send, drag left to cancel, as in WhatsApp
/// Recordings under one second are dropped.
class VoiceButton extends StatefulWidget {
  const VoiceButton({
    super.key,
    required this.onRecorded,
    this.onRecording,
    this.platform,
  });

  /// A voice message to send.
  final ValueChanged<VoiceMessage> onRecorded;

  /// While recording: the seconds so far and whether release cancels; null
  /// when not recording. The conversation shows it in place of the box.
  final ValueChanged<({int seconds, bool canceling})?>? onRecording;
  final MediaPlatform? platform;

  /// How far left a drag cancels.
  static const cancelDistance = 80.0;

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton> {
  late final MediaPlatform _platform = widget.platform ?? mediaPlatform;
  bool _recording = false;
  bool _canceling = false;
  int _seconds = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    if (_recording) _platform.recordCancel();
    super.dispose();
  }

  void _report() => widget.onRecording?.call(
    _recording ? (seconds: _seconds, canceling: _canceling) : null,
  );

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(aboveComposer(text));

  Future<void> _start() async {
    if (!await _platform.micPermission()) {
      _say('Sem a permissão do microfone não dá para gravar.');
      return;
    }
    try {
      await _platform.recordStart();
    } on MediaException {
      _say('Não foi possível gravar.');
      return;
    }
    if (!mounted) return;
    Haptics.start(); // recording started
    setState(() {
      _recording = true;
      _canceling = false;
      _seconds = 0;
    });
    _report();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds++);
      _report();
    });
  }

  Future<void> _end() async {
    if (!_recording) return;
    _timer?.cancel();
    final cancel = _canceling;
    setState(() => _recording = false);
    _report();
    if (cancel) {
      await _platform.recordCancel();
      return;
    }
    final recording = await _platform.recordStop();
    if (recording == null || recording.ms < 1000) {
      _say('Áudio curto demais.');
      return;
    }
    widget.onRecorded((
      recording: recording,
      seconds: max(1, (recording.ms / 1000).round()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _say('Segure para gravar, solte para enviar.'),
      onLongPressStart: (_) => _start(),
      onLongPressMoveUpdate: (d) {
        final canceling = d.offsetFromOrigin.dx < -VoiceButton.cancelDistance;
        if (canceling != _canceling && _recording) {
          setState(() => _canceling = canceling);
          _report();
        }
      },
      onLongPressEnd: (_) => _end(),
      onLongPressCancel: _end,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(
          Symbols.mic_rounded,
          fill: _recording ? 1 : 0,
          semanticLabel: 'Gravar mensagem de voz',
        ),
      ),
    );
  }
}

/// "Gravando 0:03 · ← arraste para cancelar".
String recordingText(({int seconds, bool canceling}) r) => r.canceling
    ? 'Solte para cancelar'
    : 'Gravando ${formatDuration(r.seconds)} · ← arraste para cancelar';
