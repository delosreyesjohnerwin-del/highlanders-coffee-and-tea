import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/cart_provider.dart';
import '../cart/cart_screen.dart';
import '../home/home_screen.dart';
import '../orders/orders_screen.dart';
import '../profile/profile_screen.dart';
import 'bw_bottom_nav.dart';

/// Global tab index, so any descendant can jump tabs.
///
/// A [ValueNotifier] rather than a static field on the shell state: a static
/// method cannot reach the shell's `_index`, and this keeps the state private.
class ShellNav {
  const ShellNav._();

  static final ValueNotifier<int> index = ValueNotifier<int>(0);

  /// Switch to a tab. Values outside 0–3 are ignored.
  static void go(int i) {
    if (i < 0 || i > 3) return;
    index.value = i;
  }

  static void home() => go(0);
  static void orders() => go(1);
  static void cart() => go(2);
  static void profile() => go(3);

  /// Returns to the first tab. The notifier is process-global static state, so
  /// tests must reset it between cases or they inherit the previous tab.
  static void reset() => index.value = 0;
}

/// Root scaffold holding the four persistent tabs.
///
/// An [IndexedStack] keeps each tab's scroll position and state alive while
/// switching.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static const List<Widget> _screens = <Widget>[
    HomeScreen(),
    OrdersScreen(),
    CartScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final int cartCount = context.select<CartProvider, int>((CartProvider c) => c.itemCount);

    return ValueListenableBuilder<int>(
      valueListenable: ShellNav.index,
      builder: (BuildContext context, int index, _) {
        return Scaffold(
          body: IndexedStack(index: index, children: _screens),
          bottomNavigationBar: BwBottomNav(
            currentIndex: index,
            onTap: ShellNav.go,
            cartCount: cartCount,
          ),
        );
      },
    );
  }
}