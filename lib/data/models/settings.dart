import 'package:flutter/foundation.dart';

import 'coverage.dart';

/// Store configuration owned by the admin.
///
/// Lives in the data layer rather than in `admin_provider.dart` because it is
/// now a persisted document (`settings/shop`) and the Firestore serialiser
/// needs to reach it without importing a `ChangeNotifier`.
@immutable
class StoreSettings {
  const StoreSettings({
    required this.cafeName,
    required this.address,
    required this.isOpen,
    required this.baseFee,
    required this.freeOver,
    required this.coverageRadiusKm,
    this.cafeLat = LumbanCoverage.cafeLat,
    this.cafeLng = LumbanCoverage.cafeLng,
    required this.opensAt,
    required this.closesAt,
  });

  final String cafeName;
  final String address;
  final bool isOpen;
  final num baseFee;
  final num freeOver;
  final double coverageRadiusKm;

  /// The café's exact location, used as the origin for GPS delivery
  /// distances. Defaults to the bundled [LumbanCoverage] placeholder until the
  /// owner confirms the real coordinates in the admin panel.
  final double cafeLat;
  final double cafeLng;

  final String opensAt;
  final String closesAt;

  StoreSettings copyWith({
    String? cafeName,
    String? address,
    bool? isOpen,
    num? baseFee,
    num? freeOver,
    double? coverageRadiusKm,
    double? cafeLat,
    double? cafeLng,
    String? opensAt,
    String? closesAt,
  }) =>
      StoreSettings(
        cafeName: cafeName ?? this.cafeName,
        address: address ?? this.address,
        isOpen: isOpen ?? this.isOpen,
        baseFee: baseFee ?? this.baseFee,
        freeOver: freeOver ?? this.freeOver,
        coverageRadiusKm: coverageRadiusKm ?? this.coverageRadiusKm,
        cafeLat: cafeLat ?? this.cafeLat,
        cafeLng: cafeLng ?? this.cafeLng,
        opensAt: opensAt ?? this.opensAt,
        closesAt: closesAt ?? this.closesAt,
      );
}