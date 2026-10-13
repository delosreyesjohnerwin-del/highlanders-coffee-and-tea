import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/menu.dart';
import '../models/order.dart';
import '../models/payment.dart';
import '../models/settings.dart';
import '../models/shift_event.dart';
import '../models/staff.dart';
import '../models/staff_record.dart';
import 'firestore_errors.dart';
import 'shop_repository.dart';

/// The no-backend [ShopRepository].
///
/// This is the default. It exists for two reasons, and the second is the
/// important one:
///
///  1. The app must run — and be demonstrable — before `google-services.json`
///     exists. `FirebaseBootstrap` stays false and this takes over.
///  2. Every screen test mounts the app with no emulator behind it. Pointing the
///     providers here means the widget tests exercise the same provider code
///     production does, rather than a special test-only path.
///
/// Writes are accepted and applied in memory. That is honest about what it is:
/// [isLive] is false, the UI says so, and the next launch starts from the seed
/// again. It is not pretending to persist.
class MemoryShopRepository implements ShopRepository {
  MemoryShopRepository({
    CatalogSnapshot? catalog,
    AdminSnapshot? admin,
  })  : _catalog = catalog ?? const CatalogSnapshot.empty(),
        _admin = admin ?? const AdminSnapshot.empty();

  CatalogSnapshot _catalog;
  AdminSnapshot _admin;

  final StreamController<CatalogSnapshot> _catalogController =
      StreamController<CatalogSnapshot>.broadcast();
  final StreamController<AdminSnapshot> _adminController =
      StreamController<AdminSnapshot>.broadcast();

  /// When true, every write reports a failure.
  ///
  /// For tests that need the "your edit did not save" path without taking
  /// Firestore offline.
  bool failWrites = false;

  @override
  bool get isLive => false;

  WriteFailure? _maybeFail(String operation) =>
      failWrites ? WriteFailure(operation: operation, message: 'Simulated write failure.') : null;

  // --- catalog ------------------------------------------------------------

  @override
  Future<CatalogSnapshot> loadCatalog() async => _catalog;

  @override
  Stream<CatalogSnapshot> watchCatalog() => _catalogController.stream;

  @override
  Future<WriteFailure?> saveMenuItem(MenuItem item) async {
    if (failWrites) return _maybeFail('save menu item ${item.name}');

    final List<MenuItem> items = <MenuItem>[
      for (final MenuItem i in _catalog.items)
        if (i.id == item.id) item else i,
    ];
    if (!items.any((MenuItem i) => i.id == item.id)) items.add(item);

    _catalog = CatalogSnapshot(
      items: items,
      categories: _catalog.categories,
      promos: _catalog.promos,
      isOpen: _catalog.isOpen,
      pricing: _catalog.pricing,
    );
    _catalogController.add(_catalog);
    return null;
  }

  @override
  Future<WriteFailure?> deleteMenuItem(String id) async {
    if (failWrites) return _maybeFail('delete menu item $id');

    _catalog = CatalogSnapshot(
      items: _catalog.items.where((MenuItem i) => i.id != id).toList(growable: false),
      categories: _catalog.categories,
      promos: _catalog.promos,
      isOpen: _catalog.isOpen,
      pricing: _catalog.pricing,
    );
    _catalogController.add(_catalog);
    return null;
  }

  @override
  Future<WriteFailure?> saveCategory(MenuCategory category) async {
    if (failWrites) return _maybeFail('save category ${category.label}');

    final List<MenuCategory> categories = <MenuCategory>[
      for (final MenuCategory c in _catalog.categories)
        if (c.id == category.id) category else c,
    ];
    if (!categories.any((MenuCategory c) => c.id == category.id)) categories.add(category);

    _catalog = CatalogSnapshot(
      items: _catalog.items,
      categories: categories,
      promos: _catalog.promos,
      isOpen: _catalog.isOpen,
      pricing: _catalog.pricing,
    );
    _catalogController.add(_catalog);
    return null;
  }

