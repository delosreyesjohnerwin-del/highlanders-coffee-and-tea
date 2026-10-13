import 'package:flutter/material.dart';

import 'staff.dart';

/// Where a shift session stands.
enum StaffRecordStatus { active, completed }

extension StaffRecordStatusX on StaffRecordStatus {
  String get label => switch (this) {
    StaffRecordStatus.active => 'Active Shift',
    StaffRecordStatus.completed => 'Completed',
  };

  IconData get icon => switch (this) {
    StaffRecordStatus.active => Icons.timelapse_rounded,
    StaffRecordStatus.completed => Icons.task_alt_rounded,
  };

  bool get isActive => this == StaffRecordStatus.active;
}

/// How a session was recorded.
///
/// `qr` is the kiosk scan and the normal case. `manual` keeps a session logged
/// from a provider toggle distinguishable in the table.
enum StaffRecordMethod { qr, manual }

extension StaffRecordMethodX on StaffRecordMethod {
  String get label => switch (this) {
    StaffRecordMethod.qr => 'QR badge',
    StaffRecordMethod.manual => 'Manual',
  };
}

/// One time-in / time-out session for a staff member.
///
/// This is the row the Staff Record table prints — a clock-in opens it, and the
/// matching clock-out closes the *same* document with a [timeOut] and a status
/// of [StaffRecordStatus.completed]. That is deliberately different from
/// `ShiftEvent`, which is append-only and records each transition as its own
/// document: a session has to be mutable for "log TIME IN, then update it as
/// TIME OUT" to be a single row rather than a pairing pass over a history.
@immutable
class StaffRecord {
  const StaffRecord({
    required this.id,
    required this.staffId,
    required this.staffName,
    required this.role,
    required this.dateKey,
    required this.timeIn,
    this.timeOut,
    this.status = StaffRecordStatus.active,
    this.method = StaffRecordMethod.qr,
  });

  final String id;
  final String staffId;

  /// Denormalised so a row stays readable without a join back to the roster, and
  /// so a staff member who is later removed still has a legible history.
  final String staffName;

  final StaffRole role;

  /// The local calendar day the session opened on, as `yyyy-MM-dd`.
  ///
  /// Stored rather than derived from [timeIn] at read time: deriving a day
  /// boundary from a UTC timestamp means the same session lands on a different
  /// date depending on the reader's timezone, and the table would group by
  /// whatever day the *device* happens to be in.
  final String dateKey;

  /// When the shift started.
  final DateTime timeIn;

  /// When the shift ended, or null while it is still running.
  final DateTime? timeOut;

  final StaffRecordStatus status;
  final StaffRecordMethod method;

  /// True while the member is still clocked in.
  bool get isOpen => status == StaffRecordStatus.active && timeOut == null;

  /// Worked time so far, or zero while open.
  Duration get worked =>
      timeOut == null ? Duration.zero : timeOut!.difference(timeIn);

  /// Returns a closed copy of this session.
  StaffRecord close(DateTime at) => StaffRecord(
        id: id,
        staffId: staffId,
        staffName: staffName,
        role: role,
        dateKey: dateKey,
        timeIn: timeIn,
        timeOut: at,
        status: StaffRecordStatus.completed,
        method: method,
      );

  /// The calendar-day key for [when] in the device's local time.
  static String dateKeyFor(DateTime when) {
    final String y = when.year.toString().padLeft(4, '0');
    final String m = when.month.toString().padLeft(2, '0');
    final String d = when.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
