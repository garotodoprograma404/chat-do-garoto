import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core_bridge/core_bridge.dart';
import 'media_platform.dart';
import '../../theme/responsive.dart';

/// Videos up to this size play in the app; larger ones open with another
/// app.
const maxPlayableVideo = 64 * 1024 * 1024;

/// "0:07", "12:30".
String formatDuration(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// "820 KB", "1,2 MB".
String formatSize(int bytes) {
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).ceil()} KB';
  }
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
}

/// "PDF", "Planilha", "Word"… from the type or the file's extension.
String documentType(String mime, String fileName) {
  const byMime = {
    'application/pdf': 'PDF',
    'application/msword': 'Word',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        'Word',
    'application/vnd.ms-excel': 'Planilha',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':
        'Planilha',
    'text/plain': 'Texto',
  };
  if (byMime[mime] case final label?) return label;
  final dot = fileName.lastIndexOf('.');
  return dot >= 0 && dot < fileName.length - 1
      ? fileName.substring(dot + 1).toUpperCase()
      : 'Arquivo';
}

/// The media could not be downloaded, or WhatsApp no longer has it.
class MediaUnavailable implements Exception {
  const MediaUnavailable({required this.expired});
  final bool expired;
}

/// The bytes of a media: from the vault, downloading it first when needed
/// (only on the user's tap). Throws [MediaUnavailable].
Future<Uint8List> fetchMedia(CoreBridge bridge, ChatMessage m) async {
  if (m.media == 'expired') throw const MediaUnavailable(expired: true);
  try {
    return bridge.mediaBytes(m.chat, m.id, 'full');
  } on CoreException {
    // Not in the vault yet: download below.
  }
  final outcome = bridge.events
      .where(
        (e) =>
            e.type == 'wa_media' &&
            e.data['chat'] == m.chat &&
            e.data['id'] == m.id,
      )
      .first
      .timeout(const Duration(minutes: 3));
  try {
    bridge.downloadMedia(m.chat, m.id);
    final event = await outcome;
    switch (event.data['state']) {
      case 'downloaded':
        return bridge.mediaBytes(m.chat, m.id, 'full');
      case 'expired':
        throw const MediaUnavailable(expired: true);
      default:
        throw const MediaUnavailable(expired: false);
    }
  } on CoreException {
    throw const MediaUnavailable(expired: false);
  } on TimeoutException {
    throw const MediaUnavailable(expired: false);
  }
}

/// The one audio playing in the conversation: played from
/// memory, its position read every 200 ms.
class AudioPlayback extends ChangeNotifier {
  AudioPlayback({required this.bridge, MediaPlatform? platform})
    : _platform = platform ?? mediaPlatform;

  final CoreBridge bridge;
  final MediaPlatform _platform;
  Timer? _timer;

  /// The message playing or paused; null when stopped.
  String? current;

  /// The message being downloaded to play.
  String? loading;

  /// Messages whose download failed or expired.
  final failed = <String>{};
  final expired = <String>{};
  bool playing = false;
  int position = 0;
  int duration = 0;

  Future<void> toggle(ChatMessage m) async {
    if (current == m.id) {
      playing ? await _platform.audioPause() : await _platform.audioResume();
      playing = !playing;
      _poll(playing);
      notifyListeners();
      return;
    }
    await stop();
    loading = m.id;
    failed.remove(m.id);
    notifyListeners();
    try {
      final bytes = await fetchMedia(bridge, m);
      if (loading != m.id) return; // another audio was tapped meanwhile
      duration = await _platform.audioPlay(bytes);
      current = m.id;
      playing = true;
      position = 0;
      _poll(true);
    } on MediaUnavailable catch (e) {
      (e.expired ? expired : failed).add(m.id);
    } on MediaException {
      failed.add(m.id);
    } finally {
      if (loading == m.id) loading = null;
      notifyListeners();
    }
  }

