// booking_confirmed_dialog.dart
// Post-booking confirmation screen presenting choice between Google Maps navigation, in-app smart navigation, or returning to home

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/google_maps_launcher.dart';
import '../../../data/models/booking_model.dart';
import '../../../data/models/parking_lot_model.dart';

class BookingConfirmedDialog extends StatelessWidget {
  final Booking booking;
  final ParkingLot lot;
  final double? originLat;
  final double? originLng;
  final VoidCallback onStartInAppNav;
  final VoidCallback onReturnHome;

  const BookingConfirmedDialog({
    super.key,
    required this.booking,
    required this.lot,
    this.originLat,
    this.originLng,
    required this.onStartInAppNav,
    required this.onReturnHome,
  });

  static Future<void> show(
    BuildContext context, {
    required Booking booking,
    required ParkingLot lot,
    double? originLat,
    double? originLng,
    required VoidCallback onStartInAppNav,
    required VoidCallback onReturnHome,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BookingConfirmedDialog(
        booking: booking,
        lot: lot,
        originLat: originLat,
        originLng: originLng,
        onStartInAppNav: () {
          Navigator.of(ctx).pop();
          onStartInAppNav();
        },
        onReturnHome: () {
          Navigator.of(ctx).pop();
          onReturnHome();
        },
      ),
    );
  }

  void _launchGoogleMaps(BuildContext context) async {
    final success = await GoogleMapsLauncher.launchNavigation(
      destinationLat: lot.latitude,
      destinationLng: lot.longitude,
      originLat: originLat,
      originLng: originLng,
      destinationLabel: '${lot.name} - Slot ${booking.slotId}',
    );

    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opening Google Maps web directions...'),
          backgroundColor: Colors.black87,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final arriveFormatted = DateFormat('h:mm a').format(booking.arrivalTime);
    final holdExpiryFormatted = DateFormat('h:mm a').format(booking.effectiveHoldDeadline);

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xl),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, -8),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Sheet Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: AppSpace.md),
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Success Animated Icon Check
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF10B981),
              size: 38,
            ),
          ),

          const SizedBox(height: AppSpace.sm),

          Text(
            'Reservation Confirmed!',
            style: AppText.h2.copyWith(
              color: c.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Ref: ${booking.id} · Slot locked in cloud',
            style: AppText.caption.copyWith(color: c.textSecondary),
          ),

          const SizedBox(height: AppSpace.md),

          // Reservation Summary Card
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Parking Facility',
                      style: AppText.body.copyWith(color: c.textSecondary, fontSize: 13),
                    ),
                    Text(
                      booking.lotName,
                      style: AppText.body.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Allocated Slot',
                      style: AppText.body.copyWith(color: c.textSecondary, fontSize: 13),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        booking.slotId,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Scheduled Arrival',
                      style: AppText.body.copyWith(color: c.textSecondary, fontSize: 13),
                    ),
                    Text(
                      arriveFormatted,
                      style: AppText.body.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Guaranteed Hold Window',
                          style: AppText.caption.copyWith(
                            color: c.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '15m window starts upon arrival',
                          style: AppText.caption.copyWith(
                            color: const Color(0xFF10B981),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '$arriveFormatted – $holdExpiryFormatted',
                      style: AppText.caption.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpace.md),

          // Navigation Section Header
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'CHOOSE NAVIGATION MODE',
              style: AppText.caption.copyWith(
                color: c.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),

          const SizedBox(height: AppSpace.xs),

          // Action 1: In-App Smart Navigation
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onStartInAppNav,
              style: ElevatedButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: const Text(
                'Start In-App Smart Navigation',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ),

          const SizedBox(height: AppSpace.xs),

          // Action 2: Launch Google Maps App
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => _launchGoogleMaps(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.textPrimary,
                side: BorderSide(color: c.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.map_rounded, size: 18),
              label: const Text(
                'Open in Google Maps App',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ),

          const SizedBox(height: AppSpace.sm),

          // Action 3: Return to Main Screen (Booking keeps running in background)
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onReturnHome,
              icon: Icon(Icons.arrow_back_rounded, size: 16, color: c.textSecondary),
              label: Text(
                'Return to Main Screen (Trip Keeps Running)',
                style: AppText.caption.copyWith(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
