import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_brand.dart';
import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/widgets/bw_badge.dart';
import '../../core/widgets/bw_button.dart';
import '../../data/models/order.dart';
import '../../state/admin_provider.dart';
import '../../state/session_provider.dart';
import 'sections/admin_inventory_section.dart';
import 'sections/admin_orders_section.dart';
import 'sections/admin_overview_section.dart';
import 'sections/admin_sales_section.dart';
import 'sections/admin_settings_section.dart';
import 'sections/admin_staff_section.dart';

/// The admin panel: six sections behind a rail, a drawer, or neither.
enum AdminSection {
  overview('Overview', Icons.insights_outlined),
  inventory('Inventory', Icons.inventory_2_outlined),
  sales('Sales', Icons.receipt_long_outlined),
  orders('Orders', Icons.local_shipping_outlined),
  staff('Staff', Icons.badge_outlined),
  settings('Settings', Icons.settings_outlined);

  const AdminSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Admin panel entry point.
///
/// Deliberately a single scaffold owning its own navigation rather than six
/// pushed routes: an admin moving between the orders board and the stock list
/// should never build up a back stack.
///
/// Layout adapts at [wideBreakpoint]:
///  * at or above it, a persistent [NavigationRail] is shown;
///  * below it, a hamburger opens a [Drawer].
///
/// Sections live in an [IndexedStack], so switching preserves each one's
/// scroll position and filter state.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, this.initialSection = AdminSection.overview});

  final AdminSection initialSection;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  /// Below this width there is no room for a rail, so the drawer takes over.
  static const double wideBreakpoint = 720;

  /// Needed because this screen builds its own [Scaffold], so the hamburger
  /// cannot reach it with `Scaffold.of(context)` — the scaffold is a
  /// *descendant* of the calling context, and `of` only searches ancestors.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late AdminSection _section = widget.initialSection;

  void _select(AdminSection section) {
    setState(() => _section = section);
  }

  @override
  Widget build(BuildContext context) {
    final AdminProvider admin = context.watch<AdminProvider>();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= wideBreakpoint;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: BwColors.bg,
          drawer: wide ? null : _AdminDrawer(section: _section, onSelect: _select),
          body: SafeArea(
            child: Row(
              children: <Widget>[
                if (wide)
                  _AdminRail(
                    section: _section,
                    onSelect: _select,
                    openCount: admin.openOrders.length,
                    bottom: _SignOutButton(compact: true),
                  ),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      _AdminTopBar(
                        section: _section,
                        onMenu: wide ? null : _openDrawer,
                        // Compact icon on purpose: at phone widths this row also
                        // holds the title and the open-orders badge, and a
                        // labelled button overflows that budget. The drawer's
                        // full-width "Sign out" is the labelled path.
                        signOut: wide ? null : const _SignOutButton(compact: true),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: IndexedStack(
                          index: _section.index,
                          children: const <Widget>[
                            AdminOverviewSection(),
                            AdminInventorySection(),
                            AdminSalesSection(),
                            AdminOrdersSection(),
                            AdminStaffSection(),
                            AdminSettingsSection(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openDrawer() {
    final ScaffoldState? scaffold = _scaffoldKey.currentState;
    if (scaffold == null || scaffold.isDrawerOpen) return;
    scaffold.openDrawer();
  }
}

/// Sticky header: section title on the left, live order count on the right.
class _AdminTopBar extends StatelessWidget {
  const _AdminTopBar({
    required this.section,
    this.onMenu,
    this.signOut,
  });

  final AdminSection section;
  final VoidCallback? onMenu;
  final Widget? signOut;

  @override
  Widget build(BuildContext context) {
    final AdminProvider admin = context.watch<AdminProvider>();
    final int open = admin.openOrders.length;

    return Container(
      color: BwColors.bg,
      padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter, vertical: BwSpacing.sm),
      child: Row(
        children: <Widget>[
          if (onMenu != null)
            Builder(
              builder: (BuildContext context) => IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: onMenu,
                tooltip: 'Sections',
              ),
            ),
          // Absorbs the leftover width. Without a flex on the middle column the
          // three fixed-width pieces (menu, title, badge, sign out) overflow at
          // 360dp, and a fixed-width test font makes that reproducible.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  section.label,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: BwColors.text,
                  ),
                ),
                Text(
                  admin.settings.cafeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: BwColors.textMuted),
                ),
              ],
            ),
          ),
          if (open > 0)
            BwBadge(label: '$open open', variant: BwBadgeVariant.solid, dense: true),
          if (signOut != null) ...<Widget>[
            const SizedBox(width: BwSpacing.xs),
            signOut!,
          ],
        ],
      ),
    );
  }
}

