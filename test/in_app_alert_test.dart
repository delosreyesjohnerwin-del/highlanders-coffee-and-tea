import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlanders_coffee/data/firestore/memory_shop_repository.dart';
import 'package:highlanders_coffee/data/models/app_notification.dart';
import 'package:highlanders_coffee/data/models/order.dart';
import 'package:highlanders_coffee/services/in_app_alert.dart';
import 'package:highlanders_coffee/services/mock_auth_service.dart';
import 'package:highlanders_coffee/state/admin_provider.dart';
import 'package:highlanders_coffee/state/session_provider.dart';

/// The free notification path: with no push sender deployed, the app announces
/// the changes it can see in its own live streams. These tests pin the diffing
/// that decides whether an alert is due, which is the part most likely to
/// regress into either silence or a banner storm.
void main() {
  group('orderStatusCopy', () {
    test('reads the status, with pickup wording for a ready pickup order', () {
      final Order delivery = _order('A', DateTime(2026, 1, 1));
      final Order pickup = _order('B', DateTime(2026, 1, 1), fulfillment: Fulfillment.pickup);

      expect(orderStatusCopy(OrderStatus.confirmed, delivery), 'Order confirmed');
      expect(orderStatusCopy(OrderStatus.ready, delivery), 'Ready');
      expect(orderStatusCopy(OrderStatus.ready, pickup), 'Ready for pickup');
      expect(orderStatusCopy(OrderStatus.cancelled, delivery), 'Order cancelled');
    });
  });

  group('newOrdersBetween', () {
    test('returns only ids the café had not seen yet, newest first', () {
      final Order a = _order('A', DateTime(2026, 1, 1));
      final Order b = _order('B', DateTime(2026, 1, 3));
      final Order c = _order('C', DateTime(2026, 1, 2));

      final List<Order> fresh = newOrdersBetween(<Order>[a], <Order>[a, b, c]);
      expect(fresh.map((Order o) => o.id), <String>['B', 'C']);
    });

    test('is empty when nothing was added', () {
      final Order a = _order('A', DateTime(2026, 1, 1));
      expect(newOrdersBetween(<Order>[a], <Order>[a]), isEmpty);
    });
  });

  group('statusChangedBetween', () {
    test('reports a known order whose status moved', () {
      final Order before = _order('A', DateTime(2026, 1, 1), status: OrderStatus.pending);
      final Order after = _order('A', DateTime(2026, 1, 1), status: OrderStatus.confirmed);

      final List<Order> changed = statusChangedBetween(<Order>[before], <Order>[after]);
      expect(changed.map((Order o) => o.id), <String>['A']);
    });

    test('ignores a first load and an unchanged status', () {
      final Order a = _order('A', DateTime(2026, 1, 1), status: OrderStatus.pending);
      final Order b = _order('B', DateTime(2026, 1, 2), status: OrderStatus.pending);

      // 'A' is unknown (first load) and 'B' known but unmoved: neither is news.
      expect(statusChangedBetween(<Order>[b], <Order>[a, b]), isEmpty);
    });
  });

  group('AdminProvider', () {
    test('announces a new order once the board is already loaded', () async {
      final MemoryShopRepository repository = MemoryShopRepository();
      final _RecordingAlerts alerts = _RecordingAlerts();
      final AdminProvider admin = AdminProvider(repository: repository, alerts: alerts);
      addTearDown(admin.dispose);
      addTearDown(repository.dispose);

      admin.bind();

      // The first emission is the whole board, so it must stay silent even
      // though every order is "new" to the provider.
      await repository.saveOrder(_order('A', DateTime(2026, 1, 1), customerName: 'Ana'));
      await pumpEventQueue();
      expect(alerts.bodies, isEmpty);

      await repository.saveOrder(_order('B', DateTime(2026, 1, 2), customerName: 'Ben'));
      await pumpEventQueue();

      expect(alerts.bodies, <String>['New Order Received #B · Ben · 0 items · ₱0.00']);
    });

    test('an empty first snapshot still counts as loaded, so the first order is announced', () async {
      final MemoryShopRepository repository = MemoryShopRepository();
      final _RecordingAlerts alerts = _RecordingAlerts();
      final AdminProvider admin = AdminProvider(repository: repository, alerts: alerts);
      addTearDown(admin.dispose);
      addTearDown(repository.dispose);

      admin.bind();

      // Settings live on their own collection, so saving them emits an admin
      // snapshot whose orders and staff are both empty — exactly the fresh-shop
      // first emission. Previously the listener returned early on an empty
      // snapshot and left `_loaded` false, so the shop's very first real order
      // was later treated as the first load and its banner was swallowed.
      await repository.saveSettings(await repository.loadSettings());
      await pumpEventQueue();

      expect(admin.hasLoaded, isTrue);
      expect(alerts.bodies, isEmpty);

      await repository.saveOrder(_order('A', DateTime(2026, 1, 1), customerName: 'Ana'));
      await pumpEventQueue();

      expect(alerts.bodies, hasLength(1));
      expect(alerts.bodies.single, contains('#A'));
    });

    test('a new order is written to the admin inbox', () async {
      final MemoryShopRepository repository = MemoryShopRepository();
      final _RecordingAlerts alerts = _RecordingAlerts();
      final AdminProvider admin = AdminProvider(
        repository: repository,
        alerts: alerts,
        currentUid: () => 'u-admin',
      );
      addTearDown(admin.dispose);
      addTearDown(repository.dispose);

      admin.bind();

      // The first snapshot is the whole board, so it writes no records.
      await repository.saveOrder(_order('A', DateTime(2026, 1, 1), customerName: 'Ana'));
      await pumpEventQueue();
      expect(await repository.loadNotifications('u-admin'), isEmpty);

      await repository.saveOrder(_order('B', DateTime(2026, 1, 2), customerName: 'Ben'));
      await pumpEventQueue();

      final List<AppNotification> inbox = await repository.loadNotifications('u-admin');
      expect(inbox.map((AppNotification n) => n.id), <String>['new-order-B']);
      expect(inbox.single.body, contains('#B'));
      expect(inbox.single.type, AppNotificationType.newOrder);
    });

    test('no uid means no inbox write, but the banner still fires', () async {
      final MemoryShopRepository repository = MemoryShopRepository();
      final _RecordingAlerts alerts = _RecordingAlerts();
      // currentUid resolves null, as it does for the demo/seed account.
      final AdminProvider admin = AdminProvider(
        repository: repository,
        alerts: alerts,
        currentUid: () => null,
      );
      addTearDown(admin.dispose);
      addTearDown(repository.dispose);

      admin.bind();
      await repository.saveOrder(_order('A', DateTime(2026, 1, 1)));
      await pumpEventQueue();
      await repository.saveOrder(_order('B', DateTime(2026, 1, 2)));
      await pumpEventQueue();

      expect(alerts.bodies, hasLength(1));
      expect(await repository.loadNotifications('u-admin'), isEmpty);
    });

    test('advancing an order records a status change in the customer inbox', () async {
      final MemoryShopRepository repository = MemoryShopRepository();
      final AdminProvider admin = AdminProvider(
        repository: repository,
        alerts: _RecordingAlerts(),
      );
      addTearDown(admin.dispose);
      addTearDown(repository.dispose);

      admin.bind();
      await repository.saveOrder(_order('A', DateTime(2026, 1, 1), status: OrderStatus.pending));
      await pumpEventQueue();

      expect(admin.advanceOrder('A'), isTrue);
      await pumpEventQueue();

      final List<AppNotification> inbox = await repository.loadNotifications('u-A');
      expect(inbox.map((AppNotification n) => n.id), <String>['order-status-A-confirmed']);
      expect(inbox.single.body, contains('#A'));
      expect(inbox.single.status, OrderStatus.confirmed);
    });
  });

  group('SessionProvider', () {
    test('a customer status change is announced and written to their inbox', () async {
      final _ControllableOrdersRepository repository = _ControllableOrdersRepository();
      final _RecordingAlerts alerts = _RecordingAlerts();
      final SessionProvider session = SessionProvider(
        authService: MockAuthService(),
        roleResolver: const MockRoleResolver(),
        repository: repository,
        alerts: alerts,
      );
      addTearDown(session.dispose);
      addTearDown(repository.dispose);

      await session.signInWithPassword(
        email: 'ana.dizon@email.com',
        password: 'secret1',
        rememberMe: true,
      );
      await pumpEventQueue();
      final String uid = session.user.uid;

      // First sight of the order is the "load", not a change.
      repository.emitOrders(<Order>[
        _order('A', DateTime(2026, 1, 1), status: OrderStatus.confirmed, customerUid: uid),
      ]);
      await pumpEventQueue();
      expect(alerts.bodies, isEmpty);

      // The café advances it on another device; the stream echoes the change.
      repository.emitOrders(<Order>[
        _order('A', DateTime(2026, 1, 1), status: OrderStatus.preparing, customerUid: uid),
      ]);
      await pumpEventQueue();

      expect(alerts.bodies, hasLength(1));
      expect(alerts.bodies.single, contains('#A'));

      final List<AppNotification> inbox = await repository.loadNotifications(uid);
      expect(inbox.map((AppNotification n) => n.id), <String>['order-status-A-preparing']);
      expect(inbox.single.body, 'Your order #A is being prepared.');
    });
  });
}

