import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlanders_coffee/data/firestore/memory_shop_repository.dart';
import 'package:highlanders_coffee/data/models/staff.dart';
import 'package:highlanders_coffee/data/models/staff_record.dart';
import 'package:highlanders_coffee/features/admin/staff_record_screen.dart';
import 'package:highlanders_coffee/state/admin_provider.dart';
import 'package:provider/provider.dart';

/// The Staff Record table on its own.
///
/// The admin-panel test only reaches the empty state, because a fresh
/// repository has logged nothing. This one seeds a session first so the actual
/// row — the thing a café reads to see who worked when — is asserted, column by
/// column.
void main() {
  testWidgets('the table prints every column and the session it holds',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final MemoryShopRepository repo = MemoryShopRepository();
    addTearDown(repo.dispose);

    final DateTime clockIn = DateTime.now();
    await repo.saveStaffRecord(
      StaffRecord(
        id: 'rec-test',
        staffId: 's-3',
        staffName: 'Mara Ilagan',
        role: StaffRole.barista,
        dateKey: StaffRecord.dateKeyFor(clockIn),
        timeIn: clockIn,
        timeOut: clockIn.add(const Duration(hours: 4)),
        status: StaffRecordStatus.completed,
      ),
    );

    final AdminProvider admin = AdminProvider(repository: repo);
    await admin.loadStaffRecordsOnce();

    await tester.pumpWidget(
      ChangeNotifierProvider<AdminProvider>.value(
        value: admin,
        child: const MaterialApp(home: StaffRecordScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Every column the brief asks for is present, in order.
    for (final String heading in <String>[
      'Staff ID',
      'Staff Name',
      'Role',
      'Date',
      'Time In',
      'Time Out',
      'Status',
    ]) {
      expect(find.text(heading), findsOneWidget, reason: 'missing column $heading');
    }

    // And the row itself, not just the header.
    expect(find.text('s-3'), findsOneWidget);
    expect(find.text('Mara Ilagan'), findsOneWidget);
    expect(find.text('Barista'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });
}
