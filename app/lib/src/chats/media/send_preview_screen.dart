import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'media_tiles.dart';

/// A photo or video before sending, with a caption.
/// Pops with the caption, or null when backing out.
class SendPreviewScreen extends StatefulWidget {
  const SendPreviewScreen({
    super.key,
    required this.video,
    this.image,
    this.seconds = 0,
  });

  final bool video;

  /// The photo, or the video's thumbnail.
  final Uint8List? image;
  final int seconds;

  @override
  State<SendPreviewScreen> createState() => _SendPreviewScreenState();
}

class _SendPreviewScreenState extends State<SendPreviewScreen> {
  final _caption = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.video ? 'Enviar vídeo' : 'Enviar foto'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (widget.image case final image?)
                    InteractiveViewer(child: Image.memory(image))
                  else if (widget.video)
                    const Icon(Symbols.movie_rounded, size: 96),
                  if (widget.video) Text('▶ ${formatDuration(widget.seconds)}'),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: TextField(
                      controller: _caption,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(hintText: 'Legenda'),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Enviar',
                  icon: const Icon(Symbols.send_rounded),
                  onPressed: () => Navigator.pop(context, _caption.text.trim()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