Order _order(
  String id,
  DateTime createdAt, {
  OrderStatus status = OrderStatus.pending,
  Fulfillment fulfillment = Fulfillment.delivery,
  String? customerName,
  String? customerUid,
}) =>
    Order(
      id: id,
      customerUid: customerUid ?? 'u-$id',
      lines: const <OrderLine>[],
      status: status,
      fulfillment: fulfillment,
      paymentMethod: PaymentMethod.cash,
      createdAt: createdAt,
      customerName: customerName,
    );

/// A live repository whose customer-orders stream the test drives directly.
///
/// The in-memory repository hands back a single-value stream, so a status change
/// cannot happen after bind. This one exposes the stream so the test can emit a
/// change the way a Firestore listener would.
class _ControllableOrdersRepository extends MemoryShopRepository {
  final StreamController<List<Order>> _orders = StreamController<List<Order>>.broadcast();

  @override
  bool get isLive => true;

  @override
  Stream<List<Order>> watchOrdersFor(String uid) => _orders.stream;

  void emitOrders(List<Order> orders) => _orders.add(orders);

  @override
  Future<void> dispose() async {
    await _orders.close();
    await super.dispose();
  }
}

class _RecordingAlerts implements InAppAlertPresenter {
  final List<String> bodies = <String>[];

  @override
  void show(String body) => bodies.add(body);
}
