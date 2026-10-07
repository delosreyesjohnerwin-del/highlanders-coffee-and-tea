import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlanders_coffee/app.dart';
import 'package:highlanders_coffee/core/firebase/firebase_bootstrap.dart';
import 'package:highlanders_coffee/core/widgets/bw_card.dart';
import 'package:highlanders_coffee/data/mock/mock_data.dart';
import 'package:highlanders_coffee/data/models/coverage.dart';
import 'package:highlanders_coffee/data/models/order.dart';
import 'package:highlanders_coffee/features/address/address_form_screen.dart';
import 'package:highlanders_coffee/features/address/saved_addresses_screen.dart';
import 'package:highlanders_coffee/features/home/widgets/menu_item_card.dart';
import 'package:highlanders_coffee/features/shell/app_shell.dart';
import 'package:highlanders_coffee/features/shell/bw_bottom_nav.dart';
import 'package:highlanders_coffee/state/cart_provider.dart';
import 'package:highlanders_coffee/state/catalog_provider.dart';
import 'package:highlanders_coffee/state/session_provider.dart';

/// The delivery-address feature: GPS-aware distance maths, the saved-address
/// store (upsert + default handling) and the two screens that drive it — the
/// Profile list and the in-cart quick-add/edit/delete.
///
/// The widget flows ride the real provider graph (via [HighlandersApp]) so the
/// cart/session sync is exercised, not stubbed: adding on the cart must select
/// the new address, and deleting the selected one must clear the destination.
void main() {
  /// A Pixel-ish portrait surface: 360 x 780 logical.
  Future<void> usePhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpApp(WidgetTester tester, {Widget? home}) async {
    ShellNav.reset();
    FirebaseBootstrap.resetForTest();
    await tester.pumpWidget(HighlandersApp(home: home));
    await tester.pumpAndSettle();
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(of: find.byType(BwBottomNav), matching: find.text(label)),
    );
    await tester.pumpAndSettle();
  }

  bool matchesAny(WidgetTester tester, Finder finder) {
    try {
      return tester.any(finder);
    } on StateError {
      return false;
    }
  }

  bool fullyVisible(WidgetTester tester, Finder target, Finder scrollable) {
    final Rect r = tester.getRect(target);
    final Rect v = tester.getRect(scrollable);
    return r.top >= v.top && r.bottom <= v.bottom;
  }

  Future<void> revealByDragging(
    WidgetTester tester,
    Finder target,
    Finder scrollable, {
    int maxSteps = 24,
    double step = 220,
  }) async {
    for (int i = 0; i < maxSteps && !matchesAny(tester, target); i++) {
      await tester.drag(scrollable, Offset(0, -step));
      await tester.pumpAndSettle();
    }
    if (!matchesAny(tester, target)) return;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    if (!fullyVisible(tester, target, scrollable)) {
      final Rect r = tester.getRect(target);
      final Rect v = tester.getRect(scrollable);
      if (r.bottom > v.bottom) {
        await tester.drag(scrollable, Offset(0, -(r.bottom - v.bottom + 8)));
        await tester.pumpAndSettle();
      }
    }
  }

  /// Adds one Hawaiian sandwich to the cart from the home menu.
  Future<void> addItemToCart(WidgetTester tester) async {
    await revealByDragging(
      tester,
      find.text('Hawaiian'),
      find.byType(CustomScrollView),
    );
    final Finder plus = find.descendant(
      of: find.ancestor(of: find.text('Hawaiian'), matching: find.byType(MenuItemCard)),
      matching: find.byIcon(Icons.add_rounded),
    );
    await tester.tap(plus);
    await tester.pumpAndSettle();
  }

  /// Scrolls [target] into being (lazy lists build on demand), then nudges it
  /// clear of the bottom checkout bar / nav so a tap lands on it.
  ///
  /// `tester.ensureVisible` turns out to be a no-op inside these nested
  /// screens, so the reveal is a plain drag loop plus one corrective drag.
  Future<void> revealForTap(WidgetTester tester, Finder target) async {
    final Finder list = find.byType(ListView).first;
    for (int i = 0; i < 10 && !matchesAny(tester, target); i++) {
      await tester.drag(list, const Offset(0, -220));
      await tester.pumpAndSettle();
    }
    if (!matchesAny(tester, target)) return;

    final Rect r = tester.getRect(target);
    if (r.center.dy > 520) {
      await tester.drag(list, Offset(0, -(r.center.dy - 360)));
      await tester.pumpAndSettle();
    }
    await tester.tap(target);
  }

  /// Fills the address form: custom label, street, barangay, then saves.
  Future<void> fillAndSaveForm(
    WidgetTester tester, {
    required String label,
    required String street,
    required String barangay,
    bool asDefault = false,
  }) async {
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Custom label'), label);
    await tester.enterText(find.widgetWithText(TextFormField, 'Street / landmark'), street);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(barangay).last);
    await tester.pumpAndSettle();

    if (asDefault) {
      await revealForTap(tester, find.text('Use as my default address'));
      await tester.pumpAndSettle();
    }

    await revealForTap(tester, find.text('Save address'));
    await tester.pumpAndSettle();
  }

  group('distance maths', () {
    test('a legacy address (no pin) uses its barangay centroid', () {
      const SavedAddress legacy = SavedAddress(
        id: 'a',
        label: 'Home',
        street: '123 Poblacion Road',
        barangayCode: 'lumban-poblacion',
      );

      final double? km = legacy.distanceKm();

      const Barangay poblacion = Barangay(code: 'lumban-poblacion', name: 'Poblacion', lat: 14.2919, lng: 121.4644);
      expect(km, isNotNull);
      expect(km, closeTo(haversineKm(
        lat1: LumbanCoverage.cafeLat,
        lng1: LumbanCoverage.cafeLng,
        lat2: poblacion.lat,
        lng2: poblacion.lng,
      ), 1e-9));
    });

    test('a pinned address at the café reads as zero', () {
      const SavedAddress atCafe = SavedAddress(
        id: 'a',
        label: 'Home',
        street: '1 Mug St',
        barangayCode: 'lumban-marawoy',
        lat: 14.2919,
        lng: 121.4644,
      );

      // The barangay says Marawoy (several hundred metres away), but the pin
      // wins — the fee must be for where the rider is actually going.
      expect(atCafe.distanceKm(), closeTo(0, 1e-6));
    });

    test('a pinned address honours the passed café origin', () {
      const SavedAddress pin = SavedAddress(
        id: 'a',
        label: 'Home',
        street: '88 Lakambini St',
        barangayCode: 'lumban-santo-nino',
        lat: 14.3130,
        lng: 121.4470,
      );

      final double actual = pin.distanceKm(cafeLat: 14.0000, cafeLng: 121.0000)!;

      expect(actual, closeTo(
        haversineKm(lat1: 14.0000, lng1: 121.0000, lat2: 14.3130, lng2: 121.4470),
        1e-9,
      ));
    });

    test('an unknown barangay with no pin has no distance', () {
      const SavedAddress unknown = SavedAddress(
        id: 'a',
        label: 'Home',
        street: 'Nowhere',
        barangayCode: 'not-in-lumban',
      );

      expect(unknown.distanceKm(), isNull);
    });
  });

  group('session address store', () {
    test('addAddress replaces an existing id instead of duplicating', () {
      final SessionProvider session = SessionProvider();

      session.addAddress(const SavedAddress(
        id: 'a-home',
        label: 'Home',
        street: '100 New Road',
        barangayCode: 'lumban-santol',
      ));

      expect(session.addresses, hasLength(2));
      expect(session.addresses.firstWhere((SavedAddress a) => a.id == 'a-home').street, '100 New Road');
    });

    test('a new default clears the previous default', () {
      final SessionProvider session = SessionProvider();

      session.addAddress(const SavedAddress(
        id: 'a-condo',
        label: 'Condo',
        street: '5 Torre St',
        barangayCode: 'lumban-santol',
        isDefault: true,
      ));

      expect(session.addresses.where((SavedAddress a) => a.isDefault), hasLength(1));
      expect(session.addresses.firstWhere((SavedAddress a) => a.id == 'a-condo').isDefault, isTrue);
      expect(session.addresses.firstWhere((SavedAddress a) => a.id == 'a-home').isDefault, isFalse);
      expect(session.defaultAddress?.id, 'a-condo');
    });

    test('editing the default without the flag demotes it', () {
      final SessionProvider session = SessionProvider();

      session.addAddress(const SavedAddress(
        id: 'a-home',
        label: 'Home',
        street: '5 Torre St',
        barangayCode: 'lumban-santol',
        isDefault: false,
      ));

      expect(session.addresses.where((SavedAddress a) => a.isDefault), isEmpty);
      // The getter falls back to the first address when nothing is flagged —
      // no address is ever "missing" a default.
      expect(session.defaultAddress?.id, 'a-home');
    });

    test('an address deleted while selected is pruned from the cart', () {
      final CartProvider cart = CartProvider(CatalogProvider());
      cart.setAddresses(MockData.addresses);
      cart.selectAddress('a-home');
      expect(cart.addressSnapshot, isNotNull);

      cart.setAddresses(MockData.addresses.where((SavedAddress a) => a.id != 'a-home').toList());

      expect(cart.addressId, isNull);
      expect(cart.addressSnapshot, isNull);
    });
  });

  group('saved addresses screen', () {
    testWidgets('profile opens the saved addresses list with the default badge',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      await tapTab(tester, 'Profile');
      await tester.ensureVisible(find.text('Saved Addresses'));
      await tester.tap(find.text('Saved Addresses'));
      await tester.pumpAndSettle();

      expect(find.byType(SavedAddressesScreen), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('123 Poblacion Road'), findsOneWidget);
      expect(find.text('45 Dagatan Street'), findsOneWidget);
      // Only the seeded Home address carries the badge.
      expect(find.text('Default'), findsOneWidget);
    });

    testWidgets('adding an address as default moves the badge', (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      await tapTab(tester, 'Profile');
      await tester.ensureVisible(find.text('Saved Addresses'));
      await tester.tap(find.text('Saved Addresses'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add new address'));
      await tester.pumpAndSettle();
      expect(find.byType(AddressFormScreen), findsOneWidget);

      await fillAndSaveForm(
        tester,
        label: 'Gym',
        street: '88 Lakambini St',
        barangay: 'Santo Niño',
        asDefault: true,
      );

      // Back on the list: the new street is there, and exactly one address
      // still carries the default badge — and it must be the new one, i.e. the
      // old Home lost it rather than the toggle having been ignored.
      expect(find.byType(SavedAddressesScreen), findsOneWidget);
      expect(find.text('88 Lakambini St'), findsOneWidget);
      expect(find.text('Gym'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
      final Finder badgeCard = find
          .ancestor(of: find.text('Default'), matching: find.byType(BwCard))
          .first;
      expect(
        find.descendant(of: badgeCard, matching: find.text('88 Lakambini St')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: badgeCard, matching: find.text('123 Poblacion Road')),
        findsNothing,
      );
    });

    testWidgets('an address can be edited and deleted from the list',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);

      await tapTab(tester, 'Profile');
      await tester.ensureVisible(find.text('Saved Addresses'));
      await tester.tap(find.text('Saved Addresses'));
      await tester.pumpAndSettle();

      // Edit Work: the form must come up pre-filled.
      await tester.tap(find.byTooltip('Edit Work'));
      await tester.pumpAndSettle();
      expect(find.byType(AddressFormScreen), findsOneWidget);
      expect(find.text('45 Dagatan Street'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Street / landmark'),
        '99 New Street',
      );
      await revealForTap(tester, find.text('Save address'));
      await tester.pumpAndSettle();

      expect(find.text('99 New Street'), findsOneWidget);
      expect(find.text('45 Dagatan Street'), findsNothing);

      // Delete it: confirm first, then the row is gone.
      await tester.tap(find.byTooltip('Delete Work'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Work?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('99 New Street'), findsNothing);
      expect(find.text('Work'), findsNothing);
    });
  });

  group('cart address flows', () {
    testWidgets('quick-add saves the address and selects it', (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);
      await addItemToCart(tester);

      await tapTab(tester, 'Cart');
      expect(find.byIcon(Icons.radio_button_checked_rounded), findsNothing);

      await revealForTap(tester, find.text('Add a new address'));
      await tester.pumpAndSettle();
      expect(find.byType(AddressFormScreen), findsOneWidget);

      await fillAndSaveForm(
        tester,
        label: 'Gym',
        street: '88 Lakambini St',
        barangay: 'Santo Niño',
      );

      // Back on the cart: the new address is listed and auto-selected.
      expect(find.byType(AddressFormScreen), findsNothing);
      expect(find.text('Gym'), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
    });

    testWidgets('deleting the selected address clears the delivery destination',
        (WidgetTester tester) async {
      await usePhone(tester);
      await pumpApp(tester);
      await addItemToCart(tester);

      await tapTab(tester, 'Cart');

      // Select the seeded Home address.
      await tester.tap(find.text('Home').first);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);

      // Delete it from the cart row.
      await tester.tap(find.byTooltip('Delete Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('123 Poblacion Road'), findsNothing);
      // The pruned selection means no as-selected radio remains.
      expect(find.byIcon(Icons.radio_button_checked_rounded), findsNothing);
    });
  });
}