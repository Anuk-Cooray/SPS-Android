// colombo_live_map_view.dart
// Interactive Colombo live tile map with real markers, route polyline, and parking lot badges

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/colombo_landmark_model.dart';
import '../../../data/models/parking_lot_model.dart';

class ColomboLiveMapView extends StatefulWidget {
  final ColomboLandmark pickup;
  final ColomboLandmark destination;
  final List<ParkingLot> activeLots;
  final String? selectedLotId;
  final ValueChanged<ParkingLot> onLotSelected;
  final VoidCallback onRecenter;

  const ColomboLiveMapView({
    super.key,
    required this.pickup,
    required this.destination,
    required this.activeLots,
    required this.selectedLotId,
    required this.onLotSelected,
    required this.onRecenter,
  });

  @override
  State<ColomboLiveMapView> createState() => ColomboLiveMapViewState();
}

class ColomboLiveMapViewState extends State<ColomboLiveMapView> {
  final MapController _mapController = MapController();

  @override
  void didUpdateWidget(covariant ColomboLiveMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destination.id != widget.destination.id ||
        oldWidget.pickup.id != widget.pickup.id) {
      _fitRoute();
    }
  }

  void _fitRoute() {
    // Focus near the destination
    _mapController.move(
      LatLng(widget.destination.latitude, widget.destination.longitude),
      14.5,
    );
  }

  void recenterPickup() {
    _mapController.move(
      LatLng(widget.pickup.latitude, widget.pickup.longitude),
      15.0,
    );
  }

  void recenterDestination() {
    _mapController.move(
      LatLng(widget.destination.latitude, widget.destination.longitude),
      15.2,
    );
  }

  List<LatLng> _generateRoutePoints() {
    final start = LatLng(widget.pickup.latitude, widget.pickup.longitude);
    final end = LatLng(widget.destination.latitude, widget.destination.longitude);

    // Intermediate waypoints approximating Colombo road corridors
    final midLat = (start.latitude + end.latitude) / 2;
    final midLng = (start.longitude + end.longitude) / 2;

    // Slight realistic road deflection
    final bendLng = midLng + (start.latitude > end.latitude ? 0.003 : -0.003);

    return [
      start,
      LatLng((start.latitude * 2 + midLat) / 3, (start.longitude * 2 + bendLng) / 3),
      LatLng(midLat, bendLng),
      LatLng((midLat + end.latitude * 2) / 3, (bendLng + end.longitude * 2) / 3),
      end,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final routePoints = _generateRoutePoints();

    return Stack(
      children: [
        // 1. Live FlutterMap with OpenStreetMap / Carto tiles
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(
              widget.destination.latitude,
              widget.destination.longitude,
            ),
            initialZoom: 14.2,
            minZoom: 9.0,
            maxZoom: 18.0,
          ),
          children: [
            // CARTO Positron Grayscale Tile Layer (Design System Conforming)
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.sliit.smartparking.smart_parking',
              maxZoom: 19,
            ),

            // Route Polyline Layer
            PolylineLayer(
              polylines: [
                // Outer casing / shadow
                Polyline(
                  points: routePoints,
                  color: Colors.black.withValues(alpha: 0.25),
                  strokeWidth: 7.0,
                ),
                // Main route line
                Polyline(
                  points: routePoints,
                  color: c.accent,
                  strokeWidth: 4.5,
                ),
              ],
            ),

            // Markers Layer
            MarkerLayer(
              markers: [
                // Pickup Pin
                Marker(
                  point: LatLng(widget.pickup.latitude, widget.pickup.longitude),
                  width: 90,
                  height: 60,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                            )
                          ],
                        ),
                        child: Text(
                          'START',
                          style: AppText.caption.copyWith(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: c.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 6,
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Destination Pin
                Marker(
                  point: LatLng(widget.destination.latitude, widget.destination.longitude),
                  width: 110,
                  height: 64,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.primary,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 6,
                            )
                          ],
                        ),
                        child: Text(
                          'DESTINATION',
                          style: AppText.caption.copyWith(
                            color: c.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Icon(
                        Icons.location_on_rounded,
                        color: c.primary,
                        size: 26,
                      ),
                    ],
                  ),
                ),

                // Parking Lots Pins
                ...widget.activeLots.map((lot) {
                  final isSelected = lot.id == widget.selectedLotId;
                  final isFull = lot.isFull;

                  return Marker(
                    point: LatLng(lot.latitude, lot.longitude),
                    width: 84,
                    height: 52,
                    child: GestureDetector(
                      onTap: () => widget.onLotSelected(lot),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? c.accent
                                  : (isFull ? c.slotTaken : c.primary),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? Colors.white : Colors.transparent,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'P',
                                    style: AppText.caption.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    isFull ? 'Full' : '${lot.freeSlots}',
                                    style: AppText.caption.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isSelected ? c.accent : c.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ],
        ),

        // 2. Map Floating Quick Actions (Right side)
        Positioned(
          right: AppSpace.md,
          top: 155,
          child: Column(
            children: [
              // Recenter Destination
              FloatingActionButton.small(
                heroTag: 'recenter_dest',
                backgroundColor: c.surface,
                foregroundColor: c.textPrimary,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: c.border),
                ),
                onPressed: _fitRoute,
                tooltip: 'Focus Destination',
                child: const Icon(Icons.my_location_rounded, size: 20),
              ),

              const SizedBox(height: 8),

              // Zoom In
              FloatingActionButton.small(
                heroTag: 'zoom_in',
                backgroundColor: c.surface,
                foregroundColor: c.textPrimary,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: c.border),
                ),
                onPressed: () {
                  _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  );
                },
                child: const Icon(Icons.add_rounded, size: 20),
              ),

              const SizedBox(height: 8),

              // Zoom Out
              FloatingActionButton.small(
                heroTag: 'zoom_out',
                backgroundColor: c.surface,
                foregroundColor: c.textPrimary,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: c.border),
                ),
                onPressed: () {
                  _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  );
                },
                child: const Icon(Icons.remove_rounded, size: 20),
              ),
            ],
          ),
        ),

        // 3. Map Tile Attribution (OpenStreetMap & CARTO License Compliance)
        Positioned(
          left: AppSpace.sm,
          bottom: AppSpace.xs,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '© OpenStreetMap contributors, © CARTO',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
