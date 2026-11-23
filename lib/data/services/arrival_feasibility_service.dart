// arrival_feasibility_service.dart
// Smart Parking (J26-IT-335) — Predictive Arrival Time Validation & Learned Sri Lankan ETA Correction (SYS-01, SYS-03)

import 'package:latlong2/latlong.dart';
import '../models/colombo_landmark_model.dart';
import '../models/parking_lot_model.dart';
import 'routing/composite_route_provider.dart';
import 'routing/eta_correction_model.dart';
import 'routing/route_provider.dart';

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
  final double predictedEtaMinBaseline;
  final double predictedEtaMinProvider;
  final double predictedEtaMinCorrected;
  final String modelVersion;
  final RouteResult? route;

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
    this.predictedEtaMinBaseline = 0.0,
    this.predictedEtaMinProvider = 0.0,
    this.predictedEtaMinCorrected = 0.0,
    this.modelVersion = EtaCorrectionModel.currentVersion,
    this.route,
  });
}

class ArrivalFeasibilityService {
  /// Synchronous evaluation calculating baseline, provider, and learned model ETA.
  static ArrivalFeasibilityResult evaluate({
    required double originLat,
    required double originLng,
    required ParkingLot targetLot,
    required DateTime requestedTime,
    ColomboLandmark? landmarkContext,
    String? originZone,
    bool isRain = false,
    bool isHoliday = false,
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

    // 3. Baseline heuristic duration (22 km/h city average)
    final baseDurationMinutes = (drivingDistanceKm / 22.0) * 60.0;
    final baselineMinutes = (baseDurationMinutes * congestionMultiplier).round();
    final effectiveBaselineMinutes = baselineMinutes < 3 ? 3 : baselineMinutes;

    // 4. Nominal provider estimate (36 km/h free-flow base)
    final providerEstimateMinutes = ((drivingDistanceKm / 36.0) * 60.0 * 1.10).round().clamp(3, 999);

    // 5. Learned Sri Lankan ETA correction model
    const model = EtaCorrectionModel();
    final correctedMinutes = model.computeCorrectedMinutes(
      providerDurationMinutes: providerEstimateMinutes,
      distanceKm: drivingDistanceKm,
      departureTime: DateTime.now(),
      originZone: originZone ?? landmarkContext?.name,
      isRain: isRain,
      isHoliday: isHoliday,
    );

    // 6. Earliest feasible arrival time
    final now = DateTime.now();
    final earliestFeasibleTime = now.add(Duration(minutes: correctedMinutes));

    // 7. Feasibility check: Can driver arrive by requested time?
    final difference = requestedTime.difference(earliestFeasibleTime);
    final isFeasible = !difference.isNegative;
    final lateByMinutes = isFeasible ? 0 : difference.inMinutes.abs();

    // 8. Round recommended arrival time to nearest clean 5 minutes when infeasible
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
      drivingDurationMinutes: correctedMinutes,
      drivingDistanceKm: drivingDistanceKm,
      lateByMinutes: lateByMinutes,
      congestionLevel: congestionLevel,
      congestionMultiplier: congestionMultiplier,
      predictedEtaMinBaseline: effectiveBaselineMinutes.toDouble(),
      predictedEtaMinProvider: providerEstimateMinutes.toDouble(),
      predictedEtaMinCorrected: correctedMinutes.toDouble(),
      modelVersion: model.version,
    );
  }

  /// Asynchronous evaluation querying the RouteProvider (cached Google Routes / OSRM / Heuristic)
  /// and applying the learned ETA residual correction model.
  static Future<ArrivalFeasibilityResult> evaluateAsync({
    required double originLat,
    required double originLng,
    required ParkingLot targetLot,
    required DateTime requestedTime,
    ColomboLandmark? landmarkContext,
    RouteProvider? routeProvider,
    String? originZone,
    bool isRain = false,
    bool isHoliday = false,
  }) async {
    final router = routeProvider ?? CompositeRouteProvider();
    final route = await router.getRoute(
      origin: LatLng(originLat, originLng),
      destination: LatLng(targetLot.latitude, targetLot.longitude),
      departureTime: DateTime.now(),
    );

    const model = EtaCorrectionModel();
    final correctedMinutes = model.computeCorrectedMinutes(
      providerDurationMinutes: route.durationMinutes,
      distanceKm: route.distanceKm,
      departureTime: DateTime.now(),
      originZone: originZone ?? landmarkContext?.name,
      isRain: isRain,
      isHoliday: isHoliday,
    );

    final now = DateTime.now();
    final earliestFeasibleTime = now.add(Duration(minutes: correctedMinutes));
    final difference = requestedTime.difference(earliestFeasibleTime);
    final isFeasible = !difference.isNegative;
    final lateByMinutes = isFeasible ? 0 : difference.inMinutes.abs();

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

    final baselineMinutes = ((route.distanceKm / 22.0) * 60.0 * 1.15).roundToDouble();

    return ArrivalFeasibilityResult(
      isFeasible: isFeasible,
      requestedTime: requestedTime,
      earliestFeasibleTime: earliestFeasibleTime,
      recommendedArrivalTime: recommendedArrivalTime,
      drivingDurationMinutes: correctedMinutes,
      drivingDistanceKm: route.distanceKm,
      lateByMinutes: lateByMinutes,
      congestionLevel: landmarkContext?.congestionLevel ?? 'Moderate',
      congestionMultiplier: landmarkContext?.congestionMultiplier ?? 1.15,
      predictedEtaMinBaseline: baselineMinutes,
      predictedEtaMinProvider: route.durationMinutes.toDouble(),
      predictedEtaMinCorrected: correctedMinutes.toDouble(),
      modelVersion: model.version,
      route: route,
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
