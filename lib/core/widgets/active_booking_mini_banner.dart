// active_booking_mini_banner.dart
// Persistent mini-bar banner displaying active running booking/trip telemetry on main screen

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../utils/google_maps_launcher.dart';
import '../../data/models/booking_model.dart';
import '../../data/models/parking_lot_model.dart';

class ActiveBookingMiniBanner extends StatelessWidget {
  final Booking booking;
  final ParkingLot? lot;
  final double? originLat;
  final double? originLng;
  final VoidCallback onTap;

  const ActiveBookingMiniBanner({
    super.key,
    required this.booking,
    this.lot,
    this.originLat,
    this.originLng,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final isInTransit = now.isBefore(booking.arrivalTime);
    final arriveFormatted = DateFormat('h:mm a').format(booking.arrivalTime);

    // Calculate remaining text
    String statusSubtitle;
    Color indicatorColor;

    if (isInTransit) {
      final diff = booking.arrivalTime.difference(now);
      final minutesLeft = diff.inMinutes;
      statusSubtitle = minutesLeft > 0
          ? 'In Transit · Arriving in $minutesLeft mins ($arriveFormatted)'
          : 'In Transit · Arriving now ($arriveFormatted)';
      indicatorColor = const Color(0xFF10B981); // Green
    } else if (!booking.isHoldExpired) {
      final rem = booking.remainingHoldDuration;
      final m = rem.inMinutes;
      final s = rem.inSeconds % 60;
      final timeStr = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      statusSubtitle = 'Hold Active: $timeStr left to reach barrier';
      indicatorColor = m < 3 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
    } else {
      statusSubtitle = 'Hold Expired · Auto-cancelled';
      indicatorColor = const Color(0xFFEF4444);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.accent.withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // Pulsing Status Dot
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: indicatorColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: indicatorColor.withValues(alpha: 0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      )
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Booking Telemetry
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              booking.lotName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body.copyWith(
                                color: c.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: c.accent,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'Bay ${booking.slotId}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        statusSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          color: c.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Quick Google Maps Launcher
                if (lot != null)
                  IconButton(
                    icon: const Icon(Icons.map_rounded, size: 18),
                    color: c.textSecondary,
                    tooltip: 'Launch Google Maps',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () {
                      GoogleMapsLauncher.launchNavigation(
                        destinationLat: lot!.latitude,
                        destinationLng: lot!.longitude,
                        originLat: originLat,
                        originLng: originLng,
                        destinationLabel: '${lot!.name} - Slot ${booking.slotId}',
                      );
                    },
                  ),

                // Resume In-App Nav Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'Nav',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
