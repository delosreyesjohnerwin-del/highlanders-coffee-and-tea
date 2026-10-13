import 'package:flutter_test/flutter_test.dart';
import 'package:highlanders_coffee/data/firestore/serialisation.dart';
import 'package:highlanders_coffee/data/models/app_notification.dart';
import 'package:highlanders_coffee/data/models/order.dart';

/// The stored notification record: ids, copy and the Firestore round-trip.
///
/// The ids are the load-bearing part. The app and the Cloudflare relay both
/// write the same change, and a deterministic id is what makes those two writes
/// collapse onto one document instead of showing the order twice.
void main() {
  group('ids', () {
    test('are deterministic and content-addressed', () {
      expect(AppNotification.newOrderId('HL-1'), 'new-order-HL-1');
      expect(
        AppNotification.statusChangeId('HL-1', OrderStatus.confirmed),
        'order-status-HL-1-confirmed',
      );
    });

    test('a status change gets its own record per status', () {
      expect(
        AppNotification.statusChangeId('HL-1', OrderStatus.confirmed),
        isNot(AppNotification.statusChangeId('HL-1', OrderStatus.ready)),
      );
    });
  });

  group('forNewOrder', () {
    test('carries the order id in the id, the body and the type', () {
      final AppNotification n = AppNotification.forNewOrder(
        _order('HL-77', items: 2, customerName: 'Ben'),
      );

      expect(n.id, 'new-order-HL-77');
      expect(n.type, AppNotificationType.newOrder);
      expect(n.orderId, 'HL-77');
      expect(n.body, contains('#HL-77'));
      expect(n.body, contains('Ben'));
      expect(n.body, contains('2 items'));
      expect(n.read, isFalse);
    });

    test('reads naturally with a nameless order and a single item', () {
      final AppNotification n = AppNotification.forNewOrder(_order('HL-9', items: 1));
      expect(n.body, contains('1 item ·'));
      expect(n.body, isNot(contains('  ·')));
    });
  });

  group('forStatusChange', () {
    test('words each status with the order id', () {
      String bodyFor(OrderStatus status, {Fulfillment fulfillment = Fulfillment.delivery}) =>
          AppNotification.forStatusChange(
            _order('HL-5', status: status, fulfillment: fulfillment),
          ).body;

      expect(bodyFor(OrderStatus.pending), 'Your order #HL-5 was received.');
      expect(bodyFor(OrderStatus.confirmed), 'Your order #HL-5 has been confirmed!');
      expect(bodyFor(OrderStatus.preparing), 'Your order #HL-5 is being prepared.');
      expect(bodyFor(OrderStatus.ready), 'Your order #HL-5 is ready.');
      expect(
        bodyFor(OrderStatus.ready, fulfillment: Fulfillment.pickup),
        'Your order #HL-5 is ready for pickup!',
      );
      expect(bodyFor(OrderStatus.outForDelivery), 'Your order #HL-5 is out for delivery.');
      expect(bodyFor(OrderStatus.delivered), 'Your order #HL-5 has been delivered. Enjoy!');
      expect(bodyFor(OrderStatus.cancelled), 'Your order #HL-5 was cancelled.');
    });

    test('records the status it announced', () {
      final AppNotification n = AppNotification.forStatusChange(
        _order('HL-5', status: OrderStatus.ready),
      );
      expect(n.status, OrderStatus.ready);
      expect(n.type, AppNotificationType.orderStatus);
      expect(n.id, 'order-status-HL-5-ready');
    });
  });

  group('serialisation', () {
    test('round-trips every field', () {
      final AppNotification original = AppNotification(
        id: 'order-status-HL-5-confirmed',
        type: AppNotificationType.orderStatus,
        title: 'Highlanders Coffee & Tea',
        body: 'Your order #HL-5 has been confirmed!',
        orderId: 'HL-5',
        status: OrderStatus.confirmed,
        createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
        read: true,
      );

      final AppNotification back =
          AppNotificationSerialisation.fromMap(original.toMap(), 'fallback');

      expect(back.id, original.id);
      expect(back.type, original.type);
      expect(back.title, original.title);
      expect(back.body, original.body);
      expect(back.orderId, original.orderId);
      expect(back.status, original.status);
      expect(back.createdAt.isAtSameMomentAs(original.createdAt), isTrue);
      expect(back.read, isTrue);
    });

    test('a new-order record has no status field and reads back as such', () {
      final AppNotification original = AppNotification.forNewOrder(_order('HL-8'));
      final Map<String, dynamic> map = original.toMap();
      expect(map.containsKey('status'), isFalse);

      final AppNotification back = AppNotificationSerialisation.fromMap(map, 'x');
      expect(back.status, isNull);
      expect(back.type, AppNotificationType.newOrder);
    });

    test('a sparse document falls back rather than throwing', () {
      // The relay writes the fields, but a hand-edited or old document must not
      // take the inbox down.
      final AppNotification back = AppNotificationSerialisation.fromMap(<String, dynamic>{}, 'doc-id');
      expect(back.id, 'doc-id');
      expect(back.type, AppNotificationType.orderStatus);
      expect(back.title, 'Notification');
      expect(back.body, '');
      expect(back.read, isFalse);
    });

    test('read defaults to false when the relay omitted it', () {
      final AppNotification back = AppNotificationSerialisation.fromMap(
        <String, dynamic>{'type': 'newOrder', 'orderId': 'HL-1'},
        'new-order-HL-1',
      );
      expect(back.read, isFalse);
    });
  });
}

Order _order(
  String id, {
  OrderStatus status = OrderStatus.pending,
  Fulfillment fulfillment = Fulfillment.delivery,
  int items = 1,
  String? customerName,
}) =>
    Order(
      id: id,
      customerUid: 'u-$id',
      // One line of quantity [items] so itemCount is exercised.
      lines: <OrderLine>[
        OrderLine(itemId: 'm-1', name: 'Latte', price: 120, quantity: items),
      ],
      status: status,
      fulfillment: fulfillment,
      paymentMethod: PaymentMethod.cash,
      customerName: customerName,
      subtotal: 120 * items,
      createdAt: DateTime(2026, 1, 1),
    );
