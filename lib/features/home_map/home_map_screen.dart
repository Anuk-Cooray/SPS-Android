// home_map_screen.dart
// Interactive Colombo Live Map with Uber-Style Location Search, Dual Navigation, and Parking Discovery

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_card.dart';
import '../../data/models/colombo_landmark_model.dart';
import '../../data/models/parking_lot_model.dart';
import '../../data/services/colombo_location_service.dart';
import '../../data/services/parking_state_manager.dart';
import 'widgets/colombo_live_map_view.dart';
import 'widgets/uber_location_selector_bar.dart';

class HomeMapScreen extends StatefulWidget {
  final ValueChanged<ParkingLot> onSelectLot;

  const HomeMapScreen({super.key, required this.onSelectLot});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  late ColomboLandmark _pickup;
  late ColomboLandmark _destination;
  late List<ParkingLot> _activeLots;
  String? _selectedLotId;

  @override
  void initState() {
    super.initState();
    // Default Pickup: Current Location (SLIIT Malabe)
    _pickup = ColomboLocationService.getLandmarkById('sliit-malabe');
    // Default Destination: SLIIT Malabe Campus (Search bar allows picking any Colombo landmark)
    _destination = ColomboLocationService.getLandmarkById('sliit-malabe');
    _updateActiveLots();
  }

  void _updateActiveLots() {
    // If destination is SLIIT, prioritize live StateManager lots
    if (_destination.id == 'sliit-malabe') {
      final stateLots = context.read<ParkingStateManager>().lots;
      _activeLots = stateLots.isNotEmpty ? stateLots : _destination.nearbyLots;
    } else {
      _activeLots = _destination.nearbyLots;
    }

    if (_activeLots.isNotEmpty) {
      _selectedLotId = _activeLots.first.id;
    } else {
      _selectedLotId = null;
    }
  }

  void _swapLocations() {
    setState(() {
      final temp = _pickup;
      _pickup = _destination;
      _destination = temp;
      _updateActiveLots();
    });
  }

