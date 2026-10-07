import 'package:flutter/material.dart';

/// The single source of truth for colour in the app.
///
/// Neutrals are strictly monochrome. The one exception is [inverse]: the
/// app-wide accent carries the Highlanders brand green `#363F2C` pulled from
/// the logo, so CTAs, active tabs, badges and promo cards all speak in the
/// brand tone. Every widget pulls its colours from here so the system stays
/// cohesive and is trivially auditable.
class BwColors {
  const BwColors._();

  /// #FFFFFF — page background.
  static const Color bg = Color(0xFFFFFFFF);

  /// #FFFFFF — card and sheet surface.
  static const Color surface = Color(0xFFFFFFFF);

  /// #F5F5F5 — inactive pill fill, icon badges, muted chips.
  static const Color subtle = Color(0xFFF5F5F5);

  /// #E5E5E5 — 1px card borders and hairline dividers.
  static const Color border = Color(0xFFE5E5E5);

  /// #111111 — outlined button strokes, strong headings.
  static const Color borderStrong = Color(0xFF111111);

  /// #111111 — primary body and heading text.
  static const Color text = Color(0xFF111111);

  /// #666666 — secondary text, captions, timestamps.
  static const Color textMuted = Color(0xFF666666);

  /// #363F2C — Highlanders brand green. Solid CTAs, active tab, promo cards.
  ///
  /// Matches `BwBrand.green`, the flat fill of the logo mark. White on it and
  /// it on white both clear ~10:1 contrast, so `onInverse` stays unambiguous.
  static const Color inverse = Color(0xFF363F2C);

  /// #FFFFFF — text and icons sitting on [inverse] surfaces.
  static const Color onInverse = Color(0xFFFFFFFF);

  /// Brand-green-to-dark gradient for the hero banner and offer cards.
  static const List<Color> promoGradient = <Color>[
    Color(0xFF363F2C),
    Color(0xFF111111),
  ];

  /// Disabled foreground.
  static const Color disabled = Color(0xFFBFBFBF);

  /// Disabled background.
  static const Color disabledBg = Color(0xFFF0F0F0);

  /// Transparent, spelled out for emphasis-free layouts.
  static const Color transparent = Color(0x00000000);
}