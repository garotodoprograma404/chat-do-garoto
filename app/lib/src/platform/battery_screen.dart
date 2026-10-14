import 'package:flutter/material.dart';

import 'connection_keeper.dart';

/// Guides the user to let the app run in the background.
/// Rechecks the status when the user comes back from Android's settings.
class BatteryScreen extends StatefulWidget {
  const BatteryScreen({super.key, required this.keeper});

  final ConnectionKeeper keeper;

  @override
  State<BatteryScreen> createState() => _BatteryScreenState();
}

class _BatteryScreenState extends State<BatteryScreen>
    with WidgetsBindingObserver {
  BatteryStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final status = await widget.keeper.batteryStatus();
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('Bateria')),
      body: status == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Para receber mensagens com o app fechado, o Android não '
                  'pode desligar o Chat do Garoto para economizar bateria.',
                ),
                const SizedBox(height: 16),
                Text(
                  status.unrestricted
                      ? 'Economia de bateria: liberado'
                      : 'Economia de bateria: restrito',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (!status.unrestricted) ...[
                  const Text(
                    'Toque no botão e escolha "Permitir" (ou "Sem restrições").',
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: widget.keeper.openBatterySettings,
                    child: const Text('Liberar bateria'),
                  ),
                ],
                if (status.xiaomi) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Início automático (Xiaomi)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Text(
                    'Ligue o Chat do Garoto na lista de início automático. Se '
                    'abrir a tela do app, procure "Início automático" e, em '
                    '"Economia de bateria", escolha "Sem restrições".',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: widget.keeper.openAutostart,
                    child: const Text('Abrir início automático'),
                  ),
                ],
              ],
            ),
    );
  }
}