  @override
  Future<WriteFailure?> savePromo(Promo promo) async {
    if (failWrites) return _maybeFail('save promo ${promo.code}');

    _catalog = CatalogSnapshot(
      items: _catalog.items,
      categories: _catalog.categories,
      promos: <Promo>[
        for (final Promo p in _catalog.promos)
          if (p.code == promo.code) promo else p,
        if (!_catalog.promos.any((Promo p) => p.code == promo.code)) promo,
      ],
      isOpen: _catalog.isOpen,
      pricing: _catalog.pricing,
    );
    _catalogController.add(_catalog);
    return null;
  }

  @override
  Future<WriteFailure?> deletePromo(String code) async {
    if (failWrites) return _maybeFail('delete promo $code');

    final int before = _catalog.promos.length;
    _catalog = CatalogSnapshot(
      items: _catalog.items,
      categories: _catalog.categories,
      promos: _catalog.promos
          .where((Promo p) => p.code != code)
          .toList(growable: false),
      isOpen: _catalog.isOpen,
      pricing: _catalog.pricing,
    );
    if (_catalog.promos.length == before) return null;

    _catalogController.add(_catalog);
    return null;
  }

  // --- admin --------------------------------------------------------------

  @override
  Future<AdminSnapshot> loadAdmin() async => _admin;

  @override
  Stream<AdminSnapshot> watchAdmin() => _adminController.stream;

  @override
  Future<WriteFailure?> saveOrder(Order order) async {
    if (failWrites) return _maybeFail('save order ${order.id}');
    if (order.customerUid.isEmpty) {
      return const WriteFailure(
        operation: 'save order',
        message: 'This order is not attributed to a customer, so it cannot be saved.',
      );
    }

    _admin = AdminSnapshot(
      orders: <Order>[
        for (final Order o in _admin.orders)
          if (o.id == order.id) order else o,
        if (!_admin.orders.any((Order o) => o.id == order.id)) order,
      ],
      staff: _admin.staff,
      settings: _admin.settings,
    );
    _adminController.add(_admin);
    return null;
  }

  @override
  Future<WriteFailure?> deleteOrder(String id) async {
    if (failWrites) return _maybeFail('delete order $id');

    _admin = AdminSnapshot(
      orders: _admin.orders.where((Order o) => o.id != id).toList(growable: false),
      staff: _admin.staff,
      settings: _admin.settings,
    );
    _adminController.add(_admin);
    return null;
  }

  @override
  Future<WriteFailure?> saveStaffMember(StaffMember member) async {
    if (failWrites) return _maybeFail('save staff member ${member.name}');

    _admin = AdminSnapshot(
      orders: _admin.orders,
      staff: <StaffMember>[
        for (final StaffMember s in _admin.staff)
          if (s.id == member.id) member else s,
        if (!_admin.staff.any((StaffMember s) => s.id == member.id)) member,
      ],
      settings: _admin.settings,
    );
    _adminController.add(_admin);
    return null;
  }

  @override
  Future<WriteFailure?> deleteStaffMember(String id) async {
    if (failWrites) return _maybeFail('delete staff member $id');

    _admin = AdminSnapshot(
      orders: _admin.orders,
      staff: _admin.staff.where((StaffMember s) => s.id != id).toList(growable: false),
      settings: _admin.settings,
    );
    _adminController.add(_admin);
    return null;
  }

  /// Attendance log, namespaced by staff id. Kept out of [AdminSnapshot]
  /// deliberately: it is loaded per member on demand, not streamed as part of
  /// the board.
  final Map<String, List<ShiftEvent>> _shiftEventsByStaff = <String, List<ShiftEvent>>{};

  @override
  Future<WriteFailure?> saveShiftEvent(ShiftEvent event) async {
    if (failWrites) return _maybeFail('log shift for ${event.staffName}');

    final List<ShiftEvent> existing = _shiftEventsByStaff[event.staffId] ?? <ShiftEvent>[];
    _shiftEventsByStaff[event.staffId] = <ShiftEvent>[
      for (final ShiftEvent e in existing)
        if (e.id == event.id) event else e,
      if (!existing.any((ShiftEvent e) => e.id == event.id)) event,
    ];
    return null;
  }

