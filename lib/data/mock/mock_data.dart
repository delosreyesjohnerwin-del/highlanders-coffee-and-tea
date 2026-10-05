import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/menu.dart';
import '../models/order.dart';
import '../models/staff.dart';

/// Seed data used before Firebase is wired up, and as the reference fixture
/// for the real Highlanders menu.
///
/// TODO(owner): replace with the café's actual menu, prices and product photos
/// once Firebase is connected. Prices are in PHP.
class MockData {
  const MockData._();

  static const AppUser user = AppUser(
    uid: 'u-marco',
    fullName: 'Marco Reyes',
    email: 'marco.reyes@email.com',
    phone: '+63 917 000 0000',
    memberTier: 'Gold Member',
    orderCount: 47,
    reviewCount: 12,
    rewards: 230,
  );

  static const AppUser admin = AppUser(
    uid: 'u-admin',
    fullName: 'Café Admin',
    email: 'admin@highlanderscoffee.ph',
    role: UserRole.admin,
    memberTier: 'Gold Member',
    orderCount: 1284,
    reviewCount: 96,
    rewards: 0,
  );

  static const List<MenuCategory> categories = <MenuCategory>[
    MenuCategory(id: 'coffee', label: 'Coffee', sortOrder: 0, icon: Icons.coffee_outlined),
    MenuCategory(id: 'brews', label: 'Brews', sortOrder: 1, icon: Icons.emoji_food_beverage_outlined),
    MenuCategory(id: 'noncoffee', label: 'Non-Coffee', sortOrder: 2, icon: Icons.local_drink_outlined),
    MenuCategory(id: 'pastries', label: 'Pastries', sortOrder: 3, icon: Icons.bakery_dining_outlined),
    MenuCategory(id: 'meals', label: 'Meals', sortOrder: 4, icon: Icons.restaurant_outlined),
  ];

