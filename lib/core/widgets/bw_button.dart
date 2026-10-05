import 'package:flutter/material.dart';

import '../theme/bw_colors.dart';
import '../theme/bw_metrics.dart';

enum BwButtonVariant { solid, outlined, ghost }

/// Primary call-to-action.
///
/// [solid] is a solid black button with white text. [outlined] is a thin black
/// outline with a subtle #F5F5F5 fill. [ghost] is text-only.
class BwButton extends StatelessWidget {
  const BwButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = BwButtonVariant.solid,
    this.icon,
    this.trailingIcon,
    this.expand = true,
    this.height = 52,
    this.badgeLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final BwButtonVariant variant;
  final IconData? icon;
  final IconData? trailingIcon;

  /// Stretch to the full width of the parent. Turn off for inline buttons.
  final bool expand;
  final double height;

  /// Optional right-aligned counter, e.g. the item count on a cart button.
  final String? badgeLabel;

  bool get _enabled => onPressed != null;

  @override
  Widget build(BuildContext context) {
    final bool solid = variant == BwButtonVariant.solid;
    final bool ghost = variant == BwButtonVariant.ghost;

    final Color fg = !_enabled
        ? BwColors.disabled
        : solid
            ? BwColors.onInverse
            : BwColors.text;

    final Color bg = switch (variant) {
      BwButtonVariant.solid => _enabled ? BwColors.inverse : BwColors.disabledBg,
      BwButtonVariant.outlined => BwColors.subtle,
      BwButtonVariant.ghost => BwColors.transparent,
    };

    final Widget row = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 19, color: fg),
          const SizedBox(width: BwSpacing.sm),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
              color: fg,
            ),
          ),
        ),
        if (trailingIcon != null) ...<Widget>[
          const SizedBox(width: BwSpacing.sm),
          Icon(trailingIcon, size: 19, color: fg),
        ],
        if (badgeLabel != null) ...<Widget>[
          const SizedBox(width: BwSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: solid ? BwColors.onInverse : BwColors.inverse,
              borderRadius: BorderRadius.circular(BwRadius.pill),
            ),
            child: Text(
              badgeLabel!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: solid ? BwColors.inverse : BwColors.onInverse,
              ),
            ),
          ),
        ],
      ],
    );

    return Opacity(
      opacity: _enabled ? 1 : 0.6,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(BwRadius.card),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(BwRadius.card),
          splashColor: solid ? const Color(0x22FFFFFF) : const Color(0x0A000000),
          highlightColor: solid ? const Color(0x33FFFFFF) : const Color(0x0A000000),
          child: Container(
            height: height,
            width: expand ? double.infinity : null,
            padding: EdgeInsets.symmetric(horizontal: expand ? BwSpacing.lg : BwSpacing.xl),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BwRadius.card),
              border: ghost
                  ? null
                  : Border.all(
                      color: _enabled ? BwColors.borderStrong : BwColors.border,
                      width: variant == BwButtonVariant.outlined ? BwStroke.strong : BwStroke.hairline,
                    ),
            ),
            child: row,
          ),
        ),
      ),
    );
  }
}

/// Circular icon button with an optional 1px border — used in top bars.
class BwIconButton extends StatelessWidget {
  const BwIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.bordered = true,
    this.background = BwColors.surface,
    this.foreground = BwColors.text,
    this.size = 40,
    this.badgeCount,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool bordered;
  final Color background;
  final Color foreground;
  final double size;

  /// Shows a small count bubble in the top-right corner.
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final int? count = badgeCount;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Material(
          color: background,
          shape: CircleBorder(
            side: bordered ? const BorderSide(color: BwColors.border) : BorderSide.none,
          ),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: size * 0.45, color: foreground),
            ),
          ),
        ),
        if (count != null && count > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              decoration: BoxDecoration(
                color: BwColors.inverse,
                borderRadius: BorderRadius.circular(BwRadius.pill),
                border: Border.all(color: BwColors.bg, width: 1.5),
              ),
              child: Center(
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: BwColors.onInverse,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}