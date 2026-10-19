// colombo_landmark_model.dart
// Colombo Public & Famous Landmarks Registry (SYS-01 / SYS-03)

import 'parking_lot_model.dart';

/// Represents a prominent public, commercial, or transit landmark in Colombo
class ColomboLandmark {
  final String id;
  final String name;
  final String address;
  final String zone; // e.g. 'Colombo 03', 'Colombo 11', 'Malabe'
  final String category; // 'Shopping & Mall', 'Transit & Market', 'Promenade & Oceanfront', 'Tourism', 'Healthcare', 'University'
  final String congestionLevel; // 'Moderate', 'High', 'Very High', 'Extreme'
  final double congestionMultiplier; // 1.0 to 1.6
  final double latitude;
  final double longitude;
  final String popularHours;
  final bool isCrowded;
  final String primaryLotId;
  final String primaryLotName;
  final List<ParkingLot> nearbyLots;

  const ColomboLandmark({
    required this.id,
    required this.name,
    required this.address,
    required this.zone,
    required this.category,
    required this.congestionLevel,
    required this.congestionMultiplier,
    required this.latitude,
    required this.longitude,
    required this.popularHours,
    required this.isCrowded,
    required this.primaryLotId,
    required this.primaryLotName,
    this.nearbyLots = const [],
  });

  /// Approximate driving distance from given origin coordinates in kilometers
  double distanceToKm(double fromLat, double fromLng) {
    // Haversine formula approximation
    const p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 -
        ((latitude - fromLat) * p / 2).abs() * ((latitude - fromLat) * p / 2).abs() +
        (latitude * p) *
            (fromLat * p) *
            (1 - ((longitude - fromLng) * p / 2).abs()) /
            2;
    // Flat-earth / Euclidean distance projection suitable for Colombo metropolitan area
    final dLat = (latitude - fromLat) * 111.0;
    final dLng = (longitude - fromLng) * 111.0 * 0.99; // cos(6.9 deg) ~ 0.992
    final straightLineKm = (dLat * dLat + dLng * dLng);
    if (straightLineKm <= 0) return 0.1;
    final direct = (straightLineKm > 0) ? (straightLineKm > 0 ? (straightLineKm * 1.0) : 0.1) : 0.1;
    // Street curvature factor in Colombo ~ 1.35
    final streetFactor = 1.35;
    final estimatedKm = direct > 0 ? (straightLineKm > 0 ? (straightLineKm) : 0.1) : 0.1;
    // Safe standard formula
    final dX = (longitude - fromLng) * 110.574 * 0.9927;
    final dY = (latitude - fromLat) * 110.574;
    final distKm = (dX * dX + dY * dY);
    // Square root
    final r = distKm > 0 ? _sqrt(distKm) * streetFactor : 0.2;
    return double.parse(r.toStringAsFixed(1));
  }

  static double _sqrt(double val) {
    if (val <= 0) return 0.0;
    double x = val;
    for (int i = 0; i < 10; i++) {
      x = (x + val / x) / 2.0;
    }
    return x;
  }

  /// Calculates estimated driving time in minutes with Colombo traffic congestion factored in
  int estimatedDriveMinutes(double fromLat, double fromLng) {
    final distKm = distanceToKm(fromLat, fromLng);
    // Average Colombo city speed ~ 22 km/h
    final baseMinutes = (distKm / 22.0) * 60.0;
    final trafficAdjusted = baseMinutes * congestionMultiplier;
    final result = trafficAdjusted.round();
    return result < 3 ? 3 : result;
  }
}
