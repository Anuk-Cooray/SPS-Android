// test/route_provider_test.dart
// Smart Parking (J26-IT-335) — Route Provider Abstraction & Caching Unit Tests

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:smart_parking/data/services/routing/cached_route_provider.dart';
import 'package:smart_parking/data/services/routing/composite_route_provider.dart';
import 'package:smart_parking/data/services/routing/heuristic_route_provider.dart';
import 'package:smart_parking/data/services/routing/route_provider.dart';

class FailingMockRouteProvider implements RouteProvider {
  int callCount = 0;

  @override
  String get name => 'failing_mock';

  @override
  Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    DateTime? departureTime,
  }) async {
    callCount++;
    throw RouteProviderException('Simulated network timeout', provider: name);
  }
}

class CountingMockRouteProvider implements RouteProvider {
  int callCount = 0;

  @override
  String get name => 'counting_mock';

  @override
  Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    DateTime? departureTime,
  }) async {
    callCount++;
    return RouteResult(
      distanceKm: 5.5,
      durationMinutes: 18,
      polylinePoints: [origin, destination],
      providerName: name,
      cached: false,
    );
  }
}

void main() {
  final colomboFort = LatLng(6.9344, 79.8428); // Colombo Fort Station
  final sliitMalabe = LatLng(6.9147, 79.9733); // SLIIT Malabe Campus

  group('HeuristicRouteProvider (Research Baseline Benchmark)', () {
    const provider = HeuristicRouteProvider();

    test('Computes realistic Colombo urban driving distance and duration', () async {
      final route = await provider.getRoute(
        origin: colomboFort,
        destination: sliitMalabe,
      );

      expect(route.providerName, equals('heuristic_baseline'));
      expect(route.cached, isFalse);
      expect(route.distanceKm, greaterThan(14.0));
      expect(route.distanceKm, lessThan(24.0));
      expect(route.durationMinutes, greaterThanOrEqualTo(25));
      expect(route.polylinePoints.length, greaterThanOrEqualTo(10));
    });

    test('Applies peak congestion multiplier during rush hours', () async {
      // 8:30 AM Morning Rush
      final morningRush = DateTime(2026, 10, 20, 8, 30);
      final morningRoute = await provider.getRoute(
        origin: colomboFort,
        destination: sliitMalabe,
        departureTime: morningRush,
      );

      // 11:30 PM Night Free-flow
      final nightTime = DateTime(2026, 10, 20, 23, 30);
      final nightRoute = await provider.getRoute(
        origin: colomboFort,
        destination: sliitMalabe,
        departureTime: nightTime,
      );

      expect(morningRoute.durationMinutes, greaterThan(nightRoute.durationMinutes));
      expect(morningRoute.metadata['congestionMultiplier'], equals(1.35));
      expect(nightRoute.metadata['congestionMultiplier'], equals(1.00));
    });
  });

  group('CachedRouteProvider (0.01° Grid Cell + 15-Minute Bucket)', () {
    late CountingMockRouteProvider countingMock;
    late CachedRouteProvider cachedProvider;

    setUp(() {
      countingMock = CountingMockRouteProvider();
      cachedProvider = CachedRouteProvider(
        innerProvider: countingMock,
        ttl: const Duration(minutes: 15),
      );
    });

    test('First request fetches from provider; second identical request serves from cache', () async {
      final t = DateTime(2026, 10, 20, 9, 10);

      final r1 = await cachedProvider.getRoute(
        origin: colomboFort,
        destination: sliitMalabe,
        departureTime: t,
      );

      expect(countingMock.callCount, equals(1));
      expect(r1.cached, isFalse);

      final r2 = await cachedProvider.getRoute(
        origin: colomboFort,
        destination: sliitMalabe,
        departureTime: t,
      );

      expect(countingMock.callCount, equals(1)); // served from cache
      expect(r2.cached, isTrue);
      expect(r2.distanceKm, equals(r1.distanceKm));
      expect(r2.durationMinutes, equals(r1.durationMinutes));
    });

    test('Nearby origin within same 0.01° grid cell (~1.1 km) hits cache', () async {
      final t = DateTime(2026, 10, 20, 9, 10);

      // Initial route
      await cachedProvider.getRoute(
        origin: colomboFort, // (6.9344, 79.8428) -> cells (693, 7984)
        destination: sliitMalabe,
        departureTime: t,
      );
      expect(countingMock.callCount, equals(1));

      // Coordinate shift by 0.002° (~220m) inside same (693, 7984) cell
      final nearbyOrigin = LatLng(6.9350, 79.8435);
      final r2 = await cachedProvider.getRoute(
        origin: nearbyOrigin,
        destination: sliitMalabe,
        departureTime: t,
      );

      expect(countingMock.callCount, equals(1));
      expect(r2.cached, isTrue);
    });

    test('Advance across 15-minute time bucket triggers fresh route computation', () async {
      final bucket0 = DateTime(2026, 10, 20, 9, 10); // bucket 0 (minute 10)
      final bucket1 = DateTime(2026, 10, 20, 9, 20); // bucket 1 (minute 20)

      await cachedProvider.getRoute(
        origin: colomboFort,
        destination: sliitMalabe,
        departureTime: bucket0,
      );
      expect(countingMock.callCount, equals(1));

      await cachedProvider.getRoute(
        origin: colomboFort,
        destination: sliitMalabe,
        departureTime: bucket1,
      );
      expect(countingMock.callCount, equals(2));
    });
  });

  group('CompositeRouteProvider (Graceful Cascading Fallback)', () {
    test('Gracefully falls back to Heuristic baseline when primary network provider fails', () async {
      final failingMock = FailingMockRouteProvider();
      const heuristic = HeuristicRouteProvider();

      final composite = CompositeRouteProvider(
        providers: [failingMock, heuristic],
        enableCache: false,
      );

      final route = await composite.getRoute(
        origin: colomboFort,
        destination: sliitMalabe,
      );

      expect(failingMock.callCount, equals(1));
      expect(route.providerName, equals('heuristic_baseline'));
      expect(route.distanceKm, greaterThan(10.0));
      expect(route.durationMinutes, greaterThan(15));
    });
  });
}
