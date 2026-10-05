import 'package:flutter/material.dart';

import '../theme/bw_colors.dart';
import '../theme/bw_metrics.dart';

/// Segmented control — "Active" vs "Past Orders".
///
/// The selected segment is a solid black fill with white text; the unselected
/// segment sits on white with a dark label.
class BwSegmented<T> extends StatelessWidget {
  const BwSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.padding = const EdgeInsets.all(4),
    this.labelBuilder,
  });

  final List<T> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry padding;

  /// Custom label for each segment. Defaults to the enum name, which is why
  /// the orders screen renders "active" / "past".
  final String Function(T segment)? labelBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: BwColors.bg,
        borderRadius: BorderRadius.circular(BwRadius.card),
        border: Border.all(color: BwColors.borderStrong, width: BwStroke.strong),
      ),
      child: Row(
        children: segments.map((T segment) {
          final bool isSelected = segment == selected;

          return Expanded(
            child: Material(
              color: isSelected ? BwColors.inverse : BwColors.transparent,
              borderRadius: BorderRadius.circular(BwRadius.field),
              child: InkWell(
                onTap: () => onChanged(segment),
                borderRadius: BorderRadius.circular(BwRadius.field),
                child: Container(
                  height: 40,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: BwSpacing.sm),
                  child: Text(
                    labelBuilder?.call(segment) ?? _labelFor(segment),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? BwColors.onInverse : BwColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }

  static String _labelFor<T>(T segment) {
    if (segment is Enum) return (segment as Enum).name;
    return segment.toString();
  }
}

/// Label above a group of rows.
class BwSectionHeader extends StatelessWidget {
  const BwSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(BwSpacing.gutter, BwSpacing.xl, BwSpacing.gutter, BwSpacing.md),
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: BwColors.text,
              ),
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: BwColors.textMuted,
                    decoration: TextDecoration.underline,
                    decorationColor: BwColors.border,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}