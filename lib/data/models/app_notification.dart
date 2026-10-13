import 'package:flutter/material.dart';

import 'order.dart';

/// Which side of the shop a stored notification belongs to.
enum AppNotificationType {
  /// A freshly placed order, written to the café's inbox.
  newOrder,

  /// An order that moved through the pipeline, written to the customer's inbox.
  orderStatus,
}

/// One persisted notification in a user's inbox.
///
/// Stored under `notifications/{uid}/items/{id}`, so a customer's inbox and the
/// café's inbox are separate documents under separate rules, and a real-time
/// listener on one never sees the other's records.
///
/// Ids are **deterministic** ([newOrderId], [statusChangeId]) rather than random.
/// Two writers can race — the app writing from its own live stream, and the
/// Cloudflare relay backfilling the same change for a closed app — and both land
/// on the same document, so the inbox holds one record and FCM sends one push.
/// A random id would show the same order twice.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.orderId,
    required this.createdAt,
    this.status,
    this.read = false,
  });

  final String id;
  final AppNotificationType type;

  /// Bold line shown in the inbox row and the OS push.
  final String title;

  /// The detail line. Always carries the order id so both sides can match the
  /// record to the board or the tracking screen.
  final String body;

  final String orderId;

  /// The status this record announced, for [AppNotificationType.orderStatus].
  /// Null for a new-order record.
  final OrderStatus? status;

  final DateTime createdAt;
  final bool read;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        orderId: orderId,
        status: status,
        createdAt: createdAt,
        read: read ?? this.read,
      );

  /// The café inbox id for "order [orderId] was placed".
  static String newOrderId(String orderId) => 'new-order-$orderId';

  /// The customer inbox id for "order [orderId] reached [status]".
  static String statusChangeId(String orderId, OrderStatus status) =>
      'order-status-$orderId-${status.name}';

  /// The café-side record for a freshly placed [order].
  factory AppNotification.forNewOrder(Order order, {DateTime? at}) => AppNotification(
        id: newOrderId(order.id),
        type: AppNotificationType.newOrder,
        title: 'New order received',
        body: newOrderBody(order),
        orderId: order.id,
        createdAt: at ?? DateTime.now(),
      );

  /// The customer-side record for [order] reaching its current status.
  factory AppNotification.forStatusChange(Order order, {DateTime? at}) => AppNotification(
        id: statusChangeId(order.id, order.status),
        type: AppNotificationType.orderStatus,
        title: 'Highlanders Coffee & Tea',
        body: statusChangeBody(order),
        orderId: order.id,
        status: order.status,
        createdAt: at ?? DateTime.now(),
      );
}

/// Café-facing line for a new order, carrying the order id so the operator can
/// match it to the board at a glance.
String newOrderBody(Order order) {
  final int items = order.itemCount;
  final String customer = (order.customerName ?? '').trim();
  final String who = customer.isEmpty ? '' : '$customer · ';
  final String itemWord = items == 1 ? 'item' : 'items';
  return 'New Order Received #${order.id} · $who$items $itemWord · ₱${order.total.toStringAsFixed(2)}';
}

/// Customer-facing line for an order's current status, carrying the order id.
///
/// Mirrors the wording the relay and `functions/src/notifications.ts` send, so a
/// record written by the app and a record backfilled by the relay read the same.
String statusChangeBody(Order order) {
  final String id = order.id;
  switch (order.status) {
    case OrderStatus.pending:
      return 'Your order #$id was received.';
    case OrderStatus.confirmed:
      return 'Your order #$id has been confirmed!';
    case OrderStatus.preparing:
      return 'Your order #$id is being prepared.';
    case OrderStatus.ready:
      return order.fulfillment == Fulfillment.pickup
          ? 'Your order #$id is ready for pickup!'
          : 'Your order #$id is ready.';
    case OrderStatus.outForDelivery:
      return 'Your order #$id is out for delivery.';
    case OrderStatus.delivered:
      return 'Your order #$id has been delivered. Enjoy!';
    case OrderStatus.failedDelivery:
      return 'Delivery for order #$id failed — our team will contact you.';
    case OrderStatus.cancelled:
      return 'Your order #$id was cancelled.';
  }
}
