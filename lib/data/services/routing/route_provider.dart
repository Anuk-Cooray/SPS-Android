// route_provider.dart
// Smart Parking (J26-IT-335) — Routing Provider Abstraction
// Supports Google Routes API v2, OSRM public routing, and Heuristic Research Baseline

import 'package:latlong2/latlong.dart';

class RouteResult {
  final double distanceKm;
  final int durationMinutes;
  final List<LatLng> polylinePoints;
  final String providerName; // 'google_routes' | 'osrm' | 'heuristic_baseline'
  final bool cached;
  final Map<String, dynamic> metadata;

  const RouteResult({
    required this.distanceKm,
    required this.durationMinutes,
    required this.polylinePoints,
    required this.providerName,
    this.cached = false,
    this.metadata = const {},
  });

  RouteResult copyWith({
    double? distanceKm,
    int? durationMinutes,
    List<LatLng>? polylinePoints,
    String? providerName,
    bool? cached,
    Map<String, dynamic>? metadata,
  }) {
    return RouteResult(
      distanceKm: distanceKm ?? this.distanceKm,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      polylinePoints: polylinePoints ?? this.polylinePoints,
      providerName: providerName ?? this.providerName,
      cached: cached ?? this.cached,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'distanceKm': distanceKm,
        'durationMinutes': durationMinutes,
        'providerName': providerName,
        'cached': cached,
        'pointsCount': polylinePoints.length,
        'metadata': metadata,
      };
}

class RouteProviderException implements Exception {
  final String message;
  final String provider;
  final dynamic cause;

  RouteProviderException(this.message, {required this.provider, this.cause});

  @override
  String toString() => 'RouteProviderException [$provider]: $message';
}

abstract class RouteProvider {
  /// Computes a route between [origin] and [destination].
  /// [departureTime] enables time-aware traffic evaluation.
  Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    DateTime? departureTime,
  });

  String get name;
}
