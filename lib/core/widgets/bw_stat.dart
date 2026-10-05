import 'package:flutter/material.dart';

import '../theme/bw_colors.dart';
import '../theme/bw_metrics.dart';

/// Single figure in the profile stats card — "Orders 47", "Rewards ₱230".
class BwStat extends StatelessWidget {
  const BwStat({
    super.key,
    required this.value,
    required this.label,
    this.divider = false,
  });

  final String value;
  final String label;

  /// Draws a vertical hairline to the right — used between stats.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: BwSpacing.lg),
      decoration: divider
          ? const BoxDecoration(
              border: Border(right: BorderSide(color: BwColors.border)),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: BwColors.text,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: BwColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating white card with black borders that overlaps the black profile
/// header — the design brief's signature detail.
class BwStatsCard extends StatelessWidget {
  const BwStatsCard({super.key, required this.stats});

  final List<({String value, String label})> stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
      padding: const EdgeInsets.symmetric(horizontal: BwSpacing.sm),
      decoration: BoxDecoration(
        color: BwColors.surface,
        borderRadius: BorderRadius.circular(BwRadius.card),
        border: Border.all(color: BwColors.borderStrong, width: BwStroke.strong),
        boxShadow: BwShadow.soft,
      ),
      child: Row(
        children: stats.asMap().entries.map((MapEntry<int, ({String label, String value})> e) {
          return Expanded(
            child: BwStat(
              value: e.value.value,
              label: e.value.label,
              divider: e.key != stats.length - 1,
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}