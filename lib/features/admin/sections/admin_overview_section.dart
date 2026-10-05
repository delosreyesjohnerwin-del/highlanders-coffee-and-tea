import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/bw_colors.dart';
import '../../../core/theme/bw_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/bw_badge.dart';
import '../../../core/widgets/bw_card.dart';
import '../../../data/models/menu.dart';
import '../../../data/models/order.dart';
import '../../../state/admin_provider.dart';
import '../../../state/catalog_provider.dart';
import '../admin_dashboard_screen.dart';

/// Analytics overview: the three headline figures, a seven-day revenue chart,
/// best sellers and anything that needs restocking.
class AdminOverviewSection extends StatelessWidget {
  const AdminOverviewSection({super.key});

  @override
  Widget build(BuildContext context) {
    final AdminProvider admin = context.watch<AdminProvider>();

    return ListView(
      padding: const EdgeInsets.only(bottom: BwSpacing.xxl),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            BwSpacing.gutter,
            BwSpacing.lg,
            BwSpacing.gutter,
            0,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _MetricCard(
                  label: 'Total revenue',
                  value: Fmt.pesoWhole(admin.revenueTotal),
                  icon: Icons.payments_outlined,
                  inverse: true,
                ),
              ),
              const SizedBox(width: BwSpacing.sm),
              Expanded(
                child: _MetricCard(
                  label: 'Total orders',
                  value: '${admin.ordersTotal}',
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
                child: _MetricCard(
                  label: 'Active users',
                  value: '${admin.activeUsers}',
                  icon: Icons.people_outline_rounded,
                ),
              ),
              const SizedBox(width: BwSpacing.sm),
              Expanded(
                child: _MetricCard(
                  label: 'Avg order',
                  value: Fmt.pesoWhole(admin.averageOrderValue),
                  icon: Icons.trending_up_rounded,
                ),
              ),
            ],
          ),
        ),

        const AdminSectionHeader(
          title: 'Last 7 days',
          subtitle: 'Settled revenue per day',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
          child: BwCard(child: _RevenueChart(series: admin.lastSevenDays)),
        ),

        const AdminSectionHeader(title: 'Best sellers', subtitle: 'By units sold'),
        _TopItems(items: admin.topItems()),

        const _RestockSection(),
      ],
    );
  }
}

/// Headline figure. Inverse (solid black) for revenue, outlined for the rest,
/// so the most important number reads first.
class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.inverse = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final Color fg = inverse ? BwColors.onInverse : BwColors.text;

    return BwCard.inverse(
      onTap: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: inverse ? BwColors.onInverse : BwColors.textMuted),
          const SizedBox(height: BwSpacing.sm),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: fg,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: inverse ? BwColors.onInverse : BwColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bar chart drawn with plain containers.
