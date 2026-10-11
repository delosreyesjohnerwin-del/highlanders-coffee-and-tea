import 'package:flutter_test/flutter_test.dart';
import 'package:highlanders_coffee/data/firestore/memory_shop_repository.dart';
import 'package:highlanders_coffee/data/models/order.dart';
import 'package:highlanders_coffee/services/in_app_alert.dart';
import 'package:highlanders_coffee/state/admin_provider.dart';

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

      expect(alerts.bodies, <String>['New order from Ben']);
    });
  });
}

Order _order(
  String id,
  DateTime createdAt, {
  OrderStatus status = OrderStatus.pending,
  Fulfillment fulfillment = Fulfillment.delivery,
  String? customerName,
}) =>
    Order(
      id: id,
      customerUid: 'u-$id',
      lines: const <OrderLine>[],
      status: status,
      fulfillment: fulfillment,
      paymentMethod: PaymentMethod.cash,
      createdAt: createdAt,
      customerName: customerName,
    );

class _RecordingAlerts implements InAppAlertPresenter {
  final List<String> bodies = <String>[];

  @override
  void show(String body) => bodies.add(body);
}
