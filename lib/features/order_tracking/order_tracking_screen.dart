import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/bw_badge.dart';
import '../../core/widgets/bw_button.dart';
import '../../core/widgets/bw_card.dart';
import '../../data/models/order.dart';
import '../../state/session_provider.dart';

/// Order tracking: a vertical status stepper, driver card and order summary.
///
/// Deliberately has no live map — the driver card plus call button covers the
/// use case without a Maps API key or billing account.
class OrderTrackingScreen extends StatelessWidget {
  const OrderTrackingScreen({super.key, required this.order});

  final Order order;

  static const List<OrderStatus> _pipeline = <OrderStatus>[
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.ready,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
  ];

  @override
  Widget build(BuildContext context) {
    // Always prefer the live copy from the session.
    final Order? live = context.select<SessionProvider, Order?>(
      (SessionProvider s) => s.orderById(order.id),
    );
    final Order current = live ?? order;
    final bool pickup = current.fulfillment == Fulfillment.pickup;
    final int currentStep = _stepIndex(current.status);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track order'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(BwSpacing.gutter, BwSpacing.lg, BwSpacing.gutter, BwSpacing.xxl),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'Highlanders Coffee & Tea',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: BwColors.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      current.id,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.6,
                        color: BwColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              BwBadge(
                label: current.status.label,
                variant: current.status.isTerminal ? BwBadgeVariant.subtle : BwBadgeVariant.solid,
              ),
            ],
          ),

          const SizedBox(height: BwSpacing.xl),

          // Status stepper.
          BwCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Status',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: BwColors.text),
                ),
                const SizedBox(height: BwSpacing.lg),
                ...List<Widget>.generate(_pipeline.length, (int i) {
                  final bool done = i <= currentStep;
                  final bool isLast = i == _pipeline.length - 1;

                  return _StepRow(
                    label: _stepLabel(_pipeline[i], pickup: pickup),
                    done: done,
                    isLast: isLast,
                    isCurrent: i == currentStep,
                  );
                }),
              ],
            ),
          ),

          // Driver card — only for deliveries that are actually on the road.
          if (!pickup && (current.driverName != null || current.driverPhone != null)) ...<Widget>[
            const SizedBox(height: BwSpacing.lg),
            _DriverCard(order: current),
          ],

          // Pickup code.
          if (pickup && current.pickupCode != null) ...<Widget>[
            const SizedBox(height: BwSpacing.lg),
            _PickupCode(code: current.pickupCode!),
          ],

          // Delivery address.
          if (current.address != null) ...<Widget>[
            const SizedBox(height: BwSpacing.lg),
            BwCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.place_outlined, size: 19, color: BwColors.text),
                  const SizedBox(width: BwSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          current.address!.label,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: BwColors.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          current.address!.oneLine,
                          style: const TextStyle(fontSize: 13, color: BwColors.textMuted),
                        ),
                        if (current.distanceKm != null) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            '${Fmt.distance(current.distanceKm!)} from the café',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: BwColors.text),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Items.
          const SizedBox(height: BwSpacing.lg),
          BwCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Items',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: BwColors.text),
                ),
                const SizedBox(height: BwSpacing.md),
                ...current.lines.map(
                  (OrderLine l) => Padding(
                    padding: const EdgeInsets.only(bottom: BwSpacing.sm),
                    child: Row(
                      children: <Widget>[
                        Text(
                          '${l.quantity}×',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BwColors.text),
                        ),
                        const SizedBox(width: BwSpacing.sm),
                        Expanded(
                          child: Text(l.name, style: const TextStyle(fontSize: 13.5, color: BwColors.text)),
                        ),
                        Text(
                          Fmt.peso(l.lineTotal),
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: BwColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: BwSpacing.sm),
                  child: Divider(height: 1),
                ),
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        Fmt.dateTime(current.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: BwColors.textMuted),
                      ),
                    ),
                    const SizedBox(width: BwSpacing.sm),
                    const Spacer(),
                    Text(
                      Fmt.peso(current.total),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: BwColors.text,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: BwSpacing.lg),
          BwButton(
            label: 'Get help with this order',
            icon: Icons.help_outline_rounded,
            variant: BwButtonVariant.outlined,
            onPressed: () => ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('Help & Support — coming soon'))),
          ),
        ],
      ),
    );
  }

  static int _stepIndex(OrderStatus status) {
    if (status == OrderStatus.cancelled || status == OrderStatus.failedDelivery) return 0;
    final int i = _pipeline.indexOf(status);
    return i < 0 ? 0 : i;
  }

  static String _stepLabel(OrderStatus status, {required bool pickup}) {
    if (pickup) {
      return switch (status) {
        OrderStatus.pending => 'Order received',
        OrderStatus.confirmed => 'Confirmed',
        OrderStatus.preparing => 'Being prepared',
        OrderStatus.ready => 'Ready for pickup',
        OrderStatus.outForDelivery => 'Handed over',
        OrderStatus.delivered => 'Collected',
        _ => status.label,
      };
    }
    return status.label;
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.done,
    required this.isLast,
    required this.isCurrent,
  });

  final String label;
  final bool done;
  final bool isLast;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: done ? BwColors.inverse : BwColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: done ? BwColors.inverse : BwColors.border,
                    width: BwStroke.strong,
                  ),
                ),
                child: done
                    ? Icon(
                        isCurrent ? Icons.circle : Icons.check_rounded,
                        size: isCurrent ? 8 : 13,
                        color: BwColors.onInverse,
                      )
                    : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: done ? BwColors.inverse : BwColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: BwSpacing.md),
          Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : BwSpacing.lg, top: 1),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                color: done ? BwColors.text : BwColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return BwCard(
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: BwColors.subtle,
              borderRadius: BorderRadius.circular(BwRadius.chip),
              border: Border.all(color: BwColors.borderStrong, width: BwStroke.strong),
            ),
            child: const Icon(Icons.delivery_dining_outlined, size: 22, color: BwColors.text),
          ),
          const SizedBox(width: BwSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'Your rider',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: BwColors.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  order.driverName ?? 'Being assigned',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BwColors.text),
                ),
              ],
            ),
          ),
          if (order.driverPhone != null)
            BwButton(
              label: 'Call',
              icon: Icons.call_outlined,
              expand: false,
              height: 42,
              variant: BwButtonVariant.outlined,
              onPressed: () => ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text('Calling ${order.driverName}'))),
            ),
        ],
      ),
    );
  }
}

class _PickupCode extends StatelessWidget {
  const _PickupCode({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BwSpacing.xl),
      decoration: BoxDecoration(
        color: BwColors.inverse,
        borderRadius: BorderRadius.circular(BwRadius.card),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'PICKUP CODE',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: BwColors.onInverse.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    color: BwColors.onInverse,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.qr_code_2_rounded, size: 46, color: BwColors.onInverse),
        ],
      ),
    );
  }
}