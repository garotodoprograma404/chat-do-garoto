import 'package:flutter/material.dart';

import 'lock_controller.dart';
import 'pin_field.dart';
import '../demo/demo_app.dart';
import '../theme/brand_mark.dart';
import '../theme/responsive.dart';

/// The app is locked: only the PIN, biometrics and "forgot the PIN"; no
/// conversations, names or numbers.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.controller});

  final LockController controller;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  LockController get lock => widget.controller;

  @override
  void initState() {
    super.initState();
    // Offer biometrics right away when they are on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && lock.biometricsOn) lock.unlockWithBiometrics();
    });
  }

  Future<void> _forgot() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Esqueceu o PIN?'),
        content: const Text(
          'Ninguém consegue recuperar o PIN. Para criar um novo, os dados do '
          'app (clientes, produtos e vendas) serão apagados. A conexão com o '
          'WhatsApp e as conversas continuam.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar e criar PIN novo'),
          ),
        ],
      ),
    );
    if (confirmed == true) await lock.forgotPin();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const BrandLockup(size: 30)),
      body: DotGrid(
        child: ContentWidth(
          maxWidth: formWidth,
          child: ListenableBuilder(
            listenable: lock,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 24),
                const Center(child: BrandMark(size: 96)),
                const SizedBox(height: 24),
                const Text('Digite o PIN para abrir o app.'),
                const SizedBox(height: 16),
                PinField(
                  label: 'PIN',
                  enabled: !lock.busy,
                  onComplete: lock.unlock,
                ),
                if (lock.message case final message?)
                  Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 16),
                if (lock.biometricsOn)
                  OutlinedButton(
                    onPressed: lock.busy ? null : lock.unlockWithBiometrics,
                    child: const Text('Usar a digital'),
                  ),
                TextButton(
                  onPressed: _forgot,
                  child: const Text('Esqueci o PIN'),
                ),
                // Show the app to someone without opening my data.
                const SizedBox(height: 24),
                const Center(child: DemoButton()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
