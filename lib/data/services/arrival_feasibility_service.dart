// arrival_feasibility_service.dart
// Algorithmic travel duration and arrival time feasibility validation (SYS-01 / SYS-03)

import '../models/colombo_landmark_model.dart';
import '../models/parking_lot_model.dart';

class ArrivalFeasibilityResult {
  final bool isFeasible;
  final DateTime requestedTime;
  final DateTime earliestFeasibleTime;
  final DateTime recommendedArrivalTime;
  final int drivingDurationMinutes;
  final double drivingDistanceKm;
  final int lateByMinutes;
  final String congestionLevel;
  final double congestionMultiplier;

  const ArrivalFeasibilityResult({
    required this.isFeasible,
    required this.requestedTime,
    required this.earliestFeasibleTime,
    required this.recommendedArrivalTime,
    required this.drivingDurationMinutes,
    required this.drivingDistanceKm,
    required this.lateByMinutes,
    required this.congestionLevel,
    required this.congestionMultiplier,
  });
}

class ArrivalFeasibilityService {
  /// Evaluates whether a driver can physically arrive at the target parking lot
  /// by their desired arrival time, given current location and real-time Colombo traffic.
  static ArrivalFeasibilityResult evaluate({
    required double originLat,
    required double originLng,
    required ParkingLot targetLot,
    required DateTime requestedTime,
    ColomboLandmark? landmarkContext,
  }) {
    // 1. Calculate driving distance from origin to target lot (km)
    final dX = (targetLot.longitude - originLng) * 110.574 * 0.9927;
    final dY = (targetLot.latitude - originLat) * 110.574;
    final distSq = (dX * dX + dY * dY);
    final straightDistKm = distSq > 0 ? _sqrt(distSq) : 0.2;
    // Colombo arterial street curvature factor ~ 1.35
    final drivingDistanceKm = double.parse((straightDistKm * 1.35).toStringAsFixed(1));

    // 2. Traffic congestion multiplier
    final congestionLevel = landmarkContext?.congestionLevel ?? 'Moderate';
    final congestionMultiplier = landmarkContext?.congestionMultiplier ?? 1.15;

    // 3. Driving time calculation (average Colombo city transit speed: 22 km/h)
    final baseDurationMinutes = (drivingDistanceKm / 22.0) * 60.0;
    final trafficDurationMinutes = (baseDurationMinutes * congestionMultiplier).round();
    final effectiveDurationMinutes = trafficDurationMinutes < 3 ? 3 : trafficDurationMinutes;

    // 4. Earliest feasible arrival time
    final now = DateTime.now();
    final earliestFeasibleTime = now.add(Duration(minutes: effectiveDurationMinutes));

    // 5. Feasibility check: Can driver arrive by requested time?
    final difference = requestedTime.difference(earliestFeasibleTime);
    final isFeasible = !difference.isNegative;
    final lateByMinutes = isFeasible ? 0 : difference.inMinutes.abs();

    // 6. Round recommended arrival time to nearest clean 5 minutes when infeasible
    DateTime recommendedArrivalTime;
    if (isFeasible) {
      recommendedArrivalTime = requestedTime;
    } else {
      final remainder = earliestFeasibleTime.minute % 5;
      final addedMinutes = remainder == 0 ? 0 : (5 - remainder);
      final candidate = earliestFeasibleTime.add(Duration(minutes: addedMinutes));
      recommendedArrivalTime = DateTime(
        candidate.year,
        candidate.month,
        candidate.day,
        candidate.hour,
        candidate.minute,
      );
    }

    return ArrivalFeasibilityResult(
      isFeasible: isFeasible,
      requestedTime: requestedTime,
      earliestFeasibleTime: earliestFeasibleTime,
      recommendedArrivalTime: recommendedArrivalTime,
      drivingDurationMinutes: effectiveDurationMinutes,
      drivingDistanceKm: drivingDistanceKm,
      lateByMinutes: lateByMinutes,
      congestionLevel: congestionLevel,
      congestionMultiplier: congestionMultiplier,
    );
  }

  static double _sqrt(double val) {
    if (val <= 0) return 0.0;
    double x = val;
    for (int i = 0; i < 10; i++) {
      x = (x + val / x) / 2.0;
    }
    return x;
  }
}
