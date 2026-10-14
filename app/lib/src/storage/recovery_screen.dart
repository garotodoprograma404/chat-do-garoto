import 'package:flutter/material.dart';

import '../theme/brand_mark.dart';
import '../theme/responsive.dart';

/// Shown when `app.db` cannot be opened. Offers to start
/// over; the WhatsApp connection and messages are not affected.
class RecoveryScreen extends StatelessWidget {
  const RecoveryScreen({
    super.key,
    required this.unreadable,
    required this.onReset,
    required this.onRetry,
    this.onRestore,
  });

  /// True when the key cannot open the file; false for other failures.
  final bool unreadable;

  /// Deletes the app's data and starts over (asked after confirming).
  final VoidCallback onReset;

  final VoidCallback onRetry;

  /// Opens "Restaurar backup"; hidden when null.
  final VoidCallback? onRestore;

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar os dados do app?'),
        content: const Text(
          'Os dados do app serão apagados para começar de novo. A conexão '
          'com o WhatsApp e as conversas continuam.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar e recomeçar'),
          ),
        ],
      ),
    );
    if (confirmed == true) onReset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const BrandLockup(size: 30)),
      body: ContentWidth(
        maxWidth: formWidth,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              unreadable
                  ? 'Os dados do app não podem ser abertos: a chave que os '
                        'protege não está mais neste aparelho.'
                  : 'Não foi possível abrir os dados do app com segurança.',
            ),
            const SizedBox(height: 16),
            if (unreadable)
              FilledButton(
                onPressed: () => _confirmReset(context),
                child: const Text('Apagar dados do app e recomeçar'),
              )
            else
              FilledButton(
                onPressed: onRetry,
                child: const Text('Tentar de novo'),
              ),
            if (onRestore case final restore?) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: restore,
                child: const Text('Restaurar backup'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
