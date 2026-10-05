import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/utils/formatters.dart';
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
                    onChanged: (_Tab t) => setState(() => _tab = t),
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
                      itemBuilder: (BuildContext context, int i) => OrderCard(order: orders[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stacked order card: store row, status badge, item breakdown, total and a
/// full-width outlined Reorder button.
class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, this.showReorder = true});

  final Order order;
  final bool showReorder;

  @override
  Widget build(BuildContext context) {
    final bool delivered = order.status == OrderStatus.delivered;

    return BwCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => OrderTrackingScreen(order: order)),
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
                      order.id,
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
                label: order.status.label,
                variant: delivered ? BwBadgeVariant.subtle : BwBadgeVariant.solid,
                dense: true,
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: BwSpacing.md),
            child: Divider(height: 1),
          ),

          // Item breakdown.
          ...order.lines.map(
            (OrderLine line) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: BwColors.subtle,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${line.quantity}',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: BwColors.text),
                    ),
                  ),
                  const SizedBox(width: BwSpacing.sm),
                  Expanded(
                    child: Text(
                      line.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, color: BwColors.text),
                    ),
                  ),
                  Text(
                    Fmt.pesoWhole(line.lineTotal),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: BwColors.textMuted),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: BwSpacing.sm),
          Row(
            children: <Widget>[
              const Icon(Icons.schedule_rounded, size: 13, color: BwColors.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  Fmt.dateTime(order.createdAt),
                  style: const TextStyle(fontSize: 12, color: BwColors.textMuted),
                ),
              ),
              Text(
                Fmt.pesoWhole(order.total),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: BwColors.text,
                ),
              ),
            ],
          ),

          if (showReorder) ...<Widget>[
            const SizedBox(height: BwSpacing.lg),
            BwButton(
              label: 'Reorder',
              icon: Icons.refresh_rounded,
              variant: BwButtonVariant.outlined,
              height: 46,
              onPressed: () {
                context.read<CartProvider>().reorderFrom(order);
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