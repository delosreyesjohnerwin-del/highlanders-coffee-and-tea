import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlanders_coffee/app.dart';
import 'package:highlanders_coffee/core/firebase/firebase_bootstrap.dart';
import 'package:highlanders_coffee/features/admin/admin_dashboard_screen.dart';
import 'package:highlanders_coffee/features/admin/sections/admin_overview_section.dart';
import 'package:highlanders_coffee/features/checkout/checkout_screen.dart';
import 'package:highlanders_coffee/features/home/widgets/menu_item_card.dart';
import 'package:highlanders_coffee/features/menu/menu_item_detail_screen.dart';
import 'package:highlanders_coffee/features/order_tracking/order_success_screen.dart';
import 'package:highlanders_coffee/features/order_tracking/order_tracking_screen.dart';
import 'package:highlanders_coffee/features/shell/app_shell.dart';
import 'package:highlanders_coffee/features/shell/bw_bottom_nav.dart';

/// Renders every screen at a realistic phone size and fails on layout
/// overflow, which `flutter analyze` cannot catch.
void main() {
  /// A Pixel-ish portrait surface: 360 x 780 logical.
  Future<void> usePhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpApp(WidgetTester tester, {Widget? home}) async {
    // ShellNav holds static state that would otherwise leak between tests.
    ShellNav.reset();
    // FirebaseBootstrap is process-global too: a previous test that forced mock
    // mode would otherwise decide which auth backend this one gets.
    FirebaseBootstrap.resetForTest();
    await tester.pumpWidget(HighlandersApp(home: home));
    await tester.pumpAndSettle();
  }

  /// Bottom-nav labels are duplicated by screen headings, so always target
  /// the tab through the nav bar itself.
  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(of: find.byType(BwBottomNav), matching: find.text(label)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollToEnd(WidgetTester tester, Finder scrollable) async {
    await tester.drag(scrollable, const Offset(0, -3000));
    await tester.pumpAndSettle();
  }

  /// True when [target] sits entirely inside [scrollable]'s viewport.
  bool fullyVisible(WidgetTester tester, Finder target, Finder scrollable) {
    final Rect r = tester.getRect(target);
    final Rect v = tester.getRect(scrollable);
    return r.top >= v.top && r.bottom <= v.bottom;
  }

  /// Scrolls [target] fully into view of [scrollable].
  ///
  /// Deliberately not `scrollUntilVisible`: sliver children build lazily, so a
  /// not-yet-built target can never be matched by a finder. And merely existing
  /// is not enough — a target clipped at the viewport edge has its centre
  /// underneath the bottom navigation bar, so `tap()` would land on the nav.
  /// Whether [finder] resolves to anything at all.
  ///
  /// `tester.any` is not safe for `find.text(...).first`: `FirstFinder` throws
  /// a StateError on an empty match instead of reporting false, which would
  /// abort the scroll loop on the very first check.
  bool matchesAny(WidgetTester tester, Finder finder) {
    try {
      return tester.any(finder);
    } on StateError {
      return false;
    }
  }

  Future<void> revealByDragging(
    WidgetTester tester,
    Finder target,
    Finder scrollable, {
    int maxSteps = 24,
    double step = 220,
  }) async {
    // Phase 1 — drag until the lazy sliver has built the target.
    for (int i = 0; i < maxSteps && !matchesAny(tester, target); i++) {
      await tester.drag(scrollable, Offset(0, -step));
      await tester.pumpAndSettle();
    }

    if (!matchesAny(tester, target)) return;

    // Phase 2 — let the scroll position place it fully inside the viewport.
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();

    // ensureVisible targets the leading edge, which can still leave a tall
    // widget hanging past the bottom. Nudge once more if so.
    if (!fullyVisible(tester, target, scrollable)) {
      final Rect r = tester.getRect(target);
      final Rect v = tester.getRect(scrollable);
      if (r.bottom > v.bottom) {
        await tester.drag(scrollable, Offset(0, -(r.bottom - v.bottom + 8)));
        await tester.pumpAndSettle();
      }
    }
  }

  group('screens render without overflow', () {
    testWidgets('home', (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      expect(find.text('Lumban, Laguna'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Special Offers'), findsOneWidget);

      await scrollToEnd(tester, find.byType(CustomScrollView).first);
    });

    testWidgets('orders, active tab', (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      await tapTab(tester, 'Orders');

      expect(find.text('My Orders'), findsOneWidget);
      expect(find.text('Reorder'), findsWidgets);
    });

    testWidgets('orders, past tab', (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      await tapTab(tester, 'Orders');
      await tester.tap(find.text('past'));
      await tester.pumpAndSettle();

      expect(find.text('Delivered'), findsWidgets);
    });

    testWidgets('cart, empty state', (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      await tapTab(tester, 'Cart');

      expect(find.text('Your cart is empty'), findsOneWidget);
    });

    testWidgets('profile', (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      await tapTab(tester, 'Profile');

      expect(find.text('Marco Reyes'), findsOneWidget);
      expect(find.text('Gold Member'), findsOneWidget);
      expect(find.text('Privacy & Security'), findsOneWidget);

      await scrollToEnd(tester, find.byType(ListView).first);

      // The mock user is a customer, so the staff entry must NOT be shown.
      expect(find.text('Admin panel'), findsNothing);
    });

    testWidgets('menu item detail', (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      // The menu list sits below the hero, categories and offers.
      await revealByDragging(
        tester,
        find.text('Kopi Filipino'),
        find.byType(CustomScrollView),
      );

      await tester.tap(find.text('Kopi Filipino'));
      await tester.pumpAndSettle();

      expect(find.byType(MenuItemDetailScreen), findsOneWidget);
      expect(find.text('Choose a size'), findsOneWidget);
      expect(find.text('Regular'), findsOneWidget);

      await scrollToEnd(tester, find.byType(ListView).first);
    });
  });

  group('end-to-end order flow', () {
    testWidgets('add to cart, choose address, check out, place order', (
      WidgetTester tester,
    ) async {
      await usePhone(tester);
      await pumpApp(tester);

      await revealByDragging(
        tester,
        find.text('Kopi Filipino'),
        find.byType(CustomScrollView),
      );

      // Target the stepper inside one specific card rather than "the first
      // plus on screen", which depends on layout and build order.
      final Finder kopiPlus = find.descendant(
        of: find.ancestor(of: find.text('Kopi Filipino'), matching: find.byType(MenuItemCard)),
        matching: find.byIcon(Icons.add_rounded),
      );

      // Add once, then bump to two. The plus must not navigate to the detail.
      await tester.tap(kopiPlus);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemDetailScreen), findsNothing);

      await tester.tap(kopiPlus);
      await tester.pumpAndSettle();

      await tapTab(tester, 'Cart');
      expect(find.text('Your cart is empty'), findsNothing);
      expect(find.text('Subtotal'), findsOneWidget);

      // Checkout stays disabled until a delivery address is chosen.
      await tester.tap(find.text('Home').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Checkout'));
      await tester.pumpAndSettle();

      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(find.text('Payment method'), findsOneWidget);
      expect(find.text('GCash'), findsOneWidget);
      expect(find.text('Cash on delivery'), findsOneWidget);

      await tester.tap(find.text('Cash on delivery'));
      await tester.pumpAndSettle();

      await scrollToEnd(tester, find.byType(ListView).first);
      await tester.tap(find.textContaining('Place order'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.byType(OrderSuccessScreen), findsOneWidget);
      expect(find.text('Order confirmed'), findsOneWidget);

      await scrollToEnd(tester, find.byType(ListView).first);
    });
  });

  group('order tracking', () {
    testWidgets('opens from the orders list', (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      await tapTab(tester, 'Orders');

      // Target the card inside the list, not the tab label.
      await tester.tap(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('Highlanders Coffee & Tea'),
        ).first,
      );
      await tester.pumpAndSettle();

      expect(find.byType(OrderTrackingScreen), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);

      await scrollToEnd(tester, find.byType(ListView).first);
    });
  });

  group('admin panel', () {

    testWidgets('renders six sections behind a drawer on a phone',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester, home: const AdminDashboardScreen());

      // Overview is the landing section.
      expect(find.byType(AdminOverviewSection), findsOneWidget);
      expect(find.text('Total revenue'), findsOneWidget);

      // The rail is hidden below 720dp; the drawer carries the navigation.
      expect(find.byType(Drawer), findsNothing);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);

      // All six are declared, and all six are reachable.
      expect(AdminSection.values, hasLength(6));

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      for (final AdminSection s in AdminSection.values) {
        expect(
          find.descendant(of: find.byType(Drawer), matching: find.text(s.label)),
          findsOneWidget,
          reason: 'drawer is missing the ${s.label} entry',
        );
      }
    });

    testWidgets('shows a persistent rail on a wide surface',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpApp(tester, home: const AdminDashboardScreen());

      // Rail replaces the hamburger once there is room for it.
      expect(find.byIcon(Icons.menu_rounded), findsNothing);

      for (final AdminSection s in AdminSection.values) {
        expect(find.text(s.label), findsWidgets, reason: 'missing rail tab ${s.label}');
      }
    });

    testWidgets('overview reports revenue, orders and active users',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester, home: const AdminDashboardScreen());

      expect(find.text('Total revenue'), findsOneWidget);
      expect(find.text('Total orders'), findsOneWidget);
      expect(find.text('Active users'), findsOneWidget);
      expect(find.text('Avg order'), findsOneWidget);
      expect(find.text('Last 7 days'), findsOneWidget);
      expect(find.text('Best sellers'), findsOneWidget);

      await scrollToEnd(tester, find.byType(ListView).first);
    });

    testWidgets('inventory table lists stock and status per item',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester, home: const AdminDashboardScreen(
        initialSection: AdminSection.inventory,
      ));

      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('ITEM'), findsOneWidget);
      expect(find.text('STOCK'), findsOneWidget);
      expect(find.text('STATUS'), findsOneWidget);

      // Seeded fixtures deliberately include healthy, low and sold-out items so
      // all three status badges are exercised.
      expect(find.text('In Stock'), findsWidgets);
      expect(find.text('Low Stock'), findsWidgets);
      expect(find.text('Out of Stock'), findsWidgets);

      // The FAB opens the add form.
      expect(find.byType(BwFab), findsOneWidget);
      await tester.tap(find.byType(BwFab));
      await tester.pumpAndSettle();

      expect(find.text('Add item'), findsWidgets);
      expect(find.text('Item name'), findsOneWidget);
      expect(find.text('Reorder level'), findsOneWidget);
    });

    testWidgets('inventory row tap opens the edit form pre-filled',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester, home: const AdminDashboardScreen(
        initialSection: AdminSection.inventory,
      ));

      // Tap a specific row, not the table's centre: the table scrolls
      // horizontally, so its midpoint can sit past the viewport edge.
      final Finder firstRow = find.text('Kopi Filipino');
      await revealByDragging(tester, firstRow, find.byType(Scrollable).last);
      await tester.tap(firstRow);
      await tester.pumpAndSettle();

      expect(find.text('Edit item'), findsWidgets);
      // Pre-filled from the tapped row rather than blank.
      expect(
        tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Kopi Filipino'),
        ),
        isNotNull,
      );
    });

    testWidgets('orders board advances an order through the pipeline',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester, home: const AdminDashboardScreen(
        initialSection: AdminSection.orders,
      ));

      // The chip renders as "In flight (N)", so match on the prefix.
      expect(find.textContaining('In flight'), findsOneWidget);
      expect(find.text('Confirm order'), findsWidgets);

      // Order cards are tall and the board scrolls, so the button may start
      // below the fold — a tap there would land on whatever is in its place.
      final Finder advance = find.text('Confirm order').first;
      await revealByDragging(tester, advance, find.byType(ListView).last);
      await tester.tap(advance);
      await tester.pumpAndSettle();

      // The board now offers the *next* step for that same order.
      expect(find.text('Start preparing'), findsWidgets);
    });

    testWidgets('orders board cancels an order', (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester, home: const AdminDashboardScreen(
        initialSection: AdminSection.orders,
      ));

      // The board seeds several in-flight orders, so cancelling one must drop
      // the count by exactly one rather than emptying it.
      final int before = tester.widgetList<Text>(find.text('Cancel')).length;
      expect(before, greaterThan(0));

      final Finder cancel = find.text('Cancel').first;
      await revealByDragging(tester, cancel, find.byType(ListView).last);
      await tester.tap(cancel);
      await tester.pumpAndSettle();

      expect(tester.widgetList<Text>(find.text('Cancel')).length, before - 1);
    });

    testWidgets('sales section shows a payment split and transaction log',
        (WidgetTester tester) async {
      await usePhone(tester);
      // The fixtures only cover the six days before today, so step back one day
      // to land on a day that actually has settled orders.
      await pumpApp(tester, home: const AdminDashboardScreen(
        initialSection: AdminSection.sales,
      ));

      expect(find.text('Payment split'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
      expect(find.text('Gross'), findsOneWidget);
      expect(find.text('Avg ticket'), findsOneWidget);

      await scrollToEnd(tester, find.byType(ListView).first);
    });

    testWidgets('staff section lists roles and toggles a shift',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester, home: const AdminDashboardScreen(
        initialSection: AdminSection.staff,
      ));

      expect(find.text('On shift now'), findsOneWidget);
      expect(find.text('Aiko Ramos'), findsOneWidget);

      // Filter chips carry a count, e.g. "Owner (1)", and scroll horizontally.
      expect(find.textContaining('All ('), findsOneWidget);
      expect(find.textContaining('Owner ('), findsOneWidget);

      // The fixtures seed exactly one off-shift member, and as the last card in
      // a lazily built list it does not exist until scrolled into view.
      final Finder startShift = find.text('Start shift');

      await revealByDragging(tester, startShift, find.byType(ListView).last);
      expect(startShift, findsOneWidget, reason: 'one member should be off shift');

      await tester.tap(startShift);
      await tester.pumpAndSettle();

      // That button became "End shift": every member now works.
      expect(find.text('Start shift'), findsNothing);
      expect(find.text('End shift'), findsWidgets);
    });

    testWidgets('settings section edits store config and reports the backend',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester, home: const AdminDashboardScreen(
        initialSection: AdminSection.settings,
      ));

      expect(find.text('Shop is open'), findsOneWidget);
      expect(find.text('Delivery'), findsOneWidget);
      expect(find.text('Firebase connected'), findsNothing);

      // The backend card sits at the foot of a long settings list.
      final Finder backend = find.text('Session & backend');
      await revealByDragging(tester, backend, find.byType(ListView).first);
      expect(backend, findsOneWidget);

      await scrollToEnd(tester, find.byType(ListView).first);
    });

    testWidgets('no admin section overflows at 360dp', (WidgetTester tester) async {
      await usePhone(tester);

      for (final AdminSection section in AdminSection.values) {
        await pumpApp(
          tester,
          home: AdminDashboardScreen(initialSection: section),
        );
        // Any RenderFlex overflow fails the test automatically; the extra drag
        // just exercises the tail of each list where overflow usually hides.
        await scrollToEnd(tester, find.byType(Scrollable).first);
      }
    });
  });
}