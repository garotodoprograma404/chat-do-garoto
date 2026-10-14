import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lock_controller.dart';

/// A 6-digit, hidden PIN field that reports the PIN once complete.
class PinField extends StatefulWidget {
  const PinField({
    super.key,
    required this.label,
    required this.onComplete,
    this.enabled = true,
  });

  final String label;
  final ValueChanged<String> onComplete;
  final bool enabled;

  @override
  State<PinField> createState() => _PinFieldState();
}

class _PinFieldState extends State<PinField> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _changed(String value) {
    if (value.length < LockController.pinLength) return;
    _text.clear();
    widget.onComplete(value);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _text,
      enabled: widget.enabled,
      autofocus: true,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: LockController.pinLength,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: widget.label, counterText: ''),
      onChanged: _changed,
    );
  }
}
