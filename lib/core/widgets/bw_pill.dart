import 'package:flutter/material.dart';

import '../theme/bw_colors.dart';
import '../theme/bw_metrics.dart';

/// Horizontal filter pill used by the category carousel.
///
/// Active: solid black fill, white text. Inactive: white fill, 1px black
/// border, dark text. Exactly as specified in the brief.
class BwPill extends StatelessWidget {
  const BwPill({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onTap,
    this.icon,
    this.padding = const EdgeInsets.symmetric(horizontal: BwSpacing.lg, vertical: 11),
  });

  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final IconData? icon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final Color fg = isSelected ? BwColors.onInverse : BwColors.text;

    return Material(
      color: isSelected ? BwColors.inverse : BwColors.surface,
      borderRadius: BorderRadius.circular(BwRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BwRadius.pill),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BwRadius.pill),
            border: Border.all(
              color: isSelected ? BwColors.inverse : BwColors.borderStrong,
              width: BwStroke.strong,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scrollable strip of [BwPill]s.
class BwPillRow extends StatelessWidget {
  const BwPillRow({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
  });

  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: BwSpacing.sm),
        itemBuilder: (BuildContext context, int i) {
          return BwPill(
            label: items[i],
            isSelected: i == selectedIndex,
            onTap: () => onSelected(i),
          );
        },
      ),
    );
  }
}