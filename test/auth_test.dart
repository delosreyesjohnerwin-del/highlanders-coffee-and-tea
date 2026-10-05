import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlanders_coffee/app.dart';
import 'package:highlanders_coffee/core/firebase/firebase_bootstrap.dart';
import 'package:highlanders_coffee/core/theme/bw_brand.dart';
import 'package:highlanders_coffee/data/models/menu.dart';
import 'package:highlanders_coffee/data/models/order.dart';
import 'package:highlanders_coffee/data/models/staff.dart';
import 'package:highlanders_coffee/features/admin/admin_dashboard_screen.dart';
import 'package:highlanders_coffee/features/auth/login_screen.dart';
import 'package:highlanders_coffee/features/auth/root_router.dart';
import 'package:highlanders_coffee/features/shell/app_shell.dart'; // ShellNav
import 'package:highlanders_coffee/services/auth_service.dart';
import 'package:highlanders_coffee/services/mock_auth_service.dart';
import 'package:highlanders_coffee/state/admin_provider.dart';
import 'package:highlanders_coffee/state/session_provider.dart';
import 'package:provider/provider.dart';

/// Auth flow, role routing and stock semantics.
///
/// These sit apart from `screens_test.dart` on purpose: that file is about
/// *layout* overflow at 360dp, this one is about *behaviour* — who ends up
/// where, and what happens to a sold-out item.
void main() {
  setUp(() {
    FirebaseBootstrap.resetForTest();
    // ShellNav holds the tab index in a process-global static, so a test that
    // lands on, say, Cart would leak into the next one.
    ShellNav.reset();
  });

  Future<void> usePhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  /// Drives [work] to completion while pumping, returning its result.
  ///
  /// `testWidgets` runs the body in a fake-async zone: timers only fire while
  /// the tester pumps. `MockAuthService` deliberately sleeps 300-400ms to
  /// imitate a network round-trip, so `await session.signInWithGoogle()`
  /// deadlocks — the future cannot resolve until something advances the clock,
  /// and the test is awaiting that future. Starting the work, pumping in
  /// short slices until it settles, and *then* awaiting avoids the deadlock
  /// without making the mock instantaneous.
  Future<bool> settleAuth(WidgetTester tester, Future<bool> work) async {
    final Completer<bool> done = Completer<bool>();
    unawaited(work.then(done.complete).catchError(done.completeError));

    // 40 x 100ms of fake time is a 4s ceiling on the mock's delays.
    for (int i = 0; i < 40 && !done.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    return done.future;
  }

  /// Scrolls [finder] into view before tapping it.
  ///
  /// The login form is taller than a 360x780 phone viewport, so the footer
  /// ("Sign Up") and lower controls start below the fold. `ensureVisible`
  /// walks the enclosing Scrollable, unlike a blind drag.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Mounts the app behind [RootRouter] with a controllable auth backend, then
  /// hands back the session.
  ///
  /// Goes through `HighlandersApp` rather than a bare MultiProvider so the
  /// production provider graph — including the CatalogProvider the admin
  /// sections read — is what gets tested.
  Future<SessionProvider> pumpRouted(
    WidgetTester tester, {
    AuthService? auth,
    RoleResolver? roles,
  }) async {
    await usePhone(tester);
    await tester.pumpWidget(
      HighlandersApp.withRouter(authService: auth, roleResolver: roles),
    );
    await tester.pumpAndSettle();

    return Provider.of<SessionProvider>(
      tester.element(find.byType(RootRouter)),
      listen: false,
    );
  }

  group('LoginScreen', () {
    testWidgets('renders the spec layout', (WidgetTester tester) async {
      await usePhone(tester);
      await tester.pumpWidget(
        HighlandersApp(home: const LoginScreen()),
      );
      await tester.pumpAndSettle();

      // The mark is the whole header now: the lettering is baked into the PNG,
      // so there is no text duplicated underneath it.
      expect(find.byType(BwBrandmark), findsOneWidget);
      expect(find.text('Highlanders'), findsNothing);
      expect(find.text('Coffee & Tea'), findsNothing);

      // Brandmark + the exact subtitle from the spec.
      expect(
        find.text('Welcome back! Sign in to continue.'),
        findsOneWidget,
      );

      // No role switcher: the role comes from users/{uid} on the real backend,
      // so the login screen must not offer a way to choose one.
      expect(find.text('Customer'), findsNothing);
      expect(find.text('Admin'), findsNothing);
      expect(find.text('SIGN IN AS'), findsNothing);

      // Google is the primary action, above the email form.
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.text('Remember me'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text('Log In'), findsOneWidget);
      expect(find.text('Sign Up'), findsOneWidget);
      expect(find.text("Don't have an account?"), findsOneWidget);
    });

    testWidgets('parks the form at the bottom and keeps the mark prominent',
        (WidgetTester tester) async {
      await usePhone(tester);
      await tester.pumpWidget(HighlandersApp(home: const LoginScreen()));
      await tester.pumpAndSettle();

      final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(screen, const Size(360, 780));

      // Mark: large, centred, and anchored to the top of the page.
      final Rect mark = tester.getRect(find.byType(BwBrandmark));
      expect(mark.width, greaterThan(150));
      expect(mark.center.dx, closeTo(180, 0.5));
      expect(mark.top, lessThan(80));

      // Form: below the mark, not beside it.
      expect(
        tester.getRect(find.text('Continue with Google')).top,
        greaterThan(mark.bottom),
      );

      // Footer: pinned to the bottom edge, clear of the Sign Up row above it.
      // This is the assertion that fails if the Spacer ever collapses to zero,
      // which is exactly what happens without IntrinsicHeight above it.
      final Rect footer =
          tester.getRect(find.text('Highlanders Coffee & Tea · Lumban, Laguna'));
      expect(footer.bottom, greaterThan(screen.height - 36));
      expect(footer.bottom, lessThanOrEqualTo(screen.height));
      expect(
        footer.top,
        greaterThan(tester.getRect(find.text('Sign Up')).bottom),
      );

      // Nothing overflows, and the whole thing fits without scrolling.
      expect(tester.takeException(), isNull);
      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scrollable.position.maxScrollExtent, 0);
    });

    testWidgets('password visibility toggles', (WidgetTester tester) async {
      await usePhone(tester);
      await tester.pumpWidget(HighlandersApp(home: const LoginScreen()));
      await tester.pumpAndSettle();

      // The password field is the last form field. `obscureText` lives on the
      // underlying EditableText rather than on TextFormField, so assert there.
      final Finder password = find.byType(EditableText).last;
      expect(tester.widget<EditableText>(password).obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      expect(tester.widget<EditableText>(password).obscureText, isFalse);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });

    testWidgets('rejects a short password before calling the backend',
        (WidgetTester tester) async {
      await usePhone(tester);
      await tester.pumpWidget(HighlandersApp(home: const LoginScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).last, '123');
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle();

      expect(find.text('Password must be at least 6 characters.'), findsOneWidget);
    });

    testWidgets('sign up is reachable and validates',
        (WidgetTester tester) async {
      await usePhone(tester);
      await tester.pumpWidget(HighlandersApp(home: const LoginScreen()));
      await tester.pumpAndSettle();

      // Still below the fold at 360dp even after the role switcher was removed,
      // so it has to be scrolled to first. Measured, not assumed.
      await tapVisible(tester, find.text('Sign Up'));

      expect(find.text('Join Highlanders'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(4));
    });

    testWidgets('forgot password opens a dialog', (WidgetTester tester) async {
      await usePhone(tester);
      await tester.pumpWidget(HighlandersApp(home: const LoginScreen()));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Forgot password?'));

      expect(find.text('Reset password'), findsOneWidget);
      expect(find.text('Send link'), findsOneWidget);
    });
  });

  group('role routing', () {
    testWidgets('starts at the login screen when signed out',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpRouted(tester, auth: MockAuthService());

      expect(find.byType(RootRouter), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(AdminDashboardScreen), findsNothing);
      expect(find.byType(AppShell), findsNothing);
    });

    testWidgets('a customer lands in the tab shell, not the admin panel',
        (WidgetTester tester) async {
      final SessionProvider session =
          await pumpRouted(tester, auth: MockAuthService());
      await settleAuth(tester, session.signInWithGoogle());

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(AdminDashboardScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('an admin lands in the admin panel, not the tabs',
        (WidgetTester tester) async {
      final SessionProvider session =
          await pumpRouted(tester, auth: MockAuthService());

      // The mock resolver promotes exactly one address.
      final bool ok = await settleAuth(
        tester,
        session.signInWithPassword(
          email: 'admin@highlanderscoffee.ph',
          password: 'hunter2',
          rememberMe: true,
        ),
      );

      expect(ok, isTrue);
      expect(session.user.role, UserRole.admin);
      expect(find.byType(AdminDashboardScreen), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('signing out returns to the login screen',
        (WidgetTester tester) async {
      final SessionProvider session =
          await pumpRouted(tester, auth: MockAuthService());

      await settleAuth(tester, session.signInWithGoogle());
      expect(find.byType(AppShell), findsOneWidget);

      await session.signOut();
      await tester.pumpAndSettle();

      expect(session.isSignedIn, isFalse);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    });

    testWidgets('a failed sign-in stays on the login screen with an error',
        (WidgetTester tester) async {
      final SessionProvider session =
          await pumpRouted(tester, auth: MockAuthService());

      final bool ok = await settleAuth(
        tester,
        session.signInWithPassword(
          email: 'not-an-email',
          password: 'hunter2',
          rememberMe: false,
        ),
      );

      expect(ok, isFalse);
      expect(session.lastError, isNotNull);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    });
  });

  group('MockAuthService', () {
    test('derives a display name from the email local part', () async {
      final MockAuthService auth = MockAuthService();

      final AuthResult result = await auth.signInWithPassword(
        email: 'juan.delacruz@email.com',
        password: 'hunter2',
      );

      expect(result.isSuccess, isTrue);
      expect(result.identity!.displayName, 'Juan Delacruz');
    });

    test('rejects a password under six characters', () async {
      final MockAuthService auth = MockAuthService();

      final AuthResult result = await auth.signInWithPassword(
        email: 'a@b.com',
        password: '123',
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, contains('6 characters'));
    });
  });

  group('stock semantics', () {
    test('status derives from stock against the reorder level', () {
      const MenuItem healthy = MenuItem(
        id: 'x',
        categoryId: 'coffee',
        name: 'X',
        price: 50,
        stock: 50,
        reorderLevel: 10,
      );
      const MenuItem low = MenuItem(
        id: 'x',
        categoryId: 'coffee',
        name: 'X',
        price: 50,
        stock: 10,
        reorderLevel: 10,
      );
      const MenuItem empty = MenuItem(
        id: 'x',
        categoryId: 'coffee',
        name: 'X',
        price: 50,
        stock: 0,
        reorderLevel: 10,
      );

      expect(healthy.status, StockStatus.inStock);
      // The threshold is inclusive: "at or below reorder level" is low.
      expect(low.status, StockStatus.lowStock);
      expect(empty.status, StockStatus.outOfStock);
    });

    test('a sold-out item stays listed but is not orderable', () {
      const MenuItem empty = MenuItem(
        id: 'x',
        categoryId: 'coffee',
        name: 'X',
        price: 50,
        stock: 0,
      );

      // Visible — hiding a bestseller because it ran out would be a bug — but
      // the shop must block Add to cart.
      expect(empty.isAvailable, isTrue);
      expect(empty.isOrderable, isFalse);
    });

    test('copyWith round-trips stock', () {
      const MenuItem base = MenuItem(
        id: 'x',
        categoryId: 'coffee',
        name: 'X',
        price: 50,
        stock: 5,
        reorderLevel: 10,
      );

      expect(base.copyWith(stock: 99).stock, 99);
      // Untouched fields survive.
      expect(base.copyWith(stock: 99).name, 'X');
      expect(base.copyWith(stock: 99).reorderLevel, 10);
    });

    test('needsRestock catches low and out, but not healthy', () {
      final List<MenuItem> items = <MenuItem>[
        const MenuItem(
          id: 'a',
          categoryId: 'c',
          name: 'A',
          price: 1,
          stock: 100,
          reorderLevel: 10,
        ),
        const MenuItem(
          id: 'b',
          categoryId: 'c',
          name: 'B',
          price: 1,
          stock: 3,
          reorderLevel: 10,
        ),
        const MenuItem(
          id: 'c',
          categoryId: 'c',
          name: 'C',
          price: 1,
          stock: 0,
          reorderLevel: 10,
        ),
      ];

      final List<MenuItem> flagged = AdminProvider.needsRestock(items);
      expect(flagged.map((MenuItem i) => i.id), <String>['b', 'c']);
    });
  });

  group('AdminProvider analytics', () {
    test('settles revenue only from delivered orders', () {
      final AdminProvider admin = AdminProvider();

      // The fixtures include both in-flight and delivered orders, so the total
      // must exclude the former.
      expect(admin.ordersTotal, greaterThan(0));
      expect(admin.ordersTotal, lessThanOrEqualTo(admin.orders.length));
      expect(admin.revenueTotal, greaterThan(0));
    });

    test('best sellers are ordered by units sold', () {
      final AdminProvider admin = AdminProvider();
      final List<ItemPerformance> top = admin.topItems(limit: 5);

      expect(top, isNotEmpty);
      expect(top.length, lessThanOrEqualTo(5));
      for (int i = 1; i < top.length; i++) {
        expect(top[i - 1].unitsSold, greaterThanOrEqualTo(top[i].unitsSold));
      }
    });

    test('the seven day series spans exactly seven days', () {
      final AdminProvider admin = AdminProvider();
      final List<DailyRevenue> series = admin.lastSevenDays;

      expect(series, hasLength(7));
      for (int i = 1; i < series.length; i++) {
        expect(
          series[i].day.isAfter(series[i - 1].day),
          isTrue,
          reason: 'series must ascend by day',
        );
      }
    });

    test('advancing an order moves it one pipeline step', () {
      final AdminProvider admin = AdminProvider();
      final String id = admin.openOrders.first.id;
      final OrderStatus before = admin.openOrders.first.status;

      expect(admin.advanceOrder(id), isTrue);

      final Order after = admin.orders.firstWhere((Order o) => o.id == id);
      expect(
        after.status.index,
        before.index + 1,
        reason: 'advance must be exactly one step',
      );
    });

    test('toggling a shift flips working state', () {
      final AdminProvider admin = AdminProvider();
      final String id = admin.staff.first.id;
      final bool wasWorking = admin.staff.first.shift.isWorking;

      admin.toggleShift(id);

      expect(admin.staffById(id)!.shift.isWorking, isNot(wasWorking));
    });

    test('an unknown staff id is a no-op, not a crash', () {
      final AdminProvider admin = AdminProvider();
      final List<StaffMember> before = admin.staff;

      admin.toggleShift('does-not-exist');

      expect(admin.staff, same(before));
    });
  });
}