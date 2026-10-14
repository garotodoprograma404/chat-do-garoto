import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'connection_report_view.dart';
import 'whatsapp_controller.dart';

/// The connection stability summary of the 7-day test,
/// opened from Configurações.
class StabilityScreen extends StatefulWidget {
  const StabilityScreen({super.key, required this.controller});

  final WhatsAppController controller;

  @override
  State<StabilityScreen> createState() => _StabilityScreenState();
}

class _StabilityScreenState extends State<StabilityScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame: loading notifies the builder.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.loadReport();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estabilidade da conexão'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Symbols.refresh_rounded),
            onPressed: controller.loadReport,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (controller.report case final report?)
              ConnectionReportView(report: report)
            else
              const Text('Sem dados de conexão ainda.'),
          ],
        ),
      ),
    );
  }
}
