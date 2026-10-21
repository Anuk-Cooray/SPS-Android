import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/google_maps_launcher.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../data/models/booking_model.dart';
import '../../data/models/parking_lot_model.dart';
import '../../data/services/parking_state_manager.dart';

class ParkedScreen extends StatefulWidget {
  final Booking booking;
  final VoidCallback onExitParking;

  const ParkedScreen({
    super.key,
    required this.booking,
    required this.onExitParking,
  });

  @override
  State<ParkedScreen> createState() => _ParkedScreenState();
}

class _ParkedScreenState extends State<ParkedScreen> {
  late final DateTime _parkedAt;
  Timer? _ticker;

  Booking get booking => widget.booking;
  VoidCallback get onExitParking => widget.onExitParking;

  @override
  void initState() {
    super.initState();
    // The booking handed over may predate check-in; the screen opens at check-in
    _parkedAt = booking.checkedInAt?.toLocal() ?? DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  ParkingLot? _lotFor(BuildContext context) {
    for (final lot in context.read<ParkingStateManager>().lots) {
      if (lot.id == booking.lotId) return lot;
    }
    return null;
  }

  int? _walkingDistanceMeters(ParkingLot? lot) {
    if (lot == null) return null;
    for (final slot in lot.slots) {
      if (slot.id == booking.slotId) return slot.walkingDistanceMeters;
    }
    return null;
  }

  Future<void> _openLotInMaps(BuildContext context, ParkingLot? lot) async {
    if (lot == null) {
      showAppSnack(context, 'Location for ${booking.lotName} is not available.', tone: SnackTone.warning);
      return;
    }
    final opened = await GoogleMapsLauncher.openLocation(
      latitude: lot.latitude,
      longitude: lot.longitude,
      label: '${lot.name} · Bay ${booking.slotId}',
    );
    if (!opened && context.mounted) {
      showAppSnack(context, "Couldn't open Maps on this device.", tone: SnackTone.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final elapsed = DateTime.now().difference(_parkedAt);
    final safeElapsed = elapsed.isNegative ? Duration.zero : elapsed;
    final bookedMinutes = max(1, booking.durationHours * 60);
    final progress = (safeElapsed.inMinutes / bookedMinutes).clamp(0.0, 1.0);
    final elapsedLabel = '${safeElapsed.inHours}:${(safeElapsed.inMinutes % 60).toString().padLeft(2, '0')}';
    final feeSoFar = booking.parkingFeeFor(safeElapsed) + booking.extensionFee;
    final lot = _lotFor(context);
    final walkMeters = _walkingDistanceMeters(lot);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Column(
            children: [
              const SizedBox(height: AppSpace.sm),

              // Top Title & Session Active badge with Return Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
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
                          icon: Icon(Icons.arrow_back_rounded, color: c.textPrimary, size: 22),
                          tooltip: 'Return to Main Screen',
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: AppSpace.md),
                      Text(
                        'Parked',
                        style: AppText.h1.copyWith(color: c.textPrimary),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: c.surfaceMuted,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: c.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpace.xs),
                        Text(
                          'Session active',
                          style: AppText.caption.copyWith(
                            color: c.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpace.xl),

              // Circular Elapsed Timer Gauge
              SizedBox(
                width: 240,
                height: 240,
                child: CustomPaint(
                  painter: _CircularTimerPainter(
                    progress: progress,
                    trackColor: c.divider,
                    fillColor: c.primary,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Time parked',
                          style: AppText.caption.copyWith(color: c.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          elapsedLabel,
                          style: AppText.display.copyWith(
                            color: c.textPrimary,
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'of ${booking.durationHours} h booked',
                          style: AppText.caption.copyWith(color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppSpace.xl),

              // 3-Column Stats Card
              Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: c.border),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      // Slot
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.md,
                            vertical: AppSpace.md,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Slot', style: AppText.caption.copyWith(color: c.textSecondary)),
                              const SizedBox(height: 2),
                              Text(
                                booking.slotId,
                                style: AppText.h2.copyWith(color: c.accent),
                              ),
                            ],
                          ),
                        ),
                      ),
                      VerticalDivider(color: c.border, width: 1),

                      // In at
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.md,
                            vertical: AppSpace.md,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('In at', style: AppText.caption.copyWith(color: c.textSecondary)),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('HH:mm').format(_parkedAt),
                                style: AppText.h2.copyWith(color: c.textPrimary),
                              ),
                            ],
                          ),
                        ),
                      ),
                      VerticalDivider(color: c.border, width: 1),

                      // Fee so far
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.md,
                            vertical: AppSpace.md,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Fee so far', style: AppText.caption.copyWith(color: c.textSecondary)),
                              const SizedBox(height: 2),
                              Text(
                                'LKR $feeSoFar',
                                style: AppText.h2.copyWith(color: c.textPrimary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpace.md),

              // Find My Car Card
              Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  children: [
                    // Mini Schematic Map
                    Container(
                      height: 100,
                      decoration: BoxDecoration(
                        color: c.surfaceMuted,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _FindMyCarPainter(colors: c),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Info Row & Directions button
                    Padding(
                      padding: const EdgeInsets.all(AppSpace.md),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Find my car',
                                  style: AppText.title.copyWith(color: c.textPrimary),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  walkMeters != null
                                      ? '$walkMeters m from the entrance · ${max(1, (walkMeters / 80).ceil())} min walk'
                                      : 'Bay ${booking.slotId} · ${booking.lotName}',
                                  style: AppText.caption.copyWith(color: c.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          OutlinedButton(
                            onPressed: () {
                              _openLotInMaps(context, lot);
                            },
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(90, 40),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Directions'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Exit CTA
              PrimaryButton(
                text: 'Exit parking',
                onPressed: onExitParking,
              ),

              const SizedBox(height: AppSpace.md),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircularTimerPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color fillColor;

  _CircularTimerPainter({
    required this.progress,
    required this.trackColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;

    // Background track circle
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    canvas.drawCircle(center, radius, trackPaint);

    // Active progress arc
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularTimerPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _FindMyCarPainter extends CustomPainter {
  final AppColors colors;

  _FindMyCarPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final paintRoad = Paint()..color = colors.mapRoad;
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.5, size.width, 24), paintRoad);

    final dashPaint = Paint()
      ..color = colors.textPrimary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final start = Offset(size.width * 0.22, size.height * 0.62);
    final corner = Offset(size.width * 0.70, size.height * 0.62);
    final end = Offset(size.width * 0.70, size.height * 0.28);

    // Path
    canvas.drawLine(start, corner, dashPaint);
    canvas.drawLine(corner, end, dashPaint);

    // Current location dot
    canvas.drawCircle(start, 5, Paint()..color = colors.textPrimary);

    // Car pin
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: end, width: 18, height: 18),
        const Radius.circular(5),
      ),
      Paint()..color = colors.accent,
    );
  }

  @override
  bool shouldRepaint(covariant _FindMyCarPainter oldDelegate) => oldDelegate.colors != colors;
}