  static const List<MenuItem> menu = <MenuItem>[
    MenuItem(
      id: 'm-kopi',
      stock: 120,
      categoryId: 'coffee',
      name: 'Kopi Filipino',
      price: 55,
      description: 'The everyday local classic. Dark roast, evaporated milk, '
          'served hot or over ice. Strong, smooth and unapologetically Filipino.',
      isBestseller: true,
      prepMinutes: 4,
      sortOrder: 0,
    ),
    MenuItem(
      id: 'm-americano',
      stock: 64,
      categoryId: 'coffee',
      name: 'Americano',
      price: 90,
      description: 'Double espresso lengthened with hot water. Clean, balanced '
          'and lets the beans speak for themselves.',
      prepMinutes: 4,
      sortOrder: 1,
    ),
    MenuItem(
      id: 'm-latte',
      stock: 48,
      categoryId: 'coffee',
      name: 'Caffè Latte',
      price: 120,
      description: 'Silky steamed milk with a double shot poured through a '
          'fine microfoam. Soft and creamy with a light brown finish.',
      isBestseller: true,
      prepMinutes: 5,
      sortOrder: 2,
    ),
    MenuItem(
      id: 'm-cappuccino',
      stock: 32,
      categoryId: 'coffee',
      name: 'Cappuccino',
      price: 120,
      description: 'Equal parts espresso, steamed milk and dense foam. '
          'Finished with a dusting of cocoa.',
      prepMinutes: 5,
      sortOrder: 3,
    ),
    MenuItem(
      id: 'm-mocha',
      stock: 9,
      categoryId: 'coffee',
      name: 'Mocha',
      price: 135,
      description: 'Espresso and single-origin chocolate, lifted with steamed '
          'milk. Rich and dessert-adjacent.',
      prepMinutes: 6,
      sortOrder: 4,
    ),
    MenuItem(
      id: 'm-espresso',
      stock: 80,
      categoryId: 'coffee',
      name: 'Espresso',
      price: 75,
      description: 'A single concentrated shot with a deep amber crema. '
          'Order a doppio if you need more.',
      prepMinutes: 3,
      sortOrder: 5,
    ),
    MenuItem(
      id: 'm-colds',
      stock: 26,
      categoryId: 'brews',
      name: 'Cold Brew',
      price: 130,
      description: 'Steeped for 18 hours at low temperature. Smooth, '
          'low-acid and naturally sweet with no sugar added.',
      isBestseller: true,
      prepMinutes: 3,
      sortOrder: 0,
    ),
    MenuItem(
      id: 'm-icedlatte',
      stock: 40,
      categoryId: 'brews',
      name: 'Iced Latte',
      price: 125,
      description: 'Double shot poured over ice and cold milk. '
          'The reliable afternoon order.',
      isBestseller: true,
      prepMinutes: 4,
      sortOrder: 1,
    ),
    MenuItem(
      id: 'm-mochafrappe',
      stock: 4,
      categoryId: 'brews',
      name: 'Mocha Frappe',
      price: 150,
      description: 'Blended espresso, chocolate and milk with whipped cream. '
          'Thick, cold and properly sweet.',
      prepMinutes: 6,
      sortOrder: 2,
    ),
    MenuItem(
      id: 'm-matcha',
      stock: 18,
      categoryId: 'noncoffee',
      name: 'Matcha Latte',
      price: 135,
      description: 'Ceremonial-grade matcha whisked with steamed milk. '
          'Grassy, calm and faintly sweet.',
      prepMinutes: 5,
      sortOrder: 0,
    ),
    MenuItem(
      id: 'm-choco',
      stock: 0,
      categoryId: 'noncoffee',
      name: 'Choco Latte',
      price: 125,
      description: 'Dark chocolate and steamed milk. Caffeine-light and '
          'comforting, served hot or iced.',
      prepMinutes: 5,
      sortOrder: 1,
    ),
    MenuItem(
      id: 'm-tea',
      stock: 55,
      categoryId: 'noncoffee',
      name: 'Fresh Brewed Tea',
      price: 60,
      description: 'Loose-leaf black tea brewed to order. Ask for lemon, '
          'or enjoy it plain.',
      isAvailable: true,
      prepMinutes: 3,
      sortOrder: 2,
    ),
    MenuItem(
      id: 'm-croissant',
      stock: 30,
      categoryId: 'pastries',
      name: 'Butter Croissant',
      price: 85,
      description: 'Laminated 27 times for shatteringly crisp layers, '
          'baked fresh each morning.',
      isBestseller: true,
      prepMinutes: 2,
      sortOrder: 0,
    ),
    MenuItem(
      id: 'm-ensaymada',
      stock: 22,
      categoryId: 'pastries',
      name: 'Ensaymada',
      price: 75,
      description: 'Soft sweet bread crowned with butter, sugar and salted egg. '
          'A proper Pinoy classic.',
      prepMinutes: 2,
      sortOrder: 1,
    ),
    MenuItem(
      id: 'm-empanada',
      stock: 6,
      categoryId: 'pastries',
      name: 'Beef Empanada',
      price: 65,
      description: 'Flaky pastry packed with spiced beef and vegetables, '
          'baked to order.',
      prepMinutes: 6,
      sortOrder: 2,
    ),
    MenuItem(
      id: 'm-chocobread',
      stock: 38,
      categoryId: 'pastries',
      name: 'Choco Bread',
      price: 55,
      description: 'Soft milk bread rolled in chocolate sprinkles. '
          'Best with a fresh cup.',
      prepMinutes: 1,
      sortOrder: 3,
    ),
    MenuItem(
      id: 'm-sandwich',
      stock: 14,
      categoryId: 'meals',
      name: 'Ham & Cheese Panini',
      price: 165,
      description: 'Griddled ham and cheese with herbs on toasted sourdough. '
          'Served with a pickle spear.',
      prepMinutes: 8,
      sortOrder: 0,
    ),
    MenuItem(
      id: 'm-pasta',
      stock: 9,
      categoryId: 'meals',
      name: 'Creamy Carbonara',
      price: 195,
      description: 'Spaghetti with bacon, egg and Parmesan in a cream sauce. '
          'Black pepper, no shortcuts.',
      isBestseller: true,
      prepMinutes: 12,
      sortOrder: 1,
    ),
    MenuItem(
      id: 'm-tray',
      stock: 16,
      categoryId: 'meals',
      name: 'Highlanders Breakfast Tray',
      price: 245,
      description: 'Two eggs any style, garlic rice, fried sausage and a '
          'cup of freshly brewed coffee. Served 7am to 11am.',
      prepMinutes: 14,
      sortOrder: 2,
    ),
  ];

