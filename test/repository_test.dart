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
import 'package:highlanders_coffee/data/models/coverage.dart';
import 'package:highlanders_coffee/data/models/menu.dart';
import 'package:highlanders_coffee/data/models/order.dart';
import 'package:highlanders_coffee/data/models/payment.dart';
import 'package:highlanders_coffee/data/models/settings.dart';
import 'package:highlanders_coffee/data/models/shift_event.dart';
import 'package:highlanders_coffee/data/models/staff.dart';
import 'package:highlanders_coffee/services/staff_qr.dart';
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
          lat: 14.2919,
          lng: 121.4644,
        ),
        pickupCode: '4820',
        driverName: 'Rodel',
        driverPhone: '+63 917 555 0142',
        paymentRef: 'PAY-9F2A41',
        promoCode: 'DAMPOTIST',
        statusHistory: <OrderStatusEvent>[
          OrderStatusEvent(
            status: OrderStatus.pending,
            at: DateTime(2026, 10, 1, 14, 30),
          ),
          OrderStatusEvent(
            status: OrderStatus.confirmed,
            at: DateTime(2026, 10, 1, 14, 32),
          ),
        ],
        trackingNumber: 'JKE-4820-X1',
        carrierName: 'J&T Express',
        carrierUrl: 'https://example.com/track/JKE-4820-X1',
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
      expect(restored.address?.lat, 14.2919);
      expect(restored.address?.lng, 121.4644);
      expect(restored.driverName, 'Rodel');
      expect(restored.promoCode, 'DAMPOTIST');
      // Status history round-trips as stored events, oldest first.
      expect(restored.statusHistory, hasLength(2));
      expect(restored.statusHistory.first.status, OrderStatus.pending);
      expect(restored.statusHistory.last.status, OrderStatus.confirmed);
      expect(
        restored.enteredAt(OrderStatus.confirmed)?.toUtc(),
        DateTime(2026, 10, 1, 14, 32).toUtc(),
      );
      expect(restored.enteredAt(OrderStatus.ready), isNull);
      // Carrier fields survive when present.
      expect(restored.trackingNumber, 'JKE-4820-X1');
      expect(restored.carrierName, 'J&T Express');
      expect(restored.carrierUrl, 'https://example.com/track/JKE-4820-X1');
      // Timestamps go out as UTC and come back local. Comparing the instants
      // rather than the wall clock is the assertion that actually holds on a
      // device in a non-UTC timezone.
      expect(restored.createdAt.toUtc(), original.createdAt.toUtc());
    });

    test('an order without history reads back as empty', () {
      final Order original = Order(
        id: 'HL-2601-4820',
        customerUid: 'u-marco',
        lines: const <OrderLine>[
          OrderLine(itemId: 'm-icedlatte', name: 'Iced Latte', price: 125, quantity: 1),
        ],
        status: OrderStatus.preparing,
        fulfillment: Fulfillment.delivery,
        paymentMethod: PaymentMethod.gcash,
        createdAt: DateTime(2026, 10, 1, 9, 0),
      );

      // Documents written before status tracking never had the field at all.
      final Order restored = OrderSerialisation.fromMap(original.toMap(), 'wrong-id');
      expect(restored.statusHistory, isEmpty);

      // ... and a corrupt history entry is skipped, not fatal: a stray object
      // with no parseable timestamp must not drop the whole order.
      final Map<String, dynamic> withGarbage = original.toMap()
        ..['statusHistory'] = <Object>[
          <String, Object>{'status': 'delivered', 'at': 'not-a-date'},
          'garbage',
        ];
      final Order tolerant = OrderSerialisation.fromMap(withGarbage, 'wrong-id');
      expect(tolerant.statusHistory, isEmpty);
      expect(tolerant.status, OrderStatus.preparing);
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

    test('a staff member keeps a minted badge token', () {
      final StaffMember original = StaffMember(
        id: 's-3',
        name: 'Mara Ilagan',
        role: StaffRole.barista,
        shift: ShiftStatus.offShift,
        qrToken: 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
        qrIssuedAt: DateTime(2026, 10, 2, 9, 30),
      );

      final StaffMember restored = StaffMemberSerialisation.fromMap(original.toMap(), 'wrong-id');

      expect(restored.qrToken, original.qrToken);
      expect(restored.qrIssuedAt, isNotNull);
    });

    test('a tokenless staff member round-trips without inventing a badge', () {
      const StaffMember original = StaffMember(
        id: 's-1',
        name: 'Aiko Ramos',
        role: StaffRole.owner,
        shift: ShiftStatus.onShift,
      );

      final StaffMember restored = StaffMemberSerialisation.fromMap(original.toMap(), 'wrong-id');

      expect(restored.qrToken, isNull);
      expect(original.toMap().containsKey('qrToken'), isFalse);
    });

    test('a shift event keeps its direction, time and method', () {
      final ShiftEvent original = ShiftEvent(
        id: 'ev-1',
        staffId: 's-3',
        staffName: 'Mara Ilagan',
        type: ShiftEventType.clockOut,
        at: DateTime(2026, 10, 3, 18, 5),
        method: ShiftEventMethod.qr,
      );

      final ShiftEvent restored = ShiftEventSerialisation.fromMap(original.toMap(), 'wrong-id');

      expect(restored.id, 'ev-1');
      expect(restored.staffId, 's-3');
      expect(restored.staffName, 'Mara Ilagan');
      expect(restored.type, ShiftEventType.clockOut);
      expect(restored.method, ShiftEventMethod.qr);
    });

    test('store settings keep the open flag and the fee', () {
      const StoreSettings original = StoreSettings(
        cafeName: 'Highlanders Coffee & Tea',
        address: 'Poblacion, Lumban, Laguna',
        isOpen: false,
        baseFee: 30,
        freeOver: 600,
        coverageRadiusKm: 8,
        cafeLat: 14.1234,
        cafeLng: 121.5678,
        opensAt: '6:00 AM',
        closesAt: '9:00 PM',
      );

      final StoreSettings restored = StoreSettingsSerialisation.fromMap(original.toMap());

      expect(restored.isOpen, isFalse);
      expect(restored.baseFee, 30);
      expect(restored.freeOver, 600);
      expect(restored.coverageRadiusKm, 8);
      // The GPS origin survives the round trip — it is what the delivery fee
      // is measured from once pins exist.
      expect(restored.cafeLat, 14.1234);
      expect(restored.cafeLng, 121.5678);
      expect(restored.opensAt, '6:00 AM');
    });

    test('settings written before café coordinates existed fall back to the bundled origin', () {
      final StoreSettings restored = StoreSettingsSerialisation.fromMap(<String, dynamic>{
        'cafeName': 'Highlanders Coffee & Tea',
        'isOpen': true,
        'baseFee': 25,
        'freeOver': 500,
        'coverageRadiusKm': 10,
        'opensAt': '7:00 AM',
        'closesAt': '10:00 PM',
      });

      // The placeholder, not zero — zero would make every GPS distance read as
      // the full radius and price the farthest barangay as the closest.
      expect(restored.cafeLat, LumbanCoverage.cafeLat);
      expect(restored.cafeLng, LumbanCoverage.cafeLng);
    });

    test('a saved address keeps its barangay and optional GPS pin', () {
      const SavedAddress original = SavedAddress(
        id: 'a1',
        label: 'Home',
        street: '123 Poblacion Road',
        barangayCode: 'lumban-poblacion',
        note: 'Blue gate',
        isDefault: true,
        lat: 14.2919,
        lng: 121.4644,
      );

      final SavedAddress restored =
          SavedAddressSerialisation.fromMap(original.toMap(uid: 'u-marco'), 'wrong-id');

      expect(restored.id, 'a1');
      expect(restored.barangayCode, 'lumban-poblacion');
      expect(restored.isDefault, isTrue);
      expect(restored.lat, 14.2919);
      expect(restored.lng, 121.4644);
      // The uid rides along so the rules' `resource.data.uid` check can match.
      expect(original.toMap(uid: 'u-marco')['uid'], 'u-marco');
    });

    test('a saved address written before pins existed reads back without them', () {
      final SavedAddress restored = SavedAddressSerialisation.fromMap(<String, dynamic>{
        'id': 'a2',
        'uid': 'u-marco',
        'label': 'Work',
        'street': '45 Dagatan Street',
        'barangayCode': 'lumban-wawa',
        'isDefault': false,
      }, 'wrong-id');

      expect(restored.lat, isNull);
      expect(restored.lng, isNull);
      // And the missing pin must not break pricing: the barangay fallback is
      // still reachable.
      expect(restored.distanceKm(), isNotNull);
    });

    test('a linked payment account keeps its network, mask, tail and defaults', () {
      final PaymentAccount original = PaymentAccount(
        id: 'pm-gcash',
        network: PaymentNetwork.gcash,
        holderName: 'Marco Reyes',
        // Only the masked string — this test document contains no full number
        // anywhere, exactly as a real one must not.
        accountLabel: '0917****000',
        tail: '0000',
        email: 'marco.reyes@email.com',
        isDefault: true,
        linkedAt: DateTime(2026, 9, 2, 8, 30),
        gatewayId: 'mock-pm-1001',
      );

      final Map<String, dynamic> stored = original.toMap(uid: 'u-marco');
      final PaymentAccount restored =
          PaymentAccountSerialisation.fromMap(stored, 'wrong-id');

      expect(restored.id, 'pm-gcash');
      expect(restored.network, PaymentNetwork.gcash);
      expect(restored.holderName, 'Marco Reyes');
      expect(restored.accountLabel, '0917****000');
      expect(restored.tail, '0000');
      expect(restored.email, 'marco.reyes@email.com');
      expect(restored.isDefault, isTrue);
      expect(restored.linkedAt, DateTime(2026, 9, 2, 8, 30));
      expect(restored.gatewayId, 'mock-pm-1001');
      expect(restored.cardBrand, isNull);
      // The uid rides along so the rules' `resource.data.uid` check can match.
      expect(stored['uid'], 'u-marco');
      // The raw number is not among the stored fields by construction.
      expect(stored.keys, isNot(contains('number')));
      expect(stored.keys, isNot(contains('cvc')));
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

    test('a payment method with a corrupt body reads back usable', () {
      final PaymentAccount back =
          PaymentAccountSerialisation.fromMap(null, 'pm-fallback');

      expect(back.id, 'pm-fallback');
      // The gateway-less default, so an unknown network never crashes the read.
      expect(back.network, PaymentNetwork.gcash);
      expect(back.isDefault, isFalse);
      expect(back.linkedAt.isAfter(DateTime(2000)), isTrue);
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

      catalog.updatePrice('cl-americano', 60);

      // Optimistic: local state is already updated synchronously.
      expect(catalog.itemById('cl-americano')?.price, 60);

      await settle();
      final CatalogSnapshot snapshot = await repo.loadCatalog();
      expect(snapshot.items.firstWhere((MenuItem i) => i.id == 'cl-americano').price, 60);
    });

    test('a stock edit reaches the repository', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final CatalogProvider catalog = CatalogProvider(repository: repo)..bind();

      catalog.setStock('cl-cafe-latte', 3);

      await settle();
      final CatalogSnapshot snapshot = await repo.loadCatalog();
      final MenuItem latte = snapshot.items.firstWhere((MenuItem i) => i.id == 'cl-cafe-latte');
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

      catalog.updatePrice('cl-americano', 60);
      await settle();

      // The point of the whole exercise: the operator can find out.
      final WriteFailure? failure = catalog.consumeFailure();
      expect(failure, isNotNull);
      expect(failure!.operation, contains('Americano'));

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

    test('clocking a member by QR token flips the shift and logs the event', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final AdminProvider admin = AdminProvider(repository: repo);
      final StaffMember member = admin.staff.firstWhere((StaffMember s) => !s.shift.isWorking);

      // Minting is the panel's job; the kiosk only ever reads a token.
      await admin.ensureStaffQr(member.id);
      final StaffMember withBadge = admin.staffById(member.id)!;
      expect(withBadge.qrToken, isNotNull);

      final Uri uri = staffQrUri(withBadge)!;
      final StaffClockResult result = admin.clockByToken(uri.toString());

      expect(result.outcome, StaffClockOutcome.clockedIn);
      expect(admin.staffById(member.id)!.shift.isWorking, isTrue);

      await settle();
      final List<ShiftEvent> events = await repo.loadShiftEvents(member.id);
      expect(events, hasLength(1));
      expect(events.single.type, ShiftEventType.clockIn);
      expect(events.single.staffId, member.id);
      expect(events.single.method, ShiftEventMethod.qr);
    });

    test('a second scan clocks the same member out', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final AdminProvider admin = AdminProvider(repository: repo);
      final StaffMember member = admin.staff.firstWhere((StaffMember s) => !s.shift.isWorking);
      await admin.ensureStaffQr(member.id);

      final Uri uri = staffQrUri(admin.staffById(member.id)!)!;
      expect(admin.clockByToken(uri.toString()).outcome, StaffClockOutcome.clockedIn);
      expect(admin.clockByToken(uri.toString()).outcome, StaffClockOutcome.clockedOut);

      await settle();
      final List<ShiftEvent> events = await repo.loadShiftEvents(member.id);
      expect(events.map((ShiftEvent e) => e.type), <ShiftEventType>[
        ShiftEventType.clockOut,
        ShiftEventType.clockIn,
      ]);
    });

    test('regenerating a badge invalidates the old token', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final AdminProvider admin = AdminProvider(repository: repo);
      final StaffMember member = admin.staff.firstWhere((StaffMember s) => !s.shift.isWorking);

      await admin.ensureStaffQr(member.id);
      final Uri oldBadge = staffQrUri(admin.staffById(member.id)!)!;

      await admin.regenerateStaffQr(member.id);
      final StaffMember rotated = admin.staffById(member.id)!;
      expect(rotated.qrToken, isNot(oldBadge.queryParameters['t']));

      // The printed badge is dead the moment the token changes.
      final StaffClockResult stale = admin.clockByToken(oldBadge.toString());
      expect(stale.outcome, StaffClockOutcome.staleBadge);
      expect(admin.staffById(member.id)!.shift.isWorking, isFalse);
    });

    test('a badge for someone not on the roster is refused', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final AdminProvider admin = AdminProvider(repository: repo);

      final StaffClockResult unknown = admin.clockByToken(
        staffQrUriFor(staffId: 's-ghost', token: 'deadbeef').toString(),
      );
      expect(unknown.outcome, StaffClockOutcome.unknownStaff);

      expect(admin.clockByToken('https://example.test/not-a-badge').outcome,
          StaffClockOutcome.notABadge);
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

    test('a linked payment account persists through save and load', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      final PaymentAccount gcash = PaymentAccount(
        id: 'pm-gcash',
        network: PaymentNetwork.gcash,
        holderName: 'Marco Reyes',
        accountLabel: '0917****000',
        tail: '0000',
        isDefault: true,
        linkedAt: DateTime(2026, 9, 2),
        gatewayId: 'mock-pm-1001',
      );

      expect(await repo.savePaymentAccount('u-marco', gcash), isNull);
      final List<PaymentAccount> loaded = await repo.loadPaymentAccounts('u-marco');
      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'pm-gcash');
      expect(loaded.single.network, PaymentNetwork.gcash);
      expect(loaded.single.isDefault, isTrue);
    });

    test('saving over an existing id updates in place instead of duplicating', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      await repo.savePaymentAccount('u-marco', PaymentAccount(
        id: 'pm-gcash',
        network: PaymentNetwork.gcash,
        holderName: 'Marco Reyes',
        accountLabel: '0917****000',
        tail: '0000',
        linkedAt: DateTime(2026, 9, 2),
      ));
      await repo.savePaymentAccount('u-marco', PaymentAccount(
        id: 'pm-gcash',
        network: PaymentNetwork.gcash,
        holderName: 'New Name',
        accountLabel: '0917****000',
        tail: '0000',
        isDefault: true,
        linkedAt: DateTime(2026, 9, 2),
      ));

      final List<PaymentAccount> loaded = await repo.loadPaymentAccounts('u-marco');
      expect(loaded, hasLength(1));
      expect(loaded.single.holderName, 'New Name');
      expect(loaded.single.isDefault, isTrue);
    });

    test('an unlinked payment account is deleted', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      await repo.savePaymentAccount('u-marco', PaymentAccount(
        id: 'pm-gcash',
        network: PaymentNetwork.gcash,
        holderName: 'Marco Reyes',
        accountLabel: '0917****000',
        tail: '0000',
        linkedAt: DateTime(2026, 9, 2),
      ));
      expect(await repo.deletePaymentAccount('u-marco', 'pm-gcash'), isNull);
      expect(await repo.loadPaymentAccounts('u-marco'), isEmpty);
    });

    test('payment methods are namespaced per customer', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      await repo.savePaymentAccount('u-marco', PaymentAccount(
        id: 'pm-gcash',
        network: PaymentNetwork.gcash,
        holderName: 'Marco Reyes',
        accountLabel: '0917****000',
        tail: '0000',
        linkedAt: DateTime(2026, 9, 2),
      ));

      // Another customer linking their own GCash shares the id but must not
      // see or clobber Marco's entry — the same guarantee the rules provide.
      expect(await repo.loadPaymentAccounts('u-someone-else'), isEmpty);
      expect(await repo.loadPaymentAccounts('u-marco'), hasLength(1));
    });
  });

  group('notification tokens', () {
    test('a device token registers under its uid and keeps its identity', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      await repo.saveNotificationToken('u-marco', 'fcm-token-123');
      await repo.saveNotificationToken('u-marco', 'fcm-token-123');

      expect(repo.registeredTokens('u-marco'), hasLength(1));
      expect(repo.registeredTokens('u-marco'), contains('fcm-token-123'));
      expect(repo.registeredTokens('u-someone-else'), isEmpty);
    });

    test('a duplicate save is idempotent (the doc is the token)', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      await repo.saveNotificationToken('u-marco', 'fcm-token-123');
      // A second account signing in on the same device rewrites the uid, which
      // is exactly how a shared phone stops pushing to the previous owner.
      await repo.saveNotificationToken('u-ana', 'fcm-token-123');

      expect(repo.registeredTokens('u-marco'), isEmpty);
      expect(repo.registeredTokens('u-ana'), contains('fcm-token-123'));
    });

    test('a device token unregisters', () async {
      final MemoryShopRepository repo = MemoryShopRepository();
      addTearDown(repo.dispose);

      await repo.saveNotificationToken('u-marco', 'fcm-token-123');
      expect(await repo.deleteNotificationToken('u-marco', 'fcm-token-123'), isNull);
      expect(repo.registeredTokens('u-marco'), isEmpty);
    });

    test('a failed write is reported like every other repository write', () async {
      final MemoryShopRepository repo = MemoryShopRepository()..failWrites = true;
      addTearDown(repo.dispose);

      final WriteFailure? failure = await repo.saveNotificationToken('u-marco', 'fcm-token-123');
      expect(failure, isNotNull);
      expect(failure!.operation, contains('register device'));
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
        'shiftEvents',
        'drivers',
        'addresses',
        'paymentMethods',
        'paymentGatewayCustomers',
        'notificationTokens',
        'users',
      ];

      final List<String> used = <String>[
        FirestorePaths.menuItems,
        FirestorePaths.menuCategories,
        FirestorePaths.promos,
        FirestorePaths.settings,
        FirestorePaths.orders,
        FirestorePaths.staffMembers,
        FirestorePaths.shiftEvents,
        FirestorePaths.addresses,
        FirestorePaths.paymentMethods,
        FirestorePaths.paymentGatewayCustomers,
        FirestorePaths.notificationTokens,
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

    test('a payment-method document id is namespaced by uid', () {
      // Two customers linking their own GCash share the account id; the doc it
      // lands on must still be private per customer.
      expect(
        FirestorePaths.paymentMethodDoc('u-a', 'pm-gcash'),
        isNot(FirestorePaths.paymentMethodDoc('u-b', 'pm-gcash')),
      );
      // And the saved method mirrors the address pattern.
      expect(FirestorePaths.paymentMethodDoc('u-marco', 'pm-gcash'), 'u-marco_pm-gcash');
    });
  });
}