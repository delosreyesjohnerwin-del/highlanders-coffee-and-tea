import 'dart:async';

import 'package:flutter/material.dart';

import '../data/firestore/firestore_errors.dart';
import '../data/firestore/memory_shop_repository.dart';
import '../data/firestore/shop_repository.dart';
import '../data/mock/mock_data.dart';
import '../data/models/coverage.dart';
import '../data/models/menu.dart';
import '../data/models/order.dart';
import '../data/models/settings.dart';
import '../data/models/staff.dart';

/// One bar in the 7-day revenue chart.
@immutable
class DailyRevenue {
  const DailyRevenue({
    required this.day,
    required this.revenue,
    required this.orders,
  });

  final DateTime day;
  final num revenue;
  final int orders;
}

/// Menu item paired with units sold, for the best-sellers list.
@immutable
class ItemPerformance {
  const ItemPerformance({
    required this.itemId,
    required this.name,
    required this.unitsSold,
    required this.revenue,
  });

  final String itemId;
  final String name;
  final int unitsSold;
  final num revenue;
}

/// Everything the admin panel reads and writes.
///
/// Deliberately separate from [SessionProvider]: this holds the *shop's* view
/// of the world (every order, all stock, all staff), while the session holds
/// one customer's. Both are in-memory placeholders until Firestore replaces
/// them, at which point only this file and `catalog_provider.dart` change.
class AdminProvider extends ChangeNotifier {
  AdminProvider({ShopRepository? repository})
      : _repository = repository ?? MemoryShopRepository(),
        _orders = <Order>[...MockData.adminQueue, ...MockData.tradingHistory],
        _staff = List<StaffMember>.from(MockData.staff),
        _today = _startOfDay(DateTime.now());

  final ShopRepository _repository;
  StreamSubscription<AdminSnapshot>? _subscription;
  bool _bound = false;
  bool _loaded = false;
  WriteFailure? _failure;

  List<Order> _orders;
  List<StaffMember> _staff;
  DateTime _today;

  /// True once a live backend has answered.
  bool get isLive => _repository.isLive;

  bool get hasLoaded => _loaded;

  /// Subscribes to the repository. Idempotent.
  ///
  /// Called once the session resolves to an admin, not at startup: subscribing as
  /// a customer would put the order list and staff roster behind a rule that
  /// refuses the read, and the resulting PERMISSION_DENIED would look like a bug
  /// rather than the expected outcome.
  void bind() {
    if (_bound) return;
    _bound = true;

    _subscription = _repository.watchAdmin().listen(
      (AdminSnapshot snapshot) {
        // Guard against an empty first emission. A brand-new project returns four
        // empty collections, and replacing ₱16,085 of trading history with an
        // empty board would be a lie the operator cannot detect.
        if (snapshot.isEmpty) return;

        _orders = snapshot.orders;
        _staff = snapshot.staff;
        _settings = snapshot.settings;
        _loaded = true;
        notifyListeners();
      },
      onError: (Object error) {
        _failure = describeFailure('watch the shop', error);
        logWriteFailure(_failure!);
        notifyListeners();
      },
    );
  }