  static const List<Promo> promos = <Promo>[
    Promo(
      code: 'DAMPOTIST',
      title: 'Free Delivery on your first order',
      subtitle: 'Use code DAMPOTIST at checkout',
      badge: 'NEW HERE',
      ctaLabel: 'Order Now',
    ),
    Promo(
      code: 'BOGO-COFFEE',
      title: 'Buy 1 Get 1',
      subtitle: 'On all brewed coffee, Mon to Fri',
      badge: 'BOGO',
      buyXGetY: 'Buy 1 Get 1',
    ),
    Promo(
      code: 'TAKE20',
      title: '20% OFF',
      subtitle: 'On your pastry order over ₱200',
      badge: '20% OFF',
      discountPercent: 20,
    ),
  ];

  static const List<SavedAddress> addresses = <SavedAddress>[
    SavedAddress(
      id: 'a-home',
      label: 'Home',
      street: '123 Poblacion Road',
      barangayCode: 'lumban-poblacion',
      isDefault: true,
    ),
    SavedAddress(
      id: 'a-work',
      label: 'Work',
      street: '45 Dagatan Street',
      barangayCode: 'lumban-dagatan',
    ),
  ];

  static List<Order> ordersFor(String userId) {
    final DateTime now = DateTime.now();

    return <Order>[
      Order(
        id: 'HL-2601-4820',
        lines: const <OrderLine>[
          OrderLine(itemId: 'm-icedlatte', name: 'Iced Latte', price: 125, quantity: 2),
          OrderLine(itemId: 'm-croissant', name: 'Butter Croissant', price: 85, quantity: 1),
        ],
        status: OrderStatus.delivered,
        fulfillment: Fulfillment.delivery,
        paymentMethod: PaymentMethod.gcash,
        createdAt: now.subtract(const Duration(days: 2, hours: 5)),
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
        paymentRef: 'PAY-9F2A41',
      ),
      Order(
        id: 'HL-2601-5155',
        lines: const <OrderLine>[
          OrderLine(itemId: 'm-pasta', name: 'Creamy Carbonara', price: 195, quantity: 1),
          OrderLine(itemId: 'm-colds', name: 'Cold Brew', price: 130, quantity: 1),
        ],
        status: OrderStatus.delivered,
        fulfillment: Fulfillment.delivery,
        paymentMethod: PaymentMethod.cash,
        createdAt: now.subtract(const Duration(days: 6, hours: 2)),
        subtotal: 325,
        deliveryFee: 35,
        distanceKm: 2.4,
        address: const AddressSnapshot(
          label: 'Work',
          street: '45 Dagatan Street',
          barangayCode: 'lumban-dagatan',
          barangayName: 'Dagatan',
          distanceKm: 2.4,
        ),
        pickupCode: '5155',
        driverName: 'Rodel',
      ),
      Order(
        id: 'HL-2601-6372',
        lines: const <OrderLine>[
          OrderLine(itemId: 'm-tray', name: 'Highlanders Breakfast Tray', price: 245, quantity: 1),
        ],
        status: OrderStatus.outForDelivery,
        fulfillment: Fulfillment.delivery,
        paymentMethod: PaymentMethod.gcash,
        createdAt: now.subtract(const Duration(minutes: 32)),
        subtotal: 245,
        deliveryFee: 0,
        distanceKm: 0.9,
        address: const AddressSnapshot(
          label: 'Home',
          street: '123 Poblacion Road',
          barangayCode: 'lumban-poblacion',
          barangayName: 'Poblacion',
          distanceKm: 0.9,
        ),
        pickupCode: '6372',
        driverName: 'Marlon',
        driverPhone: '+63 917 555 0142',
        promoCode: 'DAMPOTIST',
      ),
    ];
  }

