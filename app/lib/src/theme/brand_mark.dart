import 'package:flutter/material.dart';

/// The Garoto do Programa brand colors, used wherever the app wants to say
/// "made by the Garoto": the logo, the pink ";" and the dot grid.
abstract final class Brand {
  /// The neon green of the logo.
  static const green = Color(0xFF39FF88);

  /// The pink of the ";" and of the blinking eye.
  static const pink = Color(0xFFFF2E88);

  /// The darker greens and pinks that keep contrast on light backgrounds.
  static const greenOnLight = Color(0xFF0A7A3D);
  static const pinkOnLight = Color(0xFFD6006E);

  /// The green of the logo that reads on [brightness].
  static Color greenFor(Brightness brightness) =>
      brightness == Brightness.dark ? green : greenOnLight;

  /// The pink that reads on [brightness].
  static Color pinkFor(Brightness brightness) =>
      brightness == Brightness.dark ? pink : pinkOnLight;
}

/// The Garoto's face (the logo symbol), from the channel's official SVG
/// rendered to a large transparent PNG. An image, not a drawing in code:
/// the Linux renderer (Impeller on OpenGL ES) draws paths without smoothing
/// the edges, and the face came out jagged; images are filtered.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      dark ? 'assets/brand/garoto.png' : 'assets/brand/garoto-claro.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Garoto do Programa',
    );
  }
}

/// A title with the pink ";" at the end, the channel's signature:
/// "clientes;". The text stays a plain [Text] (the ";" is a separate,
/// silent piece), so it is read, found and cut like any other title.
class SemicolonText extends StatelessWidget {
  const SemicolonText(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            text,
            style: base,
            textAlign: textAlign,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ExcludeSemantics(
          child: Text(
            ';',
            style: base.copyWith(
              color: Brand.pinkFor(Theme.of(context).brightness),
            ),
          ),
        ),
      ],
    );
  }
}

/// The logo followed by "chat do garoto;" (the app's signature), for the
/// places where the app introduces itself.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.size = 32, this.vertical = false});

  /// The height of the face.
  final double size;

  /// The name goes under the face instead of beside it.
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final name = SemicolonText(
      'Chat do Garoto',
      style: (vertical ? t.headlineSmall : t.titleLarge)!.copyWith(
        fontWeight: FontWeight.w800,
      ),
    );
    final mark = BrandMark(size: size);
    return vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [mark, const SizedBox(height: 12), name],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              const SizedBox(width: 10),
              Flexible(child: name),
            ],
          );
  }
}

/// The dark background of the channel's art: a grid of dots (radial dots of
/// `#1a222d` every 44 px). Light themes get a softer version.
class DotGrid extends StatelessWidget {
  const DotGrid({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _DotGridPainter(
        color: dark ? const Color(0xFF1A222D) : const Color(0xFFD7DEE6),
      ),
      child: child,
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 44.0;
    final paint = Paint()..color = color;
    for (var y = gap / 2; y < size.height; y += gap) {
      for (var x = gap / 2; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 1.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.color != color;
}
