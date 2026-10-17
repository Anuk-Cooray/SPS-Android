import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../data/models/booking_model.dart';

class LateArrivalModal extends StatefulWidget {
  final Booking booking;
  final VoidCallback onExtend;
  final VoidCallback onRelease;

  const LateArrivalModal({
    super.key,
    required this.booking,
    required this.onExtend,
    required this.onRelease,
  });

  static Future<void> show({
    required BuildContext context,
    required Booking booking,
    required VoidCallback onExtend,
    required VoidCallback onRelease,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LateArrivalModal(
        booking: booking,
        onExtend: onExtend,
        onRelease: onRelease,
      ),
    );
  }

  @override
  State<LateArrivalModal> createState() => _LateArrivalModalState();
}

class _LateArrivalModalState extends State<LateArrivalModal> {
  int _secondsLeft = 299; // 4:59 as in mockup
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        timer.cancel();
        widget.onRelease(); // auto-cancelled on zero
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
    final minutes = _secondsLeft ~/ 60;
    final seconds = _secondsLeft % 60;

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

          // Amber icon badge
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.warningSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.warningBorder),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.access_time_filled_rounded,
              color: c.warning,
              size: 22,
            ),
          ),

          const SizedBox(height: AppSpace.md),

          // Title
          Text(
            "You're running late",
            style: AppText.h1.copyWith(color: c.textPrimary),
          ),

          const SizedBox(height: AppSpace.xs),

          // Subtitle
          Text(
            'Slot ${widget.booking.slotId} will be released for other drivers unless you extend.',
            style: AppText.body.copyWith(color: c.textSecondary),
          ),

          const SizedBox(height: AppSpace.lg),

          // Amber Countdown Card
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg,
              vertical: AppSpace.md,
            ),
            decoration: BoxDecoration(
              color: c.warningSoft,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: c.warningBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Releases in',
                  style: AppText.body.copyWith(
                    color: c.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$minutes:${seconds.toString().padLeft(2, '0')}',
                  style: AppText.display.copyWith(
                    color: c.warning,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpace.md),

          // ETA info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Your ETA', style: AppText.body.copyWith(color: c.textSecondary)),
              Text(
                '8 min · 10:53 AM',
                style: AppText.title.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpace.xl),

          // Actions
          PrimaryButton(
            text: 'Extend 15 min · LKR 50',
            onPressed: widget.onExtend,
          ),

          const SizedBox(height: AppSpace.sm),

          SecondaryButton(
            text: 'Release slot',
            onPressed: widget.onRelease,
          ),
        ],
      ),
    );
  }
}
