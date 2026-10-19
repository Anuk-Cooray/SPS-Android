// composite_route_provider.dart
// Smart Parking (J26-IT-335) — Resilient Multi-Provider Fallback Orchestrator
// Cascades across Google Routes API -> OSRM -> Heuristic Baseline with Grid-Cell Caching

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'cached_route_provider.dart';
import 'google_routes_provider.dart';
import 'heuristic_route_provider.dart';
import 'osrm_route_provider.dart';
import 'route_provider.dart';

class CompositeRouteProvider implements RouteProvider {
  final List<RouteProvider> fallbackChain;
  final CachedRouteProvider? _cachedDecorator;

  CompositeRouteProvider({
    List<RouteProvider>? providers,
    bool enableCache = true,
    Duration cacheTtl = const Duration(minutes: 15),
  })  : fallbackChain = providers ?? _defaultChain(),
        _cachedDecorator = enableCache
            ? CachedRouteProvider(
                innerProvider: _InternalChainProvider(providers ?? _defaultChain()),
                ttl: cacheTtl,
              )
            : null;

  static List<RouteProvider> _defaultChain() {
    return [
      const GoogleRoutesProvider(),
      const OsrmRouteProvider(),
      const HeuristicRouteProvider(),
    ];
  }

  @override
  String get name => 'composite';

  int get cachedEntriesCount => _cachedDecorator?.cachedEntriesCount ?? 0;

  void clearCache() => _cachedDecorator?.clearCache();

  @override
  Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    DateTime? departureTime,
  }) async {
    if (_cachedDecorator != null) {
      return _cachedDecorator.getRoute(
        origin: origin,
        destination: destination,
        departureTime: departureTime,
      );
    }

    return _executeChain(origin, destination, departureTime);
  }

  Future<RouteResult> _executeChain(
    LatLng origin,
    LatLng destination,
    DateTime? departureTime,
  ) async {
    for (final provider in fallbackChain) {
      try {
        final result = await provider.getRoute(
          origin: origin,
          destination: destination,
          departureTime: departureTime,
        );
        return result;
      } catch (e) {
        debugPrint('[CompositeRouteProvider] ${provider.name} failed: $e. Cascading to next.');
      }
    }

    // Ultimate fallback guarantee: heuristic calculation always succeeds
    const baseline = HeuristicRouteProvider();
    return baseline.getRoute(
      origin: origin,
      destination: destination,
      departureTime: departureTime,
    );
  }
}

class _InternalChainProvider implements RouteProvider {
  final List<RouteProvider> chain;

  _InternalChainProvider(this.chain);

  @override
  String get name => 'internal_chain';

  @override
  Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    DateTime? departureTime,
  }) async {
    for (final provider in chain) {
      try {
        return await provider.getRoute(
          origin: origin,
          destination: destination,
          departureTime: departureTime,
        );
      } catch (_) {
        continue;
      }
    }
    const baseline = HeuristicRouteProvider();
    return baseline.getRoute(
      origin: origin,
      destination: destination,
      departureTime: departureTime,
    );
  }
}
