
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../data/models/booking_model.dart';
import '../../data/services/barrier_api_service.dart';
import '../../data/services/indoor_route_service.dart';

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
  late final IndoorRouteService _routeService;

  bool _isPredicting = false;
  int? _predictedSector;
  String? _predictionError;

  /// Demonstration mapping matching the sample parking layout.
  int get _bookedSlotSector {
    final row = widget.booking.slotId.split('-').first.toUpperCase();

    switch (row) {
      case 'A':
        return 1;
      case 'B':
        return 3;
      case 'C':
        return 5;
      case 'D':
        return 7;
      default:
        return 1;
    }
  }

  @override
  void initState() {
    super.initState();

    _apiService = BarrierApiService(
      baseUrl: 'http://10.0.2.2:8000',
    );

    _routeService = IndoorRouteService();
  }

  @override
  void dispose() {
    _apiService.dispose();
    super.dispose();
  }

  /// Calls the FastAPI ML model with sample RSSI values.
  ///
  /// These are demonstration values, not live Bluetooth measurements.
  Future<void> _predictCarSector() async {
    if (_isPredicting) return;

    setState(() {
      _isPredicting = true;
      _predictionError = null;
    });

    try {
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
            'Unable to predict the sector. Check that the backend is running.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPredicting = false;
        });
      }
    }
  }

  /// Opens the walking route using the ML-predicted sector.
  void _showWalkingRoute() {
    final sector = _predictedSector;

    if (sector == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please tap Find car before viewing the route.'),
        ),
      );
      return;
    }

    try {
      final route = _routeService.calculateRoute(
        destinationSector: sector,
        slotId: widget.booking.slotId,
      );

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
        builder: (_) => _WalkingRouteSheet(
          sector: sector,
          slotId: widget.booking.slotId,
          route: route,
        ),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not calculate route: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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

              Center(
                child: SizedBox(
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
              ),

              const SizedBox(height: AppSpace.xl),

              Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpace.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                    Container(
                      width: 1,
                      height: 48,
                      color: c.border,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpace.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                    Container(
                      width: 1,
                      height: 48,
                      color: c.border,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpace.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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

              const SizedBox(height: AppSpace.md),

              Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                          ? 'Booked slot: ${widget.booking.slotId}'
                                          : 'Model prediction: Sector $_predictedSector',
                                      style: AppText.caption.copyWith(
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _isPredicting
                                      ? null
                                      : _predictCarSector,
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 44),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isPredicting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text(
                                          'Find car',
                                          textAlign: TextAlign.center,
                                        ),
                                ),
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
                              'Model prediction: Sector $_predictedSector\n'
                              'Booked slot destination: Sector $_bookedSlotSector',
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
                                icon: const Icon(Icons.directions_walk),
                                label: const Text('View walking route'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpace.xl),

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
  final IndoorRouteResult route;

  const _WalkingRouteSheet({
    required this.sector,
    required this.slotId,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return FractionallySizedBox(
      heightFactor: 0.94,
      child: SingleChildScrollView(
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
              style: AppText.h1.copyWith(
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Floor 1 · Sector $sector · Slot $slotId',
              style: AppText.title.copyWith(
                color: c.accent,
              ),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Icon(Icons.route, color: c.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Calculated route: '
                    '${route.totalDistanceMeters.toStringAsFixed(0)} m',
                    style: AppText.body.copyWith(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
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
                  routeNodeIds: route.nodeIds,
                ),
                child: const SizedBox.expand(),
              ),
            ),

            const SizedBox(height: 10),
            Text(
              'Illustrative sample parking layout',
              style: AppText.caption.copyWith(
                color: c.textSecondary,
              ),
            ),

            const SizedBox(height: 20),

            Text(
              'Calculated route steps',
              style: AppText.title.copyWith(
                color: c.textPrimary,
              ),
            ),

            const SizedBox(height: 12),

            for (var i = 0; i < route.instructions.length; i++)
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
                          route.instructions[i],
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
                'The sector prediction uses sample RSSI inputs. '
                'Dijkstra’s algorithm calculates a route through '
                'a predefined sample layout. Distances and routes '
                'are illustrative, not measured from a real car park.',
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
    final center = Offset(
      size.width / 2,
      size.height / 2,
    );

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
      Rect.fromCircle(
        center: center,
        radius: radius,
      ),
      -pi / 2,
      2 * pi * progress,
      false,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _CircularTimerPainter oldDelegate,
  ) {
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
      Rect.fromLTWH(
        0,
        size.height * 0.5,
        size.width,
        24,
      ),
      roadPaint,
    );

    final pathPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final start = Offset(
      size.width * 0.22,
      size.height * 0.62,
    );

    final corner = Offset(
      size.width * 0.70,
      size.height * 0.62,
    );

    final end = Offset(
      size.width * 0.70,
      size.height * 0.28,
    );

    canvas.drawLine(start, corner, pathPaint);
    canvas.drawLine(corner, end, pathPaint);

    canvas.drawCircle(
      start,
      5,
      Paint()..color = Colors.black,
    );

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
  bool shouldRepaint(
    covariant _FindMyCarPainter oldDelegate,
  ) {
    return oldDelegate.colors != colors;
  }
}

class _ParkingRoutePainter extends CustomPainter {
  final AppColors colors;
  final List<String> routeNodeIds;

  _ParkingRoutePainter({
    required this.colors,
    required this.routeNodeIds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final left = size.width * 0.16;
    final center = size.width * 0.50;
    final right = size.width * 0.84;
    final top = size.height * 0.24;
    final middle = size.height * 0.50;
    final bottom = size.height * 0.76;

    final positions = <String, Offset>{
      'entrance': Offset(left, bottom),
      'junction_a': Offset(left, middle),
      'aisle_west': Offset(left, top),
      'aisle_center': Offset(center, middle),
      'junction_b': Offset(center, top),
      'aisle_east': Offset(right, middle),
      'junction_c': Offset(right, top),
      'sector_1': Offset(left, top * 0.55),
      'sector_2': Offset(size.width * 0.30, top * 0.55),
      'sector_3': Offset(center, top * 0.55),
      'sector_4': Offset(size.width * 0.66, top * 0.55),
      'sector_5': Offset(right, middle),
      'sector_6': Offset(size.width * 0.70, top * 0.55),
      'sector_7': Offset(right, top * 0.55),
    };

    final roadPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;

    final networkEdges = <List<String>>[
      ['entrance', 'junction_a'],
      ['junction_a', 'aisle_west'],
      ['junction_a', 'aisle_center'],
      ['aisle_center', 'junction_b'],
      ['junction_b', 'aisle_west'],
      ['junction_b', 'aisle_east'],
      ['junction_b', 'sector_3'],
      ['junction_b', 'sector_4'],
      ['aisle_east', 'junction_c'],
      ['aisle_east', 'sector_5'],
      ['junction_c', 'sector_6'],
      ['junction_c', 'sector_7'],
      ['aisle_west', 'sector_1'],
      ['aisle_west', 'sector_2'],
    ];

    for (final edge in networkEdges) {
      final start = positions[edge[0]];
      final end = positions[edge[1]];

      if (start != null && end != null) {
        canvas.drawLine(start, end, roadPaint);
      }
    }

    final routePaint = Paint()
      ..color = colors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    var started = false;

    for (final nodeId in routeNodeIds) {
      final point = positions[nodeId];

      if (point == null) continue;

      if (!started) {
        path.moveTo(point.dx, point.dy);
        started = true;
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    if (started) {
      canvas.drawPath(path, routePaint);
    }

    _drawLabel(
      canvas,
      'ENTRANCE',
      positions['entrance']! + const Offset(0, 18),
      Colors.black,
    );

    for (var sector = 1; sector <= 7; sector++) {
      final point = positions['sector_$sector'];

      if (point == null) continue;

      final isDestination =
          routeNodeIds.contains('sector_$sector');

      canvas.drawCircle(
        point,
        5,
        Paint()
          ..color = isDestination ? colors.accent : Colors.black54,
      );

      _drawLabel(
        canvas,
        'S$sector',
        point + const Offset(0, -12),
        Colors.black,
      );
    }
  }

  void _drawLabel(
    Canvas canvas,
    String label,
    Offset center,
    Color color,
  ) {
    final painter = TextPainter(
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

    painter.paint(
      canvas,
      Offset(
        center.dx - painter.width / 2,
        center.dy - painter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(
    covariant _ParkingRoutePainter oldDelegate,
  ) {
    return oldDelegate.colors != colors ||
        oldDelegate.routeNodeIds.join('|') !=
            routeNodeIds.join('|');
  }
}
