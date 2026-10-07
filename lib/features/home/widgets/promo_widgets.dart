import 'package:flutter/material.dart';

import '../../../core/theme/bw_colors.dart';
import '../../../core/theme/bw_metrics.dart';
import '../../../core/widgets/bw_badge.dart';
import '../../../data/models/menu.dart';

/// High-contrast hero promo: brand-green-to-dark card, white bold text, promo
/// tag and a solid white "Order Now" button with green text.
class PromoHeroBanner extends StatelessWidget {
  const PromoHeroBanner({super.key, required this.promo, required this.onCta});

  final Promo promo;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BwRadius.card),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: BwColors.promoGradient,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          // Decorative monochrome shapes — abstract steam rising from a cup.
          const Positioned(right: -28, top: -18, child: _Halo(size: 128)),
          const Positioned(right: 46, bottom: -46, child: _Halo(size: 96, opacity: 0.05)),
          Padding(
            padding: const EdgeInsets.all(BwSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (promo.badge != null) BwOfferTag(label: promo.badge!),
                const SizedBox(height: BwSpacing.md),
                Text(
                  promo.title,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.6,
                    color: BwColors.onInverse,
                  ),
                ),
                const SizedBox(height: BwSpacing.sm),
                Text(
                  promo.subtitle,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: BwColors.onInverse.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: BwSpacing.xl),
                _WhiteCta(label: promo.ctaLabel ?? 'Order Now', onTap: onCta),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Solid white pill button with black text, for use on dark surfaces.
class _WhiteCta extends StatelessWidget {
  const _WhiteCta({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BwColors.onInverse,
      borderRadius: BorderRadius.circular(BwRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BwRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: BwSpacing.xl, vertical: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: BwColors.inverse,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward_rounded, size: 17, color: BwColors.inverse),
            ],
          ),
        ),
      ),
    );
  }
}

class _Halo extends StatelessWidget {
  const _Halo({required this.size, this.opacity = 0.08});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: BwColors.onInverse.withValues(alpha: opacity),
          width: 14,
        ),
      ),
    );
  }
}

/// Dual promo cards for "Special Offers".
class OfferTiles extends StatelessWidget {
  const OfferTiles({super.key, required this.promos, required this.onTap});

  final List<Promo> promos;
  final ValueChanged<Promo> onTap;

  @override
  Widget build(BuildContext context) {
    if (promos.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 150,
      child: Row(
        children: promos.take(2).toList().asMap().entries.map((MapEntry<int, Promo> e) {
          final bool first = e.key == 0;

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: first ? 0 : BwSpacing.sm, right: first ? BwSpacing.sm : 0),
              child: _OfferTile(promo: e.value, onTap: () => onTap(e.value)),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.promo, required this.onTap});

  final Promo promo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String badge = promo.buyXGetY ?? (promo.discountPercent != null ? '${promo.discountPercent}% OFF' : 'OFFER');

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BwRadius.card),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            BwColors.borderStrong,
            BwColors.inverse,
          ],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: BwColors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(BwSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Align(
                  alignment: Alignment.topRight,
                  child: BwOfferTag(label: badge),
                ),
                // Flexible inner column: long promo copy must ellipsise rather
                // than overflow the fixed-height tile.
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        promo.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: BwColors.onInverse,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Flexible(
                        child: Text(
                          promo.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: BwColors.onInverse.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}