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

  // Frame the destination and every lot so their pins don't pile up, leaving room for the
  // location card on top and the lot sheet below.
  CameraFit get _lotsCameraFit => CameraFit.coordinates(
        coordinates: [
          LatLng(widget.destination.latitude, widget.destination.longitude),
          ...widget.activeLots.map((lot) => LatLng(lot.latitude, lot.longitude)),
        ],
        padding: const EdgeInsets.fromLTRB(56, 230, 80, 440),
        maxZoom: 17.5,
      );

  void _fitRoute() {
    _mapController.fitCamera(_lotsCameraFit);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // 1. Live FlutterMap with OpenStreetMap tiles, filtered to the monochrome palette
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(
              widget.destination.latitude,
              widget.destination.longitude,
            ),
            initialZoom: 14.2,
            initialCameraFit: _lotsCameraFit,
            minZoom: 9.0,
            maxZoom: 18.0,
          ),
          children: [
            // OpenStreetMap standard tiles (no API key); CARTO basemaps now require a key.
            // A colour matrix turns them grayscale (inverted in dark mode) to match the theme.
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.sliit.smartparking.smart_parking',
              maxZoom: 19,
              tileBuilder: (context, tileWidget, tile) => ColorFiltered(
                colorFilter: isDark ? _mapTilesDark : _mapTilesLight,
                child: tileWidget,
              ),
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

                // Destination pin: label-free so it never covers the lot pins clustered around it
                Marker(
                  point: LatLng(widget.destination.latitude, widget.destination.longitude),
                  width: 32,
                  height: 32,
                  alignment: Alignment.topCenter,
                  child: Semantics(
                    label: 'Destination: ${widget.destination.name}',
                    child: Icon(Icons.location_on_rounded, color: c.primary, size: 32),
                  ),
                ),

                // Parking Lots Pins
                // Selected lot last so its pin draws on top
                ...([...widget.activeLots]
                      ..sort((a, b) => (a.id == widget.selectedLotId ? 1 : 0)
                          .compareTo(b.id == widget.selectedLotId ? 1 : 0)))
                    .map((lot) {
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
          top: 212, // below the location card
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
                tooltip: 'Show all parking lots',
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
                tooltip: 'Zoom in',
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
                tooltip: 'Zoom out',
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

        // 3. Map Tile Attribution (required by the OpenStreetMap tile usage policy)
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
              '© OpenStreetMap contributors',
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

// Luminance grayscale (light theme).
const _mapTilesLight = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

// Inverted, compressed grayscale (dark theme): land ~#1F, labels stay light.
const _mapTilesDark = ColorFilter.matrix(<double>[
  -0.1913, -0.6437, -0.0650, 0, 247.5,
  -0.1913, -0.6437, -0.0650, 0, 247.5,
  -0.1913, -0.6437, -0.0650, 0, 247.5,
  0, 0, 0, 1, 0,
]);
