import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/booking_model.dart';
import '../../data/models/parking_event_model.dart';
import '../../data/services/parking_state_manager.dart';
import 'engine_tuning_modal.dart';
import 'telemetry_export_modal.dart';

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
                value: '${state.allActiveBookings.length}',
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
                        _legendDot(c.primary, 'Today', c),
                        const SizedBox(width: AppSpace.md),
                        _legendDot(c.slotTaken, 'Last week', c),
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
                          'Optimization Model (SYS-01)',
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
                    _buildParamPill('ΔS ≥ ${state.scoringWeights.minScoreImprovementPercent.toInt()}%', c, isThreshold: true),
                    _buildParamPill('Hold: ${state.scoringWeights.offerTimeoutSeconds}s', c, isThreshold: true),
                    _buildParamPill('ETA: ≤${state.scoringWeights.upgradeTriggerEtaMinutes}m', c, isThreshold: true),
                  ],
                ),
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

          const SizedBox(height: AppSpace.xl),

          // Telemetry Audit Stream (SYS-08)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Telemetry stream (SYS-08)',
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

  Widget _legendDot(Color color, String label, AppColors c) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: AppSpace.xxs),
        Text(label, style: TextStyle(fontSize: 11, color: c.textSecondary)),
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
                style: AppText.caption.copyWith(color: c.textTertiary, fontSize: 11),
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
              style: AppText.caption.copyWith(color: c.textSecondary, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
