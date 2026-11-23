// hold_countdown_timer_widget.dart
// Smart Parking (J26-IT-335) — Live Hold-Time Countdown & Auto-Release Widget

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../config/app_config.dart';
import '../../data/models/booking_model.dart';
import '../../data/services/parking_state_manager.dart';

/// Reusable countdown and auto-release card for active parking slot holds.
class HoldCountdownTimerWidget extends StatefulWidget {
  final Booking booking;
  final bool compact;
  final VoidCallback? onCheckedIn;
  final VoidCallback? onExpired;

  const HoldCountdownTimerWidget({
    super.key,
    required this.booking,
    this.compact = false,
    this.onCheckedIn,
    this.onExpired,
  });

  @override
  State<HoldCountdownTimerWidget> createState() => _HoldCountdownTimerWidgetState();
}

class _HoldCountdownTimerWidgetState extends State<HoldCountdownTimerWidget> {
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _updateRemaining();
      }
    });
  }

  void _updateRemaining() {
    final diff = widget.booking.effectiveHoldDeadline.difference(DateTime.now());
    if (diff.isNegative || diff == Duration.zero) {
      if (_remaining != Duration.zero) {
        setState(() => _remaining = Duration.zero);
        widget.onExpired?.call();
        // Auto-release booking via state manager
        final state = context.read<ParkingStateManager>();
        if (widget.booking.isActive &&
            (widget.booking.status == BookingStatus.reserved ||
                widget.booking.status == BookingStatus.upgraded)) {
          state.cancelBooking(autoCancelled: true);
        }
      } else {
        setState(() => _remaining = Duration.zero);
      }
    } else {
      setState(() => _remaining = diff);
    }
  }

  @override
  void didUpdateWidget(covariant HoldCountdownTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.booking.effectiveHoldDeadline != widget.booking.effectiveHoldDeadline) {
      _updateRemaining();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return '00:00';
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Color _getStatusColor(AppColors c) {
    if (_remaining == Duration.zero) return c.danger;
    if (_remaining.inSeconds <= 60) return c.danger;
    if (_remaining.inMinutes < 5) return c.warning;
    return c.accent;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final statusColor = _getStatusColor(c);
    final isExpired = _remaining == Duration.zero;

    // Total hold window (default 15 minutes = 900 seconds)
    final totalSeconds = widget.booking.effectiveHoldDeadline
        .difference(widget.booking.bookedAt)
        .inSeconds
        .clamp(60, 3600);
    final progress = (1.0 - (_remaining.inSeconds / totalSeconds)).clamp(0.0, 1.0);

    if (widget.compact) {
      return _buildCompact(context, c, statusColor, isExpired, progress);
    }

    return _buildExpanded(context, c, statusColor, isExpired, progress);
  }

  Widget _buildCompact(
    BuildContext context,
    AppColors c,
    Color statusColor,
    bool isExpired,
    double progress,
  ) {
    final state = context.watch<ParkingStateManager>();
    final isInTransit = widget.booking.isInTransit && widget.booking.holdExpiresAt == null;
    final arriveFormatted = DateFormat('h:mm a').format(widget.booking.arrivalTime);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: (isInTransit ? c.accent : statusColor).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(
          color: (isInTransit ? c.accent : statusColor).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isInTransit
                    ? Icons.directions_car_rounded
                    : (isExpired ? Icons.cancel_outlined : Icons.timer_outlined),
                size: 16,
                color: isInTransit ? c.accent : statusColor,
              ),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text(
                  isInTransit
                      ? 'In transit · Arriving at $arriveFormatted'
                      : (isExpired ? 'Hold expired · Auto-released' : 'Hold expires in ${_formatDuration(_remaining)}'),
                  style: AppText.caption.copyWith(
                    color: isInTransit ? c.accent : statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (AppConfig.kDemoMode) ...[
                if (isInTransit)
                  InkWell(
                    onTap: () => state.fastForwardToArrivalTime(),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fast_forward_rounded, size: 12, color: c.accent),
                          const SizedBox(width: 2),
                          Text(
                            'To Arrival',
                            style: AppText.overline.copyWith(
                              color: c.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (!isExpired)
                  InkWell(
                    onTap: () => state.fastForwardHoldTimer(remaining: const Duration(seconds: 10)),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt_rounded, size: 12, color: c.accent),
                          const SizedBox(width: 2),
                          Text(
                            'Test 10s',
                            style: AppText.overline.copyWith(
                              color: c.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
          if (!isInTransit && !isExpired) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: c.border,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                minHeight: 3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpanded(
    BuildContext context,
    AppColors c,
    Color statusColor,
    bool isExpired,
    double progress,
  ) {
    final state = context.watch<ParkingStateManager>();
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;
    final isInTransit = widget.booking.isInTransit && widget.booking.holdExpiresAt == null;
    final arriveFormatted = DateFormat('h:mm a').format(widget.booking.arrivalTime);
    final activeStatusColor = isInTransit ? c.accent : statusColor;

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: activeStatusColor.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: activeStatusColor.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: activeStatusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Flexible(
                      child: Text(
                        isInTransit ? 'TRIP IN PROGRESS' : 'HOLD RESERVATION TIMER',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.overline.copyWith(
                          color: c.textSecondary,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: activeStatusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isInTransit
                      ? 'IN TRANSIT'
                      : isExpired
                          ? 'EXPIRED'
                          : _remaining.inMinutes < 5
                              ? 'EXPIRING SOON'
                              : 'HOLD ACTIVE',
                  style: AppText.overline.copyWith(
                    color: activeStatusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpace.md),

          // Main Countdown Display
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                isInTransit
                    ? '${widget.booking.timeUntilArrival.inMinutes}m'
                    : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                style: AppText.h1.copyWith(
                  color: activeStatusColor,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  isInTransit
                      ? 'until arrival ($arriveFormatted)'
                      : (isExpired ? 'auto-released' : 'remaining hold'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    color: c.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),
          Text(
            isInTransit
                ? 'Driving to ${widget.booking.lotName}. Your 15-minute guaranteed barrier hold countdown will activate upon scheduled arrival at $arriveFormatted.'
                : isExpired
                    ? 'Your 15-minute barrier hold expired. Slot ${widget.booking.slotId} has been returned to the campus availability pool.'
                    : 'Your barrier gate pass is guaranteed. Arrive and scan before expiry to lock in your slot.',
            style: AppText.caption.copyWith(
              color: c.textSecondary,
              height: 1.35,
            ),
          ),

          const SizedBox(height: AppSpace.md),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: isInTransit ? 0.35 : progress,
              backgroundColor: c.border,
              valueColor: AlwaysStoppedAnimation<Color>(activeStatusColor),
              minHeight: 5,
            ),
          ),

          if (AppConfig.kDemoMode) ...[
            if (isInTransit) ...[
              const SizedBox(height: AppSpace.md),
              const Divider(),
              const SizedBox(height: AppSpace.xs),

              // In-Transit Fast Forward Controls
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.textPrimary,
                    side: BorderSide(color: c.border),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                    ),
                  ),
                  icon: Icon(Icons.fast_forward_rounded, size: 16, color: c.accent),
                  label: Text(
                    'Fast-Forward to Arrival Time ($arriveFormatted)',
                    style: AppText.caption.copyWith(fontWeight: FontWeight.w700),
                  ),
                  onPressed: () {
                    state.fastForwardToArrivalTime();
                  },
                ),
              ),
            ] else if (!isExpired) ...[
              const SizedBox(height: AppSpace.md),
              const Divider(),
              const SizedBox(height: AppSpace.xs),

              // Evaluation / Demo Simulation Row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        foregroundColor: c.textPrimary,
                        side: BorderSide(color: c.border),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                        ),
                      ),
                      icon: Icon(Icons.bolt_rounded, size: 16, color: c.accent),
                      label: Text(
                        'Test Auto-Release (10s)',
                        style: AppText.caption.copyWith(fontWeight: FontWeight.w700),
                      ),
                      onPressed: () {
                        state.fastForwardHoldTimer(remaining: const Duration(seconds: 10));
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      foregroundColor: c.textPrimary,
                      side: BorderSide(color: c.border),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                      ),
                    ),
                    icon: const Icon(Icons.add_alarm_rounded, size: 16),
                    label: Text(
                      '+5m',
                      style: AppText.caption.copyWith(fontWeight: FontWeight.w700),
                    ),
                    onPressed: () {
                      state.extendHoldDuration(extension: const Duration(minutes: 5));
                    },
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