  @override
  Future<List<ShiftEvent>> loadShiftEvents(String staffId, {int limit = 20}) async {
    final List<ShiftEvent> events =
        List<ShiftEvent>.from(_shiftEventsByStaff[staffId] ?? const <ShiftEvent>[])
          ..sort((ShiftEvent a, ShiftEvent b) => b.at.compareTo(a.at));
    return events.take(limit).toList(growable: false);
  }

  /// Attendance sessions, newest first. Kept out of [AdminSnapshot] like the
  /// transition log: the record table streams it on its own.
  final List<StaffRecord> _staffRecords = <StaffRecord>[];
  final StreamController<List<StaffRecord>> _staffRecordsController =
      StreamController<List<StaffRecord>>.broadcast();

  /// Newest first, so both the stream and the one-shot read agree on order.
  List<StaffRecord> _sortedStaffRecords() => List<StaffRecord>.from(_staffRecords)
    ..sort((StaffRecord a, StaffRecord b) => b.timeIn.compareTo(a.timeIn));

  @override
  Stream<List<StaffRecord>> watchStaffRecords() => _staffRecordsController.stream;

  @override
  Future<List<StaffRecord>> loadStaffRecords() async =>
      List<StaffRecord>.unmodifiable(_sortedStaffRecords());

  @override
  Future<WriteFailure?> saveStaffRecord(StaffRecord record) async {
    if (failWrites) return _maybeFail('save staff record for ${record.staffName}');

    final int i = _staffRecords.indexWhere((StaffRecord r) => r.id == record.id);
    if (i >= 0) {
      _staffRecords[i] = record;
    } else {
      _staffRecords.add(record);
    }
    _staffRecordsController.add(_sortedStaffRecords());
    return null;
  }

  // --- settings -----------------------------------------------------------

  @override
  Future<StoreSettings> loadSettings() async => _admin.settings;

  @override
  Future<WriteFailure?> saveSettings(StoreSettings settings) async {
    if (failWrites) return _maybeFail('save shop settings');

    _admin = AdminSnapshot(
      orders: _admin.orders,
      staff: _admin.staff,
      settings: settings,
    );
    _adminController.add(_admin);
    // Settings feed the customer-facing catalog too (open state, fee schedule),
    // so the catalog stream is the one the shop's banner listens to.
    _catalog = CatalogSnapshot(
      items: _catalog.items,
      categories: _catalog.categories,
      promos: _catalog.promos,
      isOpen: settings.isOpen,
      pricing: _catalog.pricing,
    );
    _catalogController.add(_catalog);
    return null;
  }

  // --- customer -----------------------------------------------------------

  final Map<String, List<Order>> _ordersByUid = <String, List<Order>>{};
  final Map<String, List<SavedAddress>> _addressesByUid = <String, List<SavedAddress>>{};
  final Map<String, List<PaymentAccount>> _paymentAccountsByUid = <String, List<PaymentAccount>>{};
  final Map<String, Set<String>> _tokensByUid = <String, Set<String>>{};

  @override
  Future<WriteFailure?> createOrder(Order order) async {
    if (failWrites) return _maybeFail('place order ${order.id}');
    if (order.customerUid.isEmpty) {
      return const WriteFailure(
        operation: 'place order',
        message: 'Sign in before placing an order.',
      );
    }

    final List<Order> existing = _ordersByUid[order.customerUid] ?? <Order>[];
    _ordersByUid[order.customerUid] = <Order>[
      for (final Order o in existing)
        if (o.id == order.id) order else o,
      if (!existing.any((Order o) => o.id == order.id)) order,
    ];
    return null;
  }

  @override
  Future<List<Order>> loadOrdersFor(String uid) async =>
      List<Order>.unmodifiable(_ordersByUid[uid] ?? const <Order>[]);

  @override
  Stream<List<Order>> watchOrdersFor(String uid) =>
      Stream<List<Order>>.value(List<Order>.unmodifiable(_ordersByUid[uid] ?? const <Order>[]));

  @override
  Future<WriteFailure?> saveAddress(String uid, SavedAddress address) async {
    if (failWrites) return _maybeFail('save address ${address.label}');

    final List<SavedAddress> existing = _addressesByUid[uid] ?? <SavedAddress>[];
    _addressesByUid[uid] = <SavedAddress>[
      for (final SavedAddress a in existing)
        if (a.id == address.id) address else a,
      if (!existing.any((SavedAddress a) => a.id == address.id)) address,
    ];
    return null;
  }

