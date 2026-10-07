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
/// TODO(owner): confirm the barangay centroids below before shipping — fees
/// and ETAs depend on them. The café pin itself is the confirmed origin.
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

  /// Bundled barangay table. Coordinates are centroids and should be
  /// replaced with authoritative values from the municipality.
  static const List<Barangay> barangays = <Barangay>[
    Barangay(code: 'lumban-poblacion', name: 'Poblacion', lat: 14.2919, lng: 121.4644),
    Barangay(code: 'lumban-santo-nino', name: 'Santo Niño', lat: 14.2880, lng: 121.4700),
    Barangay(code: 'lumban-santol', name: 'Santol', lat: 14.2960, lng: 121.4560),
    Barangay(code: 'lumban-mabini', name: 'Mabini', lat: 14.3020, lng: 121.4680),
    Barangay(code: 'lumban-dalupa', name: 'Dalupa', lat: 14.2870, lng: 121.4520),
    Barangay(code: 'lumban-marawoy', name: 'Marawoy', lat: 14.2955, lng: 121.4790),
    Barangay(code: 'lumban-mabini-west', name: 'Mabini West', lat: 14.3080, lng: 121.4560),
    Barangay(code: 'lumban-nayon', name: 'Nayon', lat: 14.2820, lng: 121.4650),
    Barangay(code: 'lumban-langat', name: 'Langat', lat: 14.3100, lng: 121.4820),
    Barangay(code: 'lumban-bagumbayan', name: 'Bagumbayan', lat: 14.2760, lng: 121.4710),
    Barangay(code: 'lumban-banalo', name: 'Banalo', lat: 14.2900, lng: 121.4880),
    Barangay(code: 'lumban-banzaan', name: 'Banzaan', lat: 14.3010, lng: 121.4930),
    Barangay(code: 'lumban-halong', name: 'Halong', lat: 14.2790, lng: 121.4820),
    Barangay(code: 'lumban-bukang', name: 'Bukang', lat: 14.2660, lng: 121.4590),
    Barangay(code: 'lumban-dagatan', name: 'Dagatan', lat: 14.3130, lng: 121.4470),
    Barangay(code: 'lumban-livesa', name: 'Livesa', lat: 14.2680, lng: 121.4900),
    Barangay(code: 'lumban-malabao', name: 'Malabao', lat: 14.3060, lng: 121.4990),
    Barangay(code: 'lumban-molina', name: 'Molina', lat: 14.2600, lng: 121.4700),
  ];

  static Barangay? byCode(String code) {
    for (final Barangay b in barangays) {
      if (b.code == code) return b;
    }
    return null;
  }
}