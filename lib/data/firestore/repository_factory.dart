import '../../core/firebase/firebase_bootstrap.dart';
import '../mock/mock_data.dart';
import '../models/menu.dart';
import '../models/order.dart';
import '../models/settings.dart';
import '../models/staff.dart';
import 'firestore_shop_repository.dart';
import 'memory_shop_repository.dart';
import 'shop_repository.dart';

/// Builds the one [ShopRepository] the app uses.
///
/// ## Why one instance
///
/// `CatalogProvider`, `AdminProvider` and `SessionProvider` all take the same
/// object. It has to be the same object, not three equivalent ones: settings are
/// read by two of them, and a second Firestore listener on `settings/shop` means
/// the second provider's copy can disagree with the first for a frame after a
/// write. One repository, one subscription each, no chance of a split.
///
/// ## Why the fallback carries the seed
///
/// When Firebase is not configured the app still needs a menu, orders and a staff
/// roster to be renderable. So the fallback is a [MemoryShopRepository] primed
/// from `MockData` rather than an empty one. An empty repository would render a
/// café with no menu at all, which looks like a bug rather than a missing config.
ShopRepository createShopRepository() {
  if (!FirebaseBootstrap.isReady) {
    return MemoryShopRepository(
      catalog: CatalogSnapshot(
        items: List<MenuItem>.from(MockData.menu),
        categories: List<MenuCategory>.from(MockData.categories),
        promos: List<Promo>.from(MockData.promos),
        isOpen: true,
      ),
      admin: AdminSnapshot(
        orders: <Order>[...MockData.adminQueue, ...MockData.tradingHistory],
        staff: List<StaffMember>.from(MockData.staff),
        settings: const StoreSettings(
          cafeName: 'Highlanders Coffee & Tea',
          address: 'Poblacion, Lumban, Laguna',
          isOpen: true,
          baseFee: 25,
          freeOver: 500,
          coverageRadiusKm: 10,
          opensAt: '7:00 AM',
          closesAt: '10:00 PM',
        ),
      ),
    );
  }

  return FirestoreShopRepository();
}