import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/booking_model.dart';
import '../../data/models/parking_event_model.dart';
import '../../data/models/parking_lot_model.dart';
import '../../data/models/parking_slot_model.dart';
import '../../data/services/parking_state_manager.dart';
import 'engine_tuning_modal.dart';
import 'hardware_integration_simulator_modal.dart';
import 'telemetry_export_modal.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.watch<ParkingStateManager>();
    final bookings = state.bookings;
    final activeLot = state.lots.isNotEmpty ? state.lots.first : null;

    // Filter bookings based on selected status filter
    final filteredBookings = bookings.where((b) {
      if (_selectedFilter == 'All') return true;
      if (_selectedFilter == 'In-Transit') return b.status == BookingStatus.reserved && b.isInTransit;
      if (_selectedFilter == 'Held') return b.status == BookingStatus.reserved && b.isHoldWindowActive;
      if (_selectedFilter == 'Upgraded') return b.status == BookingStatus.upgraded;
      if (_selectedFilter == 'Checked In') return b.status == BookingStatus.checkedIn;
      if (_selectedFilter == 'Completed') return b.status == BookingStatus.completed;
      if (_selectedFilter == 'Auto-Released') return b.status == BookingStatus.autoCancelled;
      return true;
    }).toList();

    // Calculate live dynamic KPIs
    final totalSlots = activeLot?.totalSlots ?? 72;
    final freeSlots = activeLot?.freeSlots ?? 23;
    final occupiedSlots = totalSlots - freeSlots;
    final occupancyPct = totalSlots > 0 ? ((occupiedSlots / totalSlots) * 100).round() : 0;

    final upgradedCount = bookings.where((b) => b.status == BookingStatus.upgraded).length;
    final totalOffers = state.events.where((e) => e.type == ParkingEventType.offered).length;
    final upgradeAcceptancePct = totalOffers > 0 ? ((upgradedCount / totalOffers) * 100).round() : 74;

    final autoCancelledCount = bookings.where((b) => b.status == BookingStatus.autoCancelled).length;
    final recoveredMinutes = autoCancelledCount * 120; // Avg 2h recovered per no-show release

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text('Live dashboard', style: AppText.h2.copyWith(color: c.textPrimary)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.md),
            child: Row(
              children: [
                if (AppConfig.kDemoMode) ...[
                  OutlinedButton.icon(
                    onPressed: () => HardwareIntegrationSimulatorModal.show(context),
                    icon: const Icon(Icons.developer_board_rounded, size: 16),
                    label: const Text('Stubs'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(70, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: c.accent,
                    ),
                  ),
                  const SizedBox(width: AppSpace.xs),
                ],
                OutlinedButton.icon(
                  onPressed: () => EngineTuningModal.show(context),
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: const Text('Weights'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(80, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                OutlinedButton(
                  onPressed: () => TelemetryExportModal.show(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(70, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Export'),
                ),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          Text(
            'Facility: ${activeLot?.name ?? "Colombo Central Hub"} · Live Synced',
            style: AppText.caption.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: AppSpace.md),

          // 4 Key Stats Cards
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpace.md,
            crossAxisSpacing: AppSpace.md,
            childAspectRatio: 1.45,
            children: [
              _buildStatCard(
                context,
                title: 'Occupancy',
                value: '$occupancyPct%',
                subtitle: '$occupiedSlots of $totalSlots slots occupied',
              ),
              _buildStatCard(
                context,
                title: 'Active bookings',
                value: '${state.allActiveBookings.length}',
                subtitle: 'in-transit or held',
              ),
              _buildStatCard(
                context,
                title: 'Upgrades accepted',
                value: '$upgradeAcceptancePct%',
                subtitle: '$upgradedCount upgrades · avg 58m saved',
                isHighlighted: true,
              ),
              _buildStatCard(
                context,
                title: 'Slot-min recovered',
                value: '${recoveredMinutes}m',
                subtitle: '$autoCancelledCount no-shows auto-released',
              ),
            ],
          ),

          const SizedBox(height: AppSpace.xl),

          // --- Interactive Live Slot Map (SYS-01 & Hardware Ingestion) ---
          Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.grid_view_rounded, color: c.accent, size: 20),
                        const SizedBox(width: AppSpace.xs),
                        Text(
                          'Live Slot Map (${activeLot?.slots.length ?? 72} Bays)',
                          style: AppText.title.copyWith(color: c.textPrimary),
                        ),
                      ],
                    ),
                    Text(
                      'Tap bay for details',
                      style: AppText.caption.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  'Visual representation of multi-bay facility occupancy and sensor states.',
                  style: AppText.caption.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: AppSpace.md),

                // Grid of Slots
                _buildLiveSlotGrid(context, activeLot, state),

                const SizedBox(height: AppSpace.md),
                const Divider(height: 1),
                const SizedBox(height: AppSpace.sm),

                // Map Legend adhering to exact system color semantics
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _buildLegendItem('Available', c.surface, borderColor: c.border),
                    _buildLegendItem('Reserved / Held', c.accent),
                    _buildLegendItem('Occupied', c.slotTaken),
                    _buildLegendItem('Conflict / Blocked', c.danger),
                    _buildLegendItem('Late Warning', c.surface, borderColor: c.warning, badgeColor: c.warning),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpace.xl),

          // Optimization Model Hyperparameters Card (SYS-01 & SYS-03)
          Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tune_rounded, color: c.accent, size: 20),
                        const SizedBox(width: AppSpace.xs),
                        Text(
                          'Scoring Model (${state.weightsVersion})',
                          style: AppText.title.copyWith(color: c.textPrimary),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () => EngineTuningModal.show(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Tune Weights',
                        style: AppText.caption.copyWith(
                          color: c.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Objective Function: S(s) = wd·Sdist + wz·Ssize + wp·Spref - wu·Pdemand',
                  style: AppText.caption.copyWith(
                    color: c.textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildParamPill('wd: ${(state.scoringWeights.distanceWeight * 100).toInt()}% (Distance)', c),
                    _buildParamPill('wz: ${(state.scoringWeights.sizeFitWeight * 100).toInt()}% (Size Fit)', c),
                    _buildParamPill('wp: ${(state.scoringWeights.preferenceWeight * 100).toInt()}% (Pref)', c),
                    _buildParamPill('wu: ${(state.scoringWeights.demandWeight * 100).toInt()}% (Demand)', c),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildParamPill('Δd ≥ ${state.scoringWeights.minImprovementMeters}m', c, isThreshold: true),
                    _buildParamPill('ΔS ≥ ${state.scoringWeights.minScoreImprovementPoints.toInt()} pts', c, isThreshold: true),
                    _buildParamPill('Hold: ${state.scoringWeights.offerTimeoutSeconds}s', c, isThreshold: true),
                    _buildParamPill('ETA: ≤${state.scoringWeights.upgradeTriggerEtaMinutes}m', c, isThreshold: true),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpace.xl),

          // --- Reservations Table with Live Filter Chips ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Reservations Table',
                style: AppText.h2.copyWith(color: c.textPrimary),
              ),
              Text(
                '${filteredBookings.length} bookings',
                style: AppText.caption.copyWith(color: c.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                'All',
                'In-Transit',
                'Held',
                'Upgraded',
                'Checked In',
                'Completed',
                'Auto-Released',
              ].map((filter) {
                final isSelected = _selectedFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(filter),
                    selected: isSelected,
                    onSelected: (val) => setState(() => _selectedFilter = filter),
                    labelStyle: AppText.caption.copyWith(
                      color: isSelected ? c.accent : c.textSecondary,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    backgroundColor: c.surface,
                    selectedColor: c.accentSoft,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      side: BorderSide(
                        color: isSelected ? c.accent : c.border,
                        width: 1,
                      ),
                    ),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpace.md),

          if (filteredBookings.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpace.xl),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: c.border),
              ),
              child: Text(
                'No reservations found for filter "$_selectedFilter"',
                style: AppText.body.copyWith(color: c.textSecondary),
              ),
            )
          else
            ...filteredBookings.take(8).map((b) => _ReservationRow(booking: b)),

          const SizedBox(height: AppSpace.xl),

          // Telemetry Audit Stream (SYS-08)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Telemetry Stream (SYS-08)',
                style: AppText.h2.copyWith(color: c.textPrimary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  '${state.events.length} events logged',
                  style: AppText.caption.copyWith(
                    color: c.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Algorithmic decision evaluations, upgrade offers, and lifecycle transitions.',
            style: AppText.caption.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: AppSpace.md),

          if (state.events.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpace.lg),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: c.border),
              ),
              child: Text(
                'No telemetry events recorded yet.',
                style: AppText.body.copyWith(color: c.textSecondary),
              ),
            )
          else
            ...state.events.take(6).map((e) => _TelemetryEventRow(event: e)),

          const SizedBox(height: AppSpace.xxl),
        ],
      ),
    );
  }

  Widget _buildLiveSlotGrid(BuildContext context, ParkingLot? activeLot, ParkingStateManager state) {
    final slots = activeLot?.slots ?? [];

    if (slots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpace.md),
        alignment: Alignment.center,
        child: const Text('No slots loaded.'),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const crossAxisCount = 8;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.25,
          ),
          itemCount: slots.length,
          itemBuilder: (context, idx) {
            final slot = slots[idx];
            return _buildSlotTile(context, slot, state);
          },
        );
      },
    );
  }

  Widget _buildSlotTile(BuildContext context, ParkingSlot slot, ParkingStateManager state) {
    final c = context.colors;

    // Check for associated booking
    final booking = state.bookings.cast<Booking?>().firstWhere(
          (b) => b != null && b.slotId == slot.id && b.isActive,
          orElse: () => null,
        );

    final isLateWarning = booking != null &&
        booking.status == BookingStatus.reserved &&
        DateTime.now().isAfter(booking.lateWarningTime) &&
        !booking.isHoldExpired;

    // Determine colors strictly adhering to spec:
    // available = outlined, reserved/held = accent blue, occupied = slotTaken grey, conflict/blocked = danger red
    Color fillColor;
    Color borderColor;
    Color textColor;

    if (slot.state == SlotState.blocked) {
      fillColor = c.danger;
      borderColor = c.danger;
      textColor = Colors.white;
    } else if (slot.state == SlotState.taken) {
      fillColor = c.slotTaken;
      borderColor = c.slotTaken;
      textColor = c.textSecondary;
    } else if (slot.state == SlotState.yours || booking != null) {
      fillColor = c.accent;
      borderColor = isLateWarning ? c.warning : c.accent;
      textColor = Colors.white;
    } else {
      // Available / Free = outlined
      fillColor = Colors.transparent;
      borderColor = c.border;
      textColor = c.textPrimary;
    }

    return InkWell(
      onTap: () => _showSlotDetailsModal(context, slot, booking),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: borderColor,
            width: isLateWarning ? 2.0 : 1.2,
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${slot.row}${slot.number}',
              style: AppText.caption.copyWith(
                color: textColor,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
            if (isLateWarning)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: c.warning,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSlotDetailsModal(BuildContext context, ParkingSlot slot, Booking? booking) {
    final c = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AppRadius.sheetR,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Bay ${slot.row}-${slot.number} (${slot.id})',
                    style: AppText.h2.copyWith(color: c.textPrimary),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(
                      slot.state.name.toUpperCase(),
                      style: AppText.caption.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                'Walking Distance: ${slot.walkingDistanceMeters}m · Size: ${slot.size.displayName} · Type: ${slot.type.displayName}',
                style: AppText.caption.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppSpace.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpace.md),
              if (booking != null) ...[
                Text('Active Reservation Details', style: AppText.title.copyWith(color: c.textPrimary)),
                const SizedBox(height: 4),
                Text('Booking ID: #${booking.id}', style: AppText.body),
                Text('Vehicle: ${booking.vehiclePlate}', style: AppText.body),
                Text('Arrival ETA: ${DateFormat('h:mm a').format(booking.arrivalTime)}', style: AppText.body),
                Text('Status: ${booking.status.displayName}', style: AppText.body),
                if (booking.reallocatedDueToConflict)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: c.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: c.danger),
                    ),
                    child: Text(
                      'Reallocated due to CCTV slot conflict!',
                      style: AppText.caption.copyWith(color: c.danger, fontWeight: FontWeight.bold),
                    ),
                  ),
              ] else ...[
                Text('Bay is currently available for incoming reservations.', style: AppText.body.copyWith(color: c.textSecondary)),
              ],
              const SizedBox(height: AppSpace.lg),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color fillColor, {Color? borderColor, Color? badgeColor}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: borderColor ?? fillColor, width: 1.2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppText.caption.copyWith(color: context.colors.textSecondary)),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    bool isHighlighted = false,
  }) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isHighlighted ? c.accent : c.border,
          width: isHighlighted ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: AppText.caption.copyWith(color: isHighlighted ? c.accent : c.textSecondary)),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppText.h1.copyWith(
              color: isHighlighted ? c.accent : c.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppText.caption.copyWith(color: c.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildParamPill(String label, AppColors c, {bool isThreshold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isThreshold ? c.surfaceMuted : c.accentSoft,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isThreshold ? c.border : c.accent.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        label,
        style: AppText.caption.copyWith(
          color: isThreshold ? c.textSecondary : c.accent,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _ReservationRow extends StatelessWidget {
  final Booking booking;

  const _ReservationRow({required this.booking});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isUpgraded = booking.status == BookingStatus.upgraded;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '#${booking.id}',
                style: AppText.title.copyWith(color: c.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                booking.vehiclePlate,
                style: AppText.caption.copyWith(color: c.textSecondary),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                isUpgraded
                    ? '${booking.originalSlotId ?? 'A-06'} → ${booking.slotId}'
                    : booking.slotId,
                style: AppText.label.copyWith(
                  color: isUpgraded ? c.accent : c.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                booking.isInTransit
                    ? 'ETA ${booking.timeUntilArrival.inMinutes}m'
                    : 'Held (${booking.remainingHoldDuration.inMinutes}m)',
                style: AppText.caption.copyWith(color: c.textSecondary),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isUpgraded ? c.accentSoft : c.surfaceMuted,
              borderRadius: BorderRadius.circular(6),
              border: isUpgraded ? Border.all(color: c.accent, width: 1) : null,
            ),
            child: Text(
              booking.status.displayName,
              style: AppText.caption.copyWith(
                color: isUpgraded ? c.accent : c.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TelemetryEventRow extends StatelessWidget {
  final ParkingEvent event;

  const _TelemetryEventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final timeFormatted = DateFormat('h:mm a').format(event.timestamp);

    Color badgeColor;
    Color badgeText;
    switch (event.type) {
      case ParkingEventType.accepted:
        badgeColor = c.accentSoft;
        badgeText = c.accent;
        break;
      case ParkingEventType.offered:
        badgeColor = c.accentSoft.withValues(alpha: 0.5);
        badgeText = c.accent;
        break;
      case ParkingEventType.weightsTuned:
        badgeColor = c.accentSoft;
        badgeText = c.accent;
        break;
      case ParkingEventType.autoCancelled:
      case ParkingEventType.cancelled:
        badgeColor = c.surfaceMuted;
        badgeText = c.textSecondary;
        break;
      default:
        badgeColor = c.surfaceMuted;
        badgeText = c.textPrimary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.cardSm),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  event.type.displayName,
                  style: AppText.caption.copyWith(
                    color: badgeText,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
              Text(
                timeFormatted,
                style: AppText.caption.copyWith(color: c.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            event.description,
            style: AppText.body.copyWith(color: c.textPrimary, fontSize: 13),
          ),
          if (event.bookingId.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              'Ref: #${event.bookingId}',
              style: AppText.caption.copyWith(color: c.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