  // Not const: the timestamps are fixed literals for reproducible fixtures.
  static final List<Order> adminQueue = <Order>[
    Order(
      id: 'HL-2601-6372',
      lines: <OrderLine>[
        OrderLine(itemId: 'm-tray', name: 'Highlanders Breakfast Tray', price: 245, quantity: 1),
      ],
      status: OrderStatus.outForDelivery,
      fulfillment: Fulfillment.delivery,
      paymentMethod: PaymentMethod.gcash,
      createdAt: DateTime(2026, 10, 1, 8, 30),
      subtotal: 245,
      deliveryFee: 0,
      customerName: 'Marco Reyes',
      driverName: 'Marlon',
      driverPhone: '+63 917 555 0142',
      pickupCode: '6372',
      promoCode: 'DAMPOTIST',
    ),
    Order(
      id: 'HL-2601-6390',
      lines: <OrderLine>[
        OrderLine(itemId: 'm-latte', name: 'Caffè Latte', price: 120, quantity: 2),
        OrderLine(itemId: 'm-ensaymada', name: 'Ensaymada', price: 75, quantity: 1),
      ],
      status: OrderStatus.preparing,
      fulfillment: Fulfillment.delivery,
      paymentMethod: PaymentMethod.paymaya,
      createdAt: DateTime(2026, 10, 1, 9, 2),
      subtotal: 315,
      deliveryFee: 25,
      customerName: 'Ana Villanueva',
      pickupCode: '6390',
    ),
    Order(
      id: 'HL-2601-6404',
      lines: <OrderLine>[
        OrderLine(itemId: 'm-mochafrappe', name: 'Mocha Frappe', price: 150, quantity: 2),
      ],
      status: OrderStatus.pending,
      fulfillment: Fulfillment.pickup,
      paymentMethod: PaymentMethod.cash,
      createdAt: DateTime(2026, 10, 1, 9, 14),
      subtotal: 300,
      customerName: 'Jomar Bautista',
      pickupCode: '6404',
    ),
  ];

  // --- staff --------------------------------------------------------------

  static const List<StaffMember> staff = <StaffMember>[
    StaffMember(
      id: 's-1',
      name: 'Aiko Ramos',
      role: StaffRole.owner,
      shift: ShiftStatus.onShift,
      phone: '+63 917 000 0001',
      completedToday: 12,
    ),
    StaffMember(
      id: 's-2',
      name: 'Benigno Lara',
      role: StaffRole.manager,
      shift: ShiftStatus.onShift,
      phone: '+63 917 000 0002',
      completedToday: 9,
    ),
    StaffMember(
      id: 's-3',
      name: 'Carla Mendoza',
      role: StaffRole.barista,
      shift: ShiftStatus.onShift,
      phone: '+63 917 000 0003',
      completedToday: 31,
    ),
    StaffMember(
      id: 's-4',
      name: 'Dionisio Uy',
      role: StaffRole.barista,
      shift: ShiftStatus.onBreak,
      phone: '+63 917 000 0004',
      completedToday: 22,
    ),
    StaffMember(
      id: 's-5',
      name: 'Elena Torres',
      role: StaffRole.rider,
      shift: ShiftStatus.onDelivery,
      phone: '+63 917 555 0142',
      completedToday: 7,
    ),
    StaffMember(
      id: 's-6',
      name: 'Francis Avecilla',
      role: StaffRole.rider,
      shift: ShiftStatus.offShift,
      phone: '+63 917 555 0188',
    ),
  ];

  // --- trading history ----------------------------------------------------

