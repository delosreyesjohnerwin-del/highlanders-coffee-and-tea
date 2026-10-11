import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:highlanders_coffee/data/firestore/memory_shop_repository.dart';
import 'package:highlanders_coffee/data/firestore/shop_repository.dart';
import 'package:highlanders_coffee/features/admin/admin_dashboard_screen.dart';
import 'package:highlanders_coffee/features/order_tracking/order_tracking_screen.dart';
import 'package:highlanders_coffee/services/mock_auth_service.dart';
import 'package:highlanders_coffee/services/notification_service.dart';
import 'package:highlanders_coffee/state/admin_provider.dart';
import 'package:highlanders_coffee/state/cart_provider.dart';
import 'package:highlanders_coffee/state/catalog_provider.dart';
import 'package:highlanders_coffee/state/session_provider.dart';

/// Test double for the platform slice of FCM, driven by stream controllers so
/// tests can emit tokens, messages and taps on demand.
class _FakeMessagingBackend implements MessagingBackend {
  final StreamController<String> _refresh = StreamController<String>.broadcast();
  final StreamController<RemoteMessage> _messages = StreamController<RemoteMessage>.broadcast();
  final StreamController<RemoteMessage> _opened = StreamController<RemoteMessage>.broadcast();

  bool available = true;
  String? token = 'fcm-token-test';
  RemoteMessage? initial;
  int permissionRequests = 0;

  @override
  bool get isAvailable => available;

  @override
  Future<void> requestPermission() async {
    permissionRequests += 1;
  }

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => _refresh.stream;

  @override
  Stream<RemoteMessage> get onMessage => _messages.stream;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => _opened.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async => initial;

  /// Re-emits [messages] to [onMessage] synchronously for the current test.
  void emitForeground(RemoteMessage message) => _messages.add(message);

  void dispose() {
    _refresh.close();
    _messages.close();
    _opened.close();
  }
}

