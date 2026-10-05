import 'package:flutter/material.dart';

/// Spacing, radius and elevation tokens.
///
/// A 4pt spacing scale keeps rhythm consistent across every screen.
class BwSpacing {
  const BwSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Standard horizontal page gutter.
  static const double gutter = 16;
}

class BwRadius {
  const BwRadius._();

  /// rounded-2xl — the default card and sheet radius.
  static const double card = 16;

  /// Pills and fully-rounded chips.
  static const double pill = 999;

  /// Small badges.
  static const double chip = 8;

  /// Input fields.
  static const double field = 12;
}

class BwStroke {
  const BwStroke._();

  /// 1px hairline borders (the brief specifies exactly 1px).
  static const double hairline = 1;

  /// Slightly heavier border for "strong" outlined controls.
  static const double strong = 1.5;
}

/// Shadows are intentionally almost invisible. The design leans on 1px
/// borders rather than elevation to separate surfaces.
class BwShadow {
  const BwShadow._();

  static const List<BoxShadow> none = <BoxShadow>[];

  /// Used sparingly, for bottom sheets and the floating profile stats card.
  static const List<BoxShadow> soft = <BoxShadow>[
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];
}