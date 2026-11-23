// heuristic_route_provider.dart
// Smart Parking (J26-IT-335) — Heuristic Research Baseline Route Provider
// Implements straight-line x 1.35 curvature, 22 km/h city speed, and Colombo peak-hour multipliers

import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'route_provider.dart';

class HeuristicRouteProvider implements RouteProvider {
  final double baseSpeedKmh;
  final double curvatureMultiplier;

  const HeuristicRouteProvider({
    this.baseSpeedKmh = 22.0,
    this.curvatureMultiplier = 1.35,
  });

  @override
  String get name => 'heuristic_baseline';

  @override
  Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    DateTime? departureTime,
  }) async {
    final dep = departureTime ?? DateTime.now();

    // 1. Calculate approximate distance in km (equirectangular projection for Colombo ~ 6.9°N)
    final dX = (destination.longitude - origin.longitude) * 110.574 * cos(origin.latitude * pi / 180.0);
    final dY = (destination.latitude - origin.latitude) * 110.574;
    final straightDistKm = sqrt(dX * dX + dY * dY);
    final rawDistanceKm = straightDistKm * curvatureMultiplier;
    final distanceKm = double.parse((max(rawDistanceKm, 0.2)).toStringAsFixed(2));

    // 2. Determine time-of-day Colombo congestion multiplier
    final hour = dep.hour;
    final minute = dep.minute;
    final timeDecimal = hour + (minute / 60.0);

    double congestionMultiplier = 1.15; // default moderate
    if ((timeDecimal >= 7.5 && timeDecimal <= 9.5) ||
        (timeDecimal >= 16.5 && timeDecimal <= 19.0)) {
      congestionMultiplier = 1.35; // Colombo peak rush hour
    } else if (timeDecimal >= 22.0 || timeDecimal <= 5.5) {
      congestionMultiplier = 1.00; // Night free-flow
    }

    // 3. Driving duration calculation
    final baseDurationMinutes = (distanceKm / baseSpeedKmh) * 60.0;
    final effectiveDurationMinutes = max(3, (baseDurationMinutes * congestionMultiplier).round());

    // 4. Generate smooth interpolated route polyline points (10 steps)
    final points = <LatLng>[];
    const steps = 10;
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final lat = origin.latitude + (destination.latitude - origin.latitude) * t;
      final lng = origin.longitude + (destination.longitude - origin.longitude) * t;
      // Slight perpendicular deviation for natural road-like curvature
      final offset = sin(t * pi) * 0.0015;
      points.add(LatLng(lat + offset, lng + offset * 0.5));
    }

    return RouteResult(
      distanceKm: distanceKm,
      durationMinutes: effectiveDurationMinutes,
      polylinePoints: points,
      providerName: name,
      cached: false,
      metadata: {
        'curvatureMultiplier': curvatureMultiplier,
        'baseSpeedKmh': baseSpeedKmh,
        'congestionMultiplier': congestionMultiplier,
      },
    );
  }
}
