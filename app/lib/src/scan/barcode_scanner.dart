import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/motion.dart';

/// Reads barcodes with the camera, inside the app and without the network
abstract interface class BarcodeScanner {
  /// One code, or null when closed.
  Future<String?> scanOne(BuildContext context);

  /// Codes one after another until "Pronto": [onCode] gets
  /// each new code and answers what to tell the user.
  Future<void> scanMany(
    BuildContext context, {
    required Future<String> Function(String code) onCode,
  });
}

/// The camera scanner, where there is one (Android); null elsewhere and
/// in tests, which set a fake. The buttons only show when it is set.
BarcodeScanner? barcodeScanner;

/// The button that reads a code into [field], or null
/// without a scanner (Linux, tests without a fake).
Widget? scanIntoButton(BuildContext context, TextEditingController field) {
  final scanner = barcodeScanner;
  if (scanner == null) return null;
  return IconButton(
    tooltip: 'Ler código de barras',
    icon: const Icon(Symbols.barcode_scanner_rounded),
    onPressed: () async {
      final code = await scanner.scanOne(context);
      if (code != null) field.text = code;
    },
  );
}

/// The real scanner: [ScanScreen].
class CameraBarcodeScanner implements BarcodeScanner {
  const CameraBarcodeScanner();

  @override
  Future<String?> scanOne(BuildContext context) =>
      Navigator.of(context)
          .push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));

  @override
  Future<void> scanMany(
    BuildContext context, {
    required Future<String> Function(String code) onCode,
  }) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => ScanScreen(onCode: onCode)));
}

/// Product codes (EAN, UPC) and store labels (Code 128, Code 39).
const productFormats =
    Format.ean13 |
    Format.ean8 |
    Format.upca |
    Format.upce |
    Format.code128 |
    Format.code39;

/// The camera with a frame. Without [onCode], the first code
/// read closes it with the code; with it, it keeps reading until "Pronto".
/// Nothing is saved, and the screen stays protected from captures.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.onCode});

  final Future<String> Function(String code)? onCode;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _denied = false;
  bool _done = false;

  // The same label in front of the camera reads many times a second.
  String? _last;
  DateTime _lastAt = DateTime(0);

  Future<void> _read(Code code) async {
    final text = code.text?.trim() ?? '';
    if (!code.isValid || text.isEmpty || _done) return;
    final now = DateTime.now();
    if (text == _last && now.difference(_lastAt) < sameCodePause) return;
    _last = text;
    _lastAt = now;
    Haptics.success();
    final onCode = widget.onCode;
    if (onCode == null) {
      _done = true;
      Navigator.pop(context, text);
      return;
    }
    final message = await onCode(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ler código'),
        actions: [
          if (widget.onCode != null)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Pronto'),
            ),
        ],
      ),
      body: _denied
          ? const _Denied()
          : ReaderWidget(
              codeFormat: productFormats,
              tryHarder: true,
              showGallery: false,
              showToggleCamera: false,
              showFlashlight: true,
              cropPercent: 0.7,
              scanDelay: const Duration(milliseconds: 300),
              scanDelaySuccess: const Duration(milliseconds: 600),
              onScan: _read,
              onControllerCreated: (_, error) {
                if (error != null && mounted) setState(() => _denied = true);
              },
            ),
    );
  }
}

/// How long the same code is ignored after it was read.
const sameCodePause = Duration(milliseconds: 1500);

/// The camera was refused: how to allow it, and that typing still works.
class _Denied extends StatelessWidget {
  const _Denied();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sem acesso à câmera',
              style: t.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Para ler códigos, permita a câmera em Configurações do Android '
              '→ Apps → Chat do Garoto → Permissões → Câmera. Você também pode '
              'digitar o código no campo.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Voltar'),
            ),
          ],
        ),
      ),
    );
  }
}
