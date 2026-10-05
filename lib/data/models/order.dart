import 'package:flutter/material.dart';

import 'coverage.dart';

enum OrderStatus {
  pending,
  confirmed,
  preparing,
  ready,
  outForDelivery,
  delivered,
  failedDelivery,
  cancelled,
}

extension OrderStatusX on OrderStatus {
  String get label => switch (this) {
        OrderStatus.pending => 'Pending',
        OrderStatus.confirmed => 'Confirmed',
        OrderStatus.preparing => 'Preparing',
        OrderStatus.ready => 'Ready',
        OrderStatus.outForDelivery => 'Out for delivery',
        OrderStatus.delivered => 'Delivered',
        OrderStatus.failedDelivery => 'Failed',
        OrderStatus.cancelled => 'Cancelled',
      };

  /// Filled badge for terminal states, outline for in-flight ones.
  bool get isTerminal => this == OrderStatus.delivered || this == OrderStatus.cancelled;

  /// Orders still moving through the pipeline.
  bool get isActive =>
      this != OrderStatus.delivered && this != OrderStatus.cancelled && this != OrderStatus.failedDelivery;
}

enum Fulfillment { pickup, delivery }

extension FulfillmentX on Fulfillment {
  String get label => this == Fulfillment.pickup ? 'Pick up' : 'Delivery';
}

enum PaymentMethod { gcash, paymaya, ebank, cash }

extension PaymentMethodX on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.gcash => 'GCash',
        PaymentMethod.paymaya => 'Maya',
        PaymentMethod.ebank => 'E-bank',
        PaymentMethod.cash => 'Cash on delivery',
      };

  IconData get icon => switch (this) {
        PaymentMethod.gcash => Icons.account_balance_wallet_outlined,
        PaymentMethod.paymaya => Icons.phone_iphone_outlined,
        PaymentMethod.ebank => Icons.account_balance_outlined,
        PaymentMethod.cash => Icons.payments_outlined,
      };

  /// Cash is collected by the driver at handover; the rest are prepaid.
  bool get isPrepaid => this != PaymentMethod.cash;
}

/// One line in an order.
@immutable
class OrderLine {
  const OrderLine({
    required this.itemId,
    required this.name,
    required this.price,
    required this.quantity,
  });

  final String itemId;
  final String name;
  final num price;
  final int quantity;

  num get lineTotal => price * quantity;

  OrderLine copyWith({int? quantity}) => OrderLine(
        itemId: itemId,
        name: name,
        price: price,
        quantity: quantity ?? this.quantity,
      );
}

/// Immutable copy of a delivery address, stored on the order so that later
/// edits to the customer's saved address never rewrite order history.
@immutable
class AddressSnapshot {
  const AddressSnapshot({
    required this.label,
    required this.street,
    required this.barangayCode,
    required this.barangayName,
    this.note,
    this.distanceKm,
  });

  final String label;
  final String street;
  final String barangayCode;
  final String barangayName;
  final String? note;
  final double? distanceKm;

  String get oneLine => '$street, $barangayName';
}

/// A customer order.
@immutable
class Order {
  const Order({
    required this.id,
    required this.lines,
    required this.status,
    required this.fulfillment,
    required this.paymentMethod,
    required this.createdAt,
    this.subtotal = 0,
    this.deliveryFee = 0,
    this.distanceKm,
    this.address,
    this.customerName,
    this.pickupCode,
    this.driverName,
    this.driverPhone,
    this.paymentRef,
    this.promoCode,
    this.customerUid = '',
  });

  final String id;

  /// Auth uid of the customer who placed this.
  ///
  /// This is not decoration: the Firestore rules key every order read on it
  /// (`resource.data.customerUid == request.auth.uid`), and `create` requires it
  /// to equal the caller's uid. Without it on the model there would be nowhere
  /// to keep the value an order was stored under, and the admin panel could not
  /// hand an order back to the customer who owns it.
  ///
  /// Empty means "not attributed" and such an order cannot be written — see
  /// `FirestoreOrderRepository.saveOrder`, which refuses rather than letting the
  /// server reject it.
  final String customerUid;

  final List<OrderLine> lines;
  final OrderStatus status;
  final Fulfillment fulfillment;
  final PaymentMethod paymentMethod;
  final DateTime createdAt;
  final num subtotal;
  final num deliveryFee;
  final double? distanceKm;
  final AddressSnapshot? address;
  final String? customerName;
  final String? pickupCode;
  final String? driverName;
  final String? driverPhone;
  final String? paymentRef;
  final String? promoCode;

  num get total => subtotal + deliveryFee;

  int get itemCount => lines.fold(0, (int sum, OrderLine l) => sum + l.quantity);
}

/// A saved delivery address.
@immutable
class SavedAddress {
  const SavedAddress({
    required this.id,
    required this.label,
    required this.street,
    required this.barangayCode,
    this.note,
    this.isDefault = false,
  });

  final String id;
  final String label;
  final String street;
  final String barangayCode;
  final String? note;
  final bool isDefault;

  /// Straight-line distance from the café, derived from the bundled
  /// barangay centroid. Null when the barangay is not in the coverage table.
  double? distanceKm() {
    final Barangay? b = LumbanCoverage.byCode(barangayCode);
    return b == null ? null : LumbanCoverage.distanceToBarangay(b);
  }
}

/// App user profile.
@immutable
class AppUser {
  const AppUser({
    required this.uid,
    required this.fullName,
    required this.email,
    this.phone,
    this.avatarUrl,
    this.role = UserRole.customer,
    this.memberTier = 'Gold Member',
    this.orderCount = 0,
    this.reviewCount = 0,
    this.rewards = 0,
  });

  final String uid;
  final String fullName;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final UserRole role;
  final String memberTier;
  final int orderCount;
  final int reviewCount;
  final num rewards;
}

enum UserRole { customer, admin }