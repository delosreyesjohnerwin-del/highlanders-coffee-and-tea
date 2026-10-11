import 'package:flutter/material.dart';

/// Which way a shift moved.
enum ShiftEventType { clockIn, clockOut }

extension ShiftEventTypeX on ShiftEventType {
  String get label => switch (this) {
    ShiftEventType.clockIn => 'Clocked in',
    ShiftEventType.clockOut => 'Clocked out',
  };

  IconData get icon => switch (this) {
    ShiftEventType.clockIn => Icons.login_rounded,
    ShiftEventType.clockOut => Icons.logout_rounded,
  };

  /// True for "clocked in", so the timeline tints consistently.
  bool get isIn => this == ShiftEventType.clockIn;
}

/// How a shift transition was recorded.
///
/// `qr` is the kiosk scan and is by far the common case. `manual` exists for a
/// provider-level fallback so an event logged from anywhere other than the
/// scanner is still distinguishable in the history.
enum ShiftEventMethod { qr, manual }

extension ShiftEventMethodX on ShiftEventMethod {
  String get label => switch (this) {
    ShiftEventMethod.qr => 'QR badge',
    ShiftEventMethod.manual => 'Manual',
  };
}

/// One entry in a staff member's attendance log.
///
/// Append-only: a clock-in and its matching clock-out are two documents, not an
/// edited pair, so the history reads as a timeline rather than a running total.
/// That also means a document is never rewritten, which keeps the write path a
/// plain `set` under an id the client mints.
@immutable
class ShiftEvent {
  const ShiftEvent({
    required this.id,
    required this.staffId,
    required this.staffName,
    required this.type,
    required this.at,
    this.method = ShiftEventMethod.qr,
  });

  final String id;
  final String staffId;

  /// Denormalised so the log stays readable without a join back to the roster —
  /// a staff member who is later removed still has a legible history.
  final String staffName;

  final ShiftEventType type;

  /// When the transition happened. Stamped from the device clock, the same
  /// trade-off `StaffMember.since` documents.
  final DateTime at;

  final ShiftEventMethod method;
}
