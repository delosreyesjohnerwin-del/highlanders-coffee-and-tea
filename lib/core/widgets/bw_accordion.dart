import 'package:flutter/material.dart';

import '../theme/bw_colors.dart';
import '../theme/bw_metrics.dart';

/// A collapsible card that reveals [children] under a tappable header.
///
/// The header pairs a title (optionally an accompanying [badge]) with a
/// chevron that rotates 180° while the body expands, so the affordance reads
/// the same way at every state. Collapsed by default — the whole point of an
/// accordion is that the detail stays out of the way until asked.
class BwAccordion extends StatefulWidget {
  const BwAccordion({
    super.key,
    required this.title,
    this.badge,
    required this.children,
    this.initiallyExpanded = false,
  });

  /// The header's primary text.
  final String title;

  /// Compact companion widget under the title (e.g. a status badge).
  final Widget? badge;

  /// Revealed while the accordion is expanded.
  final List<Widget> children;

  /// Whether the body starts open. Defaults to closed.
  final bool initiallyExpanded;

  @override
  State<BwAccordion> createState() => _BwAccordionState();
}

class _BwAccordionState extends State<BwAccordion> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: BwColors.surface,
        borderRadius: BorderRadius.circular(BwRadius.card),
        border: Border.all(color: BwColors.border, width: BwStroke.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Material(
            color: BwColors.transparent,
            child: InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(BwRadius.card),
              child: Padding(
                padding: const EdgeInsets.all(BwSpacing.lg),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: BwColors.text,
                              ),
                            ),
                          ),
                          if (widget.badge != null) ...<Widget>[
                            const SizedBox(width: BwSpacing.sm),
                            widget.badge!,
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: BwSpacing.sm),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        // One glyph rotated 180° rather than two swapped icons,
                        // so the rotation itself is the affordance.
                        Icons.expand_more_rounded,
                        size: 22,
                        color: _expanded ? BwColors.inverse : BwColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Divider(height: 1, color: BwColors.border),
                        Padding(
                          padding: const EdgeInsets.all(BwSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: widget.children,
                          ),
                        ),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}