import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/billing/demand_forecast_point.dart';
import '../../../data/services/billing/mock_pricing.dart' show colomboTime;

class DemandForecastChart extends StatelessWidget {
  final List<DemandForecastPoint> points;
  const DemandForecastChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (points.isEmpty) {
      return Text('No demand forecast available.', style: AppText.caption);
    }
    final format = DateFormat('EEE HH:mm');
    return Semantics(
      label:
          'Synthetic demand forecast with an illustrative uncertainty band. '
          '${points.length} hourly points. Occupancy range zero to one hundred percent.',
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Synthetic demand · Colombo time',
              style: AppText.title.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Illustrative band · not calibrated confidence',
              style: AppText.caption.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                SizedBox(
                  height: 110,
                  width: 36,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('100%', style: AppText.caption),
                      Text('0%', style: AppText.caption),
                    ],
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 110,
                    child: CustomPaint(
                      painter: _DemandPainter(
                        points,
                        c.textPrimary,
                        c.textSecondary,
                        c.border,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  format.format(colomboTime(points.first.ts)),
                  style: AppText.caption,
                ),
                Text(
                  format.format(colomboTime(points.last.ts)),
                  style: AppText.caption,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DemandPainter extends CustomPainter {
  final List<DemandForecastPoint> points;
  final Color lineColor;
  final Color bandColor;
  final Color gridColor;
  _DemandPainter(this.points, this.lineColor, this.bandColor, this.gridColor);

  @override
  void paint(Canvas canvas, Size size) {
    double y(double fraction) => size.height * (1 - fraction.clamp(0.0, 1.0));
    double x(int index) => size.width * index / (points.length - 1);
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final fraction in [0.0, 0.5, 1.0]) {
      canvas.drawLine(
        Offset(0, y(fraction)),
        Offset(size.width, y(fraction)),
        grid,
      );
    }
    final band = Paint()..color = bandColor.withValues(alpha: 0.16);
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    if (points.length == 1) {
      canvas.drawRect(
        Rect.fromLTRB(
          0,
          y(points.first.yhatUpper),
          size.width,
          y(points.first.yhatLower),
        ),
        band,
      );
      canvas.drawLine(
        Offset(0, y(points.first.yhat)),
        Offset(size.width, y(points.first.yhat)),
        line,
      );
      return;
    }
    final area = Path()..moveTo(0, y(points.first.yhatUpper));
    final path = Path()..moveTo(0, y(points.first.yhat));
    for (var i = 1; i < points.length; i++) {
      area.lineTo(x(i), y(points[i].yhatUpper));
      path.lineTo(x(i), y(points[i].yhat));
    }
    for (var i = points.length - 1; i >= 0; i--) {
      area.lineTo(x(i), y(points[i].yhatLower));
    }
    area.close();
    canvas.drawPath(area, band);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _DemandPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.bandColor != bandColor ||
      oldDelegate.gridColor != gridColor;
}