  Widget _sheetHandle(AppColors c) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: AppSpace.md),
        decoration: BoxDecoration(
          color: c.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  /// Header + lot cards, shared by the phone bottom sheet and the tablet side panel.
  List<Widget> _lotListChildren(AppColors c) {
    return [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Parking near ${_destination.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.h2.copyWith(
                      color: c.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_activeLots.length} facilities · ${_destination.zone}',
                    style: AppText.caption.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: c.success,
                      shape: BoxShape.circle,
                      boxShadow: AppEffects.glow(c.success, strength: 0.8, blur: 8),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Live',
                    style: AppText.caption.copyWith(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: AppSpace.md),

        // Lots list
        ..._activeLots.map((l) {
          final isSelected = l.id == _selectedLotId;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: _LotCard(
              lot: l,
              isSelected: isSelected,
              onTap: () {
                setState(() => _selectedLotId = l.id);
                widget.onSelectLot(l);
              },
            ),
          );
        }),
    ];
  }

  Widget _locationBar() {
    return UberLocationSelectorBar(
      pickup: _pickup,
      destination: _destination,
      onPickupChanged: (newPickup) {
        setState(() {
          _pickup = newPickup;
          _updateActiveLots();
        });
      },
      onDestinationChanged: (newDest) {
        setState(() {
          _destination = newDest;
          _updateActiveLots();
        });
      },
      onSwap: _swapLocations,
      onFilterTap: () => Navigator.pushNamed(context, '/admin'),
    );
  }

  Widget _map({EdgeInsets? fitPadding, double? controlsTop}) {
    return ColomboLiveMapView(
      pickup: _pickup,
      destination: _destination,
      activeLots: _activeLots,
      selectedLotId: _selectedLotId,
      onLotSelected: (selectedLot) {
        setState(() => _selectedLotId = selectedLot.id);
      },
      onRecenter: () {},
      fitPadding: fitPadding ?? const EdgeInsets.fromLTRB(56, 230, 80, 440),
      controlsTop: controlsTop ?? 212,
    );
  }

  /// Tablets / landscape: full-screen map with a floating glass panel on the left.
  Widget _buildWide(AppColors c) {
    const panelWidth = 440.0;
    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: _map(
              fitPadding: const EdgeInsets.fromLTRB(panelWidth + 80, 80, 120, 80),
              controlsTop: AppSpace.lg + MediaQuery.paddingOf(context).top,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top,
            child: ColoredBox(color: c.background.withValues(alpha: 0.9)),
          ),
          // Positioned, so the stack (and the map) keeps the full screen size
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: panelWidth + AppSpace.sm,
            child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, 0, AppSpace.md),
              child: SizedBox(
                width: panelWidth,
                child: Column(
                  children: [
                    _locationBar(),
                    const SizedBox(height: AppSpace.xs),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                        child: GlassCard(
                          blur: true,
                          padding: EdgeInsets.zero,
                          radius: AppRadius.sheet,
                          child: ListView(
                            padding: const EdgeInsets.all(AppSpace.md),
                            children: _lotListChildren(c),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (MediaQuery.sizeOf(context).width >= 900) return _buildWide(c);

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          // 1. Interactive Colombo live map (OpenStreetMap tiles)
          Positioned.fill(child: _map()),

          // Scrim behind the status bar so the clock and icons stay legible over the map
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top,
            child: ColoredBox(color: c.background.withValues(alpha: 0.9)),
          ),

          // 2. Uber-Style Dual Pickup & Destination Selector Bar
          SafeArea(child: _locationBar()),

          // 3. Draggable Bottom Sheet for Nearby Parking Lots & Navigation Options
          DraggableScrollableSheet(
            initialChildSize: 0.48,
            minChildSize: 0.22,
            maxChildSize: 0.85,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [c.surface, c.background],
                  ),
                  borderRadius: AppRadius.sheetR,
                  border: Border(top: BorderSide(color: c.accent.withValues(alpha: 0.35))),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 30,
                      offset: const Offset(0, -8),
                    )
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.xl),
                  children: [
                    _sheetHandle(c),
                    ..._lotListChildren(c),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LotCard extends StatelessWidget {
  final ParkingLot lot;
  final bool isSelected;
  final VoidCallback onTap;

  const _LotCard({
    required this.lot,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isFull = lot.isFull;
    final occupancy = lot.totalSlots > 0 ? 1 - lot.freeSlots / lot.totalSlots : 1.0;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${lot.name}, ${isFull ? 'full' : '${lot.freeSlots} free'}, '
          '${lot.distanceMeters} metres walk, LKR ${lot.hourlyRate.toInt()} per hour',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: GlassCard(
          selected: isSelected,
          child: Column(
            children: [
              Row(
                children: [
                  // P tile: gradient + glow when selected
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: isSelected ? AppEffects.hero : null,
                      color: isSelected ? null : c.surfaceMuted,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: isSelected ? AppEffects.glow(c.accent, strength: 0.4, blur: 18) : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'P',
                      style: AppText.h2.copyWith(
                        color: isSelected ? Colors.white : c.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lot.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.title.copyWith(color: c.textPrimary, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.directions_walk_rounded, size: AppIconSize.sm, color: c.textSecondary),
                            const SizedBox(width: 2),
                            Text('${lot.distanceMeters} m', style: AppText.caption.copyWith(color: c.textSecondary)),
                            const SizedBox(width: AppSpace.sm),
                            Icon(Icons.payments_outlined, size: AppIconSize.sm, color: c.textSecondary),
                            const SizedBox(width: 4),
                            Text('LKR ${lot.hourlyRate.toInt()}/h', style: AppText.caption.copyWith(color: c.textSecondary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  // Free count: teal when available, red when full
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isFull ? 'FULL' : '${lot.freeSlots}',
                        style: AppText.h1.copyWith(
                          color: isFull ? c.danger : c.success,
                          fontSize: isFull ? 18 : 28,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                      if (!isFull)
                        Text('FREE', style: AppText.overline.copyWith(color: c.success, fontSize: 11)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              // Occupancy bar
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: occupancy.clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: c.successSoft,
                  valueColor: AlwaysStoppedAnimation(isFull ? c.danger : c.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
