import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/booking_model.dart';
import '../../data/models/parking_lot_model.dart';
import '../../data/models/parking_slot_model.dart';
import '../../data/services/ai_occupancy_service.dart';
import '../../data/services/parking_state_manager.dart';

/// Slot board for the single lot calibrated against the YOLO camera. It never
/// treats an unknown/offline response as available.
class AiSlotBoardScreen extends StatelessWidget {
  const AiSlotBoardScreen({
    super.key,
    required this.lot,
    required this.onBooked,
  });

  final ParkingLot lot;
  final ValueChanged<Booking> onBooked;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = context.watch<ParkingStateManager>();
    final liveLot = state.lots.firstWhere(
      (item) => item.id == lot.id,
      orElse: () => lot,
    );
    final offline = state.aiError != null;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Live parking availability'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: state.isAiRefreshing ? null : state.refreshAiOccupancy,
            icon: state.isAiRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _Summary(lot: liveLot, offline: offline),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(AppSpace.lg),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 92,
                mainAxisSpacing: AppSpace.sm,
                crossAxisSpacing: AppSpace.sm,
                childAspectRatio: .88,
              ),
              itemCount: liveLot.slots.length,
              itemBuilder: (context, index) => _SlotCard(
                slot: liveLot.slots[index],
                onTap: () =>
                    _selectSlot(context, liveLot, liveLot.slots[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectSlot(
    BuildContext context,
    ParkingLot lot,
    ParkingSlot slot,
  ) async {
    if (!slot.isAvailable) {
      final label = slot.state == SlotState.unknown
          ? 'Unknown / offline'
          : 'Occupied or booked';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Slot ${slot.id}: $label')));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Book slot ${slot.id}?'),
        content: const Text(
          'The server will check live occupancy again before reserving this space.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Book'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      final booking = await context.read<ParkingStateManager>().reserveAiSlot(
        lot: lot,
        slot: slot,
        arrivalTime: DateTime.now().add(const Duration(minutes: 15)),
        durationHours: 2,
      );
      if (context.mounted) onBooked(booking);
    } on AiConflictException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
        context.read<ParkingStateManager>().refreshAiOccupancy();
      }
    } on AiApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.lot, required this.offline});
  final ParkingLot lot;
  final bool offline;
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final occupied = lot.slots
        .where((slot) => slot.state == SlotState.taken)
        .length;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(AppSpace.lg),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: offline ? colors.surfaceMuted : colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            offline ? 'Unknown / Offline' : 'Live YOLO occupancy',
            style: AppText.title.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            offline
                ? 'Slots are disabled until a recent camera detection is available.'
                : '${lot.freeSlots} available · $occupied occupied',
            style: AppText.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.md,
            children: const [
              _Legend(color: Colors.green, label: 'Available'),
              _Legend(color: Colors.red, label: 'Occupied / booked'),
              _Legend(color: Colors.grey, label: 'Unknown'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.circle, size: 10, color: color),
      const SizedBox(width: 4),
      Text(label),
    ],
  );
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.slot, required this.onTap});
  final ParkingSlot slot;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final available = slot.state == SlotState.free;
    final color = available
        ? Colors.green
        : slot.state == SlotState.unknown
        ? Colors.grey
        : Colors.red;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.slot),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(AppRadius.slot),
          border: Border.all(color: color),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_parking_rounded, color: color),
            Text(
              slot.id,
              style: AppText.body.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              available
                  ? 'Free'
                  : slot.state == SlotState.unknown
                  ? 'Unknown'
                  : 'Taken',
              style: AppText.caption.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
