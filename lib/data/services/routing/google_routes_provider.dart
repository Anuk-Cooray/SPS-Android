// google_routes_provider.dart
// Smart Parking (J26-IT-335) — Google Routes API v2 Provider
// Integrates official computeRoutes endpoint with real-time traffic-aware travel times

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'route_provider.dart';

class GoogleRoutesProvider implements RouteProvider {
  final String? apiKey;
  final Duration timeout;

  const GoogleRoutesProvider({
    this.apiKey,
    this.timeout = const Duration(seconds: 5),
  });

  String get _effectiveApiKey =>
      apiKey ?? const String.fromEnvironment('GOOGLE_ROUTES_API_KEY', defaultValue: '');

  @override
  String get name => 'google_routes';

  @override
  Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    DateTime? departureTime,
  }) async {
    final key = _effectiveApiKey;
    if (key.isEmpty) {
      throw RouteProviderException(
        'Google Routes API key is not configured. Supply via --dart-define=GOOGLE_ROUTES_API_KEY=...',
        provider: name,
      );
    }

    final uri = Uri.parse('https://routes.googleapis.com/directions/v2:computeRoutes');
    final client = HttpClient();
    client.connectionTimeout = timeout;

    try {
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('X-Goog-Api-Key', key);
      request.headers.set(
        'X-Goog-FieldMask',
        'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
      );

      final payload = {
        'origin': {
          'location': {
            'latLng': {
              'latitude': origin.latitude,
              'longitude': origin.longitude,
            },
          },
        },
        'destination': {
          'location': {
            'latLng': {
              'latitude': destination.latitude,
              'longitude': destination.longitude,
            },
          },
        },
        'travelMode': 'DRIVE',
        'routingPreference': 'TRAFFIC_AWARE',
      };

      if (departureTime != null) {
        payload['departureTime'] = departureTime.toUtc().toIso8601String();
      }

      request.write(jsonEncode(payload));
      final response = await request.close().timeout(timeout);

      if (response.statusCode != HttpStatus.ok) {
        final errBody = await response.transform(utf8.decoder).join();
        throw RouteProviderException(
          'Google Routes API error HTTP ${response.statusCode}: $errBody',
          provider: name,
        );
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final routes = json['routes'] as List<dynamic>?;

      if (routes == null || routes.isEmpty) {
        throw RouteProviderException(
          'Google Routes API returned no valid routes',
          provider: name,
        );
      }

      final firstRoute = routes.first as Map<String, dynamic>;
      final distanceMeters = (firstRoute['distanceMeters'] as num?)?.toDouble() ?? 0.0;
      final durationStr = firstRoute['duration'] as String? ?? '0s'; // e.g. "840s"
      final durationSeconds = double.tryParse(durationStr.replaceAll('s', '')) ?? 0.0;

      final distanceKm = double.parse((distanceMeters / 1000.0).toStringAsFixed(2));
      final durationMinutes = max(3, (durationSeconds / 60.0).round());

      // Decode encoded polyline if present
      final encoded = firstRoute['polyline']?['encodedPolyline'] as String?;
      final points = encoded != null ? _decodePolyline(encoded) : [origin, destination];

      return RouteResult(
        distanceKm: distanceKm,
        durationMinutes: durationMinutes,
        polylinePoints: points,
        providerName: name,
        cached: false,
        metadata: {
          'rawDuration': durationStr,
          'rawDistanceMeters': distanceMeters,
        },
      );
    } catch (e) {
      if (e is RouteProviderException) rethrow;
      throw RouteProviderException(
        'Failed to execute Google Routes request: $e',
        provider: name,
        cause: e,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Decodes a Google encoded polyline string into a list of [LatLng] points.
  List<LatLng> _decodePolyline(String encoded) {
    final poly = <LatLng>[];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return poly;
  }
}
