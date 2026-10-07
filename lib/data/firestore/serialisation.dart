import 'package:flutter/material.dart';

import '../models/coverage.dart';
import '../models/menu.dart';
import '../models/order.dart';
import '../models/settings.dart';
import '../models/staff.dart';

/// Firestore (de)serialisation for the domain models.
///
/// Every model gets a `toMap`/`fromMap` pair rather than using `cloud_firestore`
/// converters, for one reason: the admin panel and the seeding script both need
/// plain `Map<String, dynamic>`, and a converter registry would only move the
/// same code somewhere else.
///
/// Conventions, applied uniformly so a document written by this file can always
/// be read back by it:
///
///  * Enums are stored by `name`, never by index. `.index` shifts the moment
///    someone reorders a Dart enum, which would silently reinterpret every
///    stored order status.
///  * `DateTime` is stored as a UTC ISO-8601 string. Firestore's native
///    Timestamp is avoided because these maps also travel over JSON in the seed
///    path, where a Timestamp serialises to an object.
///  * Absent optional fields are omitted rather than written as null, so a
///    partial document does not come back with a field that reads as "explicitly
///    empty".
///
/// Every reader is defensive: a missing or unparseable field falls back to a
/// sensible default rather than throwing. A corrupt order should drop out of the
/// board, not take the admin panel down with it.

// --- helpers --------------------------------------------------------------

double? _toDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

