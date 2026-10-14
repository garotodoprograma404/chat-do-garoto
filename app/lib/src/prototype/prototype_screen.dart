import 'dart:async';

import 'package:flutter/material.dart';

import '../core_bridge/core_bridge.dart';

/// Test screen of delivery 1.1: proves that the app talks to the Go core.
/// Not a real screen; it goes away once the WhatsApp screens exist.
class PrototypeScreen extends StatefulWidget {
  const PrototypeScreen({super.key, required this.bridge});

  final CoreBridge bridge;

  @override
  State<PrototypeScreen> createState() => _PrototypeScreenState();
}

class _PrototypeScreenState extends State<PrototypeScreen> {
  final _text = TextEditingController(text: 'Olá, ação! 🚀');
  late final String _status;
  String? _reply;
  String? _error;
  late final StreamSubscription<CoreEvent> _events;
  int _tick = 0;
  bool _tickerRunning = false;

  @override
  void initState() {
    super.initState();
    try {
      final version = widget.bridge.version();
      _status = 'Motor Go conectado: core ${version.core} · ${version.go}';
    } on CoreException catch (e) {
      _status = 'Falha ao falar com o motor Go (${e.code})';
    }
    _events = widget.bridge.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _events.cancel();
    _text.dispose();
    super.dispose();
  }

  void _send() {
    setState(() {
      try {
        _reply = widget.bridge.echo(_text.text);
        _error = null;
      } on CoreException catch (e) {
        _reply = null;
        _error = 'Erro do motor Go: ${e.code} (${e.message})';
      }
    });
  }

  void _onEvent(CoreEvent event) {
    switch (event.type) {
      case 'tick':
        setState(() => _tick = event.data['n'] as int);
      case 'ticker_done':
        setState(() => _tickerRunning = false);
    }
  }

  void _startTicker() {
    setState(() {
      _tick = 0;
      _tickerRunning = true;
    });
    widget.bridge.startTicker(
      count: 1000,
      interval: const Duration(milliseconds: 300),
    );
  }

  void _stopTicker() {
    widget.bridge.stopTicker();
    setState(() => _tickerRunning = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat do Garoto · protótipo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            TextField(
              controller: _text,
              decoration: const InputDecoration(
                labelText: 'Texto para o Go',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _send, child: const Text('Enviar ao Go')),
            const SizedBox(height: 16),
            if (_reply case final reply?) SelectableText('Resposta: $reply'),
            if (_error case final error?)
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const Divider(height: 48),
            Text(
              'Contador ao vivo (eventos do Go)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '$_tick',
              key: const Key('tick'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _tickerRunning ? null : _startTicker,
                    child: const Text('Iniciar contador'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _tickerRunning ? _stopTicker : null,
                    child: const Text('Parar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
