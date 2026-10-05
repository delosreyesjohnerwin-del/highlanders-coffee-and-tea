import 'package:flutter/material.dart';

import '../theme/bw_colors.dart';
import '../theme/bw_metrics.dart';

/// The workhorse container: white surface, 1px #E5E5E5 hairline, 16px radius.
///
/// The design brief leans on borders rather than shadows to separate surfaces,
/// so elevation is opt-in and off by default.
class BwCard extends StatelessWidget {
  const BwCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(BwSpacing.lg),
    this.onTap,
    this.borderColor = BwColors.border,
    this.borderWidth = BwStroke.hairline,
    this.radius = BwRadius.card,
    this.color = BwColors.surface,
    this.shadows = BwShadow.none,
  });

  /// Inverse variant — solid black card with white content, used for the
  /// hero banner, the profile header and offer tiles.
  const BwCard.inverse({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(BwSpacing.lg),
    this.onTap,
    this.radius = BwRadius.card,
    this.borderColor = BwColors.inverse,
    this.borderWidth = BwStroke.hairline,
  })  : color = BwColors.inverse,
        shadows = BwShadow.none;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color borderColor;
  final double borderWidth;
  final double radius;
  final Color color;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) {
    final BorderRadius borderRadius = BorderRadius.circular(radius);

    final Widget content = Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: shadows,
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return content;

    return Material(
      color: BwColors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        splashColor: const Color(0x0A000000),
        highlightColor: const Color(0x0A000000),
        child: content,
      ),
    );
  }
}

/// A compact image tile with a graceful placeholder for missing product photos.
///
/// Placeholder is a light gray block with a monochrome glyph — never a broken
/// image icon or a coloured box.
class BwThumb extends StatelessWidget {
  const BwThumb({
    super.key,
    this.imageUrl,
    this.size = 64,
    this.radius = BwRadius.card,
    this.icon = Icons.local_cafe_outlined,
    this.fit = BoxFit.cover,
  });

  const BwThumb.rect({super.key, this.imageUrl, this.size = 64, this.icon = Icons.local_cafe_outlined})
      : radius = BwRadius.card,
        fit = BoxFit.cover;

  final String? imageUrl;
  final double size;
  final double radius;
  final IconData icon;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final String? url = imageUrl;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: BwColors.subtle,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: BwColors.border),
      ),
      child: url == null || url.isEmpty
          ? Icon(icon, size: size * 0.34, color: BwColors.disabled)
          : Image.network(
              url,
              fit: fit,
              errorBuilder: (_, _, _) =>
                  Icon(icon, size: size * 0.34, color: BwColors.disabled),
              loadingBuilder: (BuildContext ctx, Widget child, ImageChunkEvent? progress) {
                if (progress == null) return child;
                return Center(
                  child: SizedBox(
                    width: size * 0.22,
                    height: size * 0.22,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            ),
    );
  }
}