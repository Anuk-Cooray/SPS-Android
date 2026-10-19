// home_map_screen.dart
// Interactive Colombo Live Map with Uber-Style Location Search, Dual Navigation, and Parking Discovery

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          // 1. Interactive Colombo Live Map with real OSM / Carto tiles
          Positioned.fill(
            child: ColomboLiveMapView(
              pickup: _pickup,
              destination: _destination,
              activeLots: _activeLots,
              selectedLotId: _selectedLotId,
              onLotSelected: (selectedLot) {
                setState(() => _selectedLotId = selectedLot.id);
              },
              onRecenter: () {},
            ),
          ),

          // 2. Uber-Style Dual Pickup & Destination Selector Bar
          SafeArea(
            child: UberLocationSelectorBar(
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
            ),
          ),

          // 3. Draggable Bottom Sheet for Nearby Parking Lots & Navigation Options
          DraggableScrollableSheet(
            initialChildSize: 0.48,
            minChildSize: 0.22,
            maxChildSize: 0.85,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: AppRadius.sheetR,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 22,
                      offset: const Offset(0, -6),
                    )
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.lg,
                    AppSpace.xs,
                    AppSpace.lg,
                    AppSpace.xl,
                  ),
                  children: [
                    // Sheet Handle
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: AppSpace.md),
                        decoration: BoxDecoration(
                          color: c.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

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
                                  color: c.accent,
                                  shape: BoxShape.circle,
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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: isSelected ? c.accent : c.border,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Row(
          children: [
            // P icon box
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected ? c.accent : c.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                'P',
                style: AppText.title.copyWith(
                  color: isSelected ? Colors.white : c.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),

            const SizedBox(width: AppSpace.md),

            // Lot Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lot.name,
                          style: AppText.body.copyWith(
                            color: c.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Selected',
                            style: AppText.caption.copyWith(
                              color: c.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${lot.distanceMeters}m walk to entrance · LKR ${lot.hourlyRate.toInt()}/h',
                    style: AppText.caption.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),

            const SizedBox(width: AppSpace.sm),

            // Slots count badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isFull ? '0' : '${lot.freeSlots}',
                  style: AppText.h2.copyWith(
                    color: isFull ? c.slotTaken : c.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  isFull ? 'full' : 'free',
                  style: AppText.caption.copyWith(
                    color: isFull ? c.slotTaken : c.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
