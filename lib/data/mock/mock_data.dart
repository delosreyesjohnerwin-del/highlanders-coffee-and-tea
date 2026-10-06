import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/menu.dart';
import '../models/order.dart';
import '../models/staff.dart';

/// Seed data used before Firebase is wired up, and as the reference fixture
/// for the real Highlanders menu.
///
/// Menu, categories and prices now come from the café's own order database
/// (categories table + menu_items table). Product photos are still pending:
/// items render with a placeholder image until the owner provides real photos,
/// which can be set per item in Firestore without a rebuild.
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

  // The café's ten categories, in menu order. The database supplies the names
  // only; the sort order follows the file and the icons are the closest
  // monochrome Material glyph per category.
  static const List<MenuCategory> categories = <MenuCategory>[
    MenuCategory(id: 'pizza', label: 'Pizza', sortOrder: 0, icon: Icons.local_pizza_outlined),
    MenuCategory(id: 'appetizers', label: 'Appetizers', sortOrder: 1, icon: Icons.ramen_dining_outlined),
    MenuCategory(id: 'wings', label: 'Chicken Wings', sortOrder: 2, icon: Icons.set_meal_outlined),
    MenuCategory(id: 'burgers', label: 'Burgers', sortOrder: 3, icon: Icons.lunch_dining_outlined),
    MenuCategory(id: 'sandwiches', label: 'Sandwiches', sortOrder: 4, icon: Icons.dinner_dining_outlined),
    MenuCategory(id: 'breakfast', label: 'All-day Breakfast', sortOrder: 5, icon: Icons.breakfast_dining_outlined),
    MenuCategory(id: 'pastas', label: 'Pastas', sortOrder: 6, icon: Icons.soup_kitchen_outlined),
    MenuCategory(id: 'classics', label: 'Classics (Espresso Based)', sortOrder: 7, icon: Icons.local_cafe_outlined),
    MenuCategory(id: 'noncoffee', label: 'Non-Coffee', sortOrder: 8, icon: Icons.local_drink_outlined),
    MenuCategory(id: 'frappes', label: 'Frappes', sortOrder: 9, icon: Icons.icecream_outlined),
  ];

  // The café's real menu: 57 items from their database. Names, categories and
  // prices are copied exactly; the database stores drinks as `price_hot` /
  // `price_cold`, and since a menu item carries one price the hot price is used
  // (identical for the five drinks where hot == cold). No descriptions or
  // photos exist in the source, so both are left for the admin panel to fill
  // in, and stock is a flat default because the database tracks none.
  static const List<MenuItem> menu = <MenuItem>[
    // --- Pizza --------------------------------------------------------------
    MenuItem(id: 'pz-hawaiian', categoryId: 'pizza', name: 'Hawaiian', price: 349, stock: 50, sortOrder: 0),
    MenuItem(id: 'pz-pepperoni', categoryId: 'pizza', name: 'Pepperoni', price: 349, stock: 50, sortOrder: 1),
    MenuItem(id: 'pz-truffle-mushroom', categoryId: 'pizza', name: 'Truffle Mushroom Bianca', price: 399, stock: 50, sortOrder: 2),
    MenuItem(id: 'pz-chicken-barbecue', categoryId: 'pizza', name: 'Chicken Barbecue', price: 429, stock: 50, sortOrder: 3),
    MenuItem(id: 'pz-all-cheese', categoryId: 'pizza', name: 'All Cheese', price: 399, stock: 50, sortOrder: 4),
    MenuItem(id: 'pz-spinach-cheese', categoryId: 'pizza', name: 'Spinach Cheese', price: 399, stock: 50, sortOrder: 5),
    MenuItem(id: 'pz-overload', categoryId: 'pizza', name: 'Overload', price: 449, stock: 50, sortOrder: 6),

    // --- Appetizers ---------------------------------------------------------
    MenuItem(id: 'ap-nachos', categoryId: 'appetizers', name: 'Nachos', price: 319, stock: 50, sortOrder: 0),
    MenuItem(id: 'ap-french-toast', categoryId: 'appetizers', name: 'Highlanders French Toast', price: 329, stock: 50, sortOrder: 1),
    MenuItem(id: 'ap-caesar-salad', categoryId: 'appetizers', name: 'Chicken Caesar Salad', price: 349, stock: 50, sortOrder: 2),
    MenuItem(id: 'ap-house-salad', categoryId: 'appetizers', name: 'Highlanders House Salad', price: 289, stock: 50, sortOrder: 3),
    MenuItem(id: 'ap-poppers-fries', categoryId: 'appetizers', name: 'Chicken Poppers & Fries', price: 249, stock: 50, sortOrder: 4),
    MenuItem(id: 'ap-nutella-waffle', categoryId: 'appetizers', name: 'Nutella Banana Waffle', price: 239, stock: 50, sortOrder: 5),

    // --- Chicken Wings ------------------------------------------------------
    MenuItem(id: 'wn-garlic-ranch', categoryId: 'wings', name: 'Garlic Ranch', price: 299, stock: 50, sortOrder: 0),
    MenuItem(id: 'wn-garlic-parmesan', categoryId: 'wings', name: 'Garlic Parmesan', price: 279, stock: 50, sortOrder: 1),
    MenuItem(id: 'wn-sweet-soy-garlic', categoryId: 'wings', name: 'Sweet Soy Garlic', price: 249, stock: 50, sortOrder: 2),
    MenuItem(id: 'wn-bbq-hot-honey', categoryId: 'wings', name: 'BBQ Hot Honey', price: 359, stock: 50, sortOrder: 3),

    // --- Burgers ------------------------------------------------------------
    MenuItem(id: 'bg-classic', categoryId: 'burgers', name: 'Classic Burger', price: 299, stock: 50, sortOrder: 0),
    MenuItem(id: 'bg-onion-bacon', categoryId: 'burgers', name: 'Onion & Bacon', price: 329, stock: 50, sortOrder: 1),
    MenuItem(id: 'bg-mushroom', categoryId: 'burgers', name: 'Mushroom Burger', price: 369, stock: 50, sortOrder: 2),
    MenuItem(id: 'bg-crispy-chicken', categoryId: 'burgers', name: 'Crispy Chicken Burger', price: 329, stock: 50, sortOrder: 3),

    // --- Sandwiches ---------------------------------------------------------
    MenuItem(id: 'sw-chicken-fajitas', categoryId: 'sandwiches', name: 'Chicken Fajitas', price: 349, stock: 50, sortOrder: 0),
    MenuItem(id: 'sw-club', categoryId: 'sandwiches', name: 'Chicken Club Sandwich', price: 329, stock: 50, sortOrder: 1),
    MenuItem(id: 'sw-ham-cheese', categoryId: 'sandwiches', name: 'Ham & Cheese', price: 199, stock: 50, sortOrder: 2),
    MenuItem(id: 'sw-tuna-melt', categoryId: 'sandwiches', name: 'Tuna Melt Sandwich', price: 239, stock: 50, sortOrder: 3),

    // --- All-day Breakfast --------------------------------------------------
    MenuItem(id: 'bf-hickory-ribs', categoryId: 'breakfast', name: 'Hickory Baby Back Ribs', price: 469, stock: 50, sortOrder: 0),
    MenuItem(id: 'bf-beef-tapa', categoryId: 'breakfast', name: 'Beef Tapa', price: 389, stock: 50, sortOrder: 1),
    MenuItem(id: 'bf-daing-bangus', categoryId: 'breakfast', name: 'Daing na Bangus', price: 379, stock: 50, sortOrder: 2),
    MenuItem(id: 'bf-ultimate-filipino', categoryId: 'breakfast', name: 'Ultimate Filipino Breakfast', price: 439, stock: 50, sortOrder: 3),
    MenuItem(id: 'bf-american', categoryId: 'breakfast', name: 'American Breakfast', price: 439, stock: 50, sortOrder: 4),
    MenuItem(id: 'bf-continental', categoryId: 'breakfast', name: 'Continental Breakfast', price: 439, stock: 50, sortOrder: 5),
    MenuItem(id: 'bf-chicken-gravy', categoryId: 'breakfast', name: 'Chicken Mushroom Gravy', price: 299, stock: 50, sortOrder: 6),

    // --- Pastas -------------------------------------------------------------
    MenuItem(id: 'ps-chicken-alfredo', categoryId: 'pastas', name: 'Chicken Alfredo', price: 349, stock: 50, sortOrder: 0),
    MenuItem(id: 'ps-carbonara', categoryId: 'pastas', name: 'Carbonara', price: 319, stock: 50, sortOrder: 1),
    MenuItem(id: 'ps-bolognese', categoryId: 'pastas', name: 'Spaghetti Bolognese', price: 289, stock: 50, sortOrder: 2),
    MenuItem(id: 'ps-pomodoro', categoryId: 'pastas', name: 'Pomodoro Pasta', price: 229, stock: 50, sortOrder: 3),
    MenuItem(id: 'ps-meatballs', categoryId: 'pastas', name: 'Spaghetti Meatballs', price: 329, stock: 50, sortOrder: 4),
    MenuItem(id: 'ps-parmigiana', categoryId: 'pastas', name: 'Chicken Parmigiana', price: 389, stock: 50, sortOrder: 5),

    // --- Classics (Espresso Based) ------------------------------------------
    MenuItem(id: 'cl-americano', categoryId: 'classics', name: 'Americano', price: 129, stock: 50, sortOrder: 0),
    MenuItem(id: 'cl-cappuccino', categoryId: 'classics', name: 'Cappuccino', price: 139, stock: 50, sortOrder: 1),
    MenuItem(id: 'cl-cafe-latte', categoryId: 'classics', name: 'Cafe Latte', price: 139, stock: 50, sortOrder: 2),
    MenuItem(id: 'cl-cafe-mocha', categoryId: 'classics', name: 'Cafe Mocha', price: 169, stock: 50, sortOrder: 3),
    MenuItem(id: 'cl-caramel-macchiato', categoryId: 'classics', name: 'Caramel Macchiato', price: 169, stock: 50, sortOrder: 4),
    MenuItem(id: 'cl-spanish-latte', categoryId: 'classics', name: 'Spanish Latte', price: 149, stock: 50, sortOrder: 5),
    MenuItem(id: 'cl-strawberry-espresso', categoryId: 'classics', name: 'Strawberry Espresso', price: 159, stock: 50, sortOrder: 6),
    MenuItem(id: 'cl-dirty-matcha', categoryId: 'classics', name: 'Dirty Matcha', price: 189, stock: 50, sortOrder: 7),

    // --- Non-Coffee ---------------------------------------------------------
    MenuItem(id: 'nc-double-chocolate', categoryId: 'noncoffee', name: 'Double Chocolate', price: 159, stock: 50, sortOrder: 0),
    MenuItem(id: 'nc-matcha-latte', categoryId: 'noncoffee', name: 'Matcha Latte', price: 169, stock: 50, sortOrder: 1),
    MenuItem(id: 'nc-mixed-berries', categoryId: 'noncoffee', name: 'Mixed Berries Latte', price: 179, stock: 50, sortOrder: 2),
    MenuItem(id: 'nc-strawberry-latte', categoryId: 'noncoffee', name: 'Strawberry Latte', price: 169, stock: 50, sortOrder: 3),
    MenuItem(id: 'nc-strawberry-matcha', categoryId: 'noncoffee', name: 'Strawberry Matcha', price: 189, stock: 50, sortOrder: 4),

    // --- Frappes ------------------------------------------------------------
    MenuItem(id: 'fr-white-choco-mocha', categoryId: 'frappes', name: 'White Choco Mocha Frappe', price: 199, stock: 50, sortOrder: 0),
    MenuItem(id: 'fr-java-chips', categoryId: 'frappes', name: 'Java Chips Frappucino', price: 199, stock: 50, sortOrder: 1),
    MenuItem(id: 'fr-coffee-caramel', categoryId: 'frappes', name: 'Coffee Caramel Frappe', price: 199, stock: 50, sortOrder: 2),
    MenuItem(id: 'fr-strawberry', categoryId: 'frappes', name: 'Strawberry Frappe', price: 179, stock: 50, sortOrder: 3),
    MenuItem(id: 'fr-matcha', categoryId: 'frappes', name: 'Matcha Frappe', price: 199, stock: 50, sortOrder: 4),
    MenuItem(id: 'fr-ube-macapuno', categoryId: 'frappes', name: 'Ube Macapuno Frappe', price: 179, stock: 50, sortOrder: 5),
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
        customerUid: userId,
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
        customerUid: userId,
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
        customerUid: userId,
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
      customerUid: 'seed-u-marco',
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
      customerUid: 'seed-u-ana',
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
      customerUid: 'seed-u-jomar',
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

    // (display name, uid) pairs. The uid is required — the security rules key
    // every order read on `customerUid`, and `seed` skips an order without one.
    // These are synthetic, matching no real account; the seeded history exists
    // to give the charts something to draw, and it is replaced before the café
    // takes real orders.
    const List<(String, String)> customers = <(String, String)>[
      ('Ana Villanueva', 'seed-u-ana'),
      ('Jomar Bautista', 'seed-u-jomar'),
      ('Kyla Ramos', 'seed-u-kyla'),
      ('Marco Reyes', 'seed-u-marco'),
      ('Nina Toledo', 'seed-u-nina'),
      ('Paolo Aquino', 'seed-u-paolo'),
      ('Rina Santiago', 'seed-u-rina'),
      ('Tito Buenaventura', 'seed-u-tito'),
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

        final (String, String) customer = customers[rng.nextInt(customers.length)];

        orders.add(
          Order(
            id: 'HL-2609-${(dayOffset * 100 + i).toString().padLeft(4, '0')}',
            customerUid: customer.$2,
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
            customerName: customer.$1,
          ),
        );
      }
    }

    // Newest first, so list views need no extra sorting.
    orders.sort((Order a, Order b) => b.createdAt.compareTo(a.createdAt));
    return orders;
  }
}
