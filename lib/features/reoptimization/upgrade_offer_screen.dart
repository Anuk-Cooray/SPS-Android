import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../data/models/booking_model.dart';
import '../../data/models/parking_slot_model.dart';
import 'engine/upgrade_evaluation_result.dart';

class UpgradeOfferModal extends StatefulWidget {
  final Booking booking;
  final ParkingSlot newSlot;
  final UpgradeEvaluationResult? evaluationResult;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const UpgradeOfferModal({
    super.key,
    required this.booking,
    required this.newSlot,
    this.evaluationResult,
    required this.onAccept,
    required this.onDecline,
  });

  static Future<void> show({
    required BuildContext context,
    required Booking booking,
    required ParkingSlot newSlot,
    UpgradeEvaluationResult? evaluationResult,
    required VoidCallback onAccept,
    required VoidCallback onDecline,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UpgradeOfferModal(
        booking: booking,
        newSlot: newSlot,
        evaluationResult: evaluationResult,
        onAccept: onAccept,
        onDecline: onDecline,
      ),
    );
  }

  @override
  State<UpgradeOfferModal> createState() => _UpgradeOfferModalState();
}

class _UpgradeOfferModalState extends State<UpgradeOfferModal> {
  int _secondsRemaining = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
        widget.onDecline();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final currentSlotId = widget.booking.slotId;
    final newSlotId = widget.newSlot.id;
    final distanceSaved = widget.evaluationResult?.distanceSavedMeters ??
        (160 - widget.newSlot.walkingDistanceMeters).clamp(10, 500);
    final scoreImprovement = widget.evaluationResult?.scoreImprovementPercent;
    final currentWalk = widget.newSlot.walkingDistanceMeters + distanceSaved;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadius.sheetR,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xs,
        AppSpace.lg,
        AppSpace.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpace.md),
              decoration: BoxDecoration(
                color: c.slotTaken,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Top Header: Blue indicator & Countdown
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Text(
                    'Better slot available',
                    style: AppText.label.copyWith(
                      color: c.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Text(
                'Expires in 0:${_secondsRemaining.toString().padLeft(2, '0')}',
                style: AppText.caption.copyWith(color: c.textSecondary),
              ),
            ],
          ),

          const SizedBox(height: AppSpace.md),

          // Main Headline
          Text(
            'Switch to $newSlotId and walk $distanceSaved m less',
            style: AppText.h1.copyWith(
              color: c.textPrimary,
              height: 1.15,
            ),
          ),

          const SizedBox(height: AppSpace.sm),

          // Subtitle
          Text(
            'A closer slot just opened in ${widget.booking.lotName}. Same price, same arrival time.${scoreImprovement != null ? ' Match score improved +${scoreImprovement.toStringAsFixed(1)}%.' : ''}',
            style: AppText.body.copyWith(color: c.textSecondary),
          ),

          const SizedBox(height: AppSpace.xl),

          // Side-by-side comparison cards
          Row(
            children: [
              // Current Slot Card
              Expanded(
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
                        'Current',
                        style: AppText.caption.copyWith(color: c.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentSlotId,
                        style: AppText.slotId.copyWith(color: c.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$currentWalk m walk',
                        style: AppText.caption.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: AppSpace.md),

              // New Slot Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(AppSpace.md),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: c.accent, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'New',
                            style: AppText.caption.copyWith(
                              color: c.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (scoreImprovement != null && scoreImprovement > 0)
                            Text(
                              '+${scoreImprovement.toStringAsFixed(0)}%',
                              style: AppText.caption.copyWith(
                                color: c.accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        newSlotId,
                        style: AppText.slotId.copyWith(color: c.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.newSlot.walkingDistanceMeters} m walk · LKR ${widget.booking.estimatedFee}',
                        style: AppText.caption.copyWith(
                          color: c.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpace.lg),

          // Depleting Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: _secondsRemaining / 60,
              minHeight: 4,
              backgroundColor: c.divider,
              valueColor: AlwaysStoppedAnimation<Color>(c.accent),
            ),
          ),

          const SizedBox(height: AppSpace.xl),

          // CTA Buttons
          PrimaryButton(
            text: 'Switch to $newSlotId',
            onPressed: widget.onAccept,
          ),

          const SizedBox(height: AppSpace.xs),

          Center(
            child: TertiaryButton(
              text: 'Keep $currentSlotId',
              onPressed: widget.onDecline,
            ),
          ),
        ],
      ),
    );
  }
}