/// Vertical section switcher for wide layouts.
class _AdminRail extends StatelessWidget {
  const _AdminRail({
    required this.section,
    required this.onSelect,
    required this.openCount,
    required this.bottom,
  });

  final AdminSection section;
  final ValueChanged<AdminSection> onSelect;
  final int openCount;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      decoration: const BoxDecoration(
        color: BwColors.surface,
        border: Border(right: BorderSide(color: BwColors.border)),
      ),
      child: Column(
        children: <Widget>[
          const _RailBrandmark(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: BwSpacing.sm),
              children: AdminSection.values.map((AdminSection s) {
                final bool active = s == section;

                return _RailTab(
                  section: s,
                  isActive: active,
                  badge: s == AdminSection.orders && openCount > 0 ? openCount : null,
                  onTap: () => onSelect(s),
                );
              }).toList(growable: false),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(BwSpacing.sm),
            child: bottom,
          ),
        ],
      ),
    );
  }
}

class _RailBrandmark extends StatelessWidget {
  const _RailBrandmark();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BwSpacing.lg),
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BwColors.inverse,
          borderRadius: BorderRadius.circular(BwRadius.chip),
        ),
        // Knocked out to white: the brand green on this black tile would land at
        // roughly 1.9:1 and be effectively invisible.
        child: const BwBrandmark(width: 28, inverted: true),
      ),
    );
  }
}

class _RailTab extends StatelessWidget {
  const _RailTab({
    required this.section,
    required this.isActive,
    required this.onTap,
    this.badge,
  });

  final AdminSection section;
  final bool isActive;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final Color fg = isActive ? BwColors.inverse : BwColors.textMuted;
    final int? count = badge;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BwSpacing.sm, vertical: 3),
      child: Material(
        color: isActive ? BwColors.inverse : BwColors.transparent,
        borderRadius: BorderRadius.circular(BwRadius.field),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(BwRadius.field),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: BwSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Icon(section.icon, size: 21, color: fg),
                    if (count != null)
                      Positioned(
                        right: -9,
                        top: -5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                          decoration: BoxDecoration(
                            color: isActive ? BwColors.onInverse : BwColors.inverse,
                            borderRadius: BorderRadius.circular(BwRadius.pill),
                            border: Border.all(
                              color: isActive ? BwColors.inverse : BwColors.surface,
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              count > 9 ? '9+' : '$count',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                color: isActive ? BwColors.inverse : BwColors.onInverse,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  section.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Slide-in navigation for narrow layouts.
class _AdminDrawer extends StatelessWidget {
  const _AdminDrawer({required this.section, required this.onSelect});

  final AdminSection section;
  final ValueChanged<AdminSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final SessionProvider session = context.watch<SessionProvider>();
    final AdminProvider admin = context.watch<AdminProvider>();
    final int open = admin.openOrders.length;

    return Drawer(
      backgroundColor: BwColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Solid black header, mirroring the customer profile screen.
            Container(
              color: BwColors.inverse,
              padding: const EdgeInsets.all(BwSpacing.lg),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: BwColors.onInverse,
                      borderRadius: BorderRadius.circular(BwRadius.chip),
                    ),
                    // This tile is white, so the brand green is used as-is and
                    // keeps its colour here.
                    child: const BwBrandmark(width: 30),
                  ),
                  const SizedBox(width: BwSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          session.user.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: BwColors.onInverse,
                          ),
                        ),
                        const Text(
                          'Administrator',
                          style: TextStyle(fontSize: 12, color: BwColors.onInverse),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: BwSpacing.sm),
                children: AdminSection.values.map((AdminSection s) {
                  final bool active = s == section;
                  final int count = s == AdminSection.orders ? open : 0;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BwSpacing.sm,
                      vertical: 2,
                    ),
                    child: Material(
                      color: active ? BwColors.inverse : BwColors.transparent,
                      borderRadius: BorderRadius.circular(BwRadius.field),
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          onSelect(s);
                        },
                        borderRadius: BorderRadius.circular(BwRadius.field),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: BwSpacing.md,
                            vertical: BwSpacing.md,
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                s.icon,
                                size: 19,
                                color: active ? BwColors.onInverse : BwColors.textMuted,
                              ),
                              const SizedBox(width: BwSpacing.md),
                              Expanded(
                                child: Text(
                                  s.label,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: active ? BwColors.onInverse : BwColors.text,
                                  ),
                                ),
                              ),
                              if (count > 0)
                                BwBadge(
                                  label: '$count',
                                  variant: active ? BwBadgeVariant.inverse : BwBadgeVariant.outline,
                                  dense: true,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(growable: false),
              ),
            ),

            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(BwSpacing.md),
              // In the drawer's Column a full-width button is fine and reads
              // as the panel's exit action.
              child: _SignOutButton(compact: false, expand: true),
            ),
          ],
        ),
      ),
    );
  }
}

