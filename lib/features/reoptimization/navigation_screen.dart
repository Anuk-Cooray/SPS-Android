import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/campus_map_view.dart';
import '../../core/widgets/hold_countdown_timer_widget.dart';
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
  bool _modalShownForCurrentOffer = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<ParkingStateManager>();
    if (state.upgradeOfferAvailable && !_modalShownForCurrentOffer) {
      _modalShownForCurrentOffer = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onTriggerUpgradeOffer();
        }
      });
    } else if (!state.upgradeOfferAvailable) {
      _modalShownForCurrentOffer = false;
    }
  }

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
          // 1. Campus Map Canvas with Dynamic Route & Moving Vehicle Marker
          Positioned.fill(
            child: CampusMapView(
              lots: state.lots,
              showNavigationRoute: true,
              destinationSlotId: active.slotId,
              routeProgress: state.routeProgress,
            ),
          ),

          // 2. Top Turn-by-Turn Dynamic Guidance Banner with Return Button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg,
                vertical: AppSpace.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    margin: const EdgeInsets.only(right: AppSpace.sm),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(AppRadius.cardSm),
                      border: Border.all(color: c.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: c.textPrimary, size: 22),
                      tooltip: 'Return to Main Screen',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(AppSpace.md),
                      decoration: BoxDecoration(
                        color: state.hasArrivedAtDestination ? c.accent : c.primary,
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
                            state.currentManeuverIcon,
                            color: c.onPrimary,
                            size: 30,
                          ),
                          const SizedBox(width: AppSpace.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  state.currentManeuverDistance,
                                  style: AppText.h2.copyWith(
                                    color: c.onPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  state.currentManeuverText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.body.copyWith(
                                    color: c.onPrimary.withValues(alpha: 0.88),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Bottom ETA & Active Booking Sheet with Simulation Controller
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

                  const SizedBox(height: AppSpace.sm),

                  // Route Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: state.routeProgress,
                      minHeight: 5,
                      backgroundColor: c.divider,
                      valueColor: AlwaysStoppedAnimation<Color>(c.accent),
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

                  const SizedBox(height: AppSpace.sm),
                  HoldCountdownTimerWidget(booking: active, compact: true),
                  const SizedBox(height: AppSpace.md),

                  // In-Transit Simulation Controller Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 6),
                    decoration: BoxDecoration(
                      color: c.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.cardSm),
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
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: state.hasArrivedAtDestination
                                        ? c.accent
                                        : (state.isSimulatingMovement ? c.accent : c.textTertiary),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  state.hasArrivedAtDestination
                                      ? 'ARRIVED AT DESTINATION'
                                      : (state.isSimulatingMovement
                                          ? 'SIMULATING ROUTE'
                                          : 'SIMULATION PAUSED'),
                                  style: AppText.overline.copyWith(
                                    color: state.isSimulatingMovement ? c.accent : c.textSecondary,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  iconSize: 18,
                                  tooltip: 'Reset to Start',
                                  icon: Icon(Icons.replay_rounded, color: c.textSecondary),
                                  onPressed: () => state.resetMovementSimulation(),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  iconSize: 18,
                                  tooltip: 'Step Forward (+10%)',
                                  icon: Icon(Icons.skip_next_rounded, color: c.textPrimary),
                                  onPressed: () => state.tickSimulation(step: 0.10),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  iconSize: 22,
                                  tooltip: state.isSimulatingMovement ? 'Pause' : 'Start Auto Driving',
                                  icon: Icon(
                                    state.isSimulatingMovement
                                        ? Icons.pause_circle_filled_rounded
                                        : Icons.play_circle_fill_rounded,
                                    color: c.accent,
                                  ),
                                  onPressed: () {
                                    if (state.isSimulatingMovement) {
                                      state.pauseMovementSimulation();
                                    } else {
                                      state.startMovementSimulation();
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            activeTrackColor: c.accent,
                            inactiveTrackColor: c.border,
                            thumbColor: c.accent,
                          ),
                          child: Slider(
                            value: state.routeProgress,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (val) => state.setRouteProgress(val),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpace.md),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: PrimaryButton(
                          text: state.hasArrivedAtDestination ? 'Scan Gate QR to Park' : 'Show Barrier QR',
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

                  // In-transit dynamic triggers (for presentation testing)
                  const SizedBox(height: AppSpace.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        icon: Icon(Icons.bolt_rounded, size: 15, color: c.accent),
                        label: Text(
                          'Test 10m Upgrade',
                          style: AppText.caption.copyWith(color: c.accent, fontWeight: FontWeight.w600),
                        ),
                        onPressed: widget.onTriggerUpgradeOffer,
                      ),
                      const SizedBox(width: AppSpace.sm),
                      TextButton.icon(
                        icon: Icon(Icons.access_time_rounded, size: 15, color: c.warning),
                        label: Text(
                          'Test Late (+10m)',
                          style: AppText.caption.copyWith(color: c.warning, fontWeight: FontWeight.w600),
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
