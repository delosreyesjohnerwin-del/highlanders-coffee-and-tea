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
import 'order_tracking_screen.dart';

/// Post-checkout confirmation.
class OrderSuccessScreen extends StatelessWidget {
  const OrderSuccessScreen({
    super.key,
    required this.order,
    required this.lines,
    required this.subtotal,
    required this.deliveryFee,
    required this.distanceKm,
    required this.promoCode,
    required this.paymentMethod,
    required this.etaMinutes,
  });

  final Order order;
  final List<OrderLine> lines;
  final num subtotal;
  final num deliveryFee;
  final double? distanceKm;
  final String? promoCode;
  final PaymentMethod paymentMethod;
  final int etaMinutes;

  @override
  Widget build(BuildContext context) {
    final bool pickup = order.fulfillment == Fulfillment.pickup;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(BwSpacing.gutter, BwSpacing.xl, BwSpacing.gutter, BwSpacing.xxl),
          children: <Widget>[
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(color: BwColors.inverse, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 38, color: BwColors.onInverse),
              ),
            ),
            const SizedBox(height: BwSpacing.xl),
            const Text(
              'Order confirmed',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: BwColors.text,
              ),
            ),
            const SizedBox(height: BwSpacing.sm),
            Text(
              pickup
                  ? 'We will have it ready for collection shortly.'
                  : 'On its way to you in about ${Fmt.eta(Duration(minutes: etaMinutes))}.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14.5, height: 1.45, color: BwColors.textMuted),
            ),

            const SizedBox(height: BwSpacing.xxl),

            // Pickup code — the key detail for collection orders.
            if (pickup) ...<Widget>[
              Container(
                padding: const EdgeInsets.symmetric(vertical: BwSpacing.xl),
                decoration: BoxDecoration(
                  color: BwColors.inverse,
                  borderRadius: BorderRadius.circular(BwRadius.card),
                ),
                child: Column(
                  children: <Widget>[
                    Text(
                      'SHOW THIS CODE AT THE COUNTER',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: BwColors.onInverse.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: BwSpacing.sm),
                    Text(
                      order.pickupCode ?? '0000',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                        color: BwColors.onInverse,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: BwSpacing.lg),
            ],

            BwCard(
              child: Column(
                children: <Widget>[
                  _KeyValue(label: 'Order ID', value: order.id, mono: true),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: BwSpacing.md),
                    child: Divider(height: 1),
                  ),
                  _KeyValue(label: 'Placed', value: Fmt.dateTime(order.createdAt)),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: BwSpacing.md),
                    child: Divider(height: 1),
                  ),
                  _KeyValue(
                    label: pickup ? 'Collection' : 'Delivery',
                    value: pickup ? 'Highlanders Coffee & Tea' : (order.address?.oneLine ?? '—'),
                  ),
                  if (distanceKm != null) ...<Widget>[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: BwSpacing.md),
                      child: Divider(height: 1),
                    ),
                    _KeyValue(label: 'Distance', value: Fmt.distance(distanceKm!)),
                  ],
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: BwSpacing.md),
                    child: Divider(height: 1),
                  ),
                  _KeyValue(
                    label: 'Payment',
                    value: paymentMethod.label,
                    trailing: paymentMethod.isPrepaid ? const BwBadge(label: 'PAID', dense: true) : null,
                  ),
                  if (promoCode != null) ...<Widget>[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: BwSpacing.md),
                      child: Divider(height: 1),
                    ),
                    _KeyValue(label: 'Promo', value: promoCode!),
                  ],
                ],
              ),
            ),

            const SizedBox(height: BwSpacing.lg),

            BwCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Your items',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: BwColors.text),
                  ),
                  const SizedBox(height: BwSpacing.md),
                  ...lines.map(
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
                      const Text(
                        'Total paid',
                        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: BwColors.text),
                      ),
                      const Spacer(),
                      Text(
                        Fmt.peso(subtotal + deliveryFee),
                        style: const TextStyle(
                          fontSize: 19,
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

            const SizedBox(height: BwSpacing.xl),

            BwButton(
              label: 'Track order',
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => _TrackingFromOrder(order: order),
                ),
              ),
            ),
            const SizedBox(height: BwSpacing.md),
            BwButton(
              label: 'Back to menu',
              variant: BwButtonVariant.outlined,
              onPressed: () => Navigator.of(context).popUntil((Route<void> r) => r.isFirst),
            ),
          ],
        ),
      ),
    );
  }
}

/// Looks the order back up from the session so tracking always shows the
/// latest status rather than a stale snapshot.
class _TrackingFromOrder extends StatelessWidget {
  const _TrackingFromOrder({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final Order? fresh = context.read<SessionProvider>().orderById(order.id);

    return OrderTrackingScreen(order: fresh ?? order);
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value, this.mono = false, this.trailing});

  final String label;
  final String value;
  final bool mono;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: BwColors.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: BwColors.text,
              letterSpacing: mono ? 0.6 : 0,
            ),
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: BwSpacing.sm),
          trailing!,
        ],
      ],
    );
  }
}