  void _poll(bool on) {
    _timer?.cancel();
    if (!on) return;
    late final Timer timer;
    timer = _timer = Timer.periodic(const Duration(milliseconds: 200), (
      _,
    ) async {
      final s = await _platform.audioState();
      // Paused, stopped or another audio started while asking.
      if (_timer != timer || !timer.isActive) return;
      position = s.position;
      if (s.duration > 0) duration = s.duration;
      if (!s.playing) {
        // The end of the audio: back to the start, stopped, and the audio
        // held in memory freed.
        timer.cancel();
        playing = false;
        current = null;
        position = 0;
        await _platform.audioStop();
      }
      notifyListeners();
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    if (current != null) await _platform.audioStop();
    current = null;
    playing = false;
    position = 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (current != null) _platform.audioStop();
    super.dispose();
  }
}

/// An audio or voice message: play/pause and the time.
class AudioTile extends StatelessWidget {
  const AudioTile({super.key, required this.playback, required this.message});

  final AudioPlayback playback;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final p = playback;
        final id = message.id;
        if (p.expired.contains(id) || message.media == 'expired') {
          return const Text('Áudio não disponível');
        }
        final mine = p.current == id;
        final label = mine
            ? '${formatDuration(p.position ~/ 1000)} / '
                  '${formatDuration(p.duration ~/ 1000)}'
            : formatDuration(message.seconds);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (p.loading == id)
              const SizedBox.square(
                dimension: 40,
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                tooltip: mine && p.playing ? 'Pausar' : 'Tocar',
                icon: Icon(
                  mine && p.playing
                      ? Symbols.pause_rounded
                      : Symbols.play_arrow_rounded,
                ),
                onPressed: () => p.toggle(message),
              ),
            Text(message.ptt ? '🎤 $label' : '🎵 $label'),
            if (p.failed.contains(id))
              TextButton(
                onPressed: () => p.toggle(message),
                child: const Text('Tentar de novo'),
              ),
          ],
        );
      },
    );
  }
}

/// A video: its thumbnail and length; tapping opens it.
class VideoTile extends StatelessWidget {
  const VideoTile({
    super.key,
    required this.bridge,
    required this.message,
    this.thumb,
  });

  final CoreBridge bridge;
  final ChatMessage message;
  final Uint8List? thumb;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: wideRouteName),
          builder: (_) => VideoScreen(bridge: bridge, message: message),
        ),
      ),
      child: SizedBox(
        width: 200,
        height: 150,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (thumb case final t?)
              Positioned.fill(child: Image.memory(t, fit: BoxFit.cover)),
            const Icon(Symbols.play_circle_rounded, size: 48),
            Positioned(
              right: 4,
              bottom: 4,
              child: Text('▶ ${formatDuration(message.seconds)}'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _VideoPhase { loading, playing, tooBig, failed, expired }

/// A video full screen, played from memory. Larger than
/// [maxPlayableVideo], it offers another app.
class VideoScreen extends StatefulWidget implements WideScreen {
  const VideoScreen({
    super.key,
    required this.bridge,
    required this.message,
    this.platform,
  });

  final CoreBridge bridge;
  final ChatMessage message;
  final MediaPlatform? platform;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late final MediaPlatform _platform = widget.platform ?? mediaPlatform;
  _VideoPhase _phase = _VideoPhase.loading;
  OpenedVideo? _video;
  Uint8List? _bytes;
  PlayState _state = (playing: false, position: 0, duration: 0);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_video != null) _platform.videoClose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _phase = _VideoPhase.loading);
    try {
      final bytes = await fetchMedia(widget.bridge, widget.message);
      if (!mounted) return;
      if (bytes.length > maxPlayableVideo) {
        setState(() {
          _bytes = bytes;
          _phase = _VideoPhase.tooBig;
        });
        return;
      }
      final video = await _platform.videoOpen(bytes);
      if (!mounted) {
        _platform.videoClose();
        return;
      }
      await _platform.videoPlay();
      setState(() {
        _video = video;
        _phase = _VideoPhase.playing;
      });
      _timer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
        final s = await _platform.videoState();
        if (mounted) setState(() => _state = s);
      });
    } on MediaUnavailable catch (e) {
      if (mounted) {
        setState(
          () => _phase = e.expired ? _VideoPhase.expired : _VideoPhase.failed,
        );
      }
    } on MediaException {
      if (mounted) setState(() => _phase = _VideoPhase.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    return Scaffold(
      appBar: AppBar(title: Text(m.text.isEmpty ? 'Vídeo' : m.text)),
      // Clear of the system's navigation buttons, so the controls can be
      // reached.
      body: SafeArea(
        child: Center(
          child: switch (_phase) {
            _VideoPhase.loading => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [CircularProgressIndicator(), Text('Baixando…')],
            ),
            _VideoPhase.expired => const Text('Vídeo não disponível'),
            _VideoPhase.failed => TextButton(
              onPressed: _load,
              child: const Text('Não foi possível abrir. Tentar de novo'),
            ),
            _VideoPhase.tooBig => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Vídeo grande demais para tocar no app.'),
                FilledButton(
                  onPressed: () => openWithAnotherApp(
                    context,
                    _platform,
                    _bytes!,
                    'video.mp4',
                    m.mime.isEmpty ? 'video/mp4' : m.mime,
                  ),
                  child: const Text('Abrir com outro app'),
                ),
              ],
            ),
            // The video shrinks to leave room for the controls.
            _VideoPhase.playing => Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _video!.height == 0
                          ? 16 / 9
                          : _video!.width / _video!.height,
                      child: Texture(textureId: _video!.texture),
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: _state.playing ? 'Pausar' : 'Tocar',
                      icon: Icon(
                        _state.playing
                            ? Symbols.pause_rounded
                            : Symbols.play_arrow_rounded,
                      ),
                      onPressed: () => _state.playing
                          ? _platform.videoPause()
                          : _platform.videoPlay(),
                    ),
                    Expanded(
                      child: Slider(
                        value: _state.position
                            .clamp(0, _video!.duration)
                            .toDouble(),
                        max: _video!.duration <= 0
                            ? 1
                            : _video!.duration.toDouble(),
                        onChanged: (v) => _platform.videoSeek(v.toInt()),
                      ),
                    ),
                    Text(
                      '${formatDuration(_state.position ~/ 1000)} / '
                      '${formatDuration(_video!.duration ~/ 1000)}',
                    ),
                  ],
                ),
              ],
            ),
          },
        ),
      ),
    );
  }
}

