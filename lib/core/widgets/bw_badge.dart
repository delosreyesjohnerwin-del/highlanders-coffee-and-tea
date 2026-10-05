import 'package:flutter/material.dart';

import '../theme/bw_colors.dart';
import '../theme/bw_metrics.dart';

enum BwBadgeVariant { solid, outline, subtle, inverse }

/// Small status pill — "OPEN", "Delivered", "Buy 1 Get 1".
class BwBadge extends StatelessWidget {
  const BwBadge({
    super.key,
    required this.label,
    this.variant = BwBadgeVariant.solid,
    this.icon,
    this.dense = false,
  });

  final String label;
  final BwBadgeVariant variant;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Color border) = switch (variant) {
      BwBadgeVariant.solid => (BwColors.inverse, BwColors.onInverse, BwColors.inverse),
      BwBadgeVariant.outline => (BwColors.surface, BwColors.text, BwColors.borderStrong),
      BwBadgeVariant.subtle => (BwColors.subtle, BwColors.text, BwColors.subtle),
      BwBadgeVariant.inverse => (BwColors.onInverse, BwColors.inverse, BwColors.onInverse),
    };

    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 9, vertical: dense ? 3 : 4.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(BwRadius.chip),
        border: Border.all(color: border, width: BwStroke.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: dense ? 10 : 12, color: fg),
            SizedBox(width: dense ? 3 : 4),
          ],
          // Flexible so a long label ellipsises inside a constrained parent
          // while still sizing to its content when unbounded.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: dense ? 10 : 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Big promotional tag for the hero banner and offer tiles — e.g. "20% OFF".
class BwOfferTag extends StatelessWidget {
  const BwOfferTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: BwColors.onInverse,
        borderRadius: BorderRadius.circular(BwRadius.chip),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: BwColors.inverse,
        ),
      ),
    );
  }
}