import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../data/models/parking_lot_model.dart';

class CampusMapView extends StatelessWidget {
  final List<ParkingLot> lots;
  final String? selectedLotId;
  final ValueChanged<ParkingLot>? onLotSelected;
  final bool showNavigationRoute;
  final String? destinationSlotId;
  final double routeProgress;

  const CampusMapView({
    super.key,
    required this.lots,
    this.selectedLotId,
    this.onLotSelected,
    this.showNavigationRoute = false,
    this.destinationSlotId,
    this.routeProgress = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Stack(
      children: [
        // Vector map background canvas
        Positioned.fill(
          child: CustomPaint(
            painter: _MapCanvasPainter(
              colors: c,
              showRoute: showNavigationRoute,
              routeProgress: routeProgress,
            ),
          ),
        ),

        // Interactive Lot Markers
        if (!showNavigationRoute)
          ...lots.map((lot) {
            final isSelected = lot.id == selectedLotId;
            final isFull = lot.isFull;

            // Approximate screen positions for SLIIT campus lots
            double top = 0;
            double left = 0;

            if (lot.id == 'lot-main') {
              top = 0.38;
              left = 0.48;
            } else if (lot.id == 'lot-new-p2') {
              top = 0.46;
              left = 0.12;
            } else {
              top = 0.18;
              left = 0.78;
            }

            return Align(
              alignment: FractionalOffset(left, top),
              child: GestureDetector(
                onTap: () => onLotSelected?.call(lot),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected || lot.id == 'lot-main'
                        ? c.accent
                        : (isFull ? c.surface : c.primary),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: (isSelected || lot.id == 'lot-main' ? c.accent : Colors.black)
                            .withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isFull ? 'P Full' : 'P ${lot.freeSlots}',
                        style: AppText.label.copyWith(
                          color: isFull ? c.textSecondary : Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

        // Destination Slot badge when in navigation mode
        if (showNavigationRoute && destinationSlotId != null)
          Align(
            alignment: const FractionalOffset(0.78, 0.21),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: c.accent.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Text(
                destinationSlotId!,
                style: AppText.label.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MapCanvasPainter extends CustomPainter {
  final AppColors colors;
  final bool showRoute;
  final double routeProgress;

  _MapCanvasPainter({
    required this.colors,
    required this.showRoute,
    this.routeProgress = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Background Land
    final landPaint = Paint()..color = colors.mapLand;
    canvas.drawRect(Offset.zero & size, landPaint);

    // 2. Building blocks
    final blockPaint = Paint()..color = colors.mapBlock;

    // Building A (Top left)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.08, size.height * 0.12, size.width * 0.24, size.height * 0.14),
        const Radius.circular(8),
      ),
      blockPaint,
    );

    // Building B (Center)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.44, size.height * 0.12, size.width * 0.28, size.height * 0.14),
        const Radius.circular(8),
      ),
      blockPaint,
    );

    // Building C (Bottom Left)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.05, size.height * 0.38, size.width * 0.28, size.height * 0.13),
        const Radius.circular(8),
      ),
      blockPaint,
    );

    // Building D (Middle Right)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.52, size.height * 0.38, size.width * 0.18, size.height * 0.10),
        const Radius.circular(8),
      ),
      blockPaint,
    );

    // Building E (Far Right)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.78, size.height * 0.35, size.width * 0.22, size.height * 0.14),
        const Radius.circular(8),
      ),
      blockPaint,
    );

    // Building F (Center Lower)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.46, size.height * 0.48, size.width * 0.22, size.height * 0.12),
        const Radius.circular(8),
      ),
      blockPaint,
    );

    // 3. Roads (White / dark road lines)
    final roadPaint = Paint()
      ..color = colors.mapRoad
      ..strokeWidth = 28
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    // Horizontal top road
    canvas.drawLine(
      Offset(0, size.height * 0.10),
      Offset(size.width, size.height * 0.10),
      roadPaint,
    );

    // Horizontal middle road
    canvas.drawLine(
      Offset(0, size.height * 0.32),
      Offset(size.width, size.height * 0.32),
      roadPaint,
    );

    // Horizontal bottom road
    canvas.drawLine(
      Offset(0, size.height * 0.58),
      Offset(size.width, size.height * 0.58),
      roadPaint,
    );

    // Vertical main road
    canvas.drawLine(
      Offset(size.width * 0.38, 0),
      Offset(size.width * 0.44, size.height),
      roadPaint,
    );

    // Vertical right road
    canvas.drawLine(
      Offset(size.width * 0.73, 0),
      Offset(size.width * 0.77, size.height),
      roadPaint,
    );

    // 4. Current user location dot (shown when not in in-transit navigation mode)
    if (!showRoute) {
      final userDotCenter = Offset(size.width * 0.42, size.height * 0.24);
      canvas.drawCircle(
        userDotCenter,
        9,
        Paint()..color = colors.surface,
      );
      canvas.drawCircle(
        userDotCenter,
        5,
        Paint()..color = colors.textPrimary,
      );
    }

    // 5. Navigation Route Line & Moving Vehicle Marker
    if (showRoute) {
      final path = Path();
      final start = Offset(size.width * 0.42, size.height * 0.62);
      path.moveTo(start.dx, start.dy);
      path.lineTo(size.width * 0.42, size.height * 0.36);
      path.lineTo(size.width * 0.76, size.height * 0.36);
      path.lineTo(size.width * 0.76, size.height * 0.23);

      // Remaining planned route (subtle line)
      final remainingPaint = Paint()
        ..color = colors.mapRoute.withValues(alpha: 0.35)
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, remainingPaint);

      // Traveled route line (solid vibrant accent)
      final pathMetrics = path.computeMetrics().toList();
      if (pathMetrics.isNotEmpty) {
        final metric = pathMetrics.first;
        final totalLen = metric.length;
        final currentDist = totalLen * routeProgress.clamp(0.0, 1.0);

        if (currentDist > 0) {
          final traveledPath = metric.extractPath(0, currentDist);
          final traveledPaint = Paint()
            ..color = colors.mapRoute
            ..strokeWidth = 6
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;
          canvas.drawPath(traveledPath, traveledPaint);
        }

        // Draw animated vehicle marker at current position
        final tangent = metric.getTangentForOffset(currentDist);
        if (tangent != null) {
          final carPos = tangent.position;

          // Outer halo pulse
          canvas.drawCircle(
            carPos,
            14,
            Paint()..color = colors.mapRoute.withValues(alpha: 0.25),
          );

          // White border ring
          canvas.drawCircle(
            carPos,
            9,
            Paint()..color = Colors.white,
          );

          // Inner accent circle
          canvas.drawCircle(
            carPos,
            6.5,
            Paint()..color = colors.mapRoute,
          );

          // Directional heading arrow
          final angle = tangent.angle;
          canvas.save();
          canvas.translate(carPos.dx, carPos.dy);
          canvas.rotate(angle);

          final headingPath = Path();
          headingPath.moveTo(4, 0);
          headingPath.lineTo(-3, -3);
          headingPath.lineTo(-1, 0);
          headingPath.lineTo(-3, 3);
          headingPath.close();

          canvas.drawPath(headingPath, Paint()..color = Colors.white);
          canvas.restore();
        }
      }

      // Start circle dot
      canvas.drawCircle(
        start,
        6,
        Paint()..color = colors.mapRoute,
      );
      canvas.drawCircle(
        start,
        3,
        Paint()..color = colors.surface,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MapCanvasPainter oldDelegate) {
    return oldDelegate.colors != colors ||
        oldDelegate.showRoute != showRoute ||
        oldDelegate.routeProgress != routeProgress;
  }
}