num? _toNum(Object? v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

int? _toInt(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

bool? _toBool(Object? v) {
  if (v is bool) return v;
  if (v is String) return v == 'true';
  return null;
}

String? _toStr(Object? v) => v is String && v.isNotEmpty ? v : null;

/// Normalises a Firestore document body to a map.
///
/// `DocumentSnapshot.data()` is nullable — it returns null when the document does
/// not exist — and a query can hand back a document that was deleted between the
/// snapshot and the read. Every `fromMap` takes this shape rather than a
/// `Map<String, dynamic>` so no caller has to decide what an absent body means.
/// The answer is always the same: an object built entirely from defaults.
Map<String, dynamic> _body(Map<String, dynamic>? map) => map ?? const <String, dynamic>{};

DateTime? _toDate(Object? v) {
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  // Tolerate a numeric epoch in milliseconds, in case a document was written
  // by hand or by the REST API rather than by this code.
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  return null;
}

String _date(DateTime d) => d.toUtc().toIso8601String();

/// Enum by name, falling back to [fallback] when the stored value is unknown.
///
/// A forward-compatible default is what keeps an added enum value from
/// discarding a whole order.
///
/// ## Accepts the label as well as the name, and this is load-bearing
///
/// Writers store `enum.name` — `delivered`, `rider` — because that is the stable
/// identifier. The reader also accepts `enum.label` — `Delivered`, `Rider` — and
/// that tolerance is not lenience, it is correctness: comparing *only* against
/// the label means every document written by this file reads back as the
/// fallback, which silently turns a delivered order into a pending one and a
/// rider into a barista. The two tests that caught that assert on status and role
/// specifically, because they are the two fields where a wrong value changes what
/// the operator sees rather than raising anything.
///
/// Also lowercases before comparing, so a document hand-edited in the console
/// with `Delivered` is not a lost order.
T _enumByName<T extends Enum>(
  Object? raw,
  List<T> values,
  T fallback, {
  String? Function(T)? labelOf,
}) {
  if (raw is! String) return fallback;

  final String needle = raw.trim().toLowerCase();
  if (needle.isEmpty) return fallback;

  for (final T v in values) {
    if (v.name.toLowerCase() == needle) return v;
  }

  if (labelOf != null) {
    for (final T v in values) {
      final String label = labelOf(v) ?? v.name;
      if (label.toLowerCase() == needle) return v;
    }
  }

  return fallback;
}

/// IconData is not serialisable, so categories store an icon *key* and map it
/// back through a fixed table. Storing the code point would work but would break
/// if Material reordered its icon enum.
IconData _iconFromKey(Object? raw) => _iconKeys[raw] ?? Icons.local_cafe_outlined;

String _iconToKey(IconData icon) => _iconKeys.entries
    .firstWhere((MapEntry<String, IconData> e) => e.value.codePoint == icon.codePoint,
        orElse: () => const MapEntry<String, IconData>('cafe', Icons.local_cafe_outlined))
    .key;

const Map<String, IconData> _iconKeys = <String, IconData>{
  'cafe': Icons.local_cafe_outlined,
  'coffee': Icons.coffee_outlined,
  'brews': Icons.emoji_food_beverage_outlined,
  'drink': Icons.local_drink_outlined,
  'bakery': Icons.bakery_dining_outlined,
  'restaurant': Icons.restaurant_outlined,
};

// --- MenuCategory ---------------------------------------------------------

extension MenuCategorySerialisation on MenuCategory {
  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'label': label,
        'sortOrder': sortOrder,
        'iconKey': _iconToKey(icon),
      };

  static MenuCategory fromMap(Map<String, dynamic>? raw, String fallbackId) => MenuCategory(
        id: _toStr(_body(raw)['id']) ?? fallbackId,
        label: _toStr(_body(raw)['label']) ?? 'Unnamed',
        sortOrder: _toInt(_body(raw)['sortOrder']) ?? 0,
        icon: _iconFromKey(_body(raw)['iconKey']),
      );
}

// --- StoreSettings --------------------------------------------------------
//
// Open state and fee rates live in the same document as the café's name and
// hours, not in a separate "open" flag. Reason: the shop's trading state is
// something the customer sees *and* the admin toggles, and two documents
// holding related facts is a way to end up with "open" and a closed-hours
// string disagreeing.

extension StoreSettingsSerialisation on StoreSettings {
  Map<String, dynamic> toMap() => <String, dynamic>{
        'cafeName': cafeName,
        'address': address,
        'isOpen': isOpen,
        'baseFee': baseFee.toDouble(),
        'freeOver': freeOver.toDouble(),
        'coverageRadiusKm': coverageRadiusKm,
        'cafeLat': cafeLat,
        'cafeLng': cafeLng,
        'opensAt': opensAt,
        'closesAt': closesAt,
      };

  static StoreSettings fromMap(Map<String, dynamic>? raw) => StoreSettings(
        cafeName: _toStr(_body(raw)['cafeName']) ?? 'Highlanders Coffee & Tea',
        address: _toStr(_body(raw)['address']) ?? 'Poblacion, Lumban, Laguna',
        // Defaulting to open matters: a document that fails to parse must not
        // close the shop. Closing is the more expensive mistake — nobody orders
        // from a café that claims to be shut.
        isOpen: _toBool(_body(raw)['isOpen']) ?? true,
        baseFee: _toNum(_body(raw)['baseFee']) ?? 25,
        freeOver: _toNum(_body(raw)['freeOver']) ?? 500,
        coverageRadiusKm: _toDouble(_body(raw)['coverageRadiusKm']) ?? 10,
        // A settings document written before the café coordinates existed
        // falls back to the bundled placeholder rather than to zero, which
        // would make every distance read as the full radius.
        cafeLat: _toDouble(_body(raw)['cafeLat']) ?? LumbanCoverage.cafeLat,
        cafeLng: _toDouble(_body(raw)['cafeLng']) ?? LumbanCoverage.cafeLng,
        opensAt: _toStr(_body(raw)['opensAt']) ?? '7:00 AM',
        closesAt: _toStr(_body(raw)['closesAt']) ?? '10:00 PM',
      );
}

// --- MenuItem -------------------------------------------------------------

extension MenuItemSerialisation on MenuItem {
  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'categoryId': categoryId,
        'name': name,
        'price': price.toDouble(),
        'description': description,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'isAvailable': isAvailable,
        'isBestseller': isBestseller,
        'prepMinutes': prepMinutes,
        'sortOrder': sortOrder,
        'stock': stock,
        'reorderLevel': reorderLevel,
      };

  static MenuItem fromMap(Map<String, dynamic>? raw, String fallbackId) => MenuItem(
        id: _toStr(_body(raw)['id']) ?? fallbackId,
        categoryId: _toStr(_body(raw)['categoryId']) ?? 'coffee',
        name: _toStr(_body(raw)['name']) ?? 'Unnamed item',
        price: _toNum(_body(raw)['price']) ?? 0,
        description: _body(raw)['description'] is String ? _body(raw)['description'] as String : '',
        imageUrl: _toStr(_body(raw)['imageUrl']),
        isAvailable: _toBool(_body(raw)['isAvailable']) ?? true,
        isBestseller: _toBool(_body(raw)['isBestseller']) ?? false,
        prepMinutes: _toInt(_body(raw)['prepMinutes']) ?? 5,
        sortOrder: _toInt(_body(raw)['sortOrder']) ?? 0,
        stock: _toInt(_body(raw)['stock']) ?? 0,
        reorderLevel: _toInt(_body(raw)['reorderLevel']) ?? 10,
      );
}

