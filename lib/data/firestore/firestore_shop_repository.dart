// `Order` is hidden because `cloud_firestore` exports its own `Order` (a query
// ordering enum). The domain model wins here — this file is about shop orders,
// and qualifying every use as `models.Order` would be worse than one import
// clause.
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../models/coverage.dart';
import '../models/menu.dart';
import '../models/order.dart';
import '../models/settings.dart';
import '../models/staff.dart';
import 'firestore_errors.dart';
import 'firestore_paths.dart';
import 'serialisation.dart';
import 'shop_repository.dart';
import 'stream_zip.dart';

/// The real [ShopRepository], backed by Cloud Firestore.
///
/// ## Why no converters
///
/// Documents are converted with the hand-written `toMap`/`fromMap` pairs in
/// `serialisation.dart` rather than `withConverter`. Converters would throw on
/// an unparseable field, and one bad order document taken from a partially
/// written batch would then take the whole admin panel down. Here a bad
/// document degrades to a default-valued order instead.
///
/// ## Ordering
///
/// Firestore orders by a field that exists on every document. `createdAt` is
/// stored as an ISO-8601 *string*, and ISO-8601 sorts lexicographically in the
/// same order it sorts chronologically — provided every writer agrees on
/// timezone. `serialisation.dart` always writes UTC, and readers convert back to
/// local, so the sort holds across the device's timezone. It does not hold for
/// a document written by hand in local time, which is why `fromMap` also sorts
/// client-side as a safety net.
class FirestoreShopRepository implements ShopRepository {
  FirestoreShopRepository({FirebaseFirestore? firestore}) : _injected = firestore;

  final FirebaseFirestore? _injected;

  /// `FirebaseFirestore.instance` throws when no default app exists, so the
  /// accessor is lazy and the caller is responsible for only constructing this
  /// class after [FirebaseBootstrap.ensureInitialized] has succeeded.
  FirebaseFirestore get _db => _injected ?? FirebaseFirestore.instance;

  @override
  bool get isLive => true;

  // --- helpers ------------------------------------------------------------

  /// Runs [body], converting a throw into a [WriteFailure].
  ///
  /// The `operation` string is written for the person who will read the toast,
  /// not for the log: "mark order HL-2601-6372 delivered" tells them which tap
  /// failed, which the exception's own message never does.
  Future<WriteFailure?> _guard(String operation, Future<void> Function() body) async {
    try {
      await body();
      return null;
    } catch (error) {
      final WriteFailure failure = describeFailure(operation, error);
      logWriteFailure(failure);
      return failure;
    }
  }

  CollectionReference<Map<String, dynamic>> _collection(String name) =>
      _db.collection(name);

  // --- catalog reads ------------------------------------------------------

  @override
  Future<CatalogSnapshot> loadCatalog() async {
    // Three reads in parallel. Sequential would cost three round trips instead
    // of one, which on a phone in a weak-signal town is the difference between
    // the menu appearing and a spinner.
    final List<QuerySnapshot<Map<String, dynamic>>> results = await Future.wait(<Future<QuerySnapshot<Map<String, dynamic>>>>[
      _collection(FirestorePaths.menuItems).get(),
      _collection(FirestorePaths.menuCategories).get(),
      _collection(FirestorePaths.promos).get(),
    ]);

    final DocumentSnapshot<Map<String, dynamic>> settings =
        await _collection(FirestorePaths.settings).doc(FirestorePaths.settingsDoc).get();

    return _catalogFrom(
      results[0],
      results[1],
      results[2],
      settings.exists ? settings.data() : null,
    );
  }

  @override
  Stream<CatalogSnapshot> watchCatalog() {
    // Four streams, one emission: the panel repaints when any one changes, and
    // never paints before all four have produced a first value.
    return zip4<List<MenuItem>, List<MenuCategory>, List<Promo>, StoreSettings?, CatalogSnapshot>(
      _items(),
      _categories(),
      _promos(),
      _settings(),
      _catalogFromLists,
    );
  }

