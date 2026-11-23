// osrm_route_provider.dart
// Smart Parking (J26-IT-335) — OpenStreetMap (OSRM) Routing Provider
// Free, open-source routing provider returning real road-network topology and driving duration

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'route_provider.dart';

class OsrmRouteProvider implements RouteProvider {
  final String baseUrl;
  final Duration timeout;

  const OsrmRouteProvider({
    this.baseUrl = 'https://router.project-osrm.org',
    this.timeout = const Duration(seconds: 4),
  });

  @override
  String get name => 'osrm';

  @override
  Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    DateTime? departureTime,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/route/v1/driving/'
      '${origin.longitude},${origin.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson',
    );

    final client = HttpClient();
    client.connectionTimeout = timeout;

    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);

      if (response.statusCode != HttpStatus.ok) {
        throw RouteProviderException(
          'OSRM server responded with HTTP ${response.statusCode}',
          provider: name,
        );
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json['code'] != 'Ok' || (json['routes'] as List).isEmpty) {
        throw RouteProviderException(
          'OSRM returned no routes: ${json['message'] ?? json['code']}',
          provider: name,
        );
      }

      final route = (json['routes'] as List).first as Map<String, dynamic>;
      final distanceMeters = (route['distance'] as num).toDouble();
      final durationSeconds = (route['duration'] as num).toDouble();

      final distanceKm = double.parse((distanceMeters / 1000.0).toStringAsFixed(2));
      final durationMinutes = max(3, (durationSeconds / 60.0).round());

      // Parse geometry coordinates: [lng, lat]
      final geometry = route['geometry'] as Map<String, dynamic>?;
      final coordinates = (geometry?['coordinates'] as List<dynamic>?) ?? [];
      final points = coordinates.map((coord) {
        final pair = coord as List<dynamic>;
        return LatLng(
          (pair[1] as num).toDouble(),
          (pair[0] as num).toDouble(),
        );
      }).toList();

      return RouteResult(
        distanceKm: distanceKm,
        durationMinutes: durationMinutes,
        polylinePoints: points.isNotEmpty ? points : [origin, destination],
        providerName: name,
        cached: false,
        metadata: {
          'rawDurationSeconds': durationSeconds,
          'rawDistanceMeters': distanceMeters,
        },
      );
    } catch (e) {
      if (e is RouteProviderException) rethrow;
      throw RouteProviderException(
        'Failed to query OSRM routing endpoint: $e',
        provider: name,
        cause: e,
      );
    } finally {
      client.close(force: true);
    }
  }
}
