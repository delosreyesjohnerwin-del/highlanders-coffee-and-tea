import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlanders_coffee/data/firestore/firestore_errors.dart';
import 'package:highlanders_coffee/data/firestore/firestore_paths.dart';
import 'package:highlanders_coffee/data/firestore/memory_shop_repository.dart';
import 'package:highlanders_coffee/data/firestore/serialisation.dart';
import 'package:highlanders_coffee/data/firestore/shop_repository.dart';
import 'package:highlanders_coffee/data/firestore/stream_zip.dart';
import 'package:highlanders_coffee/data/mock/mock_data.dart';
import 'package:highlanders_coffee/data/models/menu.dart';
import 'package:highlanders_coffee/data/models/order.dart';
import 'package:highlanders_coffee/data/models/settings.dart';
import 'package:highlanders_coffee/data/models/staff.dart';
import 'package:highlanders_coffee/state/admin_provider.dart';
import 'package:highlanders_coffee/state/catalog_provider.dart';

/// The persistence layer.
///
/// Two things are being protected here, and they are different in kind.
///
/// **Round-tripping** — does an object survive being written and read back? A
/// silent failure here is the worst kind of bug in this layer: a menu item
/// comes back with `stock: 0` and the shop is quietly closed for that drink, and
/// nothing anywhere reports an error.
///
/// **Optimistic writes** — does an admin edit reach the backend, and does a
/// failure become visible? The second half matters more than it looks. An edit
/// that fails silently is indistinguishable from an edit that worked, so the
/// operator retypes the price and wonders why the old number is still there.
///
/// `MemoryShopRepository` is the subject here, not `FirestoreShopRepository`:
/// the Firestore one needs a live project, and everything worth asserting about
/// it is either a serialisation concern (covered above) or an SDK concern. The
/// `isLive` flag is what stops the memory repository being mistaken for
/// production behaviour.
void main() {
  /// Lets queued microtasks and stream events run.
  ///
  /// The providers write through asynchronously and the memory repository
  /// broadcasts to its listeners, so a single `await Future.delayed(Duration.zero)`
  /// only drains the write — the notification arrives on the next turn. Two
  /// turns is enough for the whole chain; anything deeper would be a real
  /// ordering problem, not a test-timing one.
  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  group('serialisation round trips', () {
    test('a menu item keeps every field', () {
      const MenuItem original = MenuItem(
        id: 'm-kopi',
        categoryId: 'coffee',
        name: 'Kopi Filipino',
        price: 55,
        description: 'Dark roast, evaporated milk.',
        imageUrl: 'https://example.test/kopi.jpg',
        isAvailable: true,
        isBestseller: true,
        prepMinutes: 4,
        sortOrder: 3,
        stock: 40,
        reorderLevel: 12,
      );

      final MenuItem restored = MenuItemSerialisation.fromMap(original.toMap(), 'wrong-id');

      expect(restored.id, 'm-kopi');
      expect(restored.categoryId, 'coffee');
      expect(restored.name, 'Kopi Filipino');
      expect(restored.price, 55);
      expect(restored.description, 'Dark roast, evaporated milk.');
      expect(restored.imageUrl, 'https://example.test/kopi.jpg');
      expect(restored.isAvailable, isTrue);
      expect(restored.isBestseller, isTrue);
      expect(restored.prepMinutes, 4);
      expect(restored.sortOrder, 3);
      expect(restored.stock, 40);
      expect(restored.reorderLevel, 12);
    });

    test('a category keeps its label, order and icon', () {
      const MenuCategory original = MenuCategory(
        id: 'pastries',
        label: 'Pastries',
        sortOrder: 3,
        icon: Icons.bakery_dining_outlined,
      );

      final MenuCategory restored =
          MenuCategorySerialisation.fromMap(original.toMap(), 'wrong-id');

      expect(restored.id, 'pastries');
      expect(restored.label, 'Pastries');
      expect(restored.sortOrder, 3);
      // The icon survives as a *key*, not a code point — see _iconKeys.
      expect(restored.icon.codePoint, Icons.bakery_dining_outlined.codePoint);
    });

    test('a promo keeps its discount shape', () {
      const Promo original = Promo(
        code: 'TAKE20',
        title: '20% OFF',
        subtitle: 'On your pastry order over ₱200',
        badge: '20% OFF',
        ctaLabel: 'Order Now',
        discountPercent: 20,
      );

      final Promo restored = PromoSerialisation.fromMap(original.toMap(), 'wrong-id');

      expect(restored.code, 'TAKE20');
      expect(restored.title, '20% OFF');
      expect(restored.discountPercent, 20);
      expect(restored.buyXGetY, isNull);
    });

    test('an order keeps its lines, totals and owning customer', () {
      final Order original = Order(
        id: 'HL-2601-4820',
        customerUid: 'u-marco',
        lines: const <OrderLine>[
          OrderLine(itemId: 'm-icedlatte', name: 'Iced Latte', price: 125, quantity: 2),
          OrderLine(itemId: 'm-croissant', name: 'Butter Croissant', price: 85, quantity: 1),
        ],
        status: OrderStatus.delivered,
        fulfillment: Fulfillment.delivery,
        paymentMethod: PaymentMethod.gcash,
        createdAt: DateTime(2026, 10, 1, 14, 30),
        subtotal: 335,
        deliveryFee: 25,
        distanceKm: 1.2,
        address: const AddressSnapshot(
          label: 'Home',
          street: '123 Poblacion Road',
          barangayCode: 'lumban-poblacion',
          barangayName: 'Poblacion',
          distanceKm: 1.2,
        ),
        pickupCode: '4820',
        driverName: 'Rodel',
        driverPhone: '+63 917 555 0142',
        paymentRef: 'PAY-9F2A41',
        promoCode: 'DAMPOTIST',
      );

      final Order restored = OrderSerialisation.fromMap(original.toMap(), 'wrong-id');

      expect(restored.id, 'HL-2601-4820');
      // The one that the security rules key on.
      expect(restored.customerUid, 'u-marco');
      expect(restored.lines, hasLength(2));
      expect(restored.lines.first.itemId, 'm-icedlatte');
      expect(restored.lines.first.quantity, 2);
      expect(restored.status, OrderStatus.delivered);
      expect(restored.fulfillment, Fulfillment.delivery);
      expect(restored.paymentMethod, PaymentMethod.gcash);
      expect(restored.subtotal, 335);
      expect(restored.deliveryFee, 25);
      expect(restored.total, 360);
      expect(restored.address?.barangayCode, 'lumban-poblacion');
      expect(restored.address?.distanceKm, 1.2);
      expect(restored.driverName, 'Rodel');
      expect(restored.promoCode, 'DAMPOTIST');
      // Timestamps go out as UTC and come back local. Comparing the instants
      // rather than the wall clock is the assertion that actually holds on a
      // device in a non-UTC timezone.
      expect(restored.createdAt.toUtc(), original.createdAt.toUtc());
    });

    test('a staff member keeps their shift', () {
      final StaffMember original = StaffMember(
        id: 's-2',
        name: 'Rodel Bautista',
        role: StaffRole.rider,
        shift: ShiftStatus.onDelivery,
        phone: '+63 917 555 0142',
        since: DateTime(2026, 10, 1, 8),
        completedToday: 6,
      );

      final StaffMember restored = StaffMemberSerialisation.fromMap(original.toMap(), 'wrong-id');

      expect(restored.id, 's-2');
      expect(restored.name, 'Rodel Bautista');
      expect(restored.role, StaffRole.rider);
      expect(restored.shift, ShiftStatus.onDelivery);
      expect(restored.since, isNotNull);
      expect(restored.completedToday, 6);
    });

    test('store settings keep the open flag and the fee', () {
      const StoreSettings original = StoreSettings(
        cafeName: 'Highlanders Coffee & Tea',
        address: 'Poblacion, Lumban, Laguna',
        isOpen: false,
        baseFee: 30,
        freeOver: 600,
        coverageRadiusKm: 8,
        opensAt: '6:00 AM',
        closesAt: '9:00 PM',
      );

      final StoreSettings restored = StoreSettingsSerialisation.fromMap(original.toMap());

      expect(restored.isOpen, isFalse);
      expect(restored.baseFee, 30);
      expect(restored.freeOver, 600);
      expect(restored.coverageRadiusKm, 8);
      expect(restored.opensAt, '6:00 AM');
    });

    test('a saved address keeps its barangay', () {
      const SavedAddress original = SavedAddress(
        id: 'a1',
        label: 'Home',
        street: '123 Poblacion Road',
        barangayCode: 'lumban-poblacion',
        note: 'Blue gate',
        isDefault: true,
      );

      final SavedAddress restored =
          SavedAddressSerialisation.fromMap(original.toMap(uid: 'u-marco'), 'wrong-id');

      expect(restored.id, 'a1');
      expect(restored.barangayCode, 'lumban-poblacion');
      expect(restored.isDefault, isTrue);
      // The uid rides along so the rules' `resource.data.uid` check can match.
      expect(original.toMap(uid: 'u-marco')['uid'], 'u-marco');
    });
  });

  group('serialisation tolerates damaged documents', () {
    test('an empty body yields a usable object rather than a throw', () {
      final MenuItem item = MenuItemSerialisation.fromMap(null, 'm-fallback');

      expect(item.id, 'm-fallback');
      expect(item.isAvailable, isTrue);
      expect(item.stock, 0);
    });

    test('a wrong-typed field falls back instead of crashing the read', () {
      // The realistic version of this: a price typed into the console as a
      // string, or an `orderBy` field someone hand-edited to a number.
      final MenuItem item = MenuItemSerialisation.fromMap(<String, dynamic>{
        'id': 'm-kopi',
        'name': 'Kopi Filipino',
        'price': '55.00',
        'stock': '40',
        'isAvailable': 'false',
      }, 'm-kopi');

      expect(item.price, 55);
      expect(item.stock, 40);
      expect(item.isAvailable, isFalse);
    });

    test('an unknown order status falls back to pending, not to a crash', () {
      final Order order = OrderSerialisation.fromMap(<String, dynamic>{
        'id': 'HL-1',
        'status': 'teleported',
        'lines': <dynamic>[],
      }, 'HL-1');

      expect(order.status, OrderStatus.pending);
    });

    test('an order with a corrupt createdAt lands on now, not the epoch', () {
      final Order order = OrderSerialisation.fromMap(<String, dynamic>{
        'id': 'HL-1',
        'createdAt': 'not-a-date',
        'lines': <dynamic>[],
      }, 'HL-1');

      // Epoch ordering would pin this order to the bottom of every list forever.
      expect(order.createdAt.isAfter(DateTime(2000)), isTrue);
    });

    test('lines that are not maps are dropped, not fatal', () {
      final Order order = OrderSerialisation.fromMap(<String, dynamic>{
        'id': 'HL-1',
        'lines': <dynamic>[
          'garbage',
          <String, dynamic>{'itemId': 'm-kopi', 'name': 'Kopi Filipino', 'price': 55, 'quantity': 1},
        ],
      }, 'HL-1');

      expect(order.lines, hasLength(1));
      expect(order.lines.single.name, 'Kopi Filipino');
    });

    test('an absent settings document reads as open', () {
      // A document that fails to parse must not close the shop.
      expect(StoreSettingsSerialisation.fromMap(null).isOpen, isTrue);
    });
  });

  group('stream combination', () {
    test('holds back until every source has emitted', () async {
      final StreamController<int> a = StreamController<int>();
      final StreamController<int> b = StreamController<int>();
      addTearDown(a.close);
      addTearDown(b.close);

      final List<String> seen = <String>[];

      zip2<int, int, String>(a.stream, b.stream, (int x, int y) => '$x/$y')
          .listen(seen.add);

      a.add(1);
      await settle();
      // b has not spoken, so nothing has been emitted yet.
      expect(seen, isEmpty);

      b.add(9);
      await settle();
      expect(seen, <String>['1/9']);
    });

    test('emits again on each later value', () async {
      final StreamController<int> a = StreamController<int>();
      final StreamController<int> b = StreamController<int>();
      addTearDown(a.close);
      addTearDown(b.close);

      final List<String> seen = <String>[];

      zip2<int, int, String>(a.stream, b.stream, (int x, int y) => '$x/$y')
          .listen(seen.add);

      a.add(1);
      b.add(9);
      await settle();
      a.add(2);
      await settle();

      expect(seen, <String>['1/9', '2/9']);
    });
  });

  group('seed data integrity', () {
    test('every mock order is attributed to a customer', () {
      // `seed` skips an unattributed order without saying so, which would quietly
      // drop rows from the seeded history. Asserted here so that skip is a test
      // failure rather than missing data in production.
      final List<Order> all = <Order>[
        ...MockData.adminQueue,
        ...MockData.tradingHistory,
        ...MockData.ordersFor('u-marco'),
      ];

      final List<String> unattributed = <String>[
        for (final Order o in all)
          if (o.customerUid.isEmpty) o.id,
      ];

      expect(unattributed, isEmpty);
    });

    test('mock order ids are unique', () {
      final List<String> ids = <String>[
        for (final Order o in <Order>[...MockData.adminQueue, ...MockData.tradingHistory])
          o.id,
      ];

      // Order documents are keyed by id, so a duplicate would silently overwrite
      // one order with another.
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('every seeded staff member has a role', () {
      for (final StaffMember s in MockData.staff) {
        expect(s.role, isNotNull);
        expect(s.name, isNotEmpty);
      }
    });
  });

  group('catalog provider writes through', () {
    test('a price edit reaches the repository', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final CatalogProvider catalog = CatalogProvider(repository: repo)..bind();

      catalog.updatePrice('m-kopi', 60);

      // Optimistic: local state is already updated synchronously.
      expect(catalog.itemById('m-kopi')?.price, 60);

      await settle();
      final CatalogSnapshot snapshot = await repo.loadCatalog();
      expect(snapshot.items.firstWhere((MenuItem i) => i.id == 'm-kopi').price, 60);
    });

    test('a stock edit reaches the repository', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final CatalogProvider catalog = CatalogProvider(repository: repo)..bind();

      catalog.setStock('m-latte', 3);

      await settle();
      final CatalogSnapshot snapshot = await repo.loadCatalog();
      final MenuItem latte = snapshot.items.firstWhere((MenuItem i) => i.id == 'm-latte');
      expect(latte.stock, 3);
      // Below the reorder level, so the restock list should pick it up.
      expect(latte.status, StockStatus.lowStock);
    });

    test('a promo edit reaches the repository', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final CatalogProvider catalog = CatalogProvider(repository: repo)..bind();

      catalog.upsertPromo(
        const Promo(
          code: 'SUMMER25',
          title: 'Summer 25%',
          subtitle: 'Ice drinks, all month.',
          discountPercent: 25,
        ),
      );

      await settle();
      final CatalogSnapshot snapshot = await repo.loadCatalog();
      final Promo saved = snapshot.promos.firstWhere((Promo p) => p.code == 'SUMMER25');
      expect(saved.title, 'Summer 25%');
      expect(saved.discountPercent, 25);
    });

    test('a promo delete reaches the repository, not just local state', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final CatalogProvider catalog = CatalogProvider(repository: repo)..bind();
      expect(catalog.allPromos, isNotEmpty);

      catalog.removePromo('DAMPOTIST');

      // Optimistic, same as every other admin action.
      expect(catalog.allPromos.any((Promo p) => p.code == 'DAMPOTIST'), isFalse);

      await settle();
      // The point: gone from the backend too, so it does not come back on the
      // next catalog read. A delete that only touched local state would reappear
      // the moment the Firestore listener fired.
      final CatalogSnapshot snapshot = await repo.loadCatalog();
      expect(snapshot.promos.any((Promo p) => p.code == 'DAMPOTIST'), isFalse);
    });

    test('a paused promo is hidden from customers but still listed for admin', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final CatalogProvider catalog = CatalogProvider(repository: repo)..bind();
      final Promo original = catalog.allPromos.first;

      catalog.upsertPromo(
        Promo(
          code: original.code,
          title: original.title,
          subtitle: original.subtitle,
          badge: original.badge,
          ctaLabel: original.ctaLabel,
          discountPercent: original.discountPercent,
          buyXGetY: original.buyXGetY,
          active: false,
        ),
      );

      // Still in the document — pausing is not deleting, so the owner can bring
      // it back. Filtered on read, so an already-open customer app drops it
      // immediately rather than at the next restart.
      expect(catalog.allPromos.any((Promo p) => p.code == original.code), isTrue);
      expect(catalog.promos.any((Promo p) => p.code == original.code), isFalse);
    });

    test('a failed write is recorded, not swallowed', () async {
      final MemoryShopRepository repo = MemoryShopRepository()..failWrites = true;
      addTearDown(repo.dispose);

      final CatalogProvider catalog = CatalogProvider(repository: repo)..bind();

      catalog.updatePrice('m-kopi', 60);
      await settle();

      // The point of the whole exercise: the operator can find out.
      final WriteFailure? failure = catalog.consumeFailure();
      expect(failure, isNotNull);
      expect(failure!.operation, contains('Kopi Filipino'));

      // One-shot, so a toast does not reappear on the next rebuild.
      expect(catalog.consumeFailure(), isNull);
    });

    test('a failed promo delete is recorded too', () async {
      final MemoryShopRepository repo = MemoryShopRepository()..failWrites = true;
      addTearDown(repo.dispose);

      final CatalogProvider catalog = CatalogProvider(repository: repo)..bind();

      catalog.removePromo('DAMPOTIST');
      await settle();

      // Deleting an offer is the action most likely to fail on a café's flaky
      // connection, and the one where a silent failure is most costly: the owner
      // believes the promo is gone and a customer is still seeing it.
      final WriteFailure? failure = catalog.consumeFailure();
      expect(failure, isNotNull);
      expect(failure!.operation, contains('DAMPOTIST'));
    });
  });

  group('admin provider writes through', () {
    test('advancing an order persists the new status', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final AdminProvider admin = AdminProvider(repository: repo)..bind();

      final Order target = admin.openOrders.first;
      expect(admin.advanceOrder(target.id), isTrue);

      await settle();
      final AdminSnapshot snapshot = await repo.loadAdmin();
      final Order stored =
          snapshot.orders.firstWhere((Order o) => o.id == target.id);
      expect(stored.status, isNot(target.status));
    });

    test('an advanced order keeps the customer it belongs to', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final AdminProvider admin = AdminProvider(repository: repo)..bind();

      final Order target = admin.openOrders.first;
      admin.advanceOrder(target.id);
      await settle();

      // Losing this field would make the order invisible to the customer who
      // placed it, because their query filters on it.
      final AdminSnapshot snapshot = await repo.loadAdmin();
      expect(
        snapshot.orders.firstWhere((Order o) => o.id == target.id).customerUid,
        target.customerUid,
      );
    });

    test('an unattributed order is refused with a readable message', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final WriteFailure? failure = await repo.saveOrder(Order(
        id: 'HL-ORPHAN',
        customerUid: '',
        lines: const <OrderLine>[OrderLine(itemId: 'm-kopi', name: 'Kopi Filipino', price: 55, quantity: 1)],
        status: OrderStatus.pending,
        fulfillment: Fulfillment.pickup,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime(2026, 10, 1),
        subtotal: 55,
      ));

      // Not a raw permission error: the operator needs to know *why*, and that it
      // is a data problem rather than a rules problem.
      expect(failure, isNotNull);
      expect(failure!.message, contains('not attributed'));
    });

    test('a shift toggle persists', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final AdminProvider admin = AdminProvider(repository: repo)..bind();
      final StaffMember member = admin.staff.firstWhere((StaffMember s) => !s.shift.isWorking);

      admin.toggleShift(member.id);
      await settle();

      final AdminSnapshot snapshot = await repo.loadAdmin();
      expect(
        snapshot.staff.firstWhere((StaffMember s) => s.id == member.id).shift.isWorking,
        isTrue,
      );
    });

    test('cancelling an order persists', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final AdminProvider admin = AdminProvider(repository: repo)..bind();
      final Order target = admin.openOrders.first;

      admin.cancelOrder(target.id);
      await settle();

      final AdminSnapshot snapshot = await repo.loadAdmin();
      expect(
        snapshot.orders.firstWhere((Order o) => o.id == target.id).status,
        OrderStatus.cancelled,
      );
    });

    test('settings edits persist and reach the customer-facing open flag', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final AdminProvider admin = AdminProvider(repository: repo)..bind();
      final CatalogProvider catalog = CatalogProvider(repository: repo)..bind();

      admin.updateSettings(admin.settings.copyWith(isOpen: false));
      await settle();

      // Both providers share one repository, so this is the test that a settings
      // write actually reaches the customer side rather than stopping at admin.
      final CatalogSnapshot snapshot = await repo.loadCatalog();
      expect(snapshot.isOpen, isFalse);
      expect(catalog.isOpen, isFalse);
    });

    test('seeding refuses without a backend', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      // The in-memory repository is not live, so there is nowhere to seed to and
      // it says so instead of pretending.
      final AdminProvider admin = AdminProvider(repository: repo);

      final WriteFailure? failure = await admin.seedFromMock();
      expect(failure, isNotNull);
      expect(failure!.message, contains('nowhere to seed'));
    });
  });

  group('customer writes', () {
    test('an order is filed under the signed-in customer only', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final WriteFailure? failure = await repo.createOrder(Order(
        id: 'HL-2601-9001',
        customerUid: 'u-marco',
        lines: const <OrderLine>[OrderLine(itemId: 'm-kopi', name: 'Kopi Filipino', price: 55, quantity: 1)],
        status: OrderStatus.pending,
        fulfillment: Fulfillment.delivery,
        paymentMethod: PaymentMethod.gcash,
        createdAt: DateTime(2026, 10, 1, 9),
        subtotal: 55,
        deliveryFee: 25,
      ));

      expect(failure, isNull);
      expect(await repo.loadOrdersFor('u-marco'), hasLength(1));
      // Another customer must not see it — this is the guarantee the rules
      // provide in production and the reason the query filters on the uid.
      expect(await repo.loadOrdersFor('u-someone-else'), isEmpty);
    });

    test('placing an order without signing in is refused', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final WriteFailure? failure = await repo.createOrder(Order(
        id: 'HL-2601-9002',
        customerUid: '',
        lines: const <OrderLine>[],
        status: OrderStatus.pending,
        fulfillment: Fulfillment.pickup,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime(2026, 10, 1, 9),
        subtotal: 0,
      ));

      expect(failure, isNotNull);
      expect(failure!.message, contains('Sign in'));
    });
  });

  group('collection names match the security rules', () {
    test('every path is one the rules actually name', () {
      // A typo here does not fail loudly. The catch-all at the bottom of
      // firestore.rules denies reads on an undeclared collection, so the document
      // simply disappears. Asserting the names here ties the code to the rules.
      const List<String> declaredInRules = <String>[
        'menuCategories',
        'menuItems',
        'promos',
        'settings',
        'orders',
        'staffMembers',
        'drivers',
        'addresses',
        'users',
      ];

      final List<String> used = <String>[
        FirestorePaths.menuItems,
        FirestorePaths.menuCategories,
        FirestorePaths.promos,
        FirestorePaths.settings,
        FirestorePaths.orders,
        FirestorePaths.staffMembers,
        FirestorePaths.addresses,
      ];

      for (final String name in used) {
        expect(declaredInRules, contains(name), reason: '$name is not in firestore.rules');
      }
    });

    test('an address document id is namespaced by uid', () {
      // Two customers could otherwise pick the same address id and one would
      // overwrite the other's.
      expect(
        FirestorePaths.addressDoc('u-a', 'home'),
        isNot(FirestorePaths.addressDoc('u-b', 'home')),
      );
    });
  });
}