void main() {
  MemoryShopRepository newRepository() => MemoryShopRepository();

  NotificationService newService({
    required ShopRepository repository,
    required SessionProvider session,
    required GlobalKey<NavigatorState> navigatorKey,
    required _FakeMessagingBackend backend,
  }) =>
      NotificationService(
        repository: repository,
        session: session,
        navigatorKey: navigatorKey,
        backend: backend,
      );

  group('device token registration', () {
    test('registers the token when the user signs in', () async {
      final MemoryShopRepository repo = newRepository();
      final SessionProvider session = SessionProvider(
        authService: MockAuthService(),
        roleResolver: const MockRoleResolver(),
        repository: repo,
      );
      final _FakeMessagingBackend backend = _FakeMessagingBackend();
      final NotificationService service = newService(
        repository: repo,
        session: session,
        navigatorKey: GlobalKey<NavigatorState>(),
        backend: backend,
      );
      addTearDown(service.dispose);
      addTearDown(backend.dispose);

      await service.init();
      await session.signInWithPassword(
        email: 'ana.dizon@email.com',
        password: 'secret1',
        rememberMe: true,
      );
      await pumpEventQueue();

      expect(repo.registeredTokens('demo-ana.dizon@email.com'), contains('fcm-token-test'));
    });

    test('unregisters the token on sign-out', () async {
      final MemoryShopRepository repo = newRepository();
      final SessionProvider session = SessionProvider(
        authService: MockAuthService(),
        roleResolver: const MockRoleResolver(),
        repository: repo,
      );
      final _FakeMessagingBackend backend = _FakeMessagingBackend();
      final NotificationService service = newService(
        repository: repo,
        session: session,
        navigatorKey: GlobalKey<NavigatorState>(),
        backend: backend,
      );
      addTearDown(service.dispose);
      addTearDown(backend.dispose);

      await service.init();
      await session.signInWithPassword(
        email: 'ana.dizon@email.com',
        password: 'secret1',
        rememberMe: true,
      );
      await pumpEventQueue();
      expect(repo.registeredTokens('demo-ana.dizon@email.com'), isNotEmpty);

      await session.signOut();
      await pumpEventQueue();

      expect(repo.registeredTokens('demo-ana.dizon@email.com'), isEmpty);
    });

    test('re-registers the same device when the OS rotates the token', () async {
      final MemoryShopRepository repo = newRepository();
      final SessionProvider session = SessionProvider(
        authService: MockAuthService(),
        roleResolver: const MockRoleResolver(),
        repository: repo,
      );
      final _FakeMessagingBackend backend = _FakeMessagingBackend();
      final NotificationService service = newService(
        repository: repo,
        session: session,
        navigatorKey: GlobalKey<NavigatorState>(),
        backend: backend,
      );
      addTearDown(service.dispose);
      addTearDown(backend.dispose);

      await service.init();
      await session.signInWithPassword(
        email: 'ana.dizon@email.com',
        password: 'secret1',
        rememberMe: true,
      );
      await pumpEventQueue();

      backend.token = 'fcm-token-v2';
      backend._refresh.add('fcm-token-v2');
      await pumpEventQueue();

      expect(repo.registeredTokens('demo-ana.dizon@email.com'), contains('fcm-token-v2'));
      expect(repo.registeredTokens('demo-ana.dizon@email.com'), isNot(contains('fcm-token-test')));
    });

    test('does nothing when the messaging backend is unavailable', () async {
      final MemoryShopRepository repo = newRepository();
      final SessionProvider session = SessionProvider(
        authService: MockAuthService(),
        roleResolver: const MockRoleResolver(),
        repository: repo,
      );
      final _FakeMessagingBackend backend = _FakeMessagingBackend()..available = false;
      final NotificationService service = newService(
        repository: repo,
        session: session,
        navigatorKey: GlobalKey<NavigatorState>(),
        backend: backend,
      );
      addTearDown(service.dispose);
      addTearDown(backend.dispose);

      await service.init();
      await session.signInWithPassword(
        email: 'ana.dizon@email.com',
        password: 'secret1',
        rememberMe: true,
      );
      await pumpEventQueue();

      expect(backend.permissionRequests, 0);
      expect(repo.registeredTokens('demo-ana.dizon@email.com'), isEmpty);
    });
  });

  group('notification routing', () {
    /// Mirrors the provider graph in `app.dart` (minus the notification
    /// provider, which the test constructs separately) so a pushed screen gets
    /// everything it reads from above.
    Future<void> pumpHarness(
      WidgetTester tester, {
      required ShopRepository repository,
      required SessionProvider session,
      required GlobalKey<NavigatorState> navigatorKey,
    }) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogProvider>(
              create: (_) => CatalogProvider(repository: repository)..bind(),
            ),
            ChangeNotifierProvider<SessionProvider>.value(value: session),
            ChangeNotifierProvider<AdminProvider>(
              create: (_) => AdminProvider(repository: repository),
            ),
            ChangeNotifierProxyProvider2<CatalogProvider, SessionProvider, CartProvider>(
              create: (BuildContext context) =>
                  CartProvider(context.read<CatalogProvider>()),
              update: (BuildContext ctx, CatalogProvider catalog, SessionProvider session,
                  CartProvider? cart) {
                final CartProvider next = cart ?? CartProvider(catalog);
                next.setAddresses(session.addresses);
                return next;
              },
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('an order-status tap opens the order tracking screen', (WidgetTester tester) async {
      final MemoryShopRepository repo = newRepository();
      final SessionProvider session = SessionProvider(repository: repo);
      final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
      final _FakeMessagingBackend backend = _FakeMessagingBackend();
      final NotificationService service = newService(
        repository: repo,
        session: session,
        navigatorKey: navigatorKey,
        backend: backend,
      );
      addTearDown(service.dispose);
      addTearDown(backend.dispose);

      await pumpHarness(tester,
          repository: repo, session: session, navigatorKey: navigatorKey);

      // The customer's seeded orders include an in-flight order.
      service.open(const NotificationTap(
        type: NotificationTap.orderStatus,
        orderId: 'HL-2601-6372',
      ));
      await tester.pumpAndSettle();

      expect(find.byType(OrderTrackingScreen), findsOneWidget);
    });

    testWidgets('a tap on a push the session cannot resolve is dropped',
        (WidgetTester tester) async {
      final MemoryShopRepository repo = newRepository();
      final SessionProvider session = SessionProvider(repository: repo);
      final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
      final _FakeMessagingBackend backend = _FakeMessagingBackend();
      final NotificationService service = newService(
        repository: repo,
        session: session,
        navigatorKey: navigatorKey,
        backend: backend,
      );
      addTearDown(service.dispose);
      addTearDown(backend.dispose);

      await pumpHarness(tester,
          repository: repo, session: session, navigatorKey: navigatorKey);

      service.open(const NotificationTap(
        type: NotificationTap.orderStatus,
        orderId: 'HL-9999-0000', // not one of the seeded orders
      ));
      await tester.pumpAndSettle();

      expect(find.byType(OrderTrackingScreen), findsNothing);
    });

    testWidgets('a new-order tap opens the admin orders board', (WidgetTester tester) async {
      final MemoryShopRepository repo = newRepository();
      final SessionProvider session = SessionProvider(repository: repo);
      final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
      final _FakeMessagingBackend backend = _FakeMessagingBackend();
      final NotificationService service = newService(
        repository: repo,
        session: session,
        navigatorKey: navigatorKey,
        backend: backend,
      );
      addTearDown(service.dispose);
      addTearDown(backend.dispose);

      await pumpHarness(tester,
          repository: repo, session: session, navigatorKey: navigatorKey);

      service.open(const NotificationTap(
        type: NotificationTap.newOrder,
        orderId: 'HL-2602-1000',
      ));
      await tester.pumpAndSettle();

      expect(find.byType(AdminDashboardScreen), findsOneWidget);
    });

    testWidgets('a backgrounded-app tap is decoded from the data map and routed',
        (WidgetTester tester) async {
      final MemoryShopRepository repo = newRepository();
      final SessionProvider session = SessionProvider(repository: repo);
      final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
      final _FakeMessagingBackend backend = _FakeMessagingBackend();
      final NotificationService service = newService(
        repository: repo,
        session: session,
        navigatorKey: navigatorKey,
        backend: backend,
      );
      addTearDown(service.dispose);
      addTearDown(backend.dispose);

      await pumpHarness(tester,
          repository: repo, session: session, navigatorKey: navigatorKey);

      // init() wires the app-side message streams; a tap on a tray notification
      // then arrives through them.
      await service.init();

      backend._opened.add(RemoteMessage(
        data: <String, dynamic>{
          'type': NotificationTap.orderStatus,
          'orderId': 'HL-2601-6372',
        },
        notification: const RemoteNotification(
          title: 'Highlanders Coffee & Tea',
          body: 'Your order is out for delivery.',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(OrderTrackingScreen), findsOneWidget);
    });

    testWidgets('a foreground message shows an in-app banner, not a route push',
        (WidgetTester tester) async {
      final MemoryShopRepository repo = newRepository();
      final SessionProvider session = SessionProvider(repository: repo);
      final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
      final _FakeMessagingBackend backend = _FakeMessagingBackend();
      final NotificationService service = newService(
        repository: repo,
        session: session,
        navigatorKey: navigatorKey,
        backend: backend,
      );
      addTearDown(service.dispose);
      addTearDown(backend.dispose);

      await pumpHarness(tester,
          repository: repo, session: session, navigatorKey: navigatorKey);

      // init() wires the foreground-message stream.
      await service.init();

      backend.emitForeground(RemoteMessage(
        data: <String, dynamic>{'type': NotificationTap.orderStatus, 'orderId': 'HL-2601-6372'},
        notification: const RemoteNotification(
          title: 'Highlanders Coffee & Tea',
          body: 'Your order is out for delivery.',
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Your order is out for delivery.'),
        findsOneWidget,
      );
      expect(find.byType(OrderTrackingScreen), findsNothing);
    });
  });
}