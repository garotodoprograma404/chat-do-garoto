import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../demo/demo_app.dart';
import '../settings/settings_menu.dart';
import 'whatsapp_controller.dart';
import '../theme/brand_mark.dart';

/// Links the app to WhatsApp by pairing code or QR code, and shows the
/// connection once linked.
class ConnectScreen extends StatelessWidget {
  const ConnectScreen({
    super.key,
    required this.controller,
    this.onOpenPrototype,
    this.onOpenSettings,
  });

  final WhatsAppController controller;

  /// Shows the ⋮ menu when this screen is the Conversas section.
  final VoidCallback? onOpenSettings;

  /// Opens the phase 1 test screen; hidden when null.
  final VoidCallback? onOpenPrototype;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const BrandLockup(size: 30),
        actions: [
          if (onOpenSettings case final open?)
            SettingsMenuButton(onOpenSettings: open),
        ],
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (controller.notice case final notice?)
              _Banner(
                text: notice,
                color: Theme.of(context).colorScheme.tertiaryContainer,
              ),
            if (controller.error case final error?)
              _Banner(
                text: error,
                color: Theme.of(context).colorScheme.errorContainer,
              ),
            switch (controller.phase) {
              WhatsAppPhase.pairing => _Pairing(
                key: const ValueKey('pairing'),
                controller: controller,
              ),
              WhatsAppPhase.connected => _Connected(controller: controller),
              WhatsAppPhase.disconnecting => const _Progress('Desconectando…'),
              _ => const _Progress('Conectando ao WhatsApp…'),
            },
            if (onOpenPrototype != null) ...[
              const Divider(height: 48),
              TextButton(
                onPressed: onOpenPrototype,
                child: const Text('Tela de teste (protótipo)'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      child: Padding(padding: const EdgeInsets.all(12), child: Text(text)),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(label),
        ],
      ),
    );
  }
}

class _Connected extends StatelessWidget {
  const _Connected({required this.controller});

  final WhatsAppController controller;

  @override
  Widget build(BuildContext context) {
    final name = controller.pushName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Icon(
          Symbols.check_circle_rounded,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          name == null || name.isEmpty
              ? 'Conectado ao WhatsApp'
              : 'Conectado como $name',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: controller.logout,
          child: const Text('Desconectar'),
        ),
      ],
    );
  }
}

/// The two ways to pair: code (default on phones) and QR (default elsewhere).
class _Pairing extends StatefulWidget {
  const _Pairing({super.key, required this.controller});

  final WhatsAppController controller;

  @override
  State<_Pairing> createState() => _PairingState();
}

enum _Method { code, qr }

class _PairingState extends State<_Pairing> {
  final _phone = TextEditingController();
  _Method _method = Platform.isAndroid || Platform.isIOS
      ? _Method.code
      : _Method.qr;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Conectar ao WhatsApp',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        SegmentedButton<_Method>(
          segments: const [
            ButtonSegment(value: _Method.code, label: Text('Com código')),
            ButtonSegment(value: _Method.qr, label: Text('Com QR Code')),
          ],
          selected: {_method},
          onSelectionChanged: (s) => setState(() => _method = s.first),
        ),
        const SizedBox(height: 24),
        if (_method == _Method.code)
          ..._code(context, controller)
        else
          ..._qr(controller),
        // Or look around first, with invented data.
        const SizedBox(height: 24),
        const Center(child: DemoButton()),
      ],
    );
  }

  List<Widget> _code(BuildContext context, WhatsAppController controller) => [
    TextField(
      controller: _phone,
      keyboardType: TextInputType.phone,
      decoration: const InputDecoration(
        labelText: 'Número do WhatsApp com código do país',
        hintText: '55 11 99999-0000',
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 12),
    FilledButton(
      onPressed: controller.requestingCode
          ? null
          : () => controller.requestCode(_phone.text),
      child: const Text('Gerar código'),
    ),
    const SizedBox(height: 24),
    if (controller.requestingCode)
      const _Progress('Pedindo o código ao WhatsApp…'),
    if (controller.pairingCode case final code?) ...[
      SelectableText(
        code,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.displaySmall
            ?.copyWith(letterSpacing: 4),
      ),
      const SizedBox(height: 16),
      const Text(
        'No celular com o WhatsApp:\n'
        '1. Toque na notificação "Insira o código", ou abra '
        'Configurações → Aparelhos conectados → Conectar um aparelho.\n'
        '2. Toque em "Conectar com número de telefone".\n'
        '3. Digite o código acima.',
      ),
    ],
  ];

  List<Widget> _qr(WhatsAppController controller) => [
    if (controller.expired)
      FilledButton(
        onPressed: controller.start,
        child: const Text('Gerar novo QR Code'),
      )
    else if (controller.qrCode case final qr?)
      Center(
        child: QrImageView(data: qr, size: 260, backgroundColor: Colors.white),
      )
    else
      const _Progress('Gerando o QR Code…'),
    const SizedBox(height: 16),
    const Text(
      'No celular com o WhatsApp: Configurações → Aparelhos conectados → '
      'Conectar um aparelho, e aponte a câmera para o QR Code.',
    ),
  ];
}
