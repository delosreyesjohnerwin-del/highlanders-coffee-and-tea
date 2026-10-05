import 'package:flutter/material.dart';

import '../theme/bw_colors.dart';
import '../theme/bw_metrics.dart';

/// One row of the profile menu: grayscale icon badge, label, chevron.
///
/// Matching the brief's "Saved Addresses", "Payment Methods", etc.
class BwMenuRow extends StatelessWidget {
  const BwMenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.trailingText,
    this.showChevron = true,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? trailingText;
  final bool showChevron;

  /// Reserved for future destructive actions; kept monochrome.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BwColors.surface,
      child: InkWell(
        onTap: onTap,
        splashColor: const Color(0x0A000000),
        highlightColor: const Color(0x0A000000),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter, vertical: BwSpacing.md),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: BwColors.subtle,
                  borderRadius: BorderRadius.circular(BwRadius.chip),
                ),
                child: Icon(icon, size: 19, color: BwColors.text),
              ),
              const SizedBox(width: BwSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: BwColors.text,
                  ),
                ),
              ),
              if (trailingText != null)
                Padding(
                  padding: const EdgeInsets.only(right: BwSpacing.xs),
                  child: Text(
                    trailingText!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: BwColors.textMuted,
                    ),
                  ),
                ),
              if (showChevron)
                const Icon(Icons.chevron_right_rounded, size: 22, color: BwColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stacks [BwMenuRow]s inside one bordered card with hairline dividers.
class BwMenuGroup extends StatelessWidget {
  const BwMenuGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];

    for (int i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(const Padding(
          padding: EdgeInsets.only(left: 68),
          child: Divider(height: 1),
        ));
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: BwColors.surface,
        borderRadius: BorderRadius.circular(BwRadius.card),
        border: Border.all(color: BwColors.border),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}