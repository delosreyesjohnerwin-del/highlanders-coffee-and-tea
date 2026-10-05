import 'package:flutter/material.dart';

/// A staff access level. Ordering mirrors the role field in `users/{uid}`.
enum StaffRole { owner, manager, barista, rider }

extension StaffRoleX on StaffRole {
  String get label => switch (this) {
    StaffRole.owner => 'Owner',
    StaffRole.manager => 'Manager',
    StaffRole.barista => 'Barista',
    StaffRole.rider => 'Rider',
  };

  IconData get icon => switch (this) {
    StaffRole.owner => Icons.workspace_premium_outlined,
    StaffRole.manager => Icons.supervisor_account_outlined,
    StaffRole.barista => Icons.local_cafe_outlined,
    StaffRole.rider => Icons.delivery_dining_outlined,
  };
}

/// Where a staff member is in their shift.
enum ShiftStatus { onShift, offShift, onBreak, onDelivery }

extension ShiftStatusX on ShiftStatus {
  String get label => switch (this) {
    ShiftStatus.onShift => 'On shift',
    ShiftStatus.offShift => 'Off shift',
    ShiftStatus.onBreak => 'On break',
    ShiftStatus.onDelivery => 'On delivery',
  };

  IconData get icon => switch (this) {
    ShiftStatus.onShift => Icons.check_circle_outline_rounded,
    ShiftStatus.offShift => Icons.schedule_rounded,
    ShiftStatus.onBreak => Icons.pause_circle_outline_rounded,
    ShiftStatus.onDelivery => Icons.delivery_dining_outlined,
  };

  /// Only riders can be out on a delivery.
  bool get isWorking => this != ShiftStatus.offShift;
}

/// A member of café staff.
@immutable
class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    required this.role,
    required this.shift,
    this.phone,
    this.since,
    this.completedToday = 0,
  });

  final String id;
  final String name;
  final StaffRole role;
  final ShiftStatus shift;
  final String? phone;

  /// Shift start time, when they are working.
  final DateTime? since;

  /// Orders handled today — the rider's running total, or the barista's drink
  /// count.
  final int completedToday;

  StaffMember copyWith({
    ShiftStatus? shift,
    int? completedToday,
    DateTime? since,
  }) =>
      StaffMember(
        id: id,
        name: name,
        role: role,
        shift: shift ?? this.shift,
        phone: phone,
        since: since ?? this.since,
        completedToday: completedToday ?? this.completedToday,
      );
}