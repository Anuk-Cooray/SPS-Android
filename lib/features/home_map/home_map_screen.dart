import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/campus_map_view.dart';
import '../../data/models/parking_lot_model.dart';
import '../../data/services/parking_state_manager.dart';

class HomeMapScreen extends StatefulWidget {
  final ValueChanged<ParkingLot> onSelectLot;

  const HomeMapScreen({super.key, required this.onSelectLot});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  String? _selectedLotId = 'lot-main';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.watch<ParkingStateManager>();
    final lots = state.lots;

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          // 1. Campus Map Canvas
          Positioned.fill(
            child: CampusMapView(
              lots: lots,
              selectedLotId: _selectedLotId,
              onLotSelected: (lot) {
                setState(() => _selectedLotId = lot.id);
                widget.onSelectLot(lot);
              },
            ),
          ),

          // 2. Top Search & Filter Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg,
                vertical: AppSpace.sm,
              ),
              child: Row(
                children: [
                  // Search field
                  Expanded(
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: c.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded, color: c.textPrimary, size: 22),
                          const SizedBox(width: AppSpace.sm),
                          Expanded(
                            child: Text(
                              'SLIIT Malabe Campus',
                              style: AppText.body.copyWith(
                                color: c.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: AppSpace.sm),

                  // Filter button
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(Icons.tune_rounded, color: c.textPrimary, size: 22),
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Draggable Bottom Sheet for Nearby Lots
          DraggableScrollableSheet(
            initialChildSize: 0.42,
            minChildSize: 0.22,
            maxChildSize: 0.75,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: AppRadius.sheetR,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
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
                          color: c.slotTaken,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Parking nearby',
                          style: AppText.h2.copyWith(color: c.textPrimary),
                        ),
                        Text(
                          'Live · updated now',
                          style: AppText.caption.copyWith(color: c.textSecondary),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpace.md),

                    // Lots list
                    ...lots.map((lot) {
                      final isSelected = lot.id == _selectedLotId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: _LotCard(
                          lot: lot,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() => _selectedLotId = lot.id);
                            widget.onSelectLot(lot);
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
            color: isSelected ? c.textPrimary : c.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            // P icon box
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected ? c.primary : c.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                'P',
                style: AppText.title.copyWith(
                  color: isSelected ? c.onPrimary : c.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            const SizedBox(width: AppSpace.md),

            // Lot Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lot.name,
                    style: AppText.title.copyWith(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${lot.distanceMeters} m from destination · LKR ${lot.hourlyRate}/h',
                    style: AppText.caption.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),

            // Free slots count
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isFull ? '0' : '${lot.freeSlots}',
                  style: AppText.h2.copyWith(
                    color: isFull
                        ? c.textTertiary
                        : (isSelected ? c.accent : c.textPrimary),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  isFull ? 'full' : 'free',
                  style: AppText.caption.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
