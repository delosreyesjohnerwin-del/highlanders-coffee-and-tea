import 'package:flutter/material.dart';

import '../data/mock/mock_data.dart';
import '../data/models/menu.dart';
import '../data/models/order.dart';
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

/// Store configuration owned by the admin.
@immutable
class StoreSettings {
  const StoreSettings({
    required this.cafeName,
    required this.address,
    required this.isOpen,
    required this.baseFee,
    required this.freeOver,
    required this.coverageRadiusKm,
    required this.opensAt,
    required this.closesAt,
  });

  final String cafeName;
  final String address;
  final bool isOpen;
  final num baseFee;
  final num freeOver;
  final double coverageRadiusKm;
  final String opensAt;
  final String closesAt;

  StoreSettings copyWith({
    String? cafeName,
    String? address,
    bool? isOpen,
    num? baseFee,
    num? freeOver,
    double? coverageRadiusKm,
    String? opensAt,
    String? closesAt,
  }) =>
      StoreSettings(
        cafeName: cafeName ?? this.cafeName,
        address: address ?? this.address,
        isOpen: isOpen ?? this.isOpen,
        baseFee: baseFee ?? this.baseFee,
        freeOver: freeOver ?? this.freeOver,
        coverageRadiusKm: coverageRadiusKm ?? this.coverageRadiusKm,
        opensAt: opensAt ?? this.opensAt,
        closesAt: closesAt ?? this.closesAt,
      );
}

/// Everything the admin panel reads and writes.
///
/// Deliberately separate from [SessionProvider]: this holds the *shop's* view
/// of the world (every order, all stock, all staff), while the session holds
/// one customer's. Both are in-memory placeholders until Firestore replaces
/// them, at which point only this file and `catalog_provider.dart` change.
class AdminProvider extends ChangeNotifier {
  AdminProvider()
      : _orders = <Order>[...MockData.adminQueue, ...MockData.tradingHistory],
        _staff = List<StaffMember>.from(MockData.staff),
        _today = _startOfDay(DateTime.now());

  List<Order> _orders;
  List<StaffMember> _staff;
  DateTime _today;

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

    _orders = <Order>[..._orders]..[i] = _copyWithStatus(_orders[i], pipeline[step + 1]);
    notifyListeners();
    return true;
  }

  void cancelOrder(String orderId) {
    final int i = _orders.indexWhere((Order o) => o.id == orderId);
    if (i < 0) return;
    if (!_orders[i].status.isActive) return;

    _orders = <Order>[..._orders]..[i] = _copyWithStatus(_orders[i], OrderStatus.cancelled);
    notifyListeners();
  }

  /// Reassigns a delivery to a rider.
  void assignDriver(String orderId, String driverName, String? phone) {
    final int i = _orders.indexWhere((Order o) => o.id == orderId);
    if (i < 0) return;

    final Order o = _orders[i];
    _orders = <Order>[..._orders]..[i] = _copyWithStatus(o, o.status, driver: driverName, phone: phone);
    notifyListeners();
  }

  static Order _copyWithStatus(
    Order o,
    OrderStatus status, {
    String? driver,
    String? phone,
  }) =>
      Order(
        id: o.id,
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

    _staff = <StaffMember>[..._staff]
      ..[i] = _staff[i].copyWith(
        shift: shift,
        since: shift.isWorking ? DateTime.now() : null,
      );
    notifyListeners();
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