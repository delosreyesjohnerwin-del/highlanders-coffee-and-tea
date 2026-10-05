import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/bw_colors.dart';
import '../../../core/theme/bw_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/bw_badge.dart';
import '../../../core/widgets/bw_card.dart';
import '../../../data/models/menu.dart';
import '../../../state/cart_provider.dart';

/// Menu item row used on the home screen and in search results.
class MenuItemCard extends StatelessWidget {
  const MenuItemCard({
    super.key,
    required this.item,
    this.onTap,
    this.dense = false,
  });

  final MenuItem item;
  final VoidCallback? onTap;

  /// Compact variant for horizontal carousels.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return BwCard(
      onTap: onTap,
      padding: EdgeInsets.all(dense ? BwSpacing.md : BwSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          BwThumb(imageUrl: item.imageUrl, size: dense ? 56 : 72, icon: Icons.local_cafe_outlined),
          SizedBox(width: dense ? BwSpacing.md : BwSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: dense ? 14.5 : 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: BwColors.text,
                        ),
                      ),
                    ),
                    if (item.isBestseller) ...<Widget>[
                      const SizedBox(width: BwSpacing.sm),
                      const BwBadge(label: 'BEST', variant: BwBadgeVariant.subtle, dense: true),
                    ],
                  ],
                ),
                SizedBox(height: dense ? 2 : 4),
                Text(
                  item.description,
                  maxLines: dense ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: dense ? 12 : 13,
                    height: 1.4,
                    color: BwColors.textMuted,
                  ),
                ),
                SizedBox(height: dense ? BwSpacing.sm : BwSpacing.md),
                Row(
                  children: <Widget>[
                    Text(
                      Fmt.peso(item.price),
                      style: TextStyle(
                        fontSize: dense ? 14.5 : 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: BwColors.text,
                      ),
                    ),
                    const Spacer(),
                    _AddButton(item: item, dense: dense),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Minus / quantity / plus stepper, or a single plus when the item is not yet
/// in the cart.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.item, required this.dense});

  final MenuItem item;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final int qty = context.select<CartProvider, int>((CartProvider c) => c.quantityOf(item.id));
    final CartProvider cart = context.read<CartProvider>();

    final double size = dense ? 30 : 34;

    // Sold out (or delisted): replace the stepper with a static label rather
    // than a disabled button. A greyed-out "+" reads as "broken", whereas a
    // clear "Sold out" tells the customer what actually happened. The item stays
    // listed on purpose — hiding a bestseller the moment it runs out is worse
    // than admitting it is temporarily unavailable.
    if (!item.isOrderable) {
      return Container(
        height: size,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: BwSpacing.sm),
        decoration: BoxDecoration(
          color: BwColors.subtle,
          borderRadius: BorderRadius.circular(BwRadius.pill),
          border: Border.all(color: BwColors.border),
        ),
        child: Text(
          item.stock <= 0 ? 'Sold out' : 'Unavailable',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: BwColors.textMuted,
          ),
        ),
      );
    }

    if (qty == 0) {
      return _IconStep(
        icon: Icons.add_rounded,
        size: size,
        onTap: () => cart.add(item.id),
      );
    }

    return Container(
      height: size,
      decoration: BoxDecoration(
        color: BwColors.inverse,
        borderRadius: BorderRadius.circular(BwRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _IconStep(
            icon: Icons.remove_rounded,
            size: size,
            inverted: true,
            onTap: () => cart.remove(item.id),
          ),
          Text(
            '$qty',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: BwColors.onInverse,
            ),
          ),
          _IconStep(
            icon: Icons.add_rounded,
            size: size,
            inverted: true,
            // At the stock ceiling there is nothing left to add, so the plus goes
            // inert rather than tapping and silently doing nothing.
            onTap: qty >= item.stock ? null : () => cart.add(item.id),
          ),
        ],
      ),
    );
  }
}

class _IconStep extends StatelessWidget {
  const _IconStep({
    required this.icon,
    required this.size,
    this.onTap,
    this.inverted = false,
  });

  final IconData icon;
  final double size;
  final bool inverted;

  /// Null disables the button — the stock ceiling on the plus stepper.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;

    return Material(
      color: BwColors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: size * 0.55,
            // Fade rather than hide: the stepper keeps its shape, so the row
            // does not reflow when the ceiling is reached.
            color: enabled ? BwColors.onInverse : BwColors.disabled,
          ),
        ),
      ),
    );
  }
}