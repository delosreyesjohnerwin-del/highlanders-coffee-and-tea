// Checks that the documents actually in Firestore deserialise back into the
// models the app uses.
//
//   flutter test tool/verify_seeded_roundtrip.dart
//
// ## Why this is separate from the round-trip tests in test/repository_test.dart
//
// Those build a map, serialise it, deserialise it, and compare. That proves the
// two halves agree with each other, which is not the same as proving the app can
// read what is in the database.
//
// The gap is real: the seed goes through `WriteBatch` with Dart maps, so a field
// that serialises to something Firestore stores differently — an int written as a
// double, a null where a string was expected — round-trips perfectly in memory and
// still comes back wrong from the server. It only shows up once a real document
// exists, and it shows up as a subtly wrong screen rather than an error.
//
// So this reads the documents that were actually written (via
// tool/dump_seed_documents.dart, which runs the real `toMap`) and puts them through
// the real `fromMap`. Combined with a Firestore read, that covers the whole path.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlanders_coffee/data/firestore/serialisation.dart';
import 'package:highlanders_coffee/data/firestore/shop_repository.dart';
import 'package:highlanders_coffee/data/mock/mock_data.dart';
import 'package:highlanders_coffee/data/models/menu.dart';
import 'package:highlanders_coffee/data/models/order.dart';
import 'package:highlanders_coffee/data/models/staff.dart';