  /// The failure to show, and clears it.
  WriteFailure? consumeFailure() {
    final WriteFailure? failure = _failure;
    _failure = null;
    return failure;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _recordFailure(WriteFailure? failure) {
    if (failure == null) return;
    _failure = failure;
    logWriteFailure(failure);
    notifyListeners();
  }

  StoreSettings _settings = const StoreSettings(
    cafeName: 'Highlanders Coffee & Tea',
    address: 'Poblacion, Lumban, Laguna',
    isOpen: true,
    baseFee: 25,
    freeOver: 500,
    coverageRadiusKm: 10,
    opensAt: '7:00 AM',
    closesAt: '10:00 PM',
  );

  List<Order> get orders => _orders;
  List<StaffMember> get staff => _staff;
  StoreSettings get settings => _settings;

  DateTime get today => _today;

  // --- orders -------------------------------------------------------------

  /// Orders still moving through the pipeline.
  List<Order> get openOrders =>
      _orders.where((Order o) => o.status.isActive).toList(growable: false);

  List<Order> get settledOrders =>
      _orders.where((Order o) => o.status == OrderStatus.delivered).toList(growable: false);

  /// Orders placed on the selected day, newest first.
  List<Order> ordersOnDay(DateTime day) {
    final DateTime start = _startOfDay(day);
    final DateTime end = start.add(const Duration(days: 1));

    return _orders
        .where((Order o) =>
            !o.createdAt.isBefore(start) && o.createdAt.isBefore(end) &&
            o.status == OrderStatus.delivered)
        .toList(growable: false);
  }

  /// The pipeline, one step at a time.
  static const List<OrderStatus> pipeline = <OrderStatus>[
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.ready,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
  ];

  static String actionLabelFor(OrderStatus status) => switch (status) {
        OrderStatus.pending => 'Confirm order',
        OrderStatus.confirmed => 'Start preparing',
        OrderStatus.preparing => 'Mark ready',
        OrderStatus.ready => 'Hand to rider',
        OrderStatus.outForDelivery => 'Mark delivered',
        _ => 'Completed',
      };

  bool advanceOrder(String orderId) {
    final int i = _orders.indexWhere((Order o) => o.id == orderId);
    if (i < 0) return false;

    final int step = pipeline.indexOf(_orders[i].status);
    if (step < 0 || step == pipeline.length - 1) return false;

    final Order next = _copyWithStatus(_orders[i], pipeline[step + 1]);
    _orders = <Order>[..._orders]..[i] = next;
    notifyListeners();

    // `unawaited`: the caller is a button handler that must return a bool
    // synchronously for the UI's enabled/disabled logic. The write failure is
    // recorded instead of thrown — see _recordFailure.
    unawaited(_repository.saveOrder(next).then(_recordFailure));
    return true;
  }

  void cancelOrder(String orderId) {
    final int i = _orders.indexWhere((Order o) => o.id == orderId);
    if (i < 0) return;
    if (!_orders[i].status.isActive) return;

    final Order next = _copyWithStatus(_orders[i], OrderStatus.cancelled);
    _orders = <Order>[..._orders]..[i] = next;
    notifyListeners();
    unawaited(_repository.saveOrder(next).then(_recordFailure));
  }

  /// Reassigns a delivery to a rider.
  void assignDriver(String orderId, String driverName, String? phone) {
    final int i = _orders.indexWhere((Order o) => o.id == orderId);
    if (i < 0) return;

    final Order o = _orders[i];
    final Order next = _copyWithStatus(o, o.status, driver: driverName, phone: phone);
    _orders = <Order>[..._orders]..[i] = next;
    notifyListeners();
    unawaited(_repository.saveOrder(next).then(_recordFailure));
  }

  /// Deletes an order outright.
  ///
  /// Admin-only in the rules and only reachable from the order detail screen's
  /// destructive action. Exists because a cancelled order that was entered by
  /// mistake still sits in the pipeline forever otherwise.
  void deleteOrder(String orderId) {
    final int before = _orders.length;
    _orders = _orders.where((Order o) => o.id != orderId).toList(growable: false);
    if (_orders.length == before) return;
    notifyListeners();
    unawaited(_repository.deleteOrder(orderId).then(_recordFailure));
  }

  static Order _copyWithStatus(
    Order o,
    OrderStatus status, {
    String? driver,
    String? phone,
  }) =>
      Order(
        id: o.id,
        // Carried through every status change: the Firestore rules key customer
        // order reads on it, so dropping it here would make the order
        // unreachable from the app that placed it.
        customerUid: o.customerUid,
        lines: o.lines,
        status: status,
        fulfillment: o.fulfillment,
        paymentMethod: o.paymentMethod,
        createdAt: o.createdAt,
        subtotal: o.subtotal,
        deliveryFee: o.deliveryFee,
        distanceKm: o.distanceKm,
        address: o.address,
        customerName: o.customerName,
        pickupCode: o.pickupCode,
        driverName: driver ?? o.driverName,
        driverPhone: phone ?? o.driverPhone,
        paymentRef: o.paymentRef,
        promoCode: o.promoCode,
      );

  // --- staff --------------------------------------------------------------

  void setShift(String staffId, ShiftStatus shift) {
    final int i = _staff.indexWhere((StaffMember s) => s.id == staffId);
    if (i < 0) return;

    // `since` is stamped locally rather than in the serialiser, because the
    // client clock is the only one available at the moment the toggle is tapped.
    // A phone with a wrong clock produces a wrong shift start, which is a
    // cosmetic inaccuracy — better than refusing the write.
    final StaffMember next = _staff[i].copyWith(
      shift: shift,
      since: shift.isWorking ? DateTime.now() : null,
    );
    _staff = <StaffMember>[..._staff]..[i] = next;
    notifyListeners();
    unawaited(_repository.saveStaffMember(next).then(_recordFailure));
  }

  /// Flips a member between on-shift and off-shift.
  void toggleShift(String staffId) {
    final StaffMember? member = staffById(staffId);
    if (member == null) return;
    setShift(staffId, member.shift.isWorking ? ShiftStatus.offShift : ShiftStatus.onShift);
  }

  StaffMember? staffById(String id) {
    for (final StaffMember s in _staff) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<StaffMember> get onShift =>
      _staff.where((StaffMember s) => s.shift.isWorking).toList(growable: false);

  List<String> get riderNames => _staff
      .where((StaffMember s) => s.role == StaffRole.rider)
      .map((StaffMember s) => s.name)
      .toList(growable: false);

  // --- analytics ----------------------------------------------------------

  num get revenueToday => _sum(ordersOnDay(_today));

  num get revenueTotal => settledOrders.fold<num>(0, (num s, Order o) => s + o.total);

  int get ordersToday => ordersOnDay(_today).length;

  int get ordersTotal => settledOrders.length;

  /// Distinct customers who have ever ordered.
  int get activeUsers {
    final Set<String> seen = <String>{};
    for (final Order o in _orders) {
      final String? name = o.customerName;
      if (name != null && name.isNotEmpty) seen.add(name);
    }
    return seen.length;
  }

  num get averageOrderValue =>
      settledOrders.isEmpty ? 0 : revenueTotal / settledOrders.length;

  num get deliveryFeesToday =>
      ordersOnDay(_today).fold<num>(0, (num s, Order o) => s + o.deliveryFee);

  /// Cash collected in person, versus everything settled electronically.
  ({num cash, num electronic}) get paymentSplitForToday {
    final List<Order> today = ordersOnDay(_today);
    num cash = 0;
    num electronic = 0;

    for (final Order o in today) {
      if (o.paymentMethod == PaymentMethod.cash) {
        cash += o.total;
      } else {
        electronic += o.total;
      }
    }

    return (cash: cash, electronic: electronic);
  }

  /// Seven days of settled revenue, oldest first, so the chart reads
  /// left to right.
  List<DailyRevenue> get lastSevenDays {
    final List<DailyRevenue> series = <DailyRevenue>[];

    for (int i = 6; i >= 0; i--) {
      final DateTime day = _startOfDay(_today.subtract(Duration(days: i)));
      final List<Order> orders = ordersOnDay(day);

      series.add(
        DailyRevenue(
          day: day,
          revenue: _sum(orders),
          orders: orders.length,
        ),
      );
    }

    return series;
  }

  num get peakDailyRevenue {
    num peak = 0;
    for (final DailyRevenue d in lastSevenDays) {
      if (d.revenue > peak) peak = d.revenue;
    }
    return peak;
  }

  /// Best sellers across settled orders.
  List<ItemPerformance> topItems({int limit = 5}) {
    final Map<String, int> units = <String, int>{};
    final Map<String, num> revenue = <String, num>{};
    final Map<String, String> names = <String, String>{};

    for (final Order o in settledOrders) {
      for (final OrderLine line in o.lines) {
        units[line.itemId] = (units[line.itemId] ?? 0) + line.quantity;
        revenue[line.itemId] = (revenue[line.itemId] ?? 0) + line.lineTotal;
        names[line.itemId] = line.name;
      }
    }

    final List<ItemPerformance> rows = units.entries
        .map((MapEntry<String, int> e) => ItemPerformance(
              itemId: e.key,
              name: names[e.key] ?? e.key,
              unitsSold: e.value,
              revenue: revenue[e.key] ?? 0,
            ))
        .toList()
      ..sort((ItemPerformance a, ItemPerformance b) => b.unitsSold.compareTo(a.unitsSold));

    return rows.take(limit).toList(growable: false);
  }

  /// Items at or below their reorder level — the restock list.
  static List<MenuItem> needsRestock(List<MenuItem> items) => items
      .where((MenuItem i) => i.status != StockStatus.inStock)
      .toList(growable: false);

  // --- settings -----------------------------------------------------------

  void updateSettings(StoreSettings next) {
    _settings = next;
    notifyListeners();
    unawaited(_repository.saveSettings(next).then(_recordFailure));
  }

  /// Writes the mock catalogue and roster to the backend, once.
  ///
  /// Exposed as a button rather than a startup step on purpose. Seeding is
  /// irreversible — it writes 19 menu items, a staff roster and a block of trading
  /// history — and anything irreversible should require someone to mean it. The
  /// repository refuses if orders already exist, so a second tap does nothing
  /// rather than burying real history under mock data.
  ///
  /// Returns the failure, or null on success.
  Future<WriteFailure?> seedFromMock() async {
    if (!_repository.isLive) {
      return const WriteFailure(
        operation: 'seed',
        message: 'No backend configured, so there is nowhere to seed to.',
      );
    }

    final WriteFailure? failure = await _repository.seed(
      AdminSnapshot(
        // Every mock order carries a customerUid. `seed` skips any that does not,
        // so an unattributed order would be dropped silently — `mock_data_test`
        // asserts none exist, which turns that skip from a data-loss bug into a
        // test failure.
        orders: <Order>[...MockData.adminQueue, ...MockData.tradingHistory],
        staff: List<StaffMember>.from(MockData.staff),
        settings: _settings,
      ),
      CatalogSnapshot(
        items: List<MenuItem>.from(MockData.menu),
        categories: List<MenuCategory>.from(MockData.categories),
        promos: List<Promo>.from(MockData.promos),
        isOpen: _settings.isOpen,
        // Fee tiers are not in StoreSettings — they live in DeliveryPricing,
        // which the customer app owns. Seeding the document writes the settings
        // fields; the tier table itself still needs the café's real numbers
        // before it belongs in a document that overrides the bundled defaults.
        pricing: const DeliveryPricing(freeOver: 500),
      ),
    );

    _recordFailure(failure);
    return failure;
  }

  /// Moves the reporting day, used by the sales screen's date arrows.
  void shiftDay(int delta) {
    _today = _startOfDay(_today.add(Duration(days: delta)));
    notifyListeners();
  }

  void setToday(DateTime day) {
    _today = _startOfDay(day);
    notifyListeners();
  }

  static num _sum(List<Order> orders) =>
      orders.fold<num>(0, (num s, Order o) => s + o.total);

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
}