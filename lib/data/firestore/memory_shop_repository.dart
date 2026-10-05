import 'dart:async';

import '../models/menu.dart';
import '../models/order.dart';
import '../models/settings.dart';
import '../models/staff.dart';
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
  }
}