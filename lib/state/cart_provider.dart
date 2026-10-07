import 'package:flutter/foundation.dart';

import '../data/models/coverage.dart';
import '../data/models/menu.dart';
import '../data/models/order.dart';
import 'catalog_provider.dart';

/// Cart contents plus the checkout selections that affect pricing.
///
/// Total is derived, never stored: subtotal + delivery fee. The delivery fee
/// comes from [CatalogProvider.pricing] using the straight-line distance from
/// the café to the selected address's barangay.
class CartProvider extends ChangeNotifier {
  CartProvider(this._catalog) {
    _catalog.addListener(_onCatalogChanged);
  }

  final CatalogProvider _catalog;

  final Map<String, int> _quantities = <String, int>{};

  Fulfillment _fulfillment = Fulfillment.delivery;
  PaymentMethod _paymentMethod = PaymentMethod.gcash;
  String? _addressId;
  String? _promoCode;

  @override
  void dispose() {
    _catalog.removeListener(_onCatalogChanged);
    super.dispose();
  }

  void _onCatalogChanged() => notifyListeners();

  // --- contents ----------------------------------------------------------

  List<OrderLine> get lines {
    final List<OrderLine> result = <OrderLine>[];

    _quantities.forEach((String itemId, int qty) {
      final MenuItem? item = _catalog.itemById(itemId);
      if (item == null) return;
      result.add(OrderLine(itemId: itemId, name: item.name, price: item.price, quantity: qty));
    });

    return result;
  }

  bool get isEmpty => _quantities.isEmpty;
  int get itemCount => _quantities.values.fold(0, (int a, int b) => a + b);
  num get subtotal => _quantities.entries.fold<num>(
        0,
        (num sum, MapEntry<String, int> e) {
          final MenuItem? item = _catalog.itemById(e.key);
          return item == null ? sum : sum + item.price * e.value;
        },
      );

  int quantityOf(String itemId) => _quantities[itemId] ?? 0;

  // --- checkout selections ----------------------------------------------

  Fulfillment get fulfillment => _fulfillment;
  PaymentMethod get paymentMethod => _paymentMethod;
  String? get addressId => _addressId;
  String? get promoCode => _promoCode;
  List<AddressSnapshot> get availableAddresses => List<AddressSnapshot>.from(_mockAddresses);

  List<SavedAddress> _mockAddresses = const <SavedAddress>[];

  void setAddresses(List<SavedAddress> addresses) {
    _mockAddresses = addresses;
    // An address deleted while it was selected must not keep the cart thinking
    // there is a delivery destination. The session pushes the shrunk list the
    // moment the deletion lands, and this prune drops the stale selection.
    if (_addressId != null && !addresses.any((SavedAddress a) => a.id == _addressId)) {
      _addressId = null;
    }
    notifyListeners();
  }

  void setFulfillment(Fulfillment value) {
    if (_fulfillment == value) return;
    _fulfillment = value;
    notifyListeners();
  }

  void setPaymentMethod(PaymentMethod value) {
    if (_paymentMethod == value) return;
    _paymentMethod = value;
    notifyListeners();
  }

  void selectAddress(String id) {
    _addressId = id;
    notifyListeners();
  }

  AddressSnapshot? get addressSnapshot {
    final String? id = _addressId;
    if (id == null) return null;

    final DeliveryPricing pricing = _catalog.pricing;
    for (final SavedAddress a in _mockAddresses) {
      if (a.id == id) {
        final Barangay? b = LumbanCoverage.byCode(a.barangayCode);
        return AddressSnapshot(
          label: a.label,
          street: a.street,
          barangayCode: a.barangayCode,
          barangayName: b?.name ?? a.barangayCode,
          note: a.note,
          distanceKm: a.distanceKm(cafeLat: pricing.cafeLat, cafeLng: pricing.cafeLng),
          lat: a.lat,
          lng: a.lng,
        );
      }
    }
    return null;
  }

  // --- pricing -----------------------------------------------------------

  double? get distanceKm => _fulfillment == Fulfillment.delivery ? addressSnapshot?.distanceKm : null;

  num get deliveryFee {
    if (_fulfillment == Fulfillment.pickup) return 0;
    final double? km = distanceKm;
    if (km == null) return 0;
    return _catalog.pricing.feeFor(km: km, subtotal: subtotal);
  }

  num get total => subtotal + deliveryFee;

  bool get isFreeDelivery {
    final num? over = _catalog.pricing.freeOver;
    return _fulfillment == Fulfillment.delivery && over != null && subtotal >= over;
  }

  int get etaMinutes {
    final double? km = distanceKm;
    if (km == null) return 0;
    return _catalog.pricing.etaMinutes(km);
  }

  /// True when delivery is selected but the address falls outside the
  /// café's coverage radius, or no address has been chosen yet.
  bool get hasDeliveryProblem {
    if (_fulfillment != Fulfillment.delivery) return false;
    if (addressSnapshot == null) return true;
    final double km = distanceKm ?? 0;
    return !_catalog.pricing.covers(km);
  }

  bool get canCheckout => !isEmpty && !hasDeliveryProblem;

  void applyPromo(String? code) {
    _promoCode = code;
    notifyListeners();
  }

  // --- mutations ---------------------------------------------------------

  /// Adds [qty] of [itemId].
  ///
  /// Refuses unavailable and sold-out items. The stock check matters even though
  /// the button is disabled in the UI: it is the actual guard, and a race
  /// between the tap and the render (or a fast double-tap) must not be able to
  /// put an item in the cart that the shop cannot make.
  ///
  /// Returns false when the item was rejected, so callers can show a reason.
  bool add(String itemId, [int qty = 1]) {
    final MenuItem? item = _catalog.itemById(itemId);

    if (item == null || !item.isOrderable) {
      // No notify: nothing changed, and re-rendering would only make the
      // disabled button look like it failed for no reason.
      return false;
    }

    final int next = quantityOf(itemId) + qty;

    // Cap at what is physically on hand rather than silently over-ordering.
    if (next > item.stock) return false;

    _quantities[itemId] = next;
    notifyListeners();
    return true;
  }

  void remove(String itemId) {
    final int next = quantityOf(itemId) - 1;
    if (next <= 0) {
      _quantities.remove(itemId);
    } else {
      _quantities[itemId] = next;
    }
    notifyListeners();
  }

  void setQuantity(String itemId, int qty) {
    if (qty <= 0) {
      _quantities.remove(itemId);
    } else {
      _quantities[itemId] = qty;
    }
    notifyListeners();
  }

  void clear() {
    _quantities.clear();
    _promoCode = null;
    notifyListeners();
  }

  /// Re-adds every line from a past order. Used by the Reorder button.
  void reorderFrom(Order order) {
    for (final OrderLine line in order.lines) {
      _quantities[line.itemId] = (_quantities[line.itemId] ?? 0) + line.quantity;
    }
    if (order.address != null) _addressId = order.address!.label;
    notifyListeners();
  }
}