  CatalogSnapshot _catalogFrom(
    QuerySnapshot<Map<String, dynamic>> items,
    QuerySnapshot<Map<String, dynamic>> categories,
    QuerySnapshot<Map<String, dynamic>> promos,
    Map<String, dynamic>? settings,
  ) =>
      _catalogFromLists(
        items.docs.map((DocumentSnapshot<Map<String, dynamic>> d) =>
            MenuItemSerialisation.fromMap(d.data(), d.id)),
        categories.docs.map((DocumentSnapshot<Map<String, dynamic>> d) =>
            MenuCategorySerialisation.fromMap(d.data(), d.id)),
        promos.docs.map((DocumentSnapshot<Map<String, dynamic>> d) =>
            PromoSerialisation.fromMap(d.data(), d.id)),
        settings == null ? null : StoreSettingsSerialisation.fromMap(settings),
      );

  CatalogSnapshot _catalogFromLists(
    Iterable<MenuItem> items,
    Iterable<MenuCategory> categories,
    Iterable<Promo> promos,
    StoreSettings? settings,
  ) =>
      CatalogSnapshot(
        items: items.toList(growable: false),
        // Categories drive the tab order, so they sort here rather than relying
        // on document id. An admin reordering a tab is a `sortOrder` change, not
        // a rename.
        categories: (categories.toList()
              ..sort((MenuCategory a, MenuCategory b) => a.sortOrder.compareTo(b.sortOrder)))
            .toList(growable: false),
        promos: promos.toList(growable: false),
        isOpen: settings?.isOpen ?? true,
        pricing: settings == null
            ? const DeliveryPricing()
            : DeliveryPricing(
                freeOver: settings.freeOver == 0 ? null : settings.freeOver,
                coverableMaxKm: settings.coverageRadiusKm,
              ),
      );

