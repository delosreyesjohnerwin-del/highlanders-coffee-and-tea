import 'package:flutter_test/flutter_test.dart';
import 'package:highlanders_coffee/core/utils/order_progress.dart';
import 'package:highlanders_coffee/data/models/order.dart';

/// The pipeline shared by the tracking timeline and the order-card progress
/// strip. Both screens must agree on the order and the wording, or one will
/// show a step the other never reaches.
void main() {
  group('orderPipeline', () {
    test('runs pending through delivered in fulfilment order', () {
      expect(orderPipeline, <OrderStatus>[
        OrderStatus.pending,
        OrderStatus.confirmed,
        OrderStatus.preparing,
        OrderStatus.ready,
        OrderStatus.outForDelivery,
        OrderStatus.delivered,
      ]);
    });
  });

  group('orderStepIndex', () {
    test('is the position of an in-pipeline status', () {
      expect(orderStepIndex(OrderStatus.pending), 0);
      expect(orderStepIndex(OrderStatus.confirmed), 1);
      expect(orderStepIndex(OrderStatus.preparing), 2);
      expect(orderStepIndex(OrderStatus.ready), 3);
      expect(orderStepIndex(OrderStatus.outForDelivery), 4);
      expect(orderStepIndex(OrderStatus.delivered), 5);
    });

    test('terminal non-delivered states land on step 0', () {
      // The order was received, then stopped — never progressed.
      expect(orderStepIndex(OrderStatus.cancelled), 0);
      expect(orderStepIndex(OrderStatus.failedDelivery), 0);
    });
  });

  group('orderStepLabel', () {
    test('delivery orders use the plain status label', () {
      for (final OrderStatus status in orderPipeline) {
        expect(orderStepLabel(status, pickup: false), status.label);
      }
    });

    test('pickup orders use handover wording', () {
      expect(orderStepLabel(OrderStatus.pending, pickup: true), 'Order received');
      expect(orderStepLabel(OrderStatus.confirmed, pickup: true), 'Confirmed');
      expect(orderStepLabel(OrderStatus.preparing, pickup: true), 'Being prepared');
      expect(orderStepLabel(OrderStatus.ready, pickup: true), 'Ready for pickup');
      expect(orderStepLabel(OrderStatus.outForDelivery, pickup: true), 'Handed over');
      expect(orderStepLabel(OrderStatus.delivered, pickup: true), 'Collected');
    });

    test('stopped pickup orders still fall back to a readable label', () {
      expect(
        orderStepLabel(OrderStatus.cancelled, pickup: true),
        OrderStatus.cancelled.label,
      );
    });
  });
}