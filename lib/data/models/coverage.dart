import 'dart:math' as math;

/// Lumban, Laguna delivery coverage.
///
/// Barangay centroids are bundled with the app rather than fetched from a
/// geocoding API. For a single municipality this is cheaper, needs no billing
/// account, has no rate limits and works offline.
class Barangay {
  const Barangay({
    required this.code,
    required this.name,
    required this.lat,
    required this.lng,
  });

  final String code;
  final String name;
  final double lat;
  final double lng;
}

/// Straight-line distance in kilometres between two coordinates.
///
/// Uses the haversine formula. Accurate enough for fee tiers at town scale.
double haversineKm({
  required double lat1,
  required double lng1,
  required double lat2,
  required double lng2,
}) {
  const double earthRadiusKm = 6371.0088;

  double toRad(double deg) => deg * math.pi / 180.0;

  final double dLat = toRad(lat2 - lat1);
  final double dLng = toRad(lng2 - lng1);

  final double a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(toRad(lat1)) * math.cos(toRad(lat2)) * math.pow(math.sin(dLng / 2), 2);

  return 2 * earthRadiusKm * math.asin(math.min(1.0, math.sqrt(a)));
}

/// One step of the delivery fee schedule.
class FeeTier {
  const FeeTier(this.maxKm, this.fee);

  /// Inclusive upper bound in kilometres.
  final double maxKm;
  final num fee;
}

/// Fee schedule for Lumban delivery. Configurable at runtime from the admin
/// panel; these values are the shipping defaults and are placeholders until
/// the café confirms its real rates.
class DeliveryPricing {
  const DeliveryPricing({
    this.tiers = defaultTiers,
    this.freeOver,
    this.coverableMaxKm = 10.0,
    this.cafeLat = LumbanCoverage.cafeLat,
    this.cafeLng = LumbanCoverage.cafeLng,
  });

  static const List<FeeTier> defaultTiers = <FeeTier>[
    FeeTier(1.5, 25),
    FeeTier(3.0, 35),
    FeeTier(5.0, 45),
    FeeTier(8.0, 55),
    FeeTier(double.infinity, 65),
  ];

  /// Orders at or above this subtotal ship free. Null disables the waiver.
  final num? freeOver;

  /// Beyond this distance Highlanders does not deliver.
  final double coverableMaxKm;

  /// Coordinates the café quotes delivery distances from. Admin-editable via
  /// [StoreSettings.cafeLat]/[StoreSettings.cafeLng] and carried on every
  /// pricing snapshot so the cart computes fees from the same origin the admin
  /// configured — defaulting to the bundled [LumbanCoverage] placeholder.
  final double cafeLat;
  final double cafeLng;

  final List<FeeTier> tiers;

  /// Whether the café delivers to the given distance.
  bool covers(num km) => km <= coverableMaxKm;

  /// Delivery fee for a distance and subtotal. Returns 0 when the
  /// free-delivery threshold is met.
  num feeFor({required num km, required num subtotal}) {
    if (freeOver != null && subtotal >= freeOver!) return 0;

    for (final FeeTier tier in tiers) {
      if (km <= tier.maxKm) return tier.fee;
    }

    return tiers.last.fee;
  }

  /// Estimated minutes on the road, used for the ETA shown at checkout.
  int etaMinutes(num km) => 10 + (km * 2.5).ceil();
}

/// Café location and the bundled Lumban coverage table.
///
/// Barangay centroids are the PhilAtlas/PSGC points for the official 16
/// barangays of Lumban (the old table listed names Lumban does not have).
class LumbanCoverage {
  const LumbanCoverage._();

  static const String municipality = 'Lumban, Laguna';

  /// The café's confirmed location (owner-verified Google Maps pin
  /// 14.3067497,121.4773666; the municipality pin is 14.3041986,121.4381242).
  static const double cafeLat = 14.3067497;
  static const double cafeLng = 121.4773666;

  static double distanceToBarangay(Barangay b) => haversineKm(
        lat1: cafeLat,
        lng1: cafeLng,
        lat2: b.lat,
        lng2: b.lng,
      );

  /// The official 16 barangays of Lumban, Laguna (PSA PSGC), with centroid
  /// coordinates from PhilAtlas. Delivery fees fall back to these when a
  /// saved address has no GPS pin yet.
  static const List<Barangay> barangays = <Barangay>[
    Barangay(code: 'lumban-bagong-silang', name: 'Bagong Silang', lat: 14.2928, lng: 121.4627),
    Barangay(code: 'lumban-balimbingan', name: 'Balimbingan', lat: 14.3001, lng: 121.4597),
    Barangay(code: 'lumban-balubad', name: 'Balubad', lat: 14.2888, lng: 121.4633),
    Barangay(code: 'lumban-caliraya', name: 'Caliraya', lat: 14.2875, lng: 121.5007),
    Barangay(code: 'lumban-concepcion', name: 'Concepcion', lat: 14.2988, lng: 121.4567),
    Barangay(code: 'lumban-lewin', name: 'Lewin', lat: 14.3034, lng: 121.5082),
    Barangay(code: 'lumban-maracta', name: 'Maracta', lat: 14.2987, lng: 121.4597),
    Barangay(code: 'lumban-maytalang-i', name: 'Maytalang I', lat: 14.2893, lng: 121.4580),
    Barangay(code: 'lumban-maytalang-ii', name: 'Maytalang II', lat: 14.2898, lng: 121.4453),
    Barangay(code: 'lumban-primera-parang', name: 'Primera Parang', lat: 14.2920, lng: 121.4603),
    Barangay(code: 'lumban-primera-pulo', name: 'Primera Pulo', lat: 14.3016, lng: 121.4596),
    Barangay(code: 'lumban-salac', name: 'Salac', lat: 14.2955, lng: 121.4607),
    Barangay(code: 'lumban-santo-nino', name: 'Santo Niño', lat: 14.2972, lng: 121.4599),
    Barangay(code: 'lumban-segunda-parang', name: 'Segunda Parang', lat: 14.2943, lng: 121.4604),
    Barangay(code: 'lumban-segunda-pulo', name: 'Segunda Pulo', lat: 14.3029, lng: 121.4596),
    Barangay(code: 'lumban-wawa', name: 'Wawa', lat: 14.3055, lng: 121.4590),
  ];

  static Barangay? byCode(String code) {
    for (final Barangay b in barangays) {
      if (b.code == code) return b;
    }
    return null;
  }
}