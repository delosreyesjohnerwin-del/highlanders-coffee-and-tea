import '../../data/models/order.dart';

/// The six pipeline statuses an order passes through, in order.
///
/// Shared by the tracking screen (vertical timeline) and the order cards
/// (compact progress strip) so the two cannot drift apart.
const List<OrderStatus> orderPipeline = <OrderStatus>[
  OrderStatus.pending,
  OrderStatus.confirmed,
  OrderStatus.preparing,
  OrderStatus.ready,
  OrderStatus.outForDelivery,
  OrderStatus.delivered,
];

/// Index of [status] in [orderPipeline].
///
/// Terminal non-delivered states (cancelled, failed) never entered the
/// pipeline beyond step 0 — the order was received, then stopped.
int orderStepIndex(OrderStatus status) {
  if (status == OrderStatus.cancelled || status == OrderStatus.failedDelivery) return 0;
  final int i = orderPipeline.indexOf(status);
  return i < 0 ? 0 : i;
}

/// Timeline label for [status].
///
/// Pickup orders use handover wording ("Ready for pickup", "Collected");
/// delivery orders use the status's plain label.
String orderStepLabel(OrderStatus status, {required bool pickup}) {
  if (pickup) {
    return switch (status) {
      OrderStatus.pending => 'Order received',
      OrderStatus.confirmed => 'Confirmed',
      OrderStatus.preparing => 'Being prepared',
      OrderStatus.ready => 'Ready for pickup',
      OrderStatus.outForDelivery => 'Handed over',
      OrderStatus.delivered => 'Collected',
      _ => status.label,
    };
  }
  return status.label;
}