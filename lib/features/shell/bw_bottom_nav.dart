import 'package:flutter/material.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';

/// Persistent 4-tab bottom navigation: Home, Orders, Cart, Profile.
///
/// The active tab is marked with a solid black icon plus a short black
/// indicator bar underneath; inactive tabs are muted grey.
class BwBottomNav extends StatelessWidget {
  const BwBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.cartCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Shows a count bubble on the cart tab.
  final int cartCount;

  @override
  Widget build(BuildContext context) {
    const List<({IconData icon, IconData activeIcon, String label})> tabs =
        <({IconData activeIcon, IconData icon, String label})>[
      (icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
      (icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long_rounded, label: 'Orders'),
      (icon: Icons.shopping_bag_outlined, activeIcon: Icons.shopping_bag_rounded, label: 'Cart'),
      (icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: 'Profile'),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: BwColors.surface,
        border: Border(top: BorderSide(color: BwColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List<Widget>.generate(tabs.length, (int i) {
              final tab = tabs[i];
              final bool active = i == currentIndex;

              return Expanded(
                child: _NavTab(
                  icon: active ? tab.activeIcon : tab.icon,
                  label: tab.label,
                  isActive: active,
                  badgeCount: i == 2 ? cartCount : 0,
                  onTap: () => onTap(i),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final Color color = isActive ? BwColors.inverse : BwColors.textMuted;

    return Material(
      color: BwColors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: const Color(0x0A000000),
        highlightColor: BwColors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              height: 26,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Icon(icon, size: 23, color: color),
                  if (badgeCount > 0)
                    Positioned(
                      right: -9,
                      top: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                        constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                        decoration: BoxDecoration(
                          color: BwColors.inverse,
                          borderRadius: BorderRadius.circular(BwRadius.pill),
                          border: Border.all(color: BwColors.bg, width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            badgeCount > 9 ? '9+' : '$badgeCount',
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: BwColors.onInverse,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              height: 3,
              width: isActive ? 18 : 0,
              decoration: BoxDecoration(
                color: BwColors.inverse,
                borderRadius: BorderRadius.circular(BwRadius.pill),
              ),
            ),
          ],
        ),
      ),
    );
  }
}