import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/hold_countdown_timer_widget.dart';
import '../../data/models/booking_model.dart';
import '../../data/services/parking_state_manager.dart';
import 'booking_detail_modal.dart';

class BookingsListScreen extends StatefulWidget {
  final ValueChanged<Booking>? onOpenActiveBooking;

  const BookingsListScreen({super.key, this.onOpenActiveBooking});

  @override
  State<BookingsListScreen> createState() => _BookingsListScreenState();
}

class _BookingsListScreenState extends State<BookingsListScreen> {
  int _selectedTabIndex = 0; // 0: Active, 1: Upcoming, 2: History

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.watch<ParkingStateManager>();

    final activeList = state.activeBookings;
    final upcomingList = state.upcomingBookings;
    final historyList = state.historyBookings;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpace.lg),

              // Title
              Text(
                'Bookings',
                style: AppText.h1.copyWith(color: c.textPrimary),
              ),

              const SizedBox(height: AppSpace.md),

              // Segmented Tab bar
              Container(
                height: 48,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    _buildTab(0, 'Active', activeList.length),
                    _buildTab(1, 'Upcoming', upcomingList.length),
                    _buildTab(2, 'History', historyList.length),
                  ],
                ),
              ),

              const SizedBox(height: AppSpace.lg),

              // List of bookings based on selected tab
              Expanded(
                child: ListView(
                  children: [
                    if (_selectedTabIndex == 0) ...[
                      if (activeList.isEmpty)
                        _buildEmptyState(
                          'No active booking right now',
                          'Select a lot on the campus map to reserve a parking bay and start live guidance.',
                        )
                      else
                        ...activeList.map((booking) => _ActiveBookingCard(
                              booking: booking,
                              onTap: () => BookingDetailModal.show(
                                context: context,
                                booking: booking,
                                onOpenNavigation: () => widget.onOpenActiveBooking?.call(booking),
                              ),
                            )),
                    ] else if (_selectedTabIndex == 1) ...[
                      if (upcomingList.isEmpty)
                        _buildEmptyState(
                          'No upcoming bookings',
                          'Advance reservations will appear here with arrival countdowns.',
                        )
                      else
                        ...upcomingList.map((booking) => _SimpleBookingCard(
                              booking: booking,
                              onTap: () => BookingDetailModal.show(
                                context: context,
                                booking: booking,
                              ),
                            )),
                    ] else ...[
                      if (historyList.isEmpty)
                        _buildEmptyState(
                          'No previous bookings found',
                          'Completed and cancelled parking sessions will be stored in your history.',
                        )
                      else
                        ...historyList.map((booking) => _SimpleBookingCard(
                              booking: booking,
                              onTap: () => BookingDetailModal.show(
                                context: context,
                                booking: booking,
                              ),
                            )),
                    ],

                    // Earlier section (history preview on Active tab if history exists)
                    if (_selectedTabIndex == 0 && historyList.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.lg),
                      Text(
                        'EARLIER',
                        style: AppText.overline.copyWith(color: c.textSecondary),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      ...historyList.take(2).map((b) => _SimpleBookingCard(
                            booking: b,
                            onTap: () => BookingDetailModal.show(
                              context: context,
                              booking: b,
                            ),
                          )),
                    ]
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(int index, String title, int count) {
    final isSelected = _selectedTabIndex == index;
    final c = context.colors;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? c.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: AppText.label.copyWith(
              color: isSelected ? c.textPrimary : c.textSecondary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: AppSpace.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.local_parking_rounded, color: c.textSecondary, size: 28),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            title,
            style: AppText.title.copyWith(color: c.textPrimary, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ActiveBookingCard extends StatelessWidget {
  final Booking booking;
  final VoidCallback? onTap;

  const _ActiveBookingCard({required this.booking, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final timeStr = DateFormat('h:mm a').format(booking.arrivalTime);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpace.md),
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: glassDecoration(c),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
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
                      'Today · $timeStr · ${booking.durationHours} h',
                      style: AppText.caption.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
                Text(
                  booking.slotId,
                  style: AppText.slotId.copyWith(color: c.accent),
                ),
              ],
            ),

            if (booking.status == BookingStatus.reserved ||
                booking.status == BookingStatus.upgraded) ...[
              const SizedBox(height: AppSpace.md),
              HoldCountdownTimerWidget(booking: booking, compact: true),
            ],

            const SizedBox(height: AppSpace.md),
            const Divider(),
            const SizedBox(height: AppSpace.md),

            // Dynamic Timeline Items
            _TimelineItem(
              dotColor: c.textPrimary,
              title: 'Booked ${booking.originalSlotId ?? booking.slotId}',
              time: DateFormat('h:mm a').format(booking.bookedAt),
            ),
            const SizedBox(height: AppSpace.sm),

            if (booking.status == BookingStatus.upgraded) ...[
              _TimelineItem(
                dotColor: c.accent,
                title: 'Upgraded to ${booking.slotId} · saved ${booking.distanceSavedMeters} m',
                time: DateFormat('h:mm a').format(booking.bookedAt.add(const Duration(minutes: 5))),
              ),
              const SizedBox(height: AppSpace.sm),
            ],

            // Filled dot once done, hollow while still pending
            _TimelineItem(
              dotColor: booking.checkedInAt != null ? c.textPrimary : Colors.transparent,
              borderColor: booking.checkedInAt != null ? null : c.textSecondary,
              title: booking.checkedInAt != null ? 'Checked in at barrier' : 'Check in',
              time: booking.checkedInAt != null
                  ? DateFormat('h:mm a').format(booking.checkedInAt!)
                  : 'by ${DateFormat('h:mm a').format(booking.cancelDeadline)}',
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final Color dotColor;
  final Color? borderColor;
  final String title;
  final String time;
  final bool isLast;

  const _TimelineItem({
    required this.dotColor,
    this.borderColor,
    required this.title,
    required this.time,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
            border: borderColor != null
                ? Border.all(color: borderColor!, width: 1.5)
                : null,
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(
            title,
            style: AppText.body.copyWith(
              color: c.textPrimary,
              fontSize: 13,
            ),
          ),
        ),
        Text(
          time,
          style: AppText.caption.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }
}

class _SimpleBookingCard extends StatelessWidget {
  final Booking booking;
  final VoidCallback? onTap;

  const _SimpleBookingCard({required this.booking, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isReleased = booking.status == BookingStatus.autoCancelled || booking.isLapsed;
    final isCancelled = booking.status == BookingStatus.cancelled || isReleased;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpace.sm),
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: glassDecoration(c),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${booking.lotName} · Bay ${booking.slotId}',
                    style: AppText.title.copyWith(color: c.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isReleased
                        ? 'Released · hold expired without check-in'
                        : isCancelled
                            ? 'Cancelled by you · ${DateFormat('d MMM, h:mm a').format(booking.bookedAt)}'
                            : 'Completed session · ${booking.durationHours} h · ${DateFormat('d MMM, h:mm a').format(booking.bookedAt)}',
                    style: AppText.caption.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            if (isCancelled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isReleased ? 'Released' : 'Cancelled',
                  style: AppText.caption.copyWith(
                    color: c.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              Text(
                'LKR ${booking.finalFee > 0 ? booking.finalFee : booking.estimatedFee}',
                style: AppText.title.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
