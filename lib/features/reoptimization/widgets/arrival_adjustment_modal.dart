// arrival_adjustment_modal.dart
// Interactive dialog suggesting traffic-optimized arrival times when requested booking time is infeasible

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/arrival_feasibility_service.dart';

class ArrivalAdjustmentModal extends StatelessWidget {
  final ArrivalFeasibilityResult result;
  final String lotName;
  final VoidCallback onAccept;
  final VoidCallback onPickOtherTime;
  final VoidCallback onCancel;

  const ArrivalAdjustmentModal({
    super.key,
    required this.result,
    required this.lotName,
    required this.onAccept,
    required this.onPickOtherTime,
    required this.onCancel,
  });

  static Future<bool?> show(
    BuildContext context, {
    required ArrivalFeasibilityResult result,
    required String lotName,
    required VoidCallback onAccept,
    required VoidCallback onPickOtherTime,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ArrivalAdjustmentModal(
        result: result,
        lotName: lotName,
        onAccept: () {
          Navigator.of(ctx).pop(true);
          onAccept();
        },
        onPickOtherTime: () {
          Navigator.of(ctx).pop(false);
          onPickOtherTime();
        },
        onCancel: () => Navigator.of(ctx).pop(false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reqFormatted = DateFormat('h:mm a').format(result.requestedTime);
    final recFormatted = DateFormat('h:mm a').format(result.recommendedArrivalTime);
    final holdExpiryFormatted =
        DateFormat('h:mm a').format(result.recommendedArrivalTime.add(const Duration(minutes: 15)));

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xl),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, -6),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpace.md),
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Alert Header
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: c.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.traffic_rounded,
                  color: c.warning,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Arrival Time Adjustment',
                      style: AppText.h2.copyWith(
                        color: c.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Traffic & travel duration verification',
                      style: AppText.caption.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpace.md),

          // Telemetry Box
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Column(
              children: [
                // Requested Time
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Requested Arrival Time',
                      style: AppText.body.copyWith(color: c.textSecondary, fontSize: 13),
                    ),
                    Row(
                      children: [
                        Text(
                          reqFormatted,
                          style: AppText.body.copyWith(
                            color: c.danger,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: c.danger.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '-${result.lateByMinutes}m late',
                            style: AppText.caption.copyWith(
                              color: c.danger,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const Divider(height: 16),

                // Driving Distance & Traffic
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Estimated Drive to $lotName',
                      style: AppText.body.copyWith(color: c.textSecondary, fontSize: 13),
                    ),
                    Text(
                      '${result.drivingDistanceKm} km (${result.drivingDurationMinutes} mins)',
                      style: AppText.body.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),

                const Divider(height: 16),

                // Recommended Arrival Time
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recommended Arrival Time',
                          style: AppText.body.copyWith(
                            color: c.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '15m Hold Window: $recFormatted – $holdExpiryFormatted',
                          style: AppText.caption.copyWith(
                            color: c.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        recFormatted,
                        style: AppText.body.copyWith(
                          color: c.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpace.md),

          // Informational Tip
          Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: c.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your guaranteed 15-minute barrier hold window will activate at $recFormatted upon scheduled arrival. Your slot will remain securely reserved while you drive.',
                    style: AppText.caption.copyWith(
                      color: c.textSecondary,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpace.lg),

          // Primary Accept Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: onAccept,
              style: ElevatedButton.styleFrom(
                backgroundColor: c.primary,
                foregroundColor: c.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: Text(
                'Accept Recommended Time ($recFormatted)',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),

          const SizedBox(height: AppSpace.sm),

          // Secondary Options
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onPickOtherTime,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.textPrimary,
                    side: BorderSide(color: c.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Pick Other Time', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: c.textSecondary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
