import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core_bridge/core_bridge.dart';

/// Photos read from the vault for the conversation, kept in memory only
///, the most recent [_cacheSize].
final _previews = <String, Uint8List?>{};
const _cacheSize = 40;

/// What the conversation shows for a photo: the photo itself once
/// downloaded, else its thumbnail, else null.
Uint8List? previewOf(CoreBridge bridge, ChatMessage m) {
  if (m.media == 'downloaded') {
    if (_read(bridge, m, 'full') case final full?) return full;
  }
  return m.thumb ? _read(bridge, m, 'thumb') : null;
}

/// Only the thumbnail, for videos and documents: their "full"
/// part is the whole media.
Uint8List? thumbOf(CoreBridge bridge, ChatMessage m) =>
    m.thumb ? _read(bridge, m, 'thumb') : null;

Uint8List? _read(CoreBridge bridge, ChatMessage m, String part) {
  final key = '${m.chat}|${m.id}|$part';
  if (_previews.containsKey(key)) {
    final hit = _previews.remove(key);
    return _previews[key] = hit; // most recent last
  }
  Uint8List? bytes;
  try {
    bytes = bridge.mediaBytes(m.chat, m.id, part);
  } on CoreException {
    bytes = null;
  }
  _previews[key] = bytes;
  if (_previews.length > _cacheSize) _previews.remove(_previews.keys.first);
  return bytes;
}

/// One photo, full screen: downloaded on demand and shown from memory
class PhotoScreen extends StatefulWidget {
  const PhotoScreen({super.key, required this.bridge, required this.message});

  final CoreBridge bridge;
  final ChatMessage message;

  @override
  State<PhotoScreen> createState() => _PhotoScreenState();
}

enum _Phase { downloading, shown, failed, expired }

class _PhotoScreenState extends State<PhotoScreen> {
  late final StreamSubscription<CoreEvent> _events;
  _Phase _phase = _Phase.downloading;
  Uint8List? _bytes;

  ChatMessage get m => widget.message;

  @override
  void initState() {
    super.initState();
    _events = widget.bridge.events.listen(_onEvent);
    if (m.media == 'expired') {
      _phase = _Phase.expired;
    } else if (!_show()) {
      _download();
    }
  }

  @override
  void dispose() {
    _events.cancel();
    super.dispose();
  }

  /// Shows the photo if it is already in the vault.
  bool _show() {
    try {
      _bytes = widget.bridge.mediaBytes(m.chat, m.id, 'full');
      _phase = _Phase.shown;
      return true;
    } on CoreException {
      return false;
    }
  }

  void _download() {
    setState(() => _phase = _Phase.downloading);
    try {
      widget.bridge.downloadMedia(m.chat, m.id);
    } on CoreException {
      setState(() => _phase = _Phase.failed);
    }
  }

  void _onEvent(CoreEvent event) {
    if (event.type != 'wa_media' ||
        event.data['chat'] != m.chat ||
        event.data['id'] != m.id) {
      return;
    }
    setState(() {
      switch (event.data['state']) {
        case 'downloaded':
          if (!_show()) _phase = _Phase.failed;
        case 'expired':
          _phase = _Phase.expired;
        default:
          _phase = _Phase.failed;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(m.text.isEmpty ? 'Foto' : m.text)),
      body: Center(
        child: switch (_phase) {
          _Phase.shown => InteractiveViewer(child: Image.memory(_bytes!)),
          _Phase.downloading => const Column(
            mainAxisSize: MainAxisSize.min,
            children: [CircularProgressIndicator(), Text('Baixando…')],
          ),
          _Phase.failed => TextButton(
            onPressed: _download,
            child: const Text(
              'Não foi possível baixar. Tocar para tentar de novo',
            ),
          ),
          _Phase.expired => const Text('Foto não disponível'),
        },
      ),
    );
  }
}
