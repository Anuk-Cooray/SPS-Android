
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../data/models/booking_model.dart';
import '../../data/services/barrier_api_service.dart';

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
  late final BarrierApiService _apiService;

  bool _isPredicting = false;
  int? _predictedSector;
  String? _predictionError;

  @override
  void initState() {
    super.initState();
    _apiService = BarrierApiService(
      baseUrl: 'http://10.0.2.2:8000',
    );
  }

  @override
  void dispose() {
    _apiService.dispose();
    super.dispose();
  }

  Future<void> _predictCarSector() async {
    if (_isPredicting) return;

    setState(() {
      _isPredicting = true;
      _predictionError = null;
    });

    try {
      // DEMONSTRATION INPUTS ONLY.
      // These are sample RSSI readings, not live BLE measurements.
      final sector = await _apiService.predictSector(
        b1: -55,
        b2: -62,
        b3: -70,
        b4: -48,
        b5: -66,
        b6: -73,
      );

      if (!mounted) return;

      if (sector < 1 || sector > 7) {
        setState(() {
          _predictionError =
              'The model returned an unexpected sector.';
        });
        return;
      }

      setState(() {
        _predictedSector = sector;
        _predictionError = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Predicted parking sector: $sector'),
        ),
      );
    } on BarrierApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _predictionError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _predictionError =
            'Unable to predict the sector. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPredicting = false;
        });
      }
    }
  }

  void _showWalkingRoute() {
    final sector = _predictedSector;
    if (sector == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (sheetContext) {
        return _WalkingRouteSheet(
          sector: sector,
          slotId: widget.booking.slotId,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
          ),
          child: Column(
            children: [
              const SizedBox(height: AppSpace.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Parked',
                    style: AppText.h1.copyWith(
                      color: c.textPrimary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
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
              SizedBox(
                width: 240,
                height: 240,
                child: CustomPaint(
                  painter: _CircularTimerPainter(
                    progress: 0.40,
                    trackColor: c.divider,
                    fillColor: c.primary,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Time parked',
                          style: AppText.caption.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '0:48',
                          style: AppText.display.copyWith(
                            color: c.textPrimary,
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'of ${widget.booking.durationHours} h booked',
                          style: AppText.caption.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(
                    AppRadius.card,
                  ),
                  border: Border.all(color: c.border),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.md,
                            vertical: AppSpace.md,
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Slot',
                                style: AppText.caption.copyWith(
                                  color: c.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.booking.slotId,
                                style: AppText.h2.copyWith(
                                  color: c.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      VerticalDivider(
                        color: c.border,
                        width: 1,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.md,
                            vertical: AppSpace.md,
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'In at',
                                style: AppText.caption.copyWith(
                                  color: c.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '10:21',
                                style: AppText.h2.copyWith(
                                  color: c.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      VerticalDivider(
                        color: c.border,
                        width: 1,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.md,
                            vertical: AppSpace.md,
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Fee so far',
                                style: AppText.caption.copyWith(
                                  color: c.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'LKR 100',
                                style: AppText.h2.copyWith(
                                  color: c.textPrimary,
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
              const SizedBox(height: AppSpace.md),
              Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(
                    AppRadius.card,
                  ),
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 100,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppRadius.card),
                        ),
                        child: CustomPaint(
                          painter: _FindMyCarPainter(colors: c),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpace.md),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Find my car',
                                      style: AppText.title.copyWith(
                                        color: c.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _predictedSector == null
                                          ? 'Parked in slot '
                                              '${widget.booking.slotId}'
                                          : 'Predicted sector: '
                                              '$_predictedSector',
                                      style: AppText.caption.copyWith(
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: _isPredicting
                                    ? null
                                    : _predictCarSector,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(100, 40),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isPredicting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child:
                                            CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Find car'),
                              ),
                            ],
                          ),
                          if (_predictionError != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _predictionError!,
                              style: AppText.caption.copyWith(
                                color: Colors.red,
                              ),
                            ),
                          ],
                          if (_predictedSector != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Floor 1 · Sector $_predictedSector',
                              style: AppText.caption.copyWith(
                                color: c.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _showWalkingRoute,
                                icon: const Icon(
                                  Icons.directions_walk,
                                ),
                                label: const Text(
                                  'View walking route',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              PrimaryButton(
                text: 'Exit parking',
                onPressed: widget.onExitParking,
              ),
              const SizedBox(height: AppSpace.md),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalkingRouteSheet extends StatelessWidget {
  final int sector;
  final String slotId;

  const _WalkingRouteSheet({
    required this.sector,
    required this.slotId,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // Demonstration route only. This is a sample layout,
    // not a measured route for a real parking facility.
    final instructions = <String>[
      'Start at the Main Entrance on Floor 1.',
      'Walk along the main parking aisle.',
      'Follow the aisle signs toward Sector $sector.',
      'Enter Sector $sector and look for slot $slotId.',
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: c.divider,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Walking route',
            style: AppText.h1.copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Floor 1 · Sector $sector · Slot $slotId',
            style: AppText.title.copyWith(color: c.accent),
          ),
          const SizedBox(height: 16),
          Container(
            height: 220,
            width: double.infinity,
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: CustomPaint(
              painter: _ParkingRoutePainter(
                colors: c,
                destinationSector: sector,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Sample parking layout for demonstration',
            style: AppText.caption.copyWith(
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Walking instructions',
            style: AppText.title.copyWith(
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < instructions.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        instructions[i],
                        style: AppText.body.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'GPS-free demo: the route uses a predefined sample '
              'layout. The sector prediction uses sample RSSI '
              'inputs, and the instructions are illustrative.',
              style: AppText.caption.copyWith(
                color: c.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close route'),
            ),
          ),
        ],
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

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;

    canvas.drawCircle(center, radius, trackPaint);

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularTimerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.fillColor != fillColor;
  }
}

class _FindMyCarPainter extends CustomPainter {
  final AppColors colors;

  _FindMyCarPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()..color = Colors.white;

    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.5, size.width, 24),
      roadPaint,
    );

    final pathPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final start = Offset(size.width * 0.22, size.height * 0.62);
    final corner = Offset(size.width * 0.70, size.height * 0.62);
    final end = Offset(size.width * 0.70, size.height * 0.28);

    canvas.drawLine(start, corner, pathPaint);
    canvas.drawLine(corner, end, pathPaint);
    canvas.drawCircle(start, 5, Paint()..color = Colors.black);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: end,
          width: 18,
          height: 18,
        ),
        const Radius.circular(5),
      ),
      Paint()..color = colors.accent,
    );
  }

  @override
  bool shouldRepaint(covariant _FindMyCarPainter oldDelegate) {
    return oldDelegate.colors != colors;
  }
}

class _ParkingRoutePainter extends CustomPainter {
  final AppColors colors;
  final int destinationSector;

  _ParkingRoutePainter({
    required this.colors,
    required this.destinationSector,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.square;

    final routePaint = Paint()
      ..color = colors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final left = size.width * 0.18;
    final middle = size.width * 0.52;
    final right = size.width * 0.82;
    final top = size.height * 0.27;
    final bottom = size.height * 0.73;

    // Main aisle and connecting aisles in the sample layout.
    canvas.drawLine(
      Offset(left, bottom),
      Offset(right, bottom),
      roadPaint,
    );
    canvas.drawLine(
      Offset(middle, top),
      Offset(middle, bottom),
      roadPaint,
    );
    canvas.drawLine(
      Offset(left, top),
      Offset(right, top),
      roadPaint,
    );

    final route = Path()
      ..moveTo(left, bottom)
      ..lineTo(middle, bottom)
      ..lineTo(middle, top)
      ..lineTo(right, top);

    canvas.drawPath(route, routePaint);

    _drawLabel(
      canvas,
      'ENTRANCE',
      Offset(left, bottom + 23),
      Colors.black,
    );

    _drawLabel(
      canvas,
      'MAIN AISLE',
      Offset(middle, bottom + 23),
      Colors.black,
    );

    _drawLabel(
      canvas,
      'SECTOR $destinationSector',
      Offset(right, top - 24),
      colors.accent,
    );

    canvas.drawCircle(
      Offset(left, bottom),
      8,
      Paint()..color = Colors.green,
    );

    canvas.drawCircle(
      Offset(right, top),
      9,
      Paint()..color = colors.accent,
    );

    // Simple arrow showing the route direction.
    final arrowX = middle;
    final arrowY = (top + bottom) / 2;
    final arrowPaint = Paint()
      ..color = colors.accent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(arrowX, arrowY + 9),
      Offset(arrowX, arrowY - 9),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(arrowX, arrowY - 9),
      Offset(arrowX - 6, arrowY - 2),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(arrowX, arrowY - 9),
      Offset(arrowX + 6, arrowY - 2),
      arrowPaint,
    );
  }

  void _drawLabel(
    Canvas canvas,
    String label,
    Offset center,
    Color color,
  ) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _ParkingRoutePainter oldDelegate) {
    return oldDelegate.destinationSector != destinationSector ||
        oldDelegate.colors != colors;
  }
}
