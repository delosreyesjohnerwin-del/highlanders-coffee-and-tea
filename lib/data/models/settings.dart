import 'package:flutter/foundation.dart';

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
    required this.opensAt,
    required this.closesAt,
  });

  final String cafeName;
  final String address;
  final bool isOpen;
  final num baseFee;
  final num freeOver;
  final double coverageRadiusKm;
  final String opensAt;
  final String closesAt;

  StoreSettings copyWith({
    String? cafeName,
    String? address,
    bool? isOpen,
    num? baseFee,
    num? freeOver,
    double? coverageRadiusKm,
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
        opensAt: opensAt ?? this.opensAt,
        closesAt: closesAt ?? this.closesAt,
      );
}