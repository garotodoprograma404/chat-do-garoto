import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/components.dart';
import 'products_repository.dart';

const maxPhotos = 5;

enum PhotoSource { camera, gallery }

/// Picks a photo for a product; null when cancelled.
abstract interface class PhotoPicker {
  Future<Uint8List?> pick(PhotoSource source);
}

/// The system's photo picker or camera app, through image_picker: no new
/// permission. The temporary file is deleted as soon as it is read.
class DevicePhotoPicker implements PhotoPicker {
  DevicePhotoPicker({this.onLeave, this.onBack});

  /// Around the picker, so the lock allows five minutes away.
  final VoidCallback? onLeave;
  final VoidCallback? onBack;
  final _picker = ImagePicker();

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    onLeave?.call();
    try {
      final file = await _picker.pickImage(
        source: source == PhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
      if (file == null) return null;
      try {
        return await file.readAsBytes();
      } finally {
        await cleanPhotoLeftovers();
      }
    } finally {
      onBack?.call();
    }
  }
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
);

/// Deletes what image_picker leaves in the app's cache on Android: the
/// camera's file and the gallery's copy (named after a UUID) and the
/// reduced photo ("scaled_"). Runs after each photo and when the app
/// opens. Elsewhere the picked file is the user's own and stays.
Future<void> cleanPhotoLeftovers({Directory? cache}) async {
  if (cache == null && !Platform.isAndroid) return;
  try {
    final dir = cache ?? await getTemporaryDirectory();
    if (!dir.existsSync()) return;
    await for (final entry in dir.list(followLinks: false)) {
      final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (name.startsWith('scaled_') || _uuid.hasMatch(name)) {
        await entry.delete(recursive: true);
      }
    }
  } on FileSystemException {
    // Gone already, or in use: the next run tries again.
  }
}

/// A product photo read from app.db only when shown.
class ProductThumb extends StatefulWidget {
  const ProductThumb({
    super.key,
    required this.repo,
    required this.photoId,
    this.size = 56,
    this.onTap,
  });

  final ProductsRepository repo;
  final int photoId;
  final double size;
  final VoidCallback? onTap;

  @override
  State<ProductThumb> createState() => _ProductThumbState();
}

class _ProductThumbState extends State<ProductThumb> {
  late Future<Uint8List?> _bytes = widget.repo.photo(widget.photoId);

  @override
  void didUpdateWidget(ProductThumb old) {
    super.didUpdateWidget(old);
    if (old.photoId != widget.photoId) {
      _bytes = widget.repo.photo(widget.photoId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pixels = (widget.size * MediaQuery.devicePixelRatioOf(context))
        .round();
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox.square(
        dimension: widget.size,
        child: FutureBuilder(
          future: _bytes,
          builder: (context, snapshot) => switch (snapshot.data) {
            final bytes? => Image.memory(
              bytes,
              fit: BoxFit.cover,
              cacheWidth: pixels,
              gaplessPlayback: true,
            ),
            null => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}

/// A product in a list: its first photo with rounded
/// corners, or its initials on a tinted square when it has none.
class ProductAvatar extends StatelessWidget {
  const ProductAvatar({
    super.key,
    required this.product,
    required this.repo,
    this.size = 40,
  });

  final Product product;
  final ProductsRepository repo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(size * 0.3);
    if (product.photoIds.isEmpty) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.tertiaryContainer,
          borderRadius: radius,
        ),
        child: Text(
          InitialsAvatar.initials(product.name),
          style:
              (size >= 64
                      ? Theme.of(context).textTheme.headlineSmall
                      : Theme.of(context).textTheme.titleSmall)!
                  .copyWith(color: c.onTertiaryContainer),
        ),
      );
    }
    // The decoration's radius, not a clip: cheaper inside lists.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceContainerHighest,
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: ProductThumb(
          key: ValueKey(product.photoIds.first),
          repo: repo,
          photoId: product.photoIds.first,
          size: size,
        ),
      ),
    );
  }
}

/// A photo full screen.
class ProductPhotoScreen extends StatelessWidget {
  const ProductPhotoScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Foto')),
      body: Center(child: InteractiveViewer(child: Image.memory(bytes))),
    );
  }
}

/// Opens [bytes] full screen.
void openPhoto(BuildContext context, Uint8List bytes) => Navigator.of(context)
    .push(
      MaterialPageRoute<void>(builder: (_) => ProductPhotoScreen(bytes: bytes)),
    );