// --- Promo ----------------------------------------------------------------

extension PromoSerialisation on Promo {
  Map<String, dynamic> toMap() => <String, dynamic>{
        'code': code,
        'title': title,
        'subtitle': subtitle,
        if (badge != null) 'badge': badge,
        if (ctaLabel != null) 'ctaLabel': ctaLabel,
        if (discountPercent != null) 'discountPercent': discountPercent,
        if (buyXGetY != null) 'buyXGetY': buyXGetY,
        'active': active,
      };

  /// Document id is the promo code: it is already unique, human-readable, and
  /// what a person would type into the console to find the document.
  static String idOf(Promo p) => p.code;

  static Promo fromMap(Map<String, dynamic>? raw, String fallbackId) => Promo(
        code: _toStr(_body(raw)['code']) ?? fallbackId,
        title: _toStr(_body(raw)['title']) ?? 'Offer',
        subtitle: _body(raw)['subtitle'] is String ? _body(raw)['subtitle'] as String : '',
        badge: _toStr(_body(raw)['badge']),
        ctaLabel: _toStr(_body(raw)['ctaLabel']),
        discountPercent: _toInt(_body(raw)['discountPercent']),
        buyXGetY: _toStr(_body(raw)['buyXGetY']),
        active: _toBool(_body(raw)['active']) ?? true,
      );
}

// --- OrderLine ------------------------------------------------------------

extension OrderLineSerialisation on OrderLine {
  Map<String, dynamic> toMap() => <String, dynamic>{
        'itemId': itemId,
        'name': name,
        'price': price.toDouble(),
        'quantity': quantity,
      };

  static OrderLine fromMap(Map<String, dynamic>? raw) => OrderLine(
        itemId: _toStr(_body(raw)['itemId']) ?? 'unknown',
        name: _toStr(_body(raw)['name']) ?? 'Item',
        price: _toNum(_body(raw)['price']) ?? 0,
        quantity: _toInt(_body(raw)['quantity']) ?? 1,
      );
}

// --- AddressSnapshot ------------------------------------------------------

extension AddressSnapshotSerialisation on AddressSnapshot {
  Map<String, dynamic> toMap() => <String, dynamic>{
        'label': label,
        'street': street,
        'barangayCode': barangayCode,
        'barangayName': barangayName,
        if (note != null) 'note': note,
        if (distanceKm != null) 'distanceKm': distanceKm,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      };

  static AddressSnapshot fromMap(Map<String, dynamic>? raw) => AddressSnapshot(
        label: _toStr(_body(raw)['label']) ?? 'Address',
        street: _toStr(_body(raw)['street']) ?? '',
        barangayCode: _toStr(_body(raw)['barangayCode']) ?? '',
        barangayName: _toStr(_body(raw)['barangayName']) ?? '',
        note: _toStr(_body(raw)['note']),
        distanceKm: _toDouble(_body(raw)['distanceKm']),
        lat: _toDouble(_body(raw)['lat']),
        lng: _toDouble(_body(raw)['lng']),
      );
}

// --- Order ----------------------------------------------------------------

