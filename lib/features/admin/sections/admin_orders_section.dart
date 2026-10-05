import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/bw_colors.dart';
import '../../../core/theme/bw_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/bw_badge.dart';
import '../../../core/widgets/bw_button.dart';
import '../../../core/widgets/bw_card.dart';
import '../../../data/models/order.dart';
import '../../../state/admin_provider.dart';
import '../admin_dashboard_screen.dart';
import 'admin_overview_section.dart';

/// Live order board: everything in flight, with one-tap advancement.
class AdminOrdersSection extends StatefulWidget {
  const AdminOrdersSection({super.key});

  @override
  State<AdminOrdersSection> createState() => _AdminOrdersSectionState();
}

class _AdminOrdersSectionState extends State<AdminOrdersSection> {
  OrderStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final AdminProvider admin = context.watch<AdminProvider>();

    // The board shows in-flight work; settled orders belong to the Sales report.
    final List<Order> active = admin.openOrders;
    final List<Order> visible = _filter == null
        ? active
        : active.where((Order o) => o.status == _filter).toList(growable: false);

    final Map<OrderStatus, int> counts = <OrderStatus, int>{};
    for (final Order o in active) {
      counts[o.status] = (counts[o.status] ?? 0) + 1;
    }

    return Column(
      children: <Widget>[
        const SizedBox(height: BwSpacing.md),
        StatusFilterBar(
          selected: _filter,
          onChanged: (OrderStatus? s) => setState(() => _filter = s),
          allLabel: 'In flight',
          allCount: active.length,
          counts: counts,
        ),
        const SizedBox(height: BwSpacing.md),
        Expanded(
          child: visible.isEmpty
              ? AdminEmptyState(
                  message: _filter == null
                      ? 'No orders in the queue.'
                      : 'Nothing at ${_filter!.label.toLowerCase()} right now.',
                  icon: Icons.inbox_outlined,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    BwSpacing.gutter,
                    0,
                    BwSpacing.gutter,
                    BwSpacing.xxl,
                  ),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: BwSpacing.md),
                  itemBuilder: (BuildContext context, int i) => _OrderCard(order: visible[i]),
                ),
        ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final AdminProvider admin = context.read<AdminProvider>();
    final bool terminal = order.status == OrderStatus.delivered;

    return BwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  order.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: BwColors.text,
                  ),
                ),
              ),
              const SizedBox(width: BwSpacing.sm),
              BwBadge(
                label: order.status.label,
                variant: order.status.isSettled ? BwBadgeVariant.subtle : BwBadgeVariant.solid,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${order.customerName ?? 'Walk-in'} · ${Fmt.time(order.createdAt)}',
            style: const TextStyle(fontSize: 12.5, color: BwColors.textMuted),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: BwSpacing.md),
            child: Divider(height: 1),
          ),

          ...order.lines.map(
            (OrderLine l) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: <Widget>[
                  Text(
                    '${l.quantity}×',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: BwColors.text,
                    ),
                  ),
                  const SizedBox(width: BwSpacing.sm),
                  Expanded(
                    child: Text(
                      l.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, color: BwColors.text),
                    ),
                  ),
                  const SizedBox(width: BwSpacing.sm),
                  Text(
                    Fmt.peso(l.lineTotal),
                    style: const TextStyle(fontSize: 13, color: BwColors.textMuted),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: BwSpacing.sm),
          // Wrapped rather than a Row of two badges: on a narrow screen the
          // fulfilment and payment labels together exceed the available width.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              BwBadge(
                label: order.fulfillment.label,
                variant: BwBadgeVariant.subtle,
                icon: order.fulfillment == Fulfillment.pickup
                    ? Icons.shopping_basket_outlined
                    : Icons.delivery_dining_outlined,
                dense: true,
              ),
              BwBadge(label: order.paymentMethod.label, variant: BwBadgeVariant.outline, dense: true),
              if (order.address != null)
                BwBadge(
                  label: order.address!.barangayName,
                  variant: BwBadgeVariant.outline,
                  icon: Icons.place_outlined,
                  dense: true,
                ),
              if (order.driverName != null)
                BwBadge(
                  label: order.driverName!,
                  variant: BwBadgeVariant.outline,
                  icon: Icons.delivery_dining_outlined,
                  dense: true,
                ),
            ],
          ),

          const SizedBox(height: BwSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  Fmt.itemCount(order.itemCount),
                  style: const TextStyle(fontSize: 12.5, color: BwColors.textMuted),
                ),
              ),
              Text(
                Fmt.pesoWhole(order.total),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: BwColors.text,
                ),
              ),
            ],
          ),

          const SizedBox(height: BwSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: BwButton(
                  label: 'Cancel',
                  variant: BwButtonVariant.outlined,
                  height: 44,
                  onPressed: terminal ? null : () => admin.cancelOrder(order.id),
                ),
              ),
              const SizedBox(width: BwSpacing.sm),
              Expanded(
                flex: 2,
                child: BwButton(
                  label: AdminProvider.actionLabelFor(order.status),
                  height: 44,
                  onPressed: terminal ? null : () => admin.advanceOrder(order.id),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}