///
/// A charting package would pull in hues and animations the monochrome brief
/// rules out; seven bars of `Container` with a flex height do the job and stay
/// exactly on-palette.
class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.series});

  final List<DailyRevenue> series;

  static const double _chartHeight = 116;

  @override
  Widget build(BuildContext context) {
    final num peak = series.fold<num>(
      0,
      (num m, DailyRevenue d) => d.revenue > m ? d.revenue : m,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Peak ${Fmt.pesoWhole(peak)}',
          style: const TextStyle(fontSize: 12, color: BwColors.textMuted),
        ),
        const SizedBox(height: BwSpacing.md),
        SizedBox(
          height: _chartHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: series.map((DailyRevenue d) {
              // Guard against a zero peak so the bars don't divide by zero and
              // collapse to an invisible sliver.
              final double fraction = peak <= 0 ? 0 : (d.revenue / peak).toDouble();
              final bool isToday = DateUtils.isSameDay(d.day, DateTime.now());

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        height: (_chartHeight - 26) * fraction.clamp(0.0, 1.0),
                        decoration: BoxDecoration(
                          color: isToday ? BwColors.inverse : BwColors.borderStrong,
                          borderRadius: BorderRadius.circular(BwRadius.chip),
                        ),
                      ),
                      const SizedBox(height: BwSpacing.sm),
                      Text(
                        '${d.day.day}',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                          color: isToday ? BwColors.text : BwColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _TopItems extends StatelessWidget {
  const _TopItems({required this.items});

  final List<ItemPerformance> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: BwSpacing.xl),
        child: AdminEmptyState(message: 'No settled orders yet.', icon: Icons.bar_chart_rounded),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
      child: BwCard(
        padding: const EdgeInsets.symmetric(horizontal: BwSpacing.lg, vertical: BwSpacing.xs),
        child: Column(
          children: items.asMap().entries.map((MapEntry<int, ItemPerformance> e) {
            final ItemPerformance item = e.value;
            final bool last = e.key == items.length - 1;

            return Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: BwSpacing.md),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 20,
                        child: Text(
                          '${e.key + 1}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: BwColors.textMuted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: BwColors.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: BwSpacing.sm),
                      Text(
                        '${item.unitsSold}',
                        style: const TextStyle(fontSize: 13, color: BwColors.textMuted),
                      ),
                      const SizedBox(width: BwSpacing.md),
                      SizedBox(
                        width: 62,
                        child: Text(
                          Fmt.pesoWhole(item.revenue),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: BwColors.text,
                          ),
                        ),
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
    );
  }
}

/// Anything at or below its reorder level.
class _RestockSection extends StatelessWidget {
  const _RestockSection();

  @override
  Widget build(BuildContext context) {
    final List<MenuItem> low = AdminProvider.needsRestock(context.watch<CatalogProvider>().allItems);

    if (low.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AdminSectionHeader(
          title: 'Needs restocking',
          subtitle: '${low.length} item${low.length == 1 ? '' : 's'} at or below reorder level',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
          child: BwCard(
            padding: const EdgeInsets.symmetric(
              horizontal: BwSpacing.lg,
              vertical: BwSpacing.xs,
            ),
            child: Column(
              children: low.take(5).toList(growable: false).asMap().entries.map(
                    (MapEntry<int, MenuItem> e) {
                  final MenuItem item = e.value;
                  final bool last = e.key == low.take(5).length - 1;

                  return Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: BwSpacing.md),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: BwColors.text,
                                ),
                              ),
                            ),
                            const SizedBox(width: BwSpacing.sm),
                            StockStatusBadge(status: item.status),
                            const SizedBox(width: BwSpacing.sm),
                            Text(
                              '${item.stock}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: BwColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!last) const Divider(height: 1),
                    ],
                  );
                },
              ).toList(growable: false),
            ),
          ),
        ),
      ],
    );
  }
}

/// Maps a [StockStatus] onto the badge variants.
///
/// The mapping lives in the widget layer on purpose: the model knows *what*
/// the state is, the design system decides how it *looks*.
class StockStatusBadge extends StatelessWidget {
  const StockStatusBadge({super.key, required this.status, this.dense = true});

  final StockStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final BwBadgeVariant variant = switch (status) {
      StockStatus.inStock => BwBadgeVariant.solid,
      StockStatus.lowStock => BwBadgeVariant.outline,
      StockStatus.outOfStock => BwBadgeVariant.subtle,
    };

    return BwBadge(
      label: status.label,
      variant: variant,
      icon: status.icon,
      dense: dense,
    );
  }
}

/// Filter chips for the order sections.
class StatusFilterBar extends StatelessWidget {
  const StatusFilterBar({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.allLabel,
    required this.allCount,
    this.counts = const <OrderStatus, int>{},
  });

  final OrderStatus? selected;
  final ValueChanged<OrderStatus?> onChanged;
  final String allLabel;
  final int allCount;
  final Map<OrderStatus, int> counts;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
        children: <Widget>[
          _FilterChip(
            label: '$allLabel ($allCount)',
            isSelected: selected == null,
            onTap: () => onChanged(null),
          ),
          for (final OrderStatus status in OrderStatus.values)
            if ((counts[status] ?? 0) > 0)
              _FilterChip(
                label: '${status.label} (${counts[status]})',
                isSelected: selected == status,
                onTap: () => onChanged(status),
              ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg = isSelected ? BwColors.onInverse : BwColors.text;

    return Padding(
      padding: const EdgeInsets.only(right: BwSpacing.sm),
      child: Material(
        color: isSelected ? BwColors.inverse : BwColors.surface,
        borderRadius: BorderRadius.circular(BwRadius.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(BwRadius.pill),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: BwSpacing.md, vertical: BwSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BwRadius.pill),
              border: Border.all(
                color: isSelected ? BwColors.inverse : BwColors.borderStrong,
                width: BwStroke.strong,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small labelled figure used across the admin sections.
class AdminStat extends StatelessWidget {
  const AdminStat({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BwSpacing.md),
      decoration: BoxDecoration(
        color: BwColors.surface,
        borderRadius: BorderRadius.circular(BwRadius.field),
        border: Border.all(color: BwColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 14, color: BwColors.textMuted),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: BwColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: BwSpacing.xs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: BwColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Unused-import guard removed.