  @override
  Future<WriteFailure?> deleteAddress(String uid, String addressId) async {
    if (failWrites) return _maybeFail('delete address $addressId');

    _addressesByUid[uid] = (_addressesByUid[uid] ?? <SavedAddress>[])
        .where((SavedAddress a) => a.id != addressId)
        .toList(growable: false);
    return null;
  }

  @override
  Future<List<SavedAddress>> loadAddresses(String uid) async =>
      List<SavedAddress>.unmodifiable(_addressesByUid[uid] ?? const <SavedAddress>[]);

  @override
  Stream<List<SavedAddress>> watchAddresses(String uid) => Stream<List<SavedAddress>>.value(
        List<SavedAddress>.unmodifiable(_addressesByUid[uid] ?? const <SavedAddress>[]),
      );

  @override
  Future<WriteFailure?> savePaymentAccount(String uid, PaymentAccount account) async {
    if (failWrites) return _maybeFail('save payment method ${account.network.label}');

    final List<PaymentAccount> existing = _paymentAccountsByUid[uid] ?? <PaymentAccount>[];
    _paymentAccountsByUid[uid] = <PaymentAccount>[
      for (final PaymentAccount a in existing)
        if (a.id == account.id) account else a,
      if (!existing.any((PaymentAccount a) => a.id == account.id)) account,
    ];
    return null;
  }

  @override
  Future<WriteFailure?> deletePaymentAccount(String uid, String accountId) async {
    if (failWrites) return _maybeFail('delete payment method $accountId');

    _paymentAccountsByUid[uid] = (_paymentAccountsByUid[uid] ?? <PaymentAccount>[])
        .where((PaymentAccount a) => a.id != accountId)
        .toList(growable: false);
    return null;
  }

  @override
  Future<List<PaymentAccount>> loadPaymentAccounts(String uid) async =>
      List<PaymentAccount>.unmodifiable(_paymentAccountsByUid[uid] ?? const <PaymentAccount>[]);

  @override
  Stream<List<PaymentAccount>> watchPaymentAccounts(String uid) =>
      Stream<List<PaymentAccount>>.value(
        List<PaymentAccount>.unmodifiable(_paymentAccountsByUid[uid] ?? const <PaymentAccount>[]),
      );

  @override
  Future<WriteFailure?> saveNotificationToken(String uid, String token) async {
    if (failWrites) return _maybeFail('register device for notifications');

    // One registration per device token. Firestore keys the document by the
    // token itself, so a second account signing in on the same phone rewrites
    // the uid in place — mirror that by moving the token between uids rather
    // than leaving copies behind.
    for (final MapEntry<String, Set<String>> entry in _tokensByUid.entries) {
      if (entry.key != uid) entry.value.remove(token);
    }
    _tokensByUid.putIfAbsent(uid, () => <String>{}).add(token);
    return null;
  }

  @override
  Future<WriteFailure?> deleteNotificationToken(String uid, String token) async {
    if (failWrites) return _maybeFail('unregister device for notifications');

    _tokensByUid[uid]?.remove(token);
    return null;
  }

  /// Tokens registered for [uid]. The app never reads tokens back, so this is
  /// only for tests and diagnostics.
  @visibleForTesting
  Set<String> registeredTokens(String uid) =>
      Set<String>.unmodifiable(_tokensByUid[uid] ?? const <String>{});

  // --- seed ---------------------------------------------------------------

  @override
  Future<WriteFailure?> seed(AdminSnapshot admin, CatalogSnapshot catalog) async {
    if (failWrites) return _maybeFail('seed shop data');

    _admin = admin;
    _catalog = catalog;
    _adminController.add(_admin);
    _catalogController.add(_catalog);
    return null;
  }

  /// Releases both controllers. Tests must call this or the isolate complains.
  Future<void> dispose() async {
    await _catalogController.close();
    await _adminController.close();
    await _staffRecordsController.close();
  }
}