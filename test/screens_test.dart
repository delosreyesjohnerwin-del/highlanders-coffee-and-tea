import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlanders_coffee/app.dart';
import 'package:highlanders_coffee/core/firebase/firebase_bootstrap.dart';
import 'package:highlanders_coffee/data/mock/mock_data.dart';
import 'package:highlanders_coffee/data/models/menu.dart';
import 'package:highlanders_coffee/features/admin/admin_dashboard_screen.dart';
import 'package:highlanders_coffee/features/admin/sections/admin_overview_section.dart';
import 'package:highlanders_coffee/features/checkout/checkout_screen.dart';
import 'package:highlanders_coffee/features/home/widgets/menu_item_card.dart';
import 'package:highlanders_coffee/features/home/widgets/promo_carousel.dart';
import 'package:highlanders_coffee/features/home/widgets/promo_widgets.dart';
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
      expect(find.text('Best Offer'), findsOneWidget);

      // The old secondary promo row is gone, absorbed into the carousel.
      expect(find.text('Special Offers'), findsNothing);
      expect(find.byType(OfferTiles), findsNothing);

      await scrollToEnd(tester, find.byType(CustomScrollView).first);
    });

    testWidgets('best offer carousel rotates and wraps', (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      final PromoCarousel carousel = tester.widget<PromoCarousel>(
        find.byType(PromoCarousel),
      );
      // Three promos: the NEW HERE hero plus the two former offer tiles.
      expect(carousel.promos.length, 3);
      expect(carousel.interval, const Duration(seconds: 5));

      // Asserted on the controller's page rather than on visible text: PageView
      // keeps the adjacent slide in the tree, so both titles are findable at any
      // moment and a findsOneWidget check would pass or fail for the wrong
      // reason.
      final PageController controller =
          tester.widget<PageView>(find.byType(PageView)).controller!;

      expect(controller.page, moreOrLessEquals(0));

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(controller.page, moreOrLessEquals(1));

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(controller.page, moreOrLessEquals(2));

      // Wrap: one more tick returns to the first slide rather than throwing.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(controller.page, moreOrLessEquals(0));

      expect(tester.takeException(), isNull);
    });

    testWidgets('search sits below the categories and above the list',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      final double categories = tester.getRect(find.text('Categories')).top;
      final double search = tester.getRect(find.byType(TextField).first).top;

      // Search moved down from under the location header to sit directly above
      // the product list, below the category pills.
      expect(search, greaterThan(categories));

      await tester.enterText(find.byType(TextField).first, 'daing');
      await tester.pumpAndSettle();

      // Searching hides the carousel block, which unmounts it and cancels the
      // timer — no animation against a disposed controller.
      expect(find.byType(PromoCarousel), findsNothing);
      expect(find.text('Search results'), findsOneWidget);
      expect(find.text('Daing na Bangus'), findsOneWidget);
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
        find.text('Hawaiian'),
        find.byType(CustomScrollView),
      );

      await tester.tap(find.text('Hawaiian'));
      await tester.pumpAndSettle();

      expect(find.byType(MenuItemDetailScreen), findsOneWidget);
      // The invented "Regular / Large +₱15" selector was removed when the real
      // menu (one price per item) went in — its UI must not come back.
      expect(find.text('Choose a size'), findsNothing);
      expect(find.text('Regular'), findsNothing);
      // The single real price is shown (header and the sticky add-bar total).
      expect(find.textContaining('₱349'), findsWidgets);

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
        find.text('Hawaiian'),
        find.byType(CustomScrollView),
      );

      // Target the stepper inside one specific card rather than "the first
      // plus on screen", which depends on layout and build order.
      final Finder kopiPlus = find.descendant(
        of: find.ancestor(of: find.text('Hawaiian'), matching: find.byType(MenuItemCard)),
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

    testWidgets('renders every section behind a drawer on a phone',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester, home: const AdminDashboardScreen());

      // Overview is the landing section.
      expect(find.byType(AdminOverviewSection), findsOneWidget);
      expect(find.text('Total revenue'), findsOneWidget);

      // The rail is hidden below 720dp; the drawer carries the navigation.
      expect(find.byType(Drawer), findsNothing);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);

      // Asserted against AdminSection.values rather than a fixed count so adding
      // a section cannot silently leave it out of the drawer: the loop below is
      // what would fail. A hard-coded 6 only proves the enum did not change.
      expect(AdminSection.values, isNotEmpty);

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

      // The real menu ships fully stocked (50 of everything): the database the
      // menu came from tracks no stock levels, so every status shows "In Stock".
      // The low/out-of-stock badge derivations stay covered by the model-level
      // tests in auth_test.dart (StockStatus), which seed their own fixtures.
      expect(find.text('In Stock'), findsWidgets);

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
      final Finder firstRow = find.text('Hawaiian');
      await revealByDragging(tester, firstRow, find.byType(Scrollable).last);
      await tester.tap(firstRow);
      await tester.pumpAndSettle();

      expect(find.text('Edit item'), findsWidgets);
      // Pre-filled from the tapped row rather than blank.
      expect(
        tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Hawaiian'),
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

    testWidgets('promos section lists promotions and pauses one',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester, home: const AdminDashboardScreen(
        initialSection: AdminSection.promos,
      ));

      expect(find.text('In the carousel'), findsOneWidget);
      expect(find.text('Not running'), findsOneWidget);

      // Every seeded promo is live, so the paused count is zero and no card
      // carries the Paused badge yet.
      expect(find.text('Paused (0)'), findsOneWidget);
      expect(find.text('Paused'), findsNothing);

      final Finder pause = find.byTooltip('Pause ${MockData.promos.first.title}').first;
      await revealByDragging(tester, pause, find.byType(ListView).last);
      await tester.tap(pause);
      await tester.pumpAndSettle();

      // The card is still listed — pausing is not deleting — but it is now
      // counted as paused and badged accordingly.
      expect(find.text('Paused (1)'), findsOneWidget);
      expect(
        find.text(MockData.promos.first.title),
        findsOneWidget,
        reason: 'a paused promo must stay listed so it can be brought back',
      );
    });

    testWidgets('promo edit sheet is pre-filled and saves',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester, home: const AdminDashboardScreen(
        initialSection: AdminSection.promos,
      ));

      final Promo original = MockData.promos.first;
      final Finder edit = find.byTooltip('Edit ${original.title}').first;
      await revealByDragging(tester, edit, find.byType(ListView).last);
      await tester.tap(edit);
      await tester.pumpAndSettle();

      // Every field arrives populated, because re-typing a promo to change one
      // word is how an owner loses the other ones.
      expect(find.text('Edit promotion'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, original.title), findsOneWidget);

      // The code identifies the Firestore document, so it is locked on edit.
      // Found by label rather than by value: the code also appears on the card
      // behind the sheet, so asserting on the text would match two widgets and
      // pass for the wrong one.
      expect(
        tester.widget<TextField>(
          find.descendant(
            of: find.byWidgetPredicate((Widget w) =>
                w is TextFormField && w.controller?.text == original.code),
            matching: find.byType(TextField),
          ),
        ).enabled,
        isFalse,
        reason: 'the code is the Firestore document id and must not be editable',
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, original.title),
        'Edited headline',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('Edited headline'), findsOneWidget);
      expect(find.text(original.title), findsNothing);
    });

    testWidgets('a new promo can be created and lands in the carousel',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester, home: const AdminDashboardScreen(
        initialSection: AdminSection.promos,
      ));

      final int before = MockData.promos.length;

      await tester.tap(find.byType(BwFab));
      await tester.pumpAndSettle();

      expect(find.text('Add promotion'), findsWidgets);
      // Nothing pre-filled from another promo — three of the six fields start
      // empty on a new promo and the rest must not carry the last one's text.
      expect(find.widgetWithText(TextFormField, MockData.promos.first.title), findsNothing);

      // The code is auto-suggested rather than left blank: a blank code collides
      // with every other blank promo the moment it is saved.
      final Finder code = find.byWidgetPredicate(
        (Widget w) => w is TextFormField && w.controller?.text.startsWith('PROMO') == true,
      );
      expect(code, findsOneWidget);
      expect(tester.widget<TextField>(find.descendant(of: code, matching: find.byType(TextField))).enabled, isTrue,
          reason: 'a new promo needs a typeable code; only an existing one locks it');

      await tester.enterText(code, 'TAPOS25');
      await tester.enterText(find.widgetWithText(TextFormField, 'Headline'), 'Tapos Anniversary');
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Sub-copy'), 'Free upgrade on any brewed drink');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Add promotion'));
      await tester.pumpAndSettle();

      // In the admin list, and counted. Not asserted on the customer side, which
      // is a different provider tree.
      expect(find.text('Tapos Anniversary'), findsOneWidget);
      expect(find.text('TAPOS25'), findsOneWidget);
      expect(find.text('Live (${before + 1})'), findsOneWidget);
      expect(find.text('All (${before + 1})'), findsOneWidget);
    });

    testWidgets('a promo code already in use is refused',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester, home: const AdminDashboardScreen(
        initialSection: AdminSection.promos,
      ));

      final String taken = MockData.promos.first.code;
      final int before = MockData.promos.length;

      await tester.tap(find.byType(BwFab));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byWidgetPredicate((Widget w) => w is TextFormField && w.controller?.text.startsWith('PROMO') == true),
        taken,
      );
      await tester.pumpAndSettle();

      // Saving over a live code would replace that promotion's headline and offer
      // with whatever was just typed, under the same document id, with no warning
      // and no way back. This is the check that stops it.
      expect(find.text('"$taken" is already in use.'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Headline'),
        'Impostor',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add promotion'));
      await tester.pumpAndSettle();

      // The sheet refused to close, so nothing was written. Asserted on the counts
      // rather than on the typed text, which is still in the open field and would
      // pass for the wrong reason.
      expect(find.text('Add promotion'), findsWidgets, reason: 'the sheet stayed open');
      expect(find.text('Live ($before)'), findsOneWidget, reason: 'no promo was added');
      expect(find.text('All ($before)'), findsOneWidget);
    });

    testWidgets('promo delete asks first, then removes the card',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester, home: const AdminDashboardScreen(
        initialSection: AdminSection.promos,
      ));

      final Promo target = MockData.promos.first;
      final Finder remove = find.byTooltip('Remove ${target.title}').first;
      await revealByDragging(tester, remove, find.byType(ListView).last);
      await tester.tap(remove);
      await tester.pumpAndSettle();

      // Deleting an offer a customer can currently see is worth one tap of
      // friction, and the dialog says pause instead for the temporary case.
      expect(find.text('Remove promotion'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text(target.title), findsNothing);
      expect(find.text(target.title), findsNothing);
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

    testWidgets('settings section edits café coordinates', (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester, home: const AdminDashboardScreen(
        initialSection: AdminSection.settings,
      ));

      // The café-location fields live in the Delivery card.
      await revealByDragging(tester, find.text('Café latitude'), find.byType(ListView).first);
      expect(find.text('Café longitude'), findsOneWidget);
      // The bundled placeholder is pre-filled.
      expect(find.text('14.2919'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey<String>('admin-cafe-lat')), '14.3000');
      await tester.pumpAndSettle();

      // The origin hint echoes the stored value with fixed precision.
      expect(find.textContaining('Coordinates (14.3000'), findsOneWidget);
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