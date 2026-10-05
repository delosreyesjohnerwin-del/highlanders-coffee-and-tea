// Dumps every Firestore document `ShopRepository.seed()` would write, as JSON.
//
//   flutter test tool/dump_seed_documents.dart
//
// Output lands in tool/seed_documents.json for tool/seed_firestore.ps1 to replay.
//
// ## Why this is a Dart program and not a PowerShell script that reads MockData
//
// Because the seed's only real risk is not a Dart bug — the repository tests cover
// that — it is whether the *live* security rules accept the documents the app
// actually produces. That has already bitten once: `orders.create` refused an
// admin writing an order attributed to another customer, and since the seed
// commits as one atomic batch the entire seed failed, menu included, surfacing as
// a bare PERMISSION_DENIED pointing at the wrong collection.
//
// A PowerShell reimplementation of the serialiser would let that regress
// silently: the probe would pass on documents shaped the way the script shapes
// them, and the app would still be refused. Running the real [toMap] extensions
// means the probe checks the exact fields and types the app sends.
//
// Writes nothing to Firestore. It only prints.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlanders_coffee/data/firestore/firestore_paths.dart';
import 'package:highlanders_coffee/data/firestore/serialisation.dart';
import 'package:highlanders_coffee/data/firestore/shop_repository.dart';
import 'package:highlanders_coffee/data/mock/mock_data.dart';
import 'package:highlanders_coffee/data/models/menu.dart';
import 'package:highlanders_coffee/data/models/order.dart';
import 'package:highlanders_coffee/data/models/staff.dart';

void main() {
  test('dump the seed documents', () {
    final Map<String, Map<String, dynamic>> docs = <String, Map<String, dynamic>>{
      for (final MenuCategory c in MockData.categories)
        '${FirestorePaths.menuCategories}/${c.id}': c.toMap(),
      for (final MenuItem i in MockData.menu)
        '${FirestorePaths.menuItems}/${i.id}': i.toMap(),
      for (final Promo p in MockData.promos)
        '${FirestorePaths.promos}/${p.code}': p.toMap(),
      for (final StaffMember s in MockData.staff)
        '${FirestorePaths.staffMembers}/${FirestorePaths.staffDoc(s.id)}': s.toMap(),
      // `adminQueue` then `tradingHistory`, matching how AdminProvider.seedFromMock
      // composes the snapshot it hands to the repository. Both, not one: the
      // queue is what the orders board renders, the history is what the revenue
      // chart and active-customer count are computed from.
      //
      // Unattributed orders are skipped here for the same reason the repository
      // skips them: `orders.create` requires a customerUid, so a batch containing
      // one would be refused in full. Mirroring that filter is deliberate — if
      // someone adds an unattributed order to the mock data, the dump goes quiet
      // about it exactly as the real seed would, rather than reporting a document
      // the app cannot actually write.
      for (final Order o in <Order>[...MockData.adminQueue, ...MockData.tradingHistory])
        if (o.customerUid.isNotEmpty) '${FirestorePaths.orders}/${o.id}': o.toMap(),
      '${FirestorePaths.settings}/${FirestorePaths.settingsDoc}':
          AdminSnapshot.defaultSettings.toMap(),
    };

    // ignore: avoid_print
    print('SEED_DOC_COUNT=${docs.length}');

    File('tool/seed_documents.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(docs));
  });
}
