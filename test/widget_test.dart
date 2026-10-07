import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:highlanders_coffee/app.dart';
import 'package:highlanders_coffee/core/theme/bw_colors.dart';
import 'package:highlanders_coffee/core/utils/formatters.dart';
import 'package:highlanders_coffee/data/models/coverage.dart';

void main() {
  testWidgets('renders the four tab shell', (WidgetTester tester) async {
    await tester.pumpWidget(const HighlandersApp());

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Cart'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('empty cart shows the empty state', (WidgetTester tester) async {
    await tester.pumpWidget(const HighlandersApp());

    // Switch to the Cart tab.
    await tester.tap(find.text('Cart'));
    await tester.pumpAndSettle();

    expect(find.text('Your cart is empty'), findsOneWidget);
    expect(find.text('Add items from the menu to get started.'), findsOneWidget);
  });

  group('Fmt', () {
    test('formats peso', () {
      expect(Fmt.peso(185), r'₱185.00');
    });

    test('formats peso without decimals', () {
      expect(Fmt.pesoWhole(185), r'₱185');
    });

    test('formats short distances in metres', () {
      expect(Fmt.distance(0.3), '300 m');
    });

    test('formats distances in kilometres', () {
      expect(Fmt.distance(1.2), '1.2 km');
    });
  });

  group('DeliveryPricing', () {
    const DeliveryPricing pricing = DeliveryPricing(freeOver: 500);

    test('uses the first tier for very short distances', () {
      expect(pricing.feeFor(km: 1.0, subtotal: 100), 25);
    });

    test('steps up through the tiers', () {
      expect(pricing.feeFor(km: 2.0, subtotal: 100), 35);
      expect(pricing.feeFor(km: 4.0, subtotal: 100), 45);
      expect(pricing.feeFor(km: 6.0, subtotal: 100), 55);
      expect(pricing.feeFor(km: 12.0, subtotal: 100), 65);
    });

    test('waives the fee above the free-delivery threshold', () {
      expect(pricing.feeFor(km: 4.0, subtotal: 500), 0);
      expect(pricing.feeFor(km: 4.0, subtotal: 499), 45);
    });

    test('coverage respects the radius', () {
      expect(pricing.covers(8), isTrue);
      expect(pricing.covers(12), isFalse);
    });
  });

  test('haversine returns zero for identical points', () {
    final double d = haversineKm(lat1: 14.2919, lng1: 121.4644, lat2: 14.2919, lng2: 121.4644);
    expect(d, closeTo(0, 0.0001));
  });

  test('bundled Lumban barangays are all resolvable', () {
    for (final Barangay b in LumbanCoverage.barangays) {
      expect(LumbanCoverage.byCode(b.code), isNotNull);
      expect(LumbanCoverage.distanceToBarangay(b), greaterThanOrEqualTo(0));
    }
  });

  test('neutrals stay strictly monochrome', () {
    // Every neutral token must have r == g == b.
    for (final Color c in <Color>[
      BwColors.bg,
      BwColors.subtle,
      BwColors.border,
      BwColors.borderStrong,
      BwColors.text,
      BwColors.textMuted,
      BwColors.onInverse,
    ]) {
      // Colour channel access via toARGB32(); the .r/.g/.b accessors are
      // deprecated in current Flutter.
      final int argb = c.toARGB32();
      final int r = (argb >> 16) & 0xFF;
      final int g = (argb >> 8) & 0xFF;
      final int b = argb & 0xFF;

      expect(r, g, reason: 'red/green mismatch in $c');
      expect(g, b, reason: 'green/blue mismatch in $c');
    }
  });

  test('the accent is the Highlanders brand green', () {
    expect(BwColors.inverse.toARGB32(), 0xFF363F2C, reason: 'accent must carry the logo green');
  });
}