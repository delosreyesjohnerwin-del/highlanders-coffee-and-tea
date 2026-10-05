import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/widgets/bw_avatar.dart';
import '../../core/widgets/bw_button.dart';
import '../../core/widgets/bw_menu_row.dart';
import '../../core/widgets/bw_stat.dart';
import '../../data/models/order.dart';
import '../../state/session_provider.dart';
import '../admin/admin_dashboard_screen.dart';

/// Profile: solid black header card with avatar, name, email and a
/// "Gold Member" tag, a floating white stats card, then the menu list.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppUser user = context.watch<SessionProvider>().user;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: BwSpacing.xxl),
          children: <Widget>[
            _ProfileHeader(user: user),

            // Floating white card that overlaps the black header.
            Transform.translate(
              offset: const Offset(0, -18),
              child: BwStatsCard(
                stats: <({String label, String value})>[
                  (value: '${user.orderCount}', label: 'Orders'),
                  (value: '${user.reviewCount}', label: 'Reviews'),
                  (value: _rewards(user.rewards), label: 'Rewards'),
                ],
              ),
            ),

            Transform.translate(
              offset: const Offset(0, -6),
              child: Column(
                children: <Widget>[
                  BwMenuGroup(
                    children: <Widget>[
                      BwMenuRow(
                        icon: Icons.place_outlined,
                        label: 'Saved Addresses',
                        onTap: () => _notReady(context, 'Saved Addresses'),
                      ),
                      BwMenuRow(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Payment Methods',
                        onTap: () => _notReady(context, 'Payment Methods'),
                      ),
                      BwMenuRow(
                        icon: Icons.card_giftcard_outlined,
                        label: 'Promo & Rewards',
                        trailingText: _rewards(user.rewards),
                        onTap: () => _notReady(context, 'Promo & Rewards'),
                      ),
                      BwMenuRow(
                        icon: Icons.favorite_border_rounded,
                        label: 'Favorites',
                        onTap: () => _notReady(context, 'Favorites'),
                      ),
                    ],
                  ),
                  const SizedBox(height: BwSpacing.md),
                  BwMenuGroup(
                    children: <Widget>[
                      BwMenuRow(
                        icon: Icons.notifications_none_rounded,
                        label: 'Notifications',
                        onTap: () => _notReady(context, 'Notifications'),
                      ),
                      BwMenuRow(
                        icon: Icons.star_outline_rounded,
                        label: 'Rate the App',
                        onTap: () => _notReady(context, 'Rate the App'),
                      ),
                      BwMenuRow(
                        icon: Icons.help_outline_rounded,
                        label: 'Help & Support',
                        onTap: () => _notReady(context, 'Help & Support'),
                      ),
                      BwMenuRow(
                        icon: Icons.lock_outline_rounded,
                        label: 'Privacy & Security',
                        onTap: () => _notReady(context, 'Privacy & Security'),
                      ),
                    ],
                  ),
                  const SizedBox(height: BwSpacing.xl),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
                    child: BwButton(
                      label: 'Sign out',
                      icon: Icons.logout_rounded,
                      variant: BwButtonVariant.outlined,
                      onPressed: () => context.read<SessionProvider>().signOut(),
                    ),
                  ),
                  if (user.role == UserRole.admin) ...<Widget>[
                    const SizedBox(height: BwSpacing.md),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: BwSpacing.gutter),
                      child: BwButton(
                        label: 'Admin panel',
                        icon: Icons.admin_panel_settings_outlined,
                        // No PIN gate. The session's role *is* the gate, so a
                        // second factor here would only be theatre — anyone who
                        // reached this button is already an admin.
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const AdminDashboardScreen()),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: BwSpacing.xl),
                  const Center(
                    child: Text(
                      'Highlanders Coffee & Tea · v1.0.0',
                      style: TextStyle(fontSize: 12, color: BwColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _rewards(num value) => value == 0 ? '—' : '₱${value.toStringAsFixed(0)}';

  static void _notReady(BuildContext context, String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label — coming soon')));
  }
}

/// Solid black top header with avatar, name, email and member tag.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(BwSpacing.xl, BwSpacing.xl, BwSpacing.xl, BwSpacing.xxl + 18),
      decoration: const BoxDecoration(
        color: BwColors.inverse,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(BwRadius.card)),
      ),
      child: Row(
        children: <Widget>[
          BwAvatar(
            imageUrl: user.avatarUrl,
            initials: BwAvatar.initialsOf(user.fullName),
            size: 62,
            inverted: true,
          ),
          const SizedBox(width: BwSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  user.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: BwColors.onInverse,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: BwColors.onInverse.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: BwSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(BwRadius.chip),
                    border: Border.all(color: BwColors.onInverse.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.workspace_premium_outlined, size: 12, color: BwColors.onInverse),
                      const SizedBox(width: 4),
                      Text(
                        user.memberTier,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: BwColors.onInverse,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}