  /// Seven days of settled orders, used by the admin analytics and sales
  /// report.
  ///
  /// Deliberately generated from a fixed seed rather than hardcoded: forty-odd
  /// literal `Order` objects would be unreadable, and `Random(seed)` is
  /// deterministic, so the charts look identical on every launch.
  static final List<Order> tradingHistory = _buildTradingHistory();

  static List<Order> _buildTradingHistory() {
    final math.Random rng = math.Random(20261001);
    final DateTime today = DateTime.now();
    final DateTime midnight = DateTime(today.year, today.month, today.day);

    const List<String> customers = <String>[
      'Ana Villanueva',
      'Jomar Bautista',
      'Kyla Ramos',
      'Marco Reyes',
      'Nina Toledo',
      'Paolo Aquino',
      'Rina Santiago',
      'Tito Buenaventura',
    ];

    const List<(String, String, num)> basket = <(String, String, num)>[
      ('m-kopi', 'Kopi Filipino', 55),
      ('m-americano', 'Americano', 90),
      ('m-latte', 'Caffè Latte', 120),
      ('m-cappuccino', 'Cappuccino', 120),
      ('m-colds', 'Cold Brew', 130),
      ('m-icedlatte', 'Iced Latte', 125),
      ('m-mochafrappe', 'Mocha Frappe', 150),
      ('m-croissant', 'Butter Croissant', 85),
      ('m-ensaymada', 'Ensaymada', 75),
      ('m-empanada', 'Beef Empanada', 65),
      ('m-sandwich', 'Ham & Cheese Panini', 165),
      ('m-pasta', 'Creamy Carbonara', 195),
    ];

    const List<PaymentMethod> methods = <PaymentMethod>[
      PaymentMethod.gcash,
      PaymentMethod.paymaya,
      PaymentMethod.cash,
      PaymentMethod.ebank,
    ];

    final List<Order> orders = <Order>[];

    for (int dayOffset = 6; dayOffset >= 1; dayOffset--) {
      final DateTime day = midnight.subtract(Duration(days: dayOffset));
      final int count = 5 + rng.nextInt(7);

      for (int i = 0; i < count; i++) {
        final int lineCount = 1 + rng.nextInt(3);
        final List<OrderLine> lines = <OrderLine>[];

        for (int l = 0; l < lineCount; l++) {
          // Index the record rather than destructuring it. Dart's record pattern
          // syntax wants a trailing comma inside the type, and the gain from
          // three bound names over `$1`/`$2` was not worth the noise.
          final (String, String, num) pick = basket[rng.nextInt(basket.length)];

          lines.add(OrderLine(
            itemId: pick.$1,
            name: pick.$2,
            price: pick.$3,
            quantity: 1 + rng.nextInt(2),
          ));
        }

        final num subtotal = lines.fold<num>(
          0,
          (num sum, OrderLine l) => sum + l.lineTotal,
        );

        // Roughly a third of orders are collected in cash.
        final bool isDelivery = rng.nextBool();
        final num fee = isDelivery ? (rng.nextBool() ? 25 : 35) : 0;

        orders.add(
          Order(
            id: 'HL-2609-${(dayOffset * 100 + i).toString().padLeft(4, '0')}',
            lines: lines,
            status: OrderStatus.delivered,
            fulfillment: isDelivery ? Fulfillment.delivery : Fulfillment.pickup,
            paymentMethod: methods[rng.nextInt(methods.length)],
            createdAt: day.add(
              Duration(hours: 6 + rng.nextInt(13), minutes: rng.nextInt(60)),
            ),
            subtotal: subtotal,
            deliveryFee: fee,
            distanceKm: isDelivery ? 0.8 + rng.nextDouble() * 3 : null,
            customerName: customers[rng.nextInt(customers.length)],
          ),
        );
      }
    }

    // Newest first, so list views need no extra sorting.
    orders.sort((Order a, Order b) => b.createdAt.compareTo(a.createdAt));
    return orders;
  }
}
