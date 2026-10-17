import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/campus_map_view.dart';
import '../../data/models/booking_model.dart';
import '../../data/services/parking_state_manager.dart';

class NavigationScreen extends StatefulWidget {
  final Booking booking;
  final VoidCallback onCancelBooking;
  final VoidCallback onShowQr;
  final VoidCallback onTriggerUpgradeOffer;
  final VoidCallback onTriggerLateArrival;

  const NavigationScreen({
    super.key,
    required this.booking,
    required this.onCancelBooking,
    required this.onShowQr,
    required this.onTriggerUpgradeOffer,
    required this.onTriggerLateArrival,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.watch<ParkingStateManager>();
    final active = state.currentActiveBooking ?? widget.booking;

    final arriveTimeFormatted = DateFormat('h:mm a').format(active.arrivalTime);
    final deadlineFormatted = DateFormat('h:mm a').format(active.cancelDeadline);

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          // 1. Campus Map Canvas with Route Line
          Positioned.fill(
            child: CampusMapView(
              lots: state.lots,
              showNavigationRoute: true,
              destinationSlotId: active.slotId,
            ),
          ),

          // 2. Top Turn-by-Turn Guidance Banner
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg,
                vertical: AppSpace.sm,
              ),
              child: Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: c.primary,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.turn_right_rounded,
                      color: c.onPrimary,
                      size: 36,
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '350 m',
                            style: AppText.h2.copyWith(
                              color: c.onPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Turn right onto New Kandy Rd',
                            style: AppText.body.copyWith(
                              color: c.onPrimary.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Bottom ETA & Active Booking Sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.xs,
                AppSpace.lg,
                AppSpace.xl,
              ),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: AppRadius.sheetR,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag Handle
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpace.md),
                    decoration: BoxDecoration(
                      color: c.slotTaken,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // ETA Display Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${state.etaMinutes} min',
                            style: AppText.display.copyWith(color: c.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Arrive $arriveTimeFormatted · ${state.distanceKm} km',
                            style: AppText.body.copyWith(color: c.textSecondary),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Your slot',
                            style: AppText.caption.copyWith(color: c.textSecondary),
                          ),
                          Text(
                            active.slotId,
                            style: AppText.slotId.copyWith(
                              color: c.accent,
                              fontSize: 26,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpace.md),

                  // Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: 0.65,
                      minHeight: 5,
                      backgroundColor: c.divider,
                      valueColor: AlwaysStoppedAnimation<Color>(c.primary),
                    ),
                  ),

                  const SizedBox(height: AppSpace.xs),

                  // Lot Name & Deadline
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        active.lotName,
                        style: AppText.caption.copyWith(color: c.textSecondary),
                      ),
                      Text(
                        'Held until $deadlineFormatted',
                        style: AppText.caption.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpace.lg),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          text: 'Show QR',
                          icon: Icons.qr_code_2_rounded,
                          onPressed: widget.onShowQr,
                        ),
                      ),
                      const SizedBox(width: AppSpace.md),
                      TertiaryButton(
                        text: 'Cancel',
                        onPressed: widget.onCancelBooking,
                      ),
                    ],
                  ),

                  // In-transit dynamic triggers (for testing / real ETA trigger)
                  const SizedBox(height: AppSpace.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        icon: Icon(Icons.bolt_rounded, size: 16, color: c.accent),
                        label: Text(
                          'Test 10m Upgrade',
                          style: AppText.caption.copyWith(color: c.accent),
                        ),
                        onPressed: widget.onTriggerUpgradeOffer,
                      ),
                      TextButton.icon(
                        icon: Icon(Icons.access_time_rounded, size: 16, color: c.warning),
                        label: Text(
                          'Test Late (+10m)',
                          style: AppText.caption.copyWith(color: c.warning),
                        ),
                        onPressed: widget.onTriggerLateArrival,
                      ),
                    ],
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
