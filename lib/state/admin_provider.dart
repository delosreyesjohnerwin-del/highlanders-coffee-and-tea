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
import '../data/models/shift_event.dart';
import '../data/models/staff.dart';
import '../services/in_app_alert.dart';
import '../services/staff_qr.dart';

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
  AdminProvider({ShopRepository? repository, InAppAlertPresenter? alerts})
      : _repository = repository ?? MemoryShopRepository(),
        _alerts = alerts ?? const NoopAlertPresenter(),
        _orders = <Order>[...MockData.adminQueue, ...MockData.tradingHistory],
        _staff = List<StaffMember>.from(MockData.staff),
        _today = _startOfDay(DateTime.now());

  final ShopRepository _repository;

  /// Where a change the café should notice becomes an in-app banner. The free
  /// path's replacement for a push: nothing sends to a closed app, so the app
  /// announces what its own live order stream shows it.
  final InAppAlertPresenter _alerts;

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

        // Diff before overwriting. The free notification path has no server
        // sender, so a new order is only ever noticed here — the café's own
        // order stream — and it must be announced before the list is replaced.
        final List<Order> previous = _orders;
        final bool firstLoad = !_loaded;

        _orders = snapshot.orders;
        _staff = snapshot.staff;
        _settings = snapshot.settings;
        _loaded = true;

        // The first live emission is the whole board, not a burst of new
        // orders. Announcing it would fire "new order" for all of history.
        if (!firstLoad) _announceNewOrders(previous, snapshot.orders);

        notifyListeners();
      },
      onError: (Object error) {
        _failure = describeFailure('watch the shop', error);
        logWriteFailure(_failure!);
        notifyListeners();
      },
    );
  }

  /// Shows a banner for the newest order the café had not seen yet.
  void _announceNewOrders(List<Order> previous, List<Order> next) {
    final List<Order> fresh = newOrdersBetween(previous, next);
    if (fresh.isEmpty) return;

    final String from = fresh.first.customerName?.trim() ?? '';
    _alerts.show(from.isEmpty ? 'New order received' : 'New order from $from');
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
    _showLocalInAppAlert(_orders[i], pipeline[step + 1]);
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
    _showLocalInAppAlert(_orders[i], next.status);
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
  }) {
    // Every progress write stamps a history event so the customer gets real
    // per-step timestamps. Undo-style writes with the *same* status (rider
    // reassignment) append nothing — the step did not happen again.
    final List<OrderStatusEvent> history = status == o.status
        ? o.statusHistory
        : <OrderStatusEvent>[
            ...o.statusHistory,
            OrderStatusEvent(status: status, at: DateTime.now()),
          ];

    return Order(
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
      updatedAt: o.updatedAt,
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
      statusHistory: history,
      trackingNumber: o.trackingNumber,
      carrierName: o.carrierName,
      carrierUrl: o.carrierUrl,
    );
  }

  void _showLocalInAppAlert(Order order, OrderStatus status) {
    _alerts.show(orderStatusCopy(status, order));
  }

  // --- staff --------------------------------------------------------------

  void setShift(String staffId, ShiftStatus shift, {ShiftEventMethod method = ShiftEventMethod.manual}) {
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
    _logShiftEvent(next, method);
  }

  /// Flips a member between on-shift and off-shift.
  void toggleShift(String staffId) {
    final StaffMember? member = staffById(staffId);
    if (member == null) return;
    setShift(staffId, member.shift.isWorking ? ShiftStatus.offShift : ShiftStatus.onShift);
  }

  /// Appends a clock-in/clock-out to the attendance log.
  ///
  /// The last timestamp handed to a shift event, so two clock actions in the
  /// same millisecond still get a strict order.
  ///
  /// The device clock is coarse enough that a scan and its immediate repeat can
  /// land on the identical instant, and a history sorted on `at` alone then has
  /// no defined order — the clock-out can appear above the clock-in. Nudging the
  /// stamp forward by a microsecond keeps the log monotonic and the timeline
  /// readable, at a resolution no one can perceive.
  DateTime _lastShiftEventAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// A strictly increasing event timestamp.
  DateTime _nextShiftEventAt() {
    final DateTime now = DateTime.now();
    final DateTime next = now.isAfter(_lastShiftEventAt)
        ? now
        : _lastShiftEventAt.add(const Duration(microseconds: 1));
    _lastShiftEventAt = next;
    return next;
  }

  /// Written after the shift itself, and best-effort like every other write: a
  /// failed history entry must not appear to fail the clock-in the operator just
  /// watched succeed.
  void _logShiftEvent(StaffMember member, ShiftEventMethod method) {
    final ShiftEvent event = ShiftEvent(
      id: mintShiftEventId(),
      staffId: member.id,
      staffName: member.name,
      type: member.shift.isWorking ? ShiftEventType.clockIn : ShiftEventType.clockOut,
      at: _nextShiftEventAt(),
      method: method,
    );
    unawaited(_repository.saveShiftEvent(event).then(_recordFailure));
  }

  // --- staff badges -------------------------------------------------------

  /// Gives [staffId] a badge token if they do not already have one.
  ///
  /// Lazy rather than a migration: a roster seeded before badges existed still
  /// has valid staff with no token, and backfilling every document on first
  /// launch would be a write storm for a feature nobody has opened. Called from
  /// the badge widget, once, the first time it is built.
  Future<void> ensureStaffQr(String staffId) async {
    final int i = _staff.indexWhere((StaffMember s) => s.id == staffId);
    if (i < 0) return;
    final String? existing = _staff[i].qrToken;
    if (existing != null && existing.isNotEmpty) return;

    await _mintStaffQr(i);
  }

  /// Issues a brand-new token, invalidating any badge already printed.
  Future<void> regenerateStaffQr(String staffId) async {
    final int i = _staff.indexWhere((StaffMember s) => s.id == staffId);
    if (i < 0) return;

    await _mintStaffQr(i);
  }

  Future<void> _mintStaffQr(int index) async {
    final StaffMember next = _staff[index].copyWith(
      qrToken: mintStaffToken(),
      qrIssuedAt: DateTime.now(),
    );
    _staff = <StaffMember>[..._staff]..[index] = next;
    notifyListeners();
    final WriteFailure? failure = await _repository.saveStaffMember(next);
    _recordFailure(failure);
  }

  /// Resolves a scanned badge to a clock action.
  ///
  /// Verifies against the locally streamed roster, so the kiosk needs no extra
  /// read and keeps working on a café's flaky connection. A successful clock
  /// toggles the member between on-shift and off-shift, which is the whole point
  /// of a single shared scanner: scan on the way in, scan on the way out.
  StaffClockResult clockByToken(String raw) {
    final StaffQrPayload? payload = parseStaffQr(raw);
    if (payload == null) {
      return const StaffClockResult(StaffClockOutcome.notABadge);
    }

    final StaffMember? member = staffById(payload.staffId);
    if (member == null) {
      return const StaffClockResult(StaffClockOutcome.unknownStaff);
    }
    if (!verifyStaffToken(member, payload.token)) {
      return const StaffClockResult(StaffClockOutcome.staleBadge);
    }

    final bool nowWorking = !member.shift.isWorking;
    setShift(member.id, nowWorking ? ShiftStatus.onShift : ShiftStatus.offShift,
        method: ShiftEventMethod.qr);

    return StaffClockResult(
      nowWorking ? StaffClockOutcome.clockedIn : StaffClockOutcome.clockedOut,
      staffName: member.name,
      at: DateTime.now(),
    );
  }

  /// One member's recent attendance, newest first.
  Future<List<ShiftEvent>> loadShiftEvents(String staffId, {int limit = 20}) =>
      _repository.loadShiftEvents(staffId, limit: limit);

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