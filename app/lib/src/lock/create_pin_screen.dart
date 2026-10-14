import 'package:flutter/material.dart';

import 'lock_controller.dart';
import 'pin_field.dart';

/// Creates the app's PIN, typed twice. Biometrics are
/// offered afterwards by [offerBiometricsDialog].
class CreatePinScreen extends StatefulWidget {
  const CreatePinScreen({super.key, required this.controller});

  final LockController controller;

  @override
  State<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<CreatePinScreen> {
  String? _first;

  Future<void> _entered(String pin) async {
    final first = _first;
    if (first == null) {
      setState(() => _first = pin);
      return;
    }
    setState(() => _first = null);
    await widget.controller.createPin(first, pin);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crie seu PIN')),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'O PIN protege os dados do app e é pedido toda vez que você '
              'abre o app. Ninguém consegue recuperá-lo, nem nós.',
            ),
            const SizedBox(height: 16),
            PinField(
              key: ValueKey(_first == null),
              label: _first == null
                  ? 'Novo PIN (6 números)'
                  : 'Digite o PIN de novo',
              enabled: !widget.controller.busy,
              onComplete: _entered,
            ),
            if (widget.controller.message case final message?)
              Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks once, after the PIN is created, whether to unlock with biometrics
/// Shown by the app's home once the lock is open.
Future<void> offerBiometricsDialog(
  BuildContext context,
  LockController lock,
) async {
  lock.biometricsOffered();
  final wants = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Desbloquear com a digital?'),
      content: const Text(
        'Você pode usar a digital do celular no lugar do PIN. O PIN '
        'continua valendo.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Agora não'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Usar a digital'),
        ),
      ],
    ),
  );
  if (wants == true) await lock.enableBiometrics();
}