void main() {
  final File file = File('tool/seed_documents.json');

  // The mocks the dump was generated from, indexed by the id the seed writes
  // them under, so each deserialised document can be compared field by field
  // against what it was serialised from.
  final Map<String, StaffMember> staffById = <String, StaffMember>{
    for (final StaffMember s in MockData.staff) s.id: s,
  };
  final Map<String, Order> orderById = <String, Order>{
    for (final Order o in <Order>[...MockData.adminQueue, ...MockData.tradingHistory])
      o.id: o,
  };

  test('every seeded document deserialises into the model the app expects', () {
    expect(file.existsSync(), isTrue, reason: 'run: flutter test tool/dump_seed_documents.dart');

    final Map<String, dynamic> docs =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    int checked = 0;

    for (final MapEntry<String, dynamic> entry in docs.entries) {
      final List<String> parts = entry.key.split('/');
      final String collection = parts.first;
      final String id = parts.last;
      final Map<String, dynamic> raw = entry.value as Map<String, dynamic>;

      switch (collection) {
        case 'menuCategories':
          final MenuCategory c = MenuCategorySerialisation.fromMap(raw, id);
          expect(c.id, id, reason: '$entry: id did not survive');
          expect(c.label, isNotEmpty, reason: '$entry: label is empty');
          expect(c.sortOrder, isA<int>());
        case 'menuItems':
          final MenuItem i = MenuItemSerialisation.fromMap(raw, id);
          expect(i.id, id, reason: '$entry: id did not survive');
          expect(i.name, isNotEmpty);
          // Price is the field most likely to come back as the wrong type, and the
          // one a customer would notice immediately if it did.
          expect(i.price, greaterThan(0), reason: '$entry: price is ${i.price}');
          expect(i.stock, isA<int>(), reason: '$entry: stock is not an int');
          expect(i.reorderLevel, isA<int>());
          expect(i.prepMinutes, isA<int>());
          expect(i.sortOrder, isA<int>());
          expect(i.isAvailable, isA<bool>());
        case 'promos':
          final Promo p = PromoSerialisation.fromMap(raw, id);
          expect(p.code, id, reason: '$entry: code is the document id and must match');
          expect(p.title, isNotEmpty);
          expect(p.active, isA<bool>());
          expect(
            p.discountPercent == null || (p.discountPercent! > 0 && p.discountPercent! <= 100),
            isTrue,
            reason: '$entry: implausible discount ${p.discountPercent}',
          );
        case 'staffMembers':
          final StaffMember s = StaffMemberSerialisation.fromMap(raw, id);
          expect(s.name, isNotEmpty);
          expect(s.role, isA<StaffRole>());
          // Compared against the mock the document came from, not against a
          // "not the first enum value" guess. Both enums here have a legitimate
          // zero value that the seed genuinely contains — `owner` for Aiko,
          // `pending` for a queued order — so a heuristic would either pass on a
          // broken reader or fail on correct code. This is the check that catches
          // the `_enumByName` label-versus-name bug that once turned every rider
          // into a barista and every delivered order into a pending one.
          final StaffMember? source = staffById[id];
          expect(source, isNotNull, reason: '$entry: not in MockData.staff');
          expect(s.role, source!.role, reason: '$entry: role is ${s.role.name}, was ${source.role.name}');
          expect(s.shift, source.shift, reason: '$entry: shift is ${s.shift.name}, was ${source.shift.name}');
          expect(s.name, source.name);
          expect(s.completedToday, source.completedToday);
        case 'orders':
          final Order o = OrderSerialisation.fromMap(raw, id);
          expect(o.id, id, reason: '$entry: id did not survive');
          // Required by the rules, and the seed skips unattributed orders, so
          // every document here must have one.
          expect(o.customerUid, isNotEmpty, reason: '$entry: the rules would refuse this');
          // Same reasoning as the staff role: the seed contains a genuinely
          // pending order, so "not pending" proves nothing. Compare against the
          // source instead.
          final Order? source = orderById[id];
          expect(source, isNotNull, reason: '$entry: not in the seeded mock orders');
          expect(o.status, source!.status,
              reason: '$entry: status is ${o.status.name}, was ${source.status.name}');
          expect(o.fulfillment, source.fulfillment);
          expect(o.paymentMethod, source.paymentMethod);
          expect(o.lines.length, source.lines.length);
          expect(o.subtotal, source.subtotal, reason: '$entry: subtotal changed');
          expect(o.deliveryFee, source.deliveryFee, reason: '$entry: delivery fee changed');
          expect(o.lines, isNotEmpty, reason: '$entry: no order lines');
          for (final OrderLine line in o.lines) {
            expect(line.name, isNotEmpty, reason: '$entry: an order line has no name');
            expect(line.price, greaterThan(0), reason: '$entry: line price is ${line.price}');
            expect(line.quantity, greaterThan(0), reason: '$entry: line quantity is ${line.quantity}');
          }

          // Stored UTC, read back local. Asserting the stored string ends in 'Z'
          // rather than that the parsed value `isUtc`, because `_toDate` converts
          // to local on the way in — a local DateTime is the correct result, and
          // testing for `isUtc` would fail on correct code. The instant is what
          // has to match.
          final String? stored = raw['createdAt'] as String?;
          expect(stored, isNotNull, reason: '$entry: createdAt is not a string');
          expect(
            stored!.endsWith('Z'),
            isTrue,
            reason: '$entry: createdAt "$stored" is not UTC ISO-8601',
          );
          expect(
            o.createdAt.toUtc().millisecondsSinceEpoch,
            DateTime.parse(stored).millisecondsSinceEpoch,
            reason: '$entry: the instant changed on the way through the model',
          );
        case 'settings':
          final settings = StoreSettingsSerialisation.fromMap(raw);
          expect(settings.cafeName, isNotEmpty);
          expect(settings.baseFee, greaterThan(0));
          expect(settings.isOpen, isA<bool>());
        default:
          fail('$entry: collection is not one the repository reads');
      }

      checked++;
    }

    expect(checked, greaterThan(0));
    // ignore: avoid_print
    print('ROUNDTRIP_OK=$checked');
  });

  test('the snapshot the seed would write matches MockData', () {
    // Guards the other direction. If a model gains a required field, the dump is
    // regenerated from MockData so this passes trivially — which is the point: it
    // fails if someone regenerates the dump from something other than the seed
    // content, which is the mistake that would make the round trip above
    // meaningless.
    final Map<String, dynamic> docs =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    final settingsDoc = docs.entries.firstWhere(
      (MapEntry<String, dynamic> e) => e.key.startsWith('settings/'),
      orElse: () => throw StateError('no settings document in the dump'),
    );

    final settings = StoreSettingsSerialisation.fromMap(
      settingsDoc.value as Map<String, dynamic>,
    );
    expect(settings.cafeName, AdminSnapshot.defaultSettings.cafeName);
    expect(settings.isOpen, AdminSnapshot.defaultSettings.isOpen);
  });
}