  Stream<List<MenuItem>> _items() => _collection(FirestorePaths.menuItems)
      .orderBy('sortOrder')
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> s) => s.docs
          .map((DocumentSnapshot<Map<String, dynamic>> d) =>
              MenuItemSerialisation.fromMap(d.data(), d.id))
          .toList(growable: false));

  Stream<List<MenuCategory>> _categories() => _collection(FirestorePaths.menuCategories)
      .orderBy('sortOrder')
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> s) => s.docs
          .map((DocumentSnapshot<Map<String, dynamic>> d) =>
              MenuCategorySerialisation.fromMap(d.data(), d.id))
          .toList(growable: false));

  Stream<List<Promo>> _promos() => _collection(FirestorePaths.promos)
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> s) => s.docs
          .map((DocumentSnapshot<Map<String, dynamic>> d) =>
              PromoSerialisation.fromMap(d.data(), d.id))
          .toList(growable: false));

  Stream<StoreSettings?> _settings() =>
      _collection(FirestorePaths.settings).doc(FirestorePaths.settingsDoc).snapshots().map(
            (DocumentSnapshot<Map<String, dynamic>> d) =>
                d.exists ? StoreSettingsSerialisation.fromMap(d.data()) : null,
          );

  // --- catalog writes -----------------------------------------------------

  @override
  Future<WriteFailure?> saveMenuItem(MenuItem item) => _guard(
        'save menu item ${item.name}',
        () => _collection(FirestorePaths.menuItems).doc(item.id).set(item.toMap()),
      );

  @override
  Future<WriteFailure?> deleteMenuItem(String id) => _guard(
        'delete menu item $id',
        () => _collection(FirestorePaths.menuItems).doc(id).delete(),
      );

  @override
  Future<WriteFailure?> saveCategory(MenuCategory category) => _guard(
        'save category ${category.label}',
        () =>
            _collection(FirestorePaths.menuCategories).doc(category.id).set(category.toMap()),
      );

  @override
  Future<WriteFailure?> savePromo(Promo promo) => _guard(
        'save promo ${promo.code}',
        () => _collection(FirestorePaths.promos).doc(PromoSerialisation.idOf(promo)).set(promo.toMap()),
      );

  // --- admin reads --------------------------------------------------------

  @override
  Future<AdminSnapshot> loadAdmin() async {
    final List<Object> results = await Future.wait(<Future<Object>>[
      _collection(FirestorePaths.orders).get(),
      _collection(FirestorePaths.staffMembers).get(),
      _collection(FirestorePaths.settings).doc(FirestorePaths.settingsDoc).get(),
    ]);

    final QuerySnapshot<Map<String, dynamic>> orders =
        results[0] as QuerySnapshot<Map<String, dynamic>>;
    final QuerySnapshot<Map<String, dynamic>> staff =
        results[1] as QuerySnapshot<Map<String, dynamic>>;
    final DocumentSnapshot<Map<String, dynamic>> settings =
        results[2] as DocumentSnapshot<Map<String, dynamic>>;

    return AdminSnapshot(
      orders: orders.docs.map(_orderFrom).toList(growable: false),
      staff: staff.docs
          .map((DocumentSnapshot<Map<String, dynamic>> d) =>
              StaffMemberSerialisation.fromMap(d.data(), d.id))
          .toList(growable: false),
      settings: settings.exists
          ? StoreSettingsSerialisation.fromMap(settings.data())
          : AdminSnapshot.defaultSettings,
    );
  }

  @override
  Stream<AdminSnapshot> watchAdmin() =>
      zip3<List<Order>, List<StaffMember>, StoreSettings?, AdminSnapshot>(
        _orders(),
        _staff(),
        _settings(),
        (List<Order> orders, List<StaffMember> staff, StoreSettings? settings) => AdminSnapshot(
          orders: orders,
          staff: staff,
          settings: settings ?? AdminSnapshot.defaultSettings,
        ),
      );

  /// Sort key.
  ///
  /// See the class doc: ISO-8601 UTC strings sort chronologically. The list is
  /// re-sorted by parsed `createdAt` anyway, because a document written by hand
  /// in local time would otherwise misorder the queue.
  static const String orderSortField = 'createdAt';

  Stream<List<Order>> _orders() => _collection(FirestorePaths.orders)
      .orderBy(orderSortField, descending: true)
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> s) {
        final List<Order> list = s.docs.map(_orderFrom).toList();
        list.sort((Order a, Order b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  Order _orderFrom(DocumentSnapshot<Map<String, dynamic>> d) =>
      OrderSerialisation.fromMap(d.data(), d.id);

  Stream<List<StaffMember>> _staff() => _collection(FirestorePaths.staffMembers)
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> s) => s.docs
          .map((DocumentSnapshot<Map<String, dynamic>> d) =>
              StaffMemberSerialisation.fromMap(d.data(), d.id))
          .toList(growable: false));

  // --- admin writes -------------------------------------------------------

  @override
  Future<WriteFailure?> saveOrder(Order order) {
    if (order.customerUid.isEmpty) {
      // Caught here rather than at the server: the rules would reject it, but
      // the message would be `permission-denied` on an order the admin did not
      // create, which reads like a permissions bug rather than "this order has
      // no owner".
      return Future<WriteFailure?>.value(
        const WriteFailure(
          operation: 'save order',
          message: 'This order is not attributed to a customer, so it cannot be saved.',
        ),
      );
    }

    return _guard(
      'save order ${order.id}',
      () => _collection(FirestorePaths.orders).doc(order.id).set(order.toMap()),
    );
  }

  @override
  Future<WriteFailure?> deleteOrder(String id) => _guard(
        'delete order $id',
        () => _collection(FirestorePaths.orders).doc(id).delete(),
      );

  @override
  Future<WriteFailure?> saveStaffMember(StaffMember member) => _guard(
        'save staff member ${member.name}',
        () => _collection(FirestorePaths.staffMembers)
            .doc(FirestorePaths.staffDoc(member.id))
            .set(member.toMap()),
      );

  @override
  Future<WriteFailure?> deleteStaffMember(String id) => _guard(
        'delete staff member $id',
        () => _collection(FirestorePaths.staffMembers).doc(FirestorePaths.staffDoc(id)).delete(),
      );

  // --- settings -----------------------------------------------------------

  @override
  Future<StoreSettings> loadSettings() async {
    final DocumentSnapshot<Map<String, dynamic>> doc = await _collection(FirestorePaths.settings)
        .doc(FirestorePaths.settingsDoc)
        .get();
    return doc.exists
        ? StoreSettingsSerialisation.fromMap(doc.data())
        : AdminSnapshot.defaultSettings;
  }

  @override
  Future<WriteFailure?> saveSettings(StoreSettings settings) => _guard(
        'save shop settings',
        () => _collection(FirestorePaths.settings)
            .doc(FirestorePaths.settingsDoc)
            .set(settings.toMap()),
      );

  // --- customer -----------------------------------------------------------

  @override
  Future<WriteFailure?> createOrder(Order order) => _guard(
        'place order ${order.id}',
        () => _collection(FirestorePaths.orders).doc(order.id).set(order.toMap()),
      );

  @override
  Future<List<Order>> loadOrdersFor(String uid) async {
    // The `where` is not optional. The `list` rule is evaluated per document
    // the query *would* return, so omitting the filter makes Firestore evaluate
    // the rule against other customers' orders and refuse the whole query.
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _collection(FirestorePaths.orders)
        .where('customerUid', isEqualTo: uid)
        .orderBy(orderSortField, descending: true)
        .get();

    final List<Order> list = snapshot.docs.map(_orderFrom).toList();
    list.sort((Order a, Order b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Stream<List<Order>> watchOrdersFor(String uid) => _collection(FirestorePaths.orders)
      .where('customerUid', isEqualTo: uid)
      .orderBy(orderSortField, descending: true)
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> s) {
        final List<Order> list = s.docs.map(_orderFrom).toList();
        list.sort((Order a, Order b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  @override
  Future<WriteFailure?> saveAddress(String uid, SavedAddress address) => _guard(
        'save address ${address.label}',
        () => _collection(FirestorePaths.addresses)
            .doc(FirestorePaths.addressDoc(uid, address.id))
            .set(address.toMap(uid: uid)),
      );

  @override
  Future<WriteFailure?> deleteAddress(String uid, String addressId) => _guard(
        'delete address $addressId',
        () => _collection(FirestorePaths.addresses)
            .doc(FirestorePaths.addressDoc(uid, addressId))
            .delete(),
      );

  @override
  Future<List<SavedAddress>> loadAddresses(String uid) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot =
        await _collection(FirestorePaths.addresses).where('uid', isEqualTo: uid).get();
    return snapshot.docs
        .map((DocumentSnapshot<Map<String, dynamic>> d) =>
            SavedAddressSerialisation.fromMap(d.data(), d.id))
        .toList(growable: false);
  }

  @override
  Stream<List<SavedAddress>> watchAddresses(String uid) => _collection(FirestorePaths.addresses)
      .where('uid', isEqualTo: uid)
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> s) => s.docs
          .map((DocumentSnapshot<Map<String, dynamic>> d) =>
              SavedAddressSerialisation.fromMap(d.data(), d.id))
          .toList(growable: false));

  // --- seed ---------------------------------------------------------------

  @override
  Future<WriteFailure?> seed(AdminSnapshot admin, CatalogSnapshot catalog) async {
    // Refuse to seed over real data. This is the one irreversible operation in
    // the repository, and a re-run after the shop has started trading would
    // replace every real order with mock history. Cheap to check, expensive to
    // discover afterwards.
    try {
      final QuerySnapshot<Map<String, dynamic>> existing =
          await _collection(FirestorePaths.orders).limit(1).get();
      if (existing.docs.isNotEmpty) {
        return const WriteFailure(
          operation: 'seed',
          message: 'Orders already exist, so seeding was skipped to avoid overwriting real data.',
        );
      }
    } catch (error) {
      final WriteFailure failure = describeFailure('seed: check existing orders', error);
      logWriteFailure(failure);
      return failure;
    }

    return _guard('seed shop data', () async {
      // `WriteBatch`: every document in one atomic commit. The alternative —
      // a loop of `.set` calls — can leave a half-seeded shop, with menu items
      // present and no staff, which is worse than nothing because it looks
      // populated.
      final WriteBatch batch = _db.batch();

      for (final MenuCategory category in catalog.categories) {
        batch.set(
          _collection(FirestorePaths.menuCategories).doc(category.id),
          category.toMap(),
        );
      }
      for (final MenuItem item in catalog.items) {
        batch.set(_collection(FirestorePaths.menuItems).doc(item.id), item.toMap());
      }
      for (final Promo promo in catalog.promos) {
        batch.set(_collection(FirestorePaths.promos).doc(PromoSerialisation.idOf(promo)), promo.toMap());
      }
      for (final StaffMember member in admin.staff) {
        batch.set(
          _collection(FirestorePaths.staffMembers).doc(FirestorePaths.staffDoc(member.id)),
          member.toMap(),
        );
      }
      batch.set(
        _collection(FirestorePaths.settings).doc(FirestorePaths.settingsDoc),
        admin.settings.toMap(),
      );
      // Orders last, and only the ones with an owning uid: `saveOrder` refuses
      // unattributed orders for the same reason the rules do.
      for (final Order order in admin.orders) {
        if (order.customerUid.isEmpty) continue;
        batch.set(_collection(FirestorePaths.orders).doc(order.id), order.toMap());
      }

      await batch.commit();
    });
  }
}