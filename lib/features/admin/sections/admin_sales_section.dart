import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/bw_colors.dart';
import '../../../core/theme/bw_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/bw_badge.dart';
import '../../../core/widgets/bw_card.dart';
import '../../../data/models/order.dart';
import '../../../state/admin_provider.dart';
import '../admin_dashboard_screen.dart';
import 'admin_overview_section.dart';

/// Sales report for a chosen day: summary figures, payment split and the
/// transaction log.
class AdminSalesSection extends StatefulWidget {
  const AdminSalesSection({super.key});

  @override
  State<AdminSalesSection> createState() => _AdminSalesSectionState();
}

class _AdminSalesSectionState extends State<AdminSalesSection> {
  @override
  Widget build(BuildContext context) {
    final AdminProvider admin = context.watch<AdminProvider>();

    final List<Order> orders = admin.ordersOnDay(admin.today);
    final num revenue = orders.fold<num>(0, (num s, Order o) => s + o.total);
    final num fees = orders.fold<num>(0, (num s, Order o) => s + o.deliveryFee);
    final ({num cash, num electronic}) split = admin.paymentSplitForToday;

    final bool isToday = DateUtils.isSameDay(admin.today, DateTime.now());

    return Column(
      children: <Widget>[
        // Date stepper. Forward is capped at today — there are no future sales.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            BwSpacing.gutter,
            BwSpacing.md,
            BwSpacing.gutter,
            BwSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => admin.shiftDay(-1),
                tooltip: 'Previous day',
              ),
              Expanded(
                child: Column(
                  children: <Widget>[
                    Text(
                      isToday ? 'Today' : Fmt.date(admin.today),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: BwColors.text,
                      ),
                    ),
                    if (isToday)
                      Text(
                        Fmt.date(admin.today),
                        style: const TextStyle(fontSize: 12, color: BwColors.textMuted),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: isToday ? null : () => admin.shiftDay(1),
                tooltip: 'Next day',
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: BwSpacing.xxl),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: AdminStat(
                        label: 'Gross',
                        value: Fmt.pesoWhole(revenue),
                        icon: Icons.payments_outlined,
                      ),
                    ),
                    const SizedBox(width: BwSpacing.sm),
                    Expanded(
                      child: AdminStat(
                        label: 'Orders',
                        value: '${orders.length}',
                        icon: Icons.receipt_long_outlined,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: BwSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: AdminStat(
                        label: 'Delivery fees',
                        value: Fmt.pesoWhole(fees),
                        icon: Icons.delivery_dining_outlined,
                      ),
                    ),
                    const SizedBox(width: BwSpacing.sm),
                    Expanded(
                      child: AdminStat(
                        label: 'Avg ticket',
                        value: Fmt.pesoWhole(
                          orders.isEmpty ? 0 : revenue / orders.length,
                        ),
                        icon: Icons.trending_up_rounded,
                      ),
                    ),
                  ],
                ),
              ),

              const AdminSectionHeader(title: 'Payment split'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
                child: BwCard(child: _PaymentSplit(cash: split.cash, electronic: split.electronic)),
              ),

              AdminSectionHeader(
                title: 'Transactions',
                subtitle: '${orders.length} settled order${orders.length == 1 ? '' : 's'}',
              ),

              if (orders.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: BwSpacing.lg),
                  child: AdminEmptyState(
                    message: 'No settled orders on this day.',
                    icon: Icons.event_busy_outlined,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
                  child: BwCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BwSpacing.lg,
                      vertical: BwSpacing.xs,
                    ),
                    child: Column(
                      children: orders.asMap().entries.map((MapEntry<int, Order> e) {
                        final Order o = e.value;
                        final bool last = e.key == orders.length - 1;

                        return Column(
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: BwSpacing.md),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  SizedBox(
                                    width: 54,
                                    child: Text(
                                      Fmt.time(o.createdAt),
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: BwColors.textMuted,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Text(
                                          o.customerName ?? 'Walk-in',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: BwColors.text,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          o.lines
                                              .map((OrderLine l) => '${l.quantity}× ${l.name}')
                                              .join(', '),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            height: 1.35,
                                            color: BwColors.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: BwSpacing.sm),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Text(
                                        Fmt.pesoWhole(o.total),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: BwColors.text,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      BwBadge(
                                        label: o.paymentMethod.label,
                                        variant: BwBadgeVariant.outline,
                                        dense: true,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (!last) const Divider(height: 1),
                          ],
                        );
                      }).toList(growable: false),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Cash versus electronic, as two proportional bars.
class _PaymentSplit extends StatelessWidget {
  const _PaymentSplit({required this.cash, required this.electronic});

  final num cash;
  final num electronic;

  @override
  Widget build(BuildContext context) {
    final num total = cash + electronic;

    // No sales yet: show zeroes rather than dividing by zero.
    final double cashFraction = total <= 0 ? 0 : (cash / total).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Cash · ${Fmt.pesoWhole(cash)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: BwColors.text),
              ),
            ),
            Text(
              '${(cashFraction * 100).round()}%',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: BwColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: BwSpacing.sm),
        // Flex proportions, so an all-cash or all-electronic day renders as a
        // full bar rather than collapsing.
        ClipRRect(
          borderRadius: BorderRadius.circular(BwRadius.chip),
          child: SizedBox(
            height: 10,
            child: Row(
              children: <Widget>[
                Expanded(
                  flex: total <= 0 ? 1 : (cashFraction * 100).round().clamp(1, 100),
                  child: Container(color: BwColors.inverse),
                ),
                Expanded(
                  flex: total <= 0 ? 1 : ((1 - cashFraction) * 100).round().clamp(1, 100),
                  child: Container(color: BwColors.border),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: BwSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'E-wallets · ${Fmt.pesoWhole(electronic)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: BwColors.text),
              ),
            ),
            const SizedBox(width: BwSpacing.sm),
            BwBadge(label: 'GCash · Maya · E-bank', variant: BwBadgeVariant.subtle, dense: true),
          ],
        ),
      ],
    );
  }
}