import 'package:flutter/material.dart';

import 'lock_controller.dart';
import 'pin_field.dart';

/// Changes the PIN: the current one, then the new one twice.
class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key, required this.controller});

  final LockController controller;

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final _pins = <String>[];

  static const _labels = [
    'PIN atual',
    'Novo PIN (6 números)',
    'Digite o novo PIN de novo',
  ];

  Future<void> _entered(String pin) async {
    setState(() => _pins.add(pin));
    if (_pins.length < 3) return;
    final [current, next, confirm] = List.of(_pins);
    setState(_pins.clear);
    if (await widget.controller.changePin(current, next, confirm) && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trocar PIN')),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PinField(
              key: ValueKey(_pins.length),
              label: _labels[_pins.length],
              enabled: !widget.controller.busy,
              onComplete: _entered,
            ),
            if (widget.controller.message case final message?) Text(message),
          ],
        ),
      ),
    );
  }
}
