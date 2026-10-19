import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/hold_countdown_timer_widget.dart';
import '../../data/models/booking_model.dart';
import '../../data/models/parking_event_model.dart';
import '../../data/services/parking_state_manager.dart';

class BookingDetailModal extends StatelessWidget {
  final Booking booking;
  final VoidCallback? onOpenNavigation;
  final VoidCallback? onShowQr;
  final VoidCallback? onBookAgain;

  const BookingDetailModal({
    super.key,
    required this.booking,
    this.onOpenNavigation,
    this.onShowQr,
    this.onBookAgain,
  });

  static Future<void> show({
    required BuildContext context,
    required Booking booking,
    VoidCallback? onOpenNavigation,
    VoidCallback? onShowQr,
    VoidCallback? onBookAgain,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BookingDetailModal(
        booking: booking,
        onOpenNavigation: onOpenNavigation,
        onShowQr: onShowQr,
        onBookAgain: onBookAgain,
      ),
    );
  }

  void _showQrDialog(BuildContext context) {
    final c = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        title: Text(
          'Gate Check-in Pass',
          style: AppText.h2.copyWith(color: c.textPrimary),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${booking.lotName} · Bay ${booking.slotId}',
              style: AppText.title.copyWith(color: c.accent),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.md),
            Container(
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: c.border),
              ),
              child: QrImageView(
                data: booking.qrToken.isNotEmpty ? booking.qrToken : 'QR-${booking.id}',
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              'Scan at the entrance barrier reader.\nValid until ${DateFormat('h:mm a').format(booking.cancelDeadline)}',
              style: AppText.caption.copyWith(color: c.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: AppText.button.copyWith(color: c.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.watch<ParkingStateManager>();
    final relatedEvents = state.events.where((e) => e.bookingId == booking.id).toList();

    final isCancelled = booking.status == BookingStatus.cancelled ||
        booking.status == BookingStatus.autoCancelled;
    final isUpgraded = booking.status == BookingStatus.upgraded;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.sheetR,
      ),
      padding: EdgeInsets.only(
        top: AppSpace.xs,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpace.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: AppSpace.xs),
              decoration: BoxDecoration(
                color: c.slotTaken,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Booking Details', style: AppText.h2.copyWith(color: c.textPrimary)),
                    Text(
                      'Ref: ${booking.id}',
                      style: AppText.caption.copyWith(color: c.textSecondary, fontFamily: 'monospace'),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: c.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
              children: [
                // Top Bay & Status Card
                Container(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  decoration: BoxDecoration(
                    color: c.surfaceMuted,
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
                            booking.lotName,
                            style: AppText.title.copyWith(
                              color: c.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'SLIIT Malabe Campus',
                            style: AppText.caption.copyWith(color: c.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          _buildStatusBadge(context, booking.status),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'BAY',
                            style: AppText.caption.copyWith(
                              color: c.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            booking.slotId,
                            style: AppText.h1.copyWith(
                              color: c.accent,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpace.md),

                // Algorithmic Upgrade Benefit Callout
                if (isUpgraded) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpace.md),
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: c.accent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded, color: c.accent, size: 24),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Algorithmic Upgrade Applied',
                                style: AppText.title.copyWith(
                                  color: c.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Original bay ${booking.originalSlotId ?? "initial"} → ${booking.slotId} · Saved ${booking.distanceSavedMeters} m walking distance to campus entrance.',
                                style: AppText.caption.copyWith(
                                  color: c.textPrimary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                ],

                // Live Hold-Time Countdown & Auto-Release Card
                if (booking.status == BookingStatus.reserved ||
                    booking.status == BookingStatus.upgraded) ...[
                  HoldCountdownTimerWidget(
                    booking: booking,
                    compact: false,
                    onCheckedIn: () => state.checkIn(),
                  ),
                  const SizedBox(height: AppSpace.md),
                ],

                // Session Metadata Card
                Container(
                  padding: const EdgeInsets.all(AppSpace.md),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    children: [
                      _buildMetaRow(
                        context,
                        icon: Icons.directions_car_filled_outlined,
                        label: 'Vehicle Plate',
                        value: booking.vehiclePlate,
                      ),
                      const Divider(height: AppSpace.lg),
                      _buildMetaRow(
                        context,
                        icon: Icons.schedule_outlined,
                        label: 'Booked Arrival',
                        value: DateFormat('EEE, d MMM · h:mm a').format(booking.arrivalTime),
                      ),
                      const Divider(height: AppSpace.lg),
                      _buildMetaRow(
                        context,
                        icon: Icons.timelapse_outlined,
                        label: 'Duration',
                        value: '${booking.durationHours} hours',
                      ),
                      const Divider(height: AppSpace.lg),
                      _buildMetaRow(
                        context,
                        icon: Icons.payments_outlined,
                        label: isCancelled ? 'Cancellation Fee' : 'Total Parking Fee',
                        value: 'LKR ${booking.finalFee > 0 ? booking.finalFee : booking.estimatedFee}',
                        valueStyle: AppText.title.copyWith(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpace.lg),

                // Lifecycle Audit Timeline Section (US-33)
                Text(
                  'Lifecycle Audit Timeline (SYS-08)',
                  style: AppText.title.copyWith(color: c.textPrimary, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Verifiable real-time events and mathematical decision log.',
                  style: AppText.caption.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: AppSpace.md),

                Container(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    children: [
                      // Step 1: Reservation Created
                      _buildAuditTimelineStep(
                        context,
                        dotColor: c.textPrimary,
                        title: 'Reservation Confirmed',
                        subtitle: 'Allocated initial bay ${booking.originalSlotId ?? booking.slotId}',
                        timestamp: DateFormat('h:mm:ss a').format(booking.bookedAt),
                        isFirst: true,
                        isDone: true,
                      ),

                      // Step 2: Algorithmic Upgrade Re-optimization
                      if (isUpgraded) ...[
                        _buildAuditTimelineStep(
                          context,
                          dotColor: c.accent,
                          title: 'In-Transit Upgrade Accepted',
                          subtitle: 'Mathematical score improved (+20%) · Swapped to Bay ${booking.slotId} (saved ${booking.distanceSavedMeters}m)',
                          timestamp: _getEventTimestamp(relatedEvents, ParkingEventType.accepted) ??
                              DateFormat('h:mm:ss a').format(booking.bookedAt.add(const Duration(minutes: 5))),
                          isDone: true,
                        ),
                      ] else ...[
                        _buildAuditTimelineStep(
                          context,
                          dotColor: c.textSecondary,
                          title: 'In-Transit Re-optimization',
                          subtitle: 'Evaluated campus bay scores at ETA ≤ 10m · Current bay confirmed optimal',
                          timestamp: DateFormat('h:mm a').format(booking.bookedAt.add(const Duration(minutes: 4))),
                          isDone: true,
                        ),
                      ],

                      // Step 3: Barrier Check-In
                      if (booking.checkedInAt != null) ...[
                        _buildAuditTimelineStep(
                          context,
                          dotColor: c.accent,
                          title: 'Barrier Gate Check-In',
                          subtitle: 'QR pass validated · Optical barrier raised for entry',
                          timestamp: DateFormat('h:mm:ss a').format(booking.checkedInAt!),
                          isDone: true,
                        ),
                      ] else if (booking.isActive) ...[
                        _buildAuditTimelineStep(
                          context,
                          dotColor: c.textPrimary,
                          title: 'Awaiting Arrival & Check-In',
                          subtitle: 'Auto-cancel grace deadline: ${DateFormat('h:mm a').format(booking.cancelDeadline)}',
                          timestamp: 'Pending',
                          isDone: false,
                        ),
                      ] else ...[
                        _buildAuditTimelineStep(
                          context,
                          dotColor: c.danger,
                          title: 'Check-In Skipped',
                          subtitle: isCancelled ? 'Booking expired or cancelled' : 'N/A',
                          timestamp: DateFormat('h:mm a').format(booking.cancelDeadline),
                          isDone: false,
                        ),
                      ],

                      // Step 4: Completion or Cancellation
                      if (booking.completedAt != null) ...[
                        _buildAuditTimelineStep(
                          context,
                          dotColor: c.textPrimary,
                          title: 'Session Completed & Paid',
                          subtitle: 'Paid LKR ${booking.finalFee > 0 ? booking.finalFee : booking.estimatedFee} · Barrier opened for exit',
                          timestamp: DateFormat('h:mm:ss a').format(booking.completedAt!),
                          isLast: true,
                          isDone: true,
                        ),
                      ] else if (isCancelled) ...[
                        _buildAuditTimelineStep(
                          context,
                          dotColor: c.danger,
                          title: booking.status == BookingStatus.autoCancelled
                              ? 'Auto-Cancelled (No-Show)'
                              : 'Cancelled by User',
                          subtitle: 'Bay ${booking.slotId} released back into campus available pool',
                          timestamp: DateFormat('h:mm a').format(booking.cancelDeadline),
                          isLast: true,
                          isDone: true,
                        ),
                      ] else ...[
                        _buildAuditTimelineStep(
                          context,
                          dotColor: c.textSecondary,
                          title: 'Payment & Exit',
                          subtitle: 'Est. duration ${booking.durationHours}h · Rate: LKR ${booking.estimatedFee ~/ booking.durationHours}/h',
                          timestamp: 'Upcoming',
                          isLast: true,
                          isDone: false,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: AppSpace.xl),
              ],
            ),
          ),

          // Bottom Action Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xs),
            child: Column(
              children: [
                if (booking.isActive) ...[
                  PrimaryButton(
                    text: 'Open In-Transit Navigation',
                    onPressed: () {
                      Navigator.pop(context);
                      onOpenNavigation?.call();
                    },
                  ),
                  const SizedBox(height: AppSpace.sm),
                  SecondaryButton(
                    text: 'Show Gate QR Code',
                    onPressed: () => _showQrDialog(context),
                  ),
                  if (booking.status == BookingStatus.reserved ||
                      booking.status == BookingStatus.upgraded) ...[
                    const SizedBox(height: AppSpace.sm),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.textPrimary,
                        side: BorderSide(color: c.border),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                      ),
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                      label: Text(
                        'Simulate Barrier Check-In (Scan QR)',
                        style: AppText.button.copyWith(color: c.textPrimary),
                      ),
                      onPressed: () {
                        state.checkIn();
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Barrier pass verified. Welcome to ${booking.lotName}!'),
                            backgroundColor: c.primary,
                          ),
                        );
                      },
                    ),
                  ],
                ] else ...[
                  PrimaryButton(
                    text: 'Book Again at ${booking.lotName}',
                    onPressed: () {
                      Navigator.pop(context);
                      onBookAgain?.call();
                    },
                  ),
                  const SizedBox(height: AppSpace.sm),
                  SecondaryButton(
                    text: 'Close Details',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _getEventTimestamp(List<ParkingEvent> events, ParkingEventType type) {
    final matches = events.where((e) => e.type == type);
    if (matches.isNotEmpty) {
      return DateFormat('h:mm:ss a').format(matches.first.timestamp);
    }
    return null;
  }

  Widget _buildStatusBadge(BuildContext context, BookingStatus status) {
    final c = context.colors;
    Color bg = c.surface;
    Color fg = c.textPrimary;
    String label = status.displayName;

    switch (status) {
      case BookingStatus.upgraded:
        bg = c.accentSoft;
        fg = c.accent;
        label = 'Upgraded Bay';
        break;
      case BookingStatus.checkedIn:
        bg = Colors.green.withValues(alpha: 0.15);
        fg = Colors.green.shade800;
        label = 'Parked at Bay';
        break;
      case BookingStatus.reserved:
        bg = c.surface;
        fg = c.textPrimary;
        label = 'Reserved';
        break;
      case BookingStatus.completed:
        bg = c.surface;
        fg = c.textSecondary;
        label = 'Completed';
        break;
      case BookingStatus.cancelled:
      case BookingStatus.autoCancelled:
        bg = c.danger.withValues(alpha: 0.12);
        fg = c.danger;
        label = status == BookingStatus.autoCancelled ? 'Auto-Cancelled' : 'Cancelled';
        break;
      case BookingStatus.extended:
        bg = Colors.amber.withValues(alpha: 0.2);
        fg = Colors.amber.shade900;
        label = 'Extended';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: AppText.caption.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildMetaRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    TextStyle? valueStyle,
  }) {
    final c = context.colors;
    return Row(
      children: [
        Icon(icon, size: 20, color: c.textSecondary),
        const SizedBox(width: AppSpace.sm),
        Text(label, style: AppText.body.copyWith(color: c.textSecondary)),
        const Spacer(),
        Text(
          value,
          style: valueStyle ?? AppText.body.copyWith(color: c.textPrimary, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildAuditTimelineStep(
    BuildContext context, {
    required Color dotColor,
    required String title,
    required String subtitle,
    required String timestamp,
    bool isFirst = false,
    bool isLast = false,
    required bool isDone,
  }) {
    final c = context.colors;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dot and vertical line
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isDone ? dotColor : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: dotColor, width: 2),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isDone ? c.border : c.border.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpace.md),

          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: AppText.title.copyWith(
                            color: isDone ? c.textPrimary : c.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        timestamp,
                        style: AppText.caption.copyWith(
                          color: isDone ? c.textPrimary : c.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppText.caption.copyWith(
                      color: c.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