/// A notice that floats above the message box, so it never covers the
/// microphone or the attach button.
SnackBar aboveComposer(String text, {SnackBarAction? action}) => SnackBar(
  content: Text(text),
  action: action,
  behavior: SnackBarBehavior.floating,
  margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
  duration: Duration(seconds: action == null ? 3 : 5),
);

/// Whether the warning about other apps was shown in this run.
bool _warnedOpenWith = false;

/// Opens [bytes] with an app the user picks, after the warning. The
/// copy is deleted when the user comes back (Kotlin).
Future<void> openWithAnotherApp(
  BuildContext context,
  MediaPlatform platform,
  Uint8List bytes,
  String name,
  String mime,
) async {
  if (!_warnedOpenWith) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abrir com outro app'),
        content: const Text(
          'O outro app vê o arquivo e pode guardar uma cópia dele. A cópia '
          'temporária daqui é apagada quando você voltar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _warnedOpenWith = true;
  }
  try {
    if (!await platform.openWith(bytes, name, mime) && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(aboveComposer('Nenhum app abre este tipo de arquivo.'));
    }
  } on MediaException {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(aboveComposer('Não foi possível abrir.'));
    }
  }
}

/// Resets the one-time warning (tests).
@visibleForTesting
void resetOpenWithWarning() => _warnedOpenWith = false;

/// A document: name, type and size; tapping downloads it and offers to
/// open it with another app or save it.
class DocumentTile extends StatefulWidget {
  const DocumentTile({
    super.key,
    required this.bridge,
    required this.message,
    this.platform,
  });

  final CoreBridge bridge;
  final ChatMessage message;
  final MediaPlatform? platform;

  @override
  State<DocumentTile> createState() => _DocumentTileState();
}

class _DocumentTileState extends State<DocumentTile> {
  late final MediaPlatform _platform = widget.platform ?? mediaPlatform;
  bool _loading = false;
  String? _problem;

  ChatMessage get m => widget.message;
  String get _name => m.fileName.isEmpty ? 'documento' : m.fileName;

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _problem = null;
    });
    Uint8List bytes;
    try {
      bytes = await fetchMedia(widget.bridge, m);
    } on MediaUnavailable catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _problem = e.expired
              ? 'Documento não disponível'
              : 'Não foi possível baixar. Tocar para tentar de novo';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    final mime = m.mime.isEmpty ? 'application/octet-stream' : m.mime;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.open_in_new_rounded),
              title: const Text('Abrir com outro app'),
              onTap: () => Navigator.pop(context, 'open'),
            ),
            ListTile(
              leading: const Icon(Symbols.save_alt_rounded),
              title: const Text('Salvar no aparelho'),
              onTap: () => Navigator.pop(context, 'save'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'open':
        await openWithAnotherApp(context, _platform, bytes, _name, mime);
      case 'save':
        try {
          final saved = await _platform.saveAs(bytes, _name, mime);
          if (saved && mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(aboveComposer('Documento salvo.'));
          }
        } on MediaException {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(aboveComposer('Não foi possível salvar.'));
          }
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = [
      documentType(m.mime, m.fileName),
      if (m.size > 0) formatSize(m.size),
    ].join(' · ');
    return InkWell(
      onTap: m.media == 'expired' || _loading ? null : _open,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _loading
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Symbols.description_rounded),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_name),
                  Text(
                    m.media == 'expired'
                        ? 'Documento não disponível'
                        : _problem ?? details,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
