import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../data/models/booking_model.dart';

class CheckInScreen extends StatelessWidget {
  final Booking booking;
  final VoidCallback onParkedConfirmed;

  const CheckInScreen({
    super.key,
    required this.booking,
    required this.onParkedConfirmed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final deadlineFormatted = DateFormat('h:mm a').format(booking.cancelDeadline);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Column(
            children: [
              const SizedBox(height: AppSpace.sm),

              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    child: IconButton(
                      tooltip: 'Back',
                      icon: Icon(Icons.chevron_left_rounded, color: c.textPrimary, size: 24),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Text(
                    'Check in',
                    style: AppText.h2.copyWith(color: c.textPrimary),
                  ),
                ],
              ),

              const SizedBox(height: AppSpace.xl),

              // Lot Name & Slot ID
              Text(
                booking.lotName,
                style: AppText.body.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppSpace.xxs),
              Text(
                booking.slotId,
                style: AppText.display.copyWith(
                  color: c.accent,
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpace.xxs),
              Text(
                'Scan at the slot barrier to unlock',
                style: AppText.body.copyWith(color: c.textSecondary),
              ),

              const SizedBox(height: AppSpace.xl),

              // QR Code Box
              Container(
                padding: const EdgeInsets.all(AppSpace.lg),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: c.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: QrImageView(
                  data: booking.qrToken,
                  version: QrVersions.auto,
                  size: 220.0,
                  eyeStyle: QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: c.textPrimary,
                  ),
                  dataModuleStyle: QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: c.textPrimary,
                  ),
                ),
              ),

              const SizedBox(height: AppSpace.md),

              Text(
                'Valid until $deadlineFormatted · Code refreshes every 30 s',
                style: AppText.caption.copyWith(color: c.textSecondary),
              ),

              const Spacer(),

              // Barrier help box
              Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: c.textPrimary, size: 20),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Text(
                        "Barrier won't open? Show this code to the attendant.",
                        style: AppText.body.copyWith(
                          color: c.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpace.md),

              // CTA
              PrimaryButton(
                text: "I'm parked",
                onPressed: onParkedConfirmed,
              ),

              const SizedBox(height: AppSpace.md),
            ],
          ),
        ),
      ),
    );
  }
}
