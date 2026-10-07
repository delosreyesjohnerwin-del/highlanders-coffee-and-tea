import 'package:flutter/material.dart';

/// The Highlanders brand mark.
///
/// Every asset referenced here is derived from `png/highlanders.jpg` by
/// `tool/generate_brand_assets.ps1`. Regenerate through that script rather than
/// editing the PNGs; it is the only thing that keeps the launcher icon, the
/// splash and the in-app mark from drifting apart.
///
/// Two notes on the source, both measured rather than assumed:
///
///  * The mark is a flat `#363F2C` fill on white with no alpha channel. A
///    luminance histogram shows exactly two populations -- the fill and the
///    ground -- with only an antialiasing skirt between them, so there is no
///    second design tone to preserve and the JPEG's per-pixel chroma noise can be
///    discarded safely.
///  * The lettering has enclosed white counters. Those are kept as transparent
///    rather than filled in, which on a white background is indistinguishable
///    from the original.
class BwBrand {
  const BwBrand._();

  /// The mark in brand green, on a transparent ground.
  ///
  /// Use this wherever it sits on white. Never place it on an
  /// [BwColors.inverse] surface: since the accent is the same green, the
  /// artwork would vanish into the background.
  static const String markAsset = 'assets/brand/highlanders_mark.png';

  /// The same silhouette knocked out to solid white.
  ///
  /// For use on black surfaces, where the green would be effectively invisible.
  static const String markAssetWhite = 'assets/brand/highlanders_mark_white.png';

  /// The brand green, `#363F2C`. Measured as the median of 79,872 deep-interior
  /// pixels in the source JPEG; contrast against white is about 11:1.
  ///
  /// [BwColors.inverse] — the app-wide accent — is this exact colour, so the
  /// CTAs, active tabs and hero cards all carry the Highlanders mark's tone.
  static const Color green = Color(0xFF363F2C);

  /// Width divided by height of the mark, from the source crop (610 x 476).
  ///
  /// The mark is landscape, so every placement is sized by width and derives its
  /// height from this rather than being laid out in a square box.
  static const double aspect = 610 / 476;
}

/// The brand mark rendered at a chosen width.
///
/// Height follows from [BwBrand.aspect] so the mark cannot be distorted by a
/// careless parent. Use [inverted] on black surfaces.
class BwBrandmark extends StatelessWidget {
  const BwBrandmark({super.key, required this.width, this.inverted = false});

  /// Rendered width in logical pixels.
  final double width;

  /// Draw the white knock-out instead of the brand green.
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      inverted ? BwBrand.markAssetWhite : BwBrand.markAsset,
      width: width,
      height: width / BwBrand.aspect,
      fit: BoxFit.contain,
      // The source is 610px wide and is usually shown far smaller, so this is a
      // real downscale; medium keeps the letterforms from aliasing.
      filterQuality: FilterQuality.medium,
    );
  }
}