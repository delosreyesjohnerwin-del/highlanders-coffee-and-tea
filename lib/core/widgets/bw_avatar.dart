import 'package:flutter/material.dart';

import '../theme/bw_colors.dart';
import '../theme/bw_metrics.dart';

/// Circular avatar that falls back to the user's initials when no photo has
/// been uploaded. Always sits inside a crisp ring.
class BwAvatar extends StatelessWidget {
  const BwAvatar({
    super.key,
    this.imageUrl,
    this.initials,
    this.size = 44,
    this.inverted = false,
    this.bordered = true,
  });

  final String? imageUrl;
  final String? initials;
  final double size;

  /// Render for use on a black surface — white ring, white initials.
  final bool inverted;
  final bool bordered;

  static String initialsOf(String name) {
    final List<String> parts = name.trim().split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final String? url = imageUrl;
    final Color ring = inverted ? BwColors.onInverse : BwColors.borderStrong;
    final Color bg = inverted ? BwColors.onInverse : BwColors.subtle;
    final Color fg = inverted ? BwColors.inverse : BwColors.text;

    final String text = (initials != null && initials!.isNotEmpty) ? initials! : initialsOf('HL');

    final Widget content = url == null || url.isEmpty
        ? Center(
            child: Text(
              text,
              style: TextStyle(
                fontSize: size * 0.36,
                fontWeight: FontWeight.w700,
                color: fg,
                letterSpacing: 0.2,
              ),
            ),
          )
        : Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Center(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: size * 0.36,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
          );

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: bordered ? Border.all(color: ring, width: BwStroke.strong) : null,
      ),
      child: content,
    );
  }
}