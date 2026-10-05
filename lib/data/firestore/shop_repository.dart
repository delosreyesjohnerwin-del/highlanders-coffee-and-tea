import '../models/coverage.dart';
import '../models/menu.dart';
import '../models/order.dart';
import '../models/settings.dart';
import '../models/staff.dart';
import 'firestore_errors.dart';

/// Everything the app needs to persist, in one interface.
///
/// Two implementations exist and they are interchangeable:
///
///  * `FirestoreShopRepository` — the real one.
///  * `MemoryShopRepository` — the default, so the app still runs with no
///    Firebase config and so tests need no emulator.
///
/// The providers hold local state and write through. That is deliberate: an
/// admin tapping "Mark ready" in a basement with no signal must see the badge
/// change immediately. The repository reports the write outcome separately so
/// the failure is visible rather than assumed.
///
/// Every method returns a [WriteFailure] instead of throwing. A repository that
/// throws forces a try/catch at each of roughly fifteen call sites, and one
/// forgotten catch is exactly the silent data loss this design is trying to
/// avoid.
abstract class ShopRepository {
  /// True when writes actually reach a server. False for [MemoryShopRepository].
  bool get isLive;

  // --- catalog ------------------------------------------------------------

  Future<CatalogSnapshot> loadCatalog();

  Stream<CatalogSnapshot> watchCatalog();

  Future<WriteFailure?> saveMenuItem(MenuItem item);

  Future<WriteFailure?> deleteMenuItem(String id);

  Future<WriteFailure?> saveCategory(MenuCategory category);

  Future<WriteFailure?> savePromo(Promo promo);

  // --- admin --------------------------------------------------------------

  Future<AdminSnapshot> loadAdmin();

  Stream<AdminSnapshot> watchAdmin();

  Future<WriteFailure?> saveOrder(Order order);

  Future<WriteFailure?> deleteOrder(String id);

  Future<WriteFailure?> saveStaffMember(StaffMember member);

  Future<WriteFailure?> deleteStaffMember(String id);

  // --- settings -----------------------------------------------------------

  Future<StoreSettings> loadSettings();

  Future<WriteFailure?> saveSettings(StoreSettings settings);

  // --- customer -----------------------------------------------------------

  /// Creates an order. The uid is taken from the signed-in session, never from
  /// the caller, because the security rules require them to match and a
  /// mismatch would be a confusing permission error instead of a clear one.
  Future<WriteFailure?> createOrder(Order order);

  Future<List<Order>> loadOrdersFor(String uid);

  Stream<List<Order>> watchOrdersFor(String uid);

  Future<WriteFailure?> saveAddress(String uid, SavedAddress address);

  Future<WriteFailure?> deleteAddress(String uid, String addressId);

  Future<List<SavedAddress>> loadAddresses(String uid);

  Stream<List<SavedAddress>> watchAddresses(String uid);

  // --- seed ---------------------------------------------------------------

  /// Writes [snapshot]'s catalog and admin content to the backend.
  ///
  /// Refuses to overwrite a database that already has orders, because seeding is
  /// a first-run convenience and a second run must not be able to bury real
  /// trading history under mock data.
  Future<WriteFailure?> seed(AdminSnapshot admin, CatalogSnapshot catalog);
}

/// Menu, categories and promos as one consistent read.
///
/// Read as a unit because the three collections change together when the admin
/// edits the menu. Reading them independently would let the panel render an item
/// whose category was deleted a moment earlier.
class CatalogSnapshot {
  const CatalogSnapshot({
    required this.items,
    required this.categories,
    required this.promos,
    this.isOpen = true,
    this.pricing = const DeliveryPricing(),
  });

  const CatalogSnapshot.empty()
      : items = const <MenuItem>[],
        categories = const <MenuCategory>[],
        promos = const <Promo>[],
        isOpen = true,
        pricing = const DeliveryPricing();

  final List<MenuItem> items;
  final List<MenuCategory> categories;
  final List<Promo> promos;
  final bool isOpen;
  final DeliveryPricing pricing;

  bool get isEmpty => items.isEmpty && categories.isEmpty && promos.isEmpty;
}

/// Orders, staff and settings as one consistent read.
class AdminSnapshot {
  const AdminSnapshot({
    required this.orders,
    required this.staff,
    required this.settings,
  });

  const AdminSnapshot.empty()
      : orders = const <Order>[],
        staff = const <StaffMember>[],
        settings = defaultSettings;

  /// The shipping shop configuration.
  ///
  /// Named so the repository and the settings provider can both reach it — a
  /// missing settings document should fall back to *something*, and duplicating
  /// that something in two files is how the two drift apart.
  static const StoreSettings defaultSettings = StoreSettings(
    cafeName: 'Highlanders Coffee & Tea',
    address: 'Poblacion, Lumban, Laguna',
    isOpen: true,
    baseFee: 25,
    freeOver: 500,
    coverageRadiusKm: 10,
    opensAt: '7:00 AM',
    closesAt: '10:00 PM',
  );

  final List<Order> orders;
  final List<StaffMember> staff;
  final StoreSettings settings;

  bool get isEmpty => orders.isEmpty && staff.isEmpty;
}