/// Signs the admin out and returns to the login screen.
///
/// [RootRouter] owns that transition: clearing the session is what swaps the
/// panel back out, so this only has to clear state.
class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.compact, this.expand = false});

  final bool compact;

  /// Stretch to the parent's width. Safe in a Column (drawer), invalid in a
  /// Row (top bar), so it is opt-in rather than inherited from [BwButton].
  final bool expand;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        icon: const Icon(Icons.logout_rounded, size: 19),
        tooltip: 'Sign out',
        onPressed: () => context.read<SessionProvider>().signOut(),
      );
    }

    return BwButton(
      label: 'Sign out',
      icon: Icons.logout_rounded,
      variant: BwButtonVariant.outlined,
      height: 44,
      expand: expand,
      onPressed: () => context.read<SessionProvider>().signOut(),
    );
  }
}

/// Shared empty-state block, reused by every admin section.
class AdminEmptyState extends StatelessWidget {
  const AdminEmptyState({super.key, required this.message, this.icon = Icons.inbox_outlined});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(BwSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 34, color: BwColors.disabled),
            const SizedBox(height: BwSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.45, color: BwColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section header used above every admin list.
class AdminSectionHeader extends StatelessWidget {
  const AdminSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BwSpacing.gutter,
        BwSpacing.lg,
        BwSpacing.gutter,
        BwSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: BwColors.text,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(fontSize: 12.5, color: BwColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Full-width black FAB matching the design system.
///
/// Flutter's stock [FloatingActionButton] paints a coloured shadow, which the
/// monochrome brief rules out, so this is a hand-rolled equivalent.
class BwFab extends StatelessWidget {
  const BwFab({super.key, required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BwColors.inverse,
      borderRadius: BorderRadius.circular(BwRadius.pill),
      elevation: 0,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(BwRadius.pill),
        splashColor: const Color(0x22FFFFFF),
        highlightColor: const Color(0x33FFFFFF),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: BwSpacing.lg, vertical: BwSpacing.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: BwColors.onInverse),
              const SizedBox(width: BwSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: BwColors.onInverse,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Status label mapping shared by the order views.
extension OrderStatusBadgeX on OrderStatus {
  bool get isSettled => this == OrderStatus.delivered || this == OrderStatus.cancelled;
}