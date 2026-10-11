import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models/order.dart';

/// The free notification path.
///
/// No push backend is deployed — sending to a closed app needs either Blaze
/// Cloud Functions or the Cloudflare relay in `push-relay/` — so nothing ever
/// reaches Firebase Cloud Messaging. What the app *can* do for free is surface
/// the changes it already sees in its own live Firestore streams:
///
///  * the café's device is told when a customer places a new order, and
///  * the customer's device is told when one of their orders changes status.
///
/// Both are best-effort and only fire while the app is open. Pushing to a
/// closed app stays dormant in `notification_service.dart` until a sender is
/// deployed.

/// Shows [body] as an in-app banner, with a system alert sound and a light
/// haptic.
///
/// A no-op when [context] is null or cannot reach a [ScaffoldMessenger] — before
/// the first frame, and in tests that mount a provider without a scaffold.
/// Never throws: an alert is a courtesy, never a fault.
void showInAppAlert(BuildContext? context, String body) {
  if (context == null || body.isEmpty) return;
  try {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(body)));
    // `catchError` rather than a `try`: these are futures, so a platform
    // failure arrives after this frame. A missing sound card or a headless test
    // must not become an unhandled error.
    unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
    unawaited(SystemSound.play(SystemSoundType.alert).catchError((Object _) {}));
  } catch (_) {
    // A messenger torn down mid-alert is not worth crashing over.
  }
}

/// Human copy for an [OrderStatus] transition, shared by both panels so the
/// customer and the café read the same words.
String orderStatusCopy(OrderStatus status, Order order) {
  switch (status) {
    case OrderStatus.pending:
      return 'Order received';
    case OrderStatus.confirmed:
      return 'Order confirmed';
    case OrderStatus.preparing:
      return 'Order is being prepared';
    case OrderStatus.ready:
      return order.fulfillment == Fulfillment.pickup ? 'Ready for pickup' : 'Ready';
    case OrderStatus.outForDelivery:
      return 'Out for delivery';
    case OrderStatus.delivered:
      return 'Order delivered — enjoy!';
    case OrderStatus.failedDelivery:
      return 'Delivery failed — contact the customer';
    case OrderStatus.cancelled:
      return 'Order cancelled';
  }
}

/// Orders in [next] whose id was absent from [previous], newest first.
///
/// Newest first so a burst of orders announces the one an operator is most
/// likely to act on.
List<Order> newOrdersBetween(List<Order> previous, List<Order> next) {
  final Set<String> known = <String>{for (final Order o in previous) o.id};
  final List<Order> fresh =
      next.where((Order o) => !known.contains(o.id)).toList(growable: false);
  if (fresh.length < 2) return fresh;
  return <Order>[...fresh]
    ..sort((Order a, Order b) => b.createdAt.compareTo(a.createdAt));
}

/// Orders in [next] whose status differs from the same id in [previous].
///
/// Only orders the app already knew about count. A first load must not announce
/// every historical order as if it had just moved, and a customer's own fresh
/// order (`placeOrder` prepends it before the stream echoes it) is not a change.
List<Order> statusChangedBetween(List<Order> previous, List<Order> next) {
  final Map<String, OrderStatus> before = <String, OrderStatus>{
    for (final Order o in previous) o.id: o.status,
  };
  return next
      .where((Order o) => before.containsKey(o.id) && before[o.id] != o.status)
      .toList(growable: false);
}

/// A `BuildContext`-free handle for showing a change as an in-app banner.
///
/// Injected into the providers so they can announce a change without holding a
/// context that might outlive a frame, and so tests can capture the alerts
/// without a live navigator.
abstract class InAppAlertPresenter {
  void show(String body);
}

/// Production presenter: reaches the app's `ScaffoldMessenger` through the
/// navigator's context.
///
/// The navigator's context, not the app root's: `ScaffoldMessenger` is created
/// *inside* `MaterialApp`, so a context above it finds nothing and every alert
/// would be dropped.
class NavigatorAlertPresenter implements InAppAlertPresenter {
  const NavigatorAlertPresenter(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  void show(String body) => showInAppAlert(navigatorKey.currentContext, body);
}

/// Presenter that drops every alert.
///
/// The default, so a provider constructed without one — tests, previews —
/// never touches platform channels.
class NoopAlertPresenter implements InAppAlertPresenter {
  const NoopAlertPresenter();

  @override
  void show(String body) {}
}
