import 'package:flutter/material.dart';

import '../../../core/theme/bw_metrics.dart';

/// Sticky bottom action row shared by the admin add/edit sheets.
///
/// Shared rather than copy-pasted into each section because the button budget is
/// the tightest constraint in those sheets: at 360dp a cancel label, a destructive
/// icon and a full-width primary label is already the whole width, and a second
/// copy drifting by a few pixels is how one sheet ends up with a 44px-tall
/// confirm button next to a 48px one.
class AdminSheetActions extends StatelessWidget {
  const AdminSheetActions({
    super.key,
    required this.submitLabel,
    required this.onSubmit,
    this.deleteTooltip,
    this.onDelete,
  });

  final String submitLabel;
  final VoidCallback onSubmit;

  /// When null, no destructive button is shown — which is the right default for a
  /// sheet that is creating something new.
  final String? deleteTooltip;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (onDelete != null) ...<Widget>[
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            tooltip: deleteTooltip,
            onPressed: onDelete,
          ),
          const SizedBox(width: BwSpacing.sm),
        ],
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: BwSpacing.sm),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: onSubmit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BwRadius.card),
              ),
            ),
            child: Text(submitLabel),
          ),
        ),
      ],
    );
  }
}
