// cached_route_provider.dart
// Smart Parking (J26-IT-335) — Grid-Cell & 15-Minute Bucket Caching Decorator
// Caches routes by origin/destination 0.01° grid cells (~1.1 km) and 15-minute time buckets

import 'package:latlong2/latlong.dart';
import 'route_provider.dart';

class _CacheRecord {
  final RouteResult result;
  final DateTime cachedAt;
  final String key;

  const _CacheRecord({
    required this.result,
    required this.cachedAt,
    required this.key,
  });

  bool isExpired(Duration ttl) =>
      DateTime.now().difference(cachedAt) > ttl;
}

class CachedRouteProvider implements RouteProvider {
  final RouteProvider innerProvider;
  final Duration ttl;
  final double gridPrecision; // 0.01 deg ~= 1.11 km in Sri Lanka

  final Map<String, _CacheRecord> _cache = {};

  CachedRouteProvider({
    required this.innerProvider,
    this.ttl = const Duration(minutes: 15),
    this.gridPrecision = 0.01,
  });

  @override
  String get name => 'cached_${innerProvider.name}';

  int get cachedEntriesCount => _cache.length;

  void clearCache() => _cache.clear();

  String generateCacheKey(LatLng origin, LatLng destination, DateTime time) {
    final scale = 1.0 / gridPrecision;
    final oLat = (origin.latitude * scale).floor();
    final oLng = (origin.longitude * scale).floor();
    final dLat = (destination.latitude * scale).floor();
    final dLng = (destination.longitude * scale).floor();
    final bucket15 = time.minute ~/ 15;

    return '${oLat}_${oLng}__${dLat}_${dLng}__dow${time.weekday}_h${time.hour}_b$bucket15';
  }

  @override
  Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    DateTime? departureTime,
  }) async {
    final dep = departureTime ?? DateTime.now();
    final key = generateCacheKey(origin, destination, dep);

    final existing = _cache[key];
    if (existing != null && !existing.isExpired(ttl)) {
      return existing.result.copyWith(
        cached: true,
        metadata: {
          ...existing.result.metadata,
          'cacheKey': key,
          'cacheAgeSeconds': DateTime.now().difference(existing.cachedAt).inSeconds,
        },
      );
    }

    final fresh = await innerProvider.getRoute(
      origin: origin,
      destination: destination,
      departureTime: dep,
    );

    _cache[key] = _CacheRecord(
      result: fresh,
      cachedAt: DateTime.now(),
      key: key,
    );

    return fresh;
  }
}