extension OrderSerialisation on Order {
  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        // Required by the security rules: a customer may only create an order
        // whose customerUid is their own uid, and it cannot be omitted. See
        // `Order.customerUid` for why this lives on the model.
        'customerUid': customerUid,
        'lines': lines.map((OrderLine l) => l.toMap()).toList(),
        'status': status.name,
        'fulfillment': fulfillment.name,
        'paymentMethod': paymentMethod.name,
        'createdAt': _date(createdAt),
        'subtotal': subtotal.toDouble(),
        'deliveryFee': deliveryFee.toDouble(),
        if (distanceKm != null) 'distanceKm': distanceKm,
        if (address != null) 'address': address!.toMap(),
        if (customerName != null) 'customerName': customerName,
        if (pickupCode != null) 'pickupCode': pickupCode,
        if (driverName != null) 'driverName': driverName,
        if (driverPhone != null) 'driverPhone': driverPhone,
        if (paymentRef != null) 'paymentRef': paymentRef,
        if (promoCode != null) 'promoCode': promoCode,
      };

  static Order fromMap(Map<String, dynamic>? raw, String fallbackId) => Order(
        id: _toStr(_body(raw)['id']) ?? fallbackId,
        customerUid: _toStr(_body(raw)['customerUid']) ?? '',
        lines: (_body(raw)['lines'] is List)
            ? (_body(raw)['lines'] as List<dynamic>)
                .whereType<Map<String, dynamic>>()
                .map(OrderLineSerialisation.fromMap)
                .toList(growable: false)
            : const <OrderLine>[],
        status: _enumByName(_body(raw)['status'], OrderStatus.values, OrderStatus.pending,
            labelOf: (OrderStatus s) => s.label),
        fulfillment: _enumByName(_body(raw)['fulfillment'], Fulfillment.values, Fulfillment.delivery,
            labelOf: (Fulfillment f) => f.name),
        paymentMethod: _enumByName(_body(raw)['paymentMethod'], PaymentMethod.values, PaymentMethod.gcash,
            labelOf: (PaymentMethod p) => p.name),
        // A missing createdAt would sort to the epoch and pin the order to the
        // bottom of every "newest first" list, so it falls back to now.
        createdAt: _toDate(_body(raw)['createdAt']) ?? DateTime.now(),
        subtotal: _toNum(_body(raw)['subtotal']) ?? 0,
        deliveryFee: _toNum(_body(raw)['deliveryFee']) ?? 0,
        distanceKm: _toDouble(_body(raw)['distanceKm']),
        address: _body(raw)['address'] is Map<String, dynamic>
            ? AddressSnapshotSerialisation.fromMap(_body(raw)['address'] as Map<String, dynamic>)
            : null,
        customerName: _toStr(_body(raw)['customerName']),
        pickupCode: _toStr(_body(raw)['pickupCode']),
        driverName: _toStr(_body(raw)['driverName']),
        driverPhone: _toStr(_body(raw)['driverPhone']),
        paymentRef: _toStr(_body(raw)['paymentRef']),
        promoCode: _toStr(_body(raw)['promoCode']),
      );
}

// --- StaffMember ----------------------------------------------------------

extension StaffMemberSerialisation on StaffMember {
  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'name': name,
        'role': role.name,
        'shift': shift.name,
        if (phone != null) 'phone': phone,
        if (since != null) 'since': _date(since!),
        'completedToday': completedToday,
      };

  static StaffMember fromMap(Map<String, dynamic>? raw, String fallbackId) => StaffMember(
        id: _toStr(_body(raw)['id']) ?? fallbackId,
        name: _toStr(_body(raw)['name']) ?? 'Unnamed',
        role: _enumByName(_body(raw)['role'], StaffRole.values, StaffRole.barista,
            labelOf: (StaffRole r) => r.label),
        shift: _enumByName(_body(raw)['shift'], ShiftStatus.values, ShiftStatus.offShift,
            labelOf: (ShiftStatus s) => s.label),
        phone: _toStr(_body(raw)['phone']),
        since: _toDate(_body(raw)['since']),
        completedToday: _toInt(_body(raw)['completedToday']) ?? 0,
      );
}

// --- SavedAddress ---------------------------------------------------------

extension SavedAddressSerialisation on SavedAddress {
  Map<String, dynamic> toMap({required String uid}) => <String, dynamic>{
        'id': id,
        'uid': uid,
        'label': label,
        'street': street,
        'barangayCode': barangayCode,
        if (note != null) 'note': note,
        'isDefault': isDefault,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      };

  static SavedAddress fromMap(Map<String, dynamic>? raw, String fallbackId) => SavedAddress(
        id: _toStr(_body(raw)['id']) ?? fallbackId,
        label: _toStr(_body(raw)['label']) ?? 'Address',
        street: _toStr(_body(raw)['street']) ?? '',
        barangayCode: _toStr(_body(raw)['barangayCode']) ?? '',
        note: _toStr(_body(raw)['note']),
        isDefault: _toBool(_body(raw)['isDefault']) ?? false,
        // Legacy documents have no pin; they read back as null so the barangay
        // fallback keeps pricing them.
        lat: _toDouble(_body(raw)['lat']),
        lng: _toDouble(_body(raw)['lng']),
      );
}