import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/booking_model.dart';
import '../../data/services/parking_state_manager.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.watch<ParkingStateManager>();
    final bookings = state.bookings;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text('Live dashboard', style: AppText.h2.copyWith(color: c.textPrimary)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.md),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Exported telemetry metrics (SYS-08) to CSV')),
                    );
                  },
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
            'All lots · Today, 17 Oct · updated live',
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
              // Card 1: Occupancy
              _buildStatCard(
                context,
                title: 'Occupancy',
                value: '68%',
                subtitle: '49 of 72 slots',
              ),
              // Card 2: Active bookings
              _buildStatCard(
                context,
                title: 'Active bookings',
                value: '${state.activeBookings.length}',
                subtitle: 'arriving in 15 min',
              ),
              // Card 3: Upgrades accepted (Blue highlighted)
              _buildStatCard(
                context,
                title: 'Upgrades accepted',
                value: '74%',
                subtitle: '17 of 23 · avg 96m saved',
                isHighlighted: true,
              ),
              // Card 4: Auto-cancelled
              _buildStatCard(
                context,
                title: 'Auto-cancelled',
                value: '5',
                subtitle: '5 slots freed for 3h 10m',
              ),
            ],
          ),

          const SizedBox(height: AppSpace.xl),

          // Hourly Occupancy Chart Card
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
                    Text('Occupancy by hour', style: AppText.title.copyWith(color: c.textPrimary)),
                    Row(
                      children: [
                        _legendDot(c.primary, 'Today'),
                        const SizedBox(width: AppSpace.md),
                        _legendDot(c.slotTaken, 'Last week'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
                SizedBox(
                  height: 140,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildBarColumn('8 AM', 0.28, 0.22, c),
                      _buildBarColumn('9', 0.52, 0.44, c),
                      _buildBarColumn('10', 0.76, 0.70, c),
                      _buildBarColumn('11', 0.82, 0.80, c),
                      _buildBarColumn('12 PM', 0.70, 0.65, c),
                      _buildBarColumn('1', 0.64, 0.55, c),
                      _buildBarColumn('2', 0.10, 0.38, c),
                      _buildBarColumn('3', 0.05, 0.32, c),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpace.xl),

          // Lots Breakdown
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
                Text('Lots', style: AppText.title.copyWith(color: c.textPrimary)),
                const SizedBox(height: AppSpace.md),
                ...state.lots.map((lot) {
                  final ratio = (lot.totalSlots - lot.freeSlots) / lot.totalSlots;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.md),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(lot.name, style: AppText.body.copyWith(fontWeight: FontWeight.w600)),
                            Text(
                              '${lot.freeSlots} free / ${lot.totalSlots}',
                              style: AppText.caption.copyWith(color: c.textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 6,
                            backgroundColor: c.divider,
                            valueColor: AlwaysStoppedAnimation<Color>(c.primary),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: AppSpace.xl),

          // Live Reservations Table
          Text(
            'Live reservations',
            style: AppText.h2.copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: AppSpace.md),

          ...bookings.take(5).map((b) => _ReservationRow(booking: b)),

          const SizedBox(height: AppSpace.xxl),
        ],
      ),
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
            style: AppText.caption.copyWith(color: c.textSecondary, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: AppSpace.xxs),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _buildBarColumn(String label, double today, double lastWeek, AppColors c) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              width: 10,
              height: 100 * lastWeek,
              decoration: BoxDecoration(
                color: c.slotTaken,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
              ),
            ),
            const SizedBox(width: 3),
            Container(
              width: 10,
              height: 100 * today,
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 10, color: c.textSecondary)),
      ],
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
              Text('ETA 6 min', style: AppText.caption.copyWith(color: c.textSecondary)),
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
