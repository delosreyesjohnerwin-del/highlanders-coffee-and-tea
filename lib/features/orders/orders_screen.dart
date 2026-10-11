import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/order_progress.dart';
import '../../core/widgets/bw_badge.dart';
import '../../core/widgets/bw_button.dart';
import '../../core/widgets/bw_card.dart';
import '../../core/widgets/bw_segment.dart';
import '../../data/models/order.dart';
import '../../state/cart_provider.dart';
import '../../state/session_provider.dart';
import '../order_tracking/order_tracking_screen.dart';
import '../shell/app_shell.dart';

enum _Tab { active, past }

/// "My Orders" with an Active / Past Orders toggle.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  _Tab _tab = _Tab.active;

  /// The card currently expanded. A single value is the whole exclusivity
  /// contract: only one card can show its details at a time, and expanding
  /// another automatically collapses the previous one.
  String? _expandedId;

  void _selectTab(_Tab t) {
    setState(() {
      _tab = t;
      // A fresh tab starts with every card collapsed.
      _expandedId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final SessionProvider session = context.watch<SessionProvider>();
    final List<Order> orders = _tab == _Tab.active ? session.activeOrders : session.pastOrders;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(BwSpacing.gutter, BwSpacing.lg, BwSpacing.gutter, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'My Orders',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: BwColors.text,
                    ),
                  ),
                  const SizedBox(height: BwSpacing.lg),
                  BwSegmented<_Tab>(
                    segments: const <_Tab>[_Tab.active, _Tab.past],
                    selected: _tab,
                    onChanged: _selectTab,
                  ),
                ],
              ),
            ),
            Expanded(
              child: orders.isEmpty
                  ? _EmptyOrders(isPast: _tab == _Tab.past)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(BwSpacing.gutter, BwSpacing.xl, BwSpacing.gutter, BwSpacing.xxl),
                      itemCount: orders.length,
                      separatorBuilder: (_, _) => const SizedBox(height: BwSpacing.md),
                      itemBuilder: (BuildContext context, int i) {
                        final Order order = orders[i];
                        return OrderCard(
                          order: order,
                          expanded: _expandedId == order.id,
                          onToggle: () => setState(() {
                            _expandedId = _expandedId == order.id ? null : order.id;
                          }),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Order card: summary by default, with a chevron that smoothly reveals the
/// full order details (items, delivery, payment breakdown, status) inside the
/// card. The card body still opens the tracking screen; the chevron is the
/// expand/collapse affordance.
class OrderCard extends StatefulWidget {
  const OrderCard({
    super.key,
    required this.order,
    required this.expanded,
    required this.onToggle,
    this.showReorder = true,
  });

  final Order order;
  final bool expanded;
  final VoidCallback onToggle;
  final bool showReorder;

  @override
  State<OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<OrderCard> with SingleTickerProviderStateMixin {
  late final AnimationController _detailsController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );

  @override
  void didUpdateWidget(OrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded != widget.expanded) {
      if (widget.expanded) {
        _detailsController.forward();
      } else {
        _detailsController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool delivered = widget.order.status == OrderStatus.delivered;

    return BwCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => OrderTrackingScreen(order: widget.order)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header: icon, title, order id, status badge.
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: BwColors.inverse,
                  borderRadius: BorderRadius.circular(BwRadius.chip),
                ),
                child: const Icon(Icons.storefront_outlined, size: 19, color: BwColors.onInverse),
              ),
              const SizedBox(width: BwSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'Highlanders Coffee & Tea',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: BwColors.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.order.id,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                        color: BwColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: BwSpacing.sm),
              BwBadge(
                label: widget.order.status.label,
                variant: delivered ? BwBadgeVariant.subtle : BwBadgeVariant.solid,
                dense: true,
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: BwSpacing.md),
            child: Divider(height: 1),
          ),

          // Summary row: placed, total, chevron.
          Row(
            children: <Widget>[
              const Icon(Icons.schedule_rounded, size: 13, color: BwColors.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  Fmt.dateTime(widget.order.createdAt),
                  style: const TextStyle(fontSize: 12, color: BwColors.textMuted),
                ),
              ),
              Text(
                Fmt.pesoWhole(widget.order.total),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: BwColors.text,
                ),
              ),
              const SizedBox(width: 4),
              _Chevron(
                key: Key('order-chevron-${widget.order.id}'),
                expanded: widget.expanded,
                onPressed: widget.onToggle,
              ),
            ],
          ),

          // Animated detail panel: height and opacity follow the controller,
          // so the reveal reads as a smooth grow-and-fade rather than a pop.
          AnimatedBuilder(
            animation: _detailsController,
            child: _ExpandedOrder(order: widget.order),
            builder: (BuildContext context, Widget? child) {
              final double t = _detailsController.value.clamp(0.0, 1.0);
              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: t,
                  child: Opacity(
                    opacity: t,
                    child: t > 0 ? child! : const SizedBox.shrink(),
                  ),
                ),
              );
            },
          ),

          if (widget.showReorder) ...<Widget>[
            const SizedBox(height: BwSpacing.lg),
            BwButton(
              label: 'Reorder',
              icon: Icons.refresh_rounded,
              variant: BwButtonVariant.outlined,
              height: 46,
              onPressed: () {
                context.read<CartProvider>().reorderFrom(widget.order);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(content: Text('Added to your cart')),
                  );
                ShellNav.cart();
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// The 44×44 circular chevron toggle with a 180° rotation affordance.
class _Chevron extends StatelessWidget {
  const _Chevron({super.key, required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: expanded ? 'Hide order details' : 'Show order details',
      // Spec: the touch target must be at least 44×44 even though the glyph
      // itself is small.
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: EdgeInsets.zero,
      iconSize: 22,
      icon: AnimatedRotation(
        turns: expanded ? 0.5 : 0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: Icon(
          Icons.expand_more_rounded,
          color: expanded ? BwColors.inverse : BwColors.textMuted,
        ),
      ),
    );
  }
}

/// The full order details revealed inside an expanded card.
class _ExpandedOrder extends StatelessWidget {
  const _ExpandedOrder({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(vertical: BwSpacing.md),
          child: Divider(height: 1),
        ),

        // Items with name, quantity × unit price, and line subtotal.
        ...order.lines.map(_itemRow),

        const Padding(
          padding: EdgeInsets.symmetric(vertical: BwSpacing.md),
          child: Divider(height: 1),
        ),

        _fulfillmentBlock(context),

        const Padding(
          padding: EdgeInsets.symmetric(vertical: BwSpacing.md),
          child: Divider(height: 1),
        ),

        _paymentBlock(context),

        const Padding(
          padding: EdgeInsets.symmetric(vertical: BwSpacing.md),
          child: Divider(height: 1),
        ),

        _statusBlock(context),
      ],
    );
  }

  Widget _itemRow(OrderLine line) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BwSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  line.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: BwColors.text),
                ),
                const SizedBox(height: 1),
                Text(
                  '${line.quantity} × ${Fmt.peso(line.price)}',
                  style: const TextStyle(fontSize: 11.5, color: BwColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: BwSpacing.sm),
          Text(
            Fmt.peso(line.lineTotal),
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: BwColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _fulfillmentBlock(BuildContext context) {
    if (order.fulfillment == Fulfillment.pickup) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _sectionTitle('Collection'),
          const SizedBox(height: 6),
          const Text(
            'Highlanders Coffee & Tea',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: BwColors.text),
          ),
          if (order.pickupCode != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              'Pickup code: ${order.pickupCode}',
              style: const TextStyle(fontSize: 12.5, color: BwColors.textMuted),
            ),
          ],
        ],
      );
    }

    final AppUser user = context.watch<SessionProvider>().user;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _sectionTitle('Delivery'),
        const SizedBox(height: 6),
        _DetailRow(
          label: 'Recipient',
          value: user.fullName,
          sub: user.phone,
        ),
        if (order.address != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            order.address!.label,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: BwColors.text),
          ),
          const SizedBox(height: 1),
          Text(
            order.address!.oneLine,
            style: const TextStyle(fontSize: 12.5, color: BwColors.textMuted),
          ),
          if (order.address!.note != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              order.address!.note!,
              style: const TextStyle(fontSize: 12, color: BwColors.textMuted),
            ),
          ],
          if (order.distanceKm != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '${Fmt.distance(order.distanceKm!)} from the café',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: BwColors.text),
            ),
          ],
        ],
      ],
    );
  }

  Widget _paymentBlock(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _sectionTitle('Payment'),
        const SizedBox(height: 6),
        _DetailRow(
          label: 'Method',
          value: order.paymentMethod.label,
          trailing: order.paymentMethod.isPrepaid
              ? const BwBadge(label: 'PAID', dense: true)
              : null,
        ),
        _DetailRow(label: 'Subtotal', value: Fmt.peso(order.subtotal)),
        _DetailRow(
          label: 'Delivery fee',
          value: order.deliveryFee == 0 ? 'Free' : Fmt.peso(order.deliveryFee),
        ),
        // The code is what the order carries; no discount amount is stored.
        if (order.promoCode != null) _DetailRow(label: 'Promo', value: order.promoCode!),
        const SizedBox(height: BwSpacing.sm),
        Row(
          children: <Widget>[
            const Text(
              'Total',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: BwColors.text),
            ),
            const Spacer(),
            Text(
              Fmt.peso(order.total),
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
    );
  }

  Widget _statusBlock(BuildContext context) {
    final int step = orderStepIndex(order.status);
    final DateTime? at =
        order.enteredAt(order.status) ?? (step == 0 ? order.createdAt : null);
    final bool stopped =
        order.status == OrderStatus.cancelled || order.status == OrderStatus.failedDelivery;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _sectionTitle('Status'),
        const SizedBox(height: 6),
        Row(
          key: Key('order-progress-${order.id}'),
          children: <Widget>[
            for (int i = 0; i < orderPipeline.length; i++) ...<Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i <= step ? BwColors.inverse : BwColors.surface,
                  border: Border.all(
                    color: i <= step ? BwColors.inverse : BwColors.border,
                    width: BwStroke.strong,
                  ),
                ),
              ),
              if (i < orderPipeline.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    color: i < step ? BwColors.inverse : BwColors.border,
                  ),
                ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          order.status.label,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: BwColors.text),
        ),
        if (at != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            Fmt.dateTime(at),
            key: Key('order-status-time-${order.id}'),
            style: const TextStyle(fontSize: 11.5, color: BwColors.textMuted),
          ),
        ],
        if (stopped) ...<Widget>[
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              const Icon(Icons.info_outline_rounded, size: 15, color: BwColors.textMuted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  order.status == OrderStatus.cancelled
                      ? 'This order was cancelled.'
                      : 'This order could not be delivered.',
                  style: const TextStyle(fontSize: 12, color: BwColors.textMuted),
                ),
              ),
            ],
          ),
        ],
        if (order.trackingNumber != null) ...<Widget>[
          const SizedBox(height: BwSpacing.sm),
          Row(
            children: <Widget>[
              const Icon(Icons.local_shipping_outlined, size: 15, color: BwColors.text),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${order.carrierName ?? 'Courier'} · #${order.trackingNumber}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: BwColors.text),
                ),
              ),
              if (order.carrierUrl != null)
                const Padding(
                  padding: EdgeInsets.only(left: BwSpacing.sm),
                  child: Icon(Icons.open_in_new_rounded, size: 13, color: BwColors.inverse),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _sectionTitle(String label) => Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: BwColors.textMuted,
        ),
      );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.sub, this.trailing});

  final String label;
  final String value;
  final String? sub;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: BwColors.textMuted),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  value,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: BwColors.text),
                ),
                if (sub != null) ...<Widget>[
                  const SizedBox(height: 1),
                  Text(
                    sub!,
                    style: const TextStyle(fontSize: 11.5, color: BwColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: BwSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders({required this.isPast});

  final bool isPast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(BwSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            isPast ? Icons.history_rounded : Icons.receipt_long_outlined,
            size: 56,
            color: BwColors.disabled,
          ),
          const SizedBox(height: BwSpacing.lg),
          Text(
            isPast ? 'No past orders' : 'No active orders',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: BwColors.text),
          ),
          const SizedBox(height: 6),
          Text(
            isPast
                ? 'Your completed orders will appear here.'
                : 'When you place an order you can track it here.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: BwColors.textMuted),
          ),
          const SizedBox(height: BwSpacing.xl),
          if (!isPast)
            BwButton(
              label: 'Browse menu',
              expand: false,
              onPressed: () => ShellNav.home(),
            ),
        ],
      ),
    );
  }
}