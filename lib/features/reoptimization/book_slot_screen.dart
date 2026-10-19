import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../data/models/booking_model.dart';
import '../../data/models/parking_lot_model.dart';
import '../../data/models/parking_slot_model.dart';
import '../../data/models/vehicle_model.dart';
import '../../data/services/arrival_feasibility_service.dart';
import '../../data/services/parking_state_manager.dart';
import 'engine/slot_score_result.dart';
import 'widgets/arrival_adjustment_modal.dart';
import 'widgets/booking_confirmed_dialog.dart';

class BookSlotScreen extends StatefulWidget {
  final ParkingLot lot;
  final double? originLat;
  final double? originLng;
  final ValueChanged<Booking> onBookingConfirmed;

  const BookSlotScreen({
    super.key,
    required this.lot,
    this.originLat,
    this.originLng,
    required this.onBookingConfirmed,
  });

  @override
  State<BookSlotScreen> createState() => _BookSlotScreenState();
}

class _BookSlotScreenState extends State<BookSlotScreen> {
  late ParkingSlot _selectedSlot;
  late ParkingSlot _recommendedSlot;
  SlotScoreResult? _recommendedScore;
  SlotScoreResult? _selectedScore;
  DateTime _arrivalTime = DateTime.now().add(const Duration(minutes: 15));
  int _durationHours = 2;

  @override
  void initState() {
    super.initState();
    final state = context.read<ParkingStateManager>();
    final recommended = state.getRecommendedSlot(widget.lot);

    final availableSlots = widget.lot.slots.where((s) => s.isAvailable).toList();
    if (recommended != null) {
      _recommendedSlot = recommended;
    } else if (availableSlots.isNotEmpty) {
      _recommendedSlot = availableSlots.first;
    } else if (widget.lot.slots.isNotEmpty) {
      _recommendedSlot = widget.lot.slots.first;
    } else {
      _recommendedSlot = ParkingSlot(
        id: 'None',
        lotId: widget.lot.id,
        row: 'A',
        number: 0,
        state: SlotState.taken,
        size: VehicleSize.medium,
        walkingDistanceMeters: widget.lot.distanceMeters,
      );
    }

    _selectedSlot = _recommendedSlot;
    _recommendedScore = state.getRecommendedSlotScore(widget.lot);
    _selectedScore = state.scoreSlot(widget.lot, _selectedSlot);
  }

  void _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_arrivalTime),
    );
    if (picked != null) {
      final now = DateTime.now();
      setState(() {
        _arrivalTime = DateTime(
          now.year,
          now.month,
          now.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  void _selectDuration() {
    final c = context.colors;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select Duration', style: AppText.h2.copyWith(color: c.textPrimary)),
              const SizedBox(height: AppSpace.md),
              ...[1, 2, 3, 4, 6, 8].map((hours) {
                return ListTile(
                  title: Text('$hours hour${hours > 1 ? 's' : ''}'),
                  trailing: _durationHours == hours
                      ? Icon(Icons.check_rounded, color: c.accent)
                      : null,
                  onTap: () {
                    setState(() => _durationHours = hours);
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showAlgorithmExplanation(BuildContext context) {
    final c = context.colors;
    final state = context.read<ParkingStateManager>();
    final weights = state.scoringWeights;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AppRadius.sheetR,
        ),
        padding: const EdgeInsets.all(AppSpace.lg),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              Row(
                children: [
                  Icon(Icons.calculate_outlined, color: c.accent, size: 24),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      'Multi-Criteria Optimization Model (SYS-01)',
                      style: AppText.h2.copyWith(color: c.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                'Objective function maximizes driver utility while balancing lot throughput and preserving large-vehicle capacity.',
                style: AppText.caption.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppSpace.md),

              // Mathematical Formulation Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: c.accent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Objective Scoring Function:',
                      style: AppText.label.copyWith(color: c.accent, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'S(s) = wd·Sdist(s) + wz·Ssize(s) + wp·Spref(s) - wu·Pdemand(s)',
                      style: AppText.body.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpace.md),
              Text('Current Parameter Weights', style: AppText.title.copyWith(color: c.textPrimary)),
              const SizedBox(height: AppSpace.sm),
              _weightRow('Distance weight (wd)', '${(weights.distanceWeight * 100).toInt()}%', c),
              _weightRow('Size fit weight (wz)', '${(weights.sizeFitWeight * 100).toInt()}%', c),
              _weightRow('Preference weight (wp)', '${(weights.preferenceWeight * 100).toInt()}%', c),
              _weightRow('Demand penalty (wu)', '${(weights.demandWeight * 100).toInt()}%', c),

              const SizedBox(height: AppSpace.md),
              Text('Evaluated Breakdown for ${_recommendedSlot.id}', style: AppText.title.copyWith(color: c.textPrimary)),
              const SizedBox(height: AppSpace.sm),
              if (_recommendedScore != null) ...[
                _scoreRow('Walking distance score', '${_recommendedScore!.distanceScore.toStringAsFixed(1)} / 100', c),
                _scoreRow('Size compatibility score', '${_recommendedScore!.sizeFitScore.toStringAsFixed(1)} / 100', c),
                _scoreRow('Driver preference score', '${_recommendedScore!.preferenceScore.toStringAsFixed(1)} / 100', c),
                _scoreRow('Lot congestion penalty', '-${_recommendedScore!.demandPenalty.toStringAsFixed(1)}', c),
                const Divider(),
                _scoreRow(
                  'Final Composite Score',
                  '${_recommendedScore!.totalScore.toStringAsFixed(1)} / 100.0',
                  c,
                  isBold: true,
                ),
              ],

              const SizedBox(height: AppSpace.lg),
              PrimaryButton(
                text: 'Done',
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _weightRow(String label, String value, AppColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.caption.copyWith(color: c.textSecondary)),
          Text(value, style: AppText.caption.copyWith(color: c.textPrimary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _scoreRow(String label, String value, AppColors c, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.body.copyWith(color: isBold ? c.textPrimary : c.textSecondary, fontWeight: isBold ? FontWeight.w700 : FontWeight.normal)),
          Text(value, style: AppText.body.copyWith(color: isBold ? c.accent : c.textPrimary, fontWeight: isBold ? FontWeight.w700 : FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildScorePill(String text, AppColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.border),
      ),
      child: Text(
        text,
        style: AppText.caption.copyWith(
          color: c.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _confirmReservation() {
    if (!_selectedSlot.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Slot ${_selectedSlot.id} is not available for reservation.'),
        ),
      );
      return;
    }

    // Predictive driving distance & traffic feasibility validation
    final originLat = widget.originLat ?? 6.9147;
    final originLng = widget.originLng ?? 79.9729;

    final feasibility = ArrivalFeasibilityService.evaluate(
      originLat: originLat,
      originLng: originLng,
      targetLot: widget.lot,
      requestedTime: _arrivalTime,
    );

    if (!feasibility.isFeasible) {
      // Display algorithmic arrival adjustment modal
      ArrivalAdjustmentModal.show(
        context,
        result: feasibility,
        lotName: widget.lot.name,
        onAccept: () {
          setState(() {
            _arrivalTime = feasibility.recommendedArrivalTime;
          });
          _finalizeBooking();
        },
        onPickOtherTime: () {
          _selectTime();
        },
      );
      return;
    }

    _finalizeBooking();
  }

  void _finalizeBooking() {
    final state = context.read<ParkingStateManager>();
    final booking = state.reserveSlot(
      lot: widget.lot,
      slot: _selectedSlot,
      arrivalTime: _arrivalTime,
      durationHours: _durationHours,
    );

    // Present post-booking dialog with navigation choices
    BookingConfirmedDialog.show(
      context,
      booking: booking,
      lot: widget.lot,
      originLat: widget.originLat,
      originLng: widget.originLng,
      onStartInAppNav: () {
        widget.onBookingConfirmed(booking);
      },
      onReturnHome: () {
        // Pop BookSlotScreen back to main screen - booking continues in background
        Navigator.of(context).pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rowASlots = widget.lot.slots.where((s) => s.row == 'A').take(6).toList();
    final rowBSlots = widget.lot.slots.where((s) => s.row == 'B').take(6).toList();

    final arriveTimeFormatted = DateFormat('h:mm a').format(_arrivalTime);
    final deadlineFormatted = DateFormat('h:mm a').format(_arrivalTime.add(const Duration(minutes: 15)));
    final totalFee = widget.lot.hourlyRate * _durationHours;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg,
                vertical: AppSpace.sm,
              ),
              child: Row(
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
                      icon: Icon(Icons.chevron_left_rounded, color: c.textPrimary, size: 24),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.lot.name,
                        style: AppText.h2.copyWith(color: c.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.lot.freeSlots} of ${widget.lot.totalSlots} free · LKR ${widget.lot.hourlyRate}/h',
                        style: AppText.caption.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                children: [
                  const SizedBox(height: AppSpace.sm),

                  // 1. Lot Layout Grid Card
                  Container(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row A Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'ROW A',
                              style: AppText.overline.copyWith(color: c.textSecondary),
                            ),
                            Text(
                              'ENTRANCE →',
                              style: AppText.overline.copyWith(color: c.textSecondary),
                            ),
                          ],
                        ),

                        const SizedBox(height: AppSpace.sm),

                        // Row A Slots Grid
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: rowASlots.map((slot) {
                            return _SlotTile(
                              slot: slot,
                              isSelected: slot.id == _selectedSlot.id,
                              onTap: () {
                                if (slot.isAvailable) {
                                  final state = context.read<ParkingStateManager>();
                                  setState(() {
                                    _selectedSlot = slot;
                                    _selectedScore = state.scoreSlot(widget.lot, slot);
                                  });
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        slot.state == SlotState.blocked
                                            ? 'Slot ${slot.id} blocked for maintenance'
                                            : 'Slot ${slot.id} is already occupied',
                                      ),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                }
                              },
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: AppSpace.md),

                        // Lane Separator
                        Row(
                          children: [
                            Expanded(child: _DashedLine(color: c.border)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                              child: Text(
                                'LANE',
                                style: AppText.overline.copyWith(color: c.textTertiary),
                              ),
                            ),
                            Expanded(child: _DashedLine(color: c.border)),
                          ],
                        ),

                        const SizedBox(height: AppSpace.md),

                        // Row B Slots Grid
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: rowBSlots.map((slot) {
                            return _SlotTile(
                              slot: slot,
                              isSelected: slot.id == _selectedSlot.id,
                              onTap: () {
                                if (slot.isAvailable) {
                                  final state = context.read<ParkingStateManager>();
                                  setState(() {
                                    _selectedSlot = slot;
                                    _selectedScore = state.scoreSlot(widget.lot, slot);
                                  });
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Slot ${slot.id} is occupied'),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                }
                              },
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: AppSpace.lg),

                        // Legend
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _LegendItem(label: 'Free', border: Border.all(color: c.slotFreeBorder, width: 1.2)),
                            _LegendItem(label: 'Taken', fill: c.slotTaken),
                            _LegendItem(label: 'Blocked', isHatched: true),
                            _LegendItem(label: 'Your pick', border: Border.all(color: c.accent, width: 1.5), fill: c.accentSoft),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpace.md),

                  // 2. Mathematical Scoring & Recommendation Card (SYS-01)
                  Container(
                    padding: const EdgeInsets.all(AppSpace.md),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.auto_awesome_rounded, color: c.accent, size: 22),
                            const SizedBox(width: AppSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Recommended: ${_recommendedSlot.id}',
                                        style: AppText.title.copyWith(
                                          color: c.textPrimary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (_recommendedScore != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c.accentSoft,
                                            borderRadius: BorderRadius.circular(AppRadius.chip),
                                          ),
                                          child: Text(
                                            'Score ${_recommendedScore!.totalScore.toStringAsFixed(1)}',
                                            style: AppText.caption.copyWith(
                                              color: c.accent,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Closest free slot to entrance · ${_recommendedSlot.walkingDistanceMeters} m walk · fits ${_recommendedSlot.size.displayName}',
                                    style: AppText.body.copyWith(
                                      color: c.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        if (_recommendedScore != null) ...[
                          const SizedBox(height: AppSpace.sm),
                          const Divider(height: 1),
                          const SizedBox(height: AppSpace.xs),
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildScorePill(
                                    'Dist: ${_recommendedScore!.distanceScore.toInt()}%',
                                    c,
                                  ),
                                  const SizedBox(width: 6),
                                  _buildScorePill(
                                    'Fit: ${_recommendedScore!.sizeFitScore.toInt()}%',
                                    c,
                                  ),
                                  const SizedBox(width: 6),
                                  _buildScorePill(
                                    'Pref: +${_recommendedScore!.preferenceScore.toInt()}',
                                    c,
                                  ),
                                ],
                              ),
                              InkWell(
                                onTap: () => _showAlgorithmExplanation(context),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'SYS-01 Model',
                                        style: AppText.caption.copyWith(
                                          color: c.accent,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded, size: 14, color: c.accent),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        // Comparison warning if user picked another slot
                        if (_selectedSlot.id != _recommendedSlot.id) ...[
                          const SizedBox(height: AppSpace.sm),
                          Container(
                            padding: const EdgeInsets.all(AppSpace.sm),
                            decoration: BoxDecoration(
                              color: c.accentSoft.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(AppRadius.cardSm),
                              border: Border.all(color: c.accent.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded, size: 18, color: c.accent),
                                const SizedBox(width: AppSpace.xs),
                                Expanded(
                                  child: Text(
                                    'Custom pick: ${_selectedSlot.id} (${_selectedSlot.walkingDistanceMeters}m, score: ${_selectedScore?.totalScore.toStringAsFixed(1) ?? "--"}). Recommended ${_recommendedSlot.id} saves ${(_selectedSlot.walkingDistanceMeters - _recommendedSlot.walkingDistanceMeters).clamp(0, 500)}m.',
                                    style: AppText.caption.copyWith(color: c.textPrimary, fontSize: 11),
                                  ),
                                ),
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedSlot = _recommendedSlot;
                                      _selectedScore = _recommendedScore;
                                    });
                                  },
                                  child: Text(
                                    'Revert',
                                    style: AppText.caption.copyWith(
                                      color: c.accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpace.md),

                  // 3. Time and Duration Selectors
                  Row(
                    children: [
                      // Arrive by
                      Expanded(
                        child: InkWell(
                          onTap: _selectTime,
                          borderRadius: BorderRadius.circular(AppRadius.card),
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
                                Text('Arrive by', style: AppText.caption.copyWith(color: c.textSecondary)),
                                const SizedBox(height: 4),
                                Text(
                                  arriveTimeFormatted,
                                  style: AppText.title.copyWith(
                                    color: c.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: AppSpace.md),

                      // Duration
                      Expanded(
                        child: InkWell(
                          onTap: _selectDuration,
                          borderRadius: BorderRadius.circular(AppRadius.card),
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
                                Text('Duration', style: AppText.caption.copyWith(color: c.textSecondary)),
                                const SizedBox(height: 4),
                                Text(
                                  '$_durationHours h',
                                  style: AppText.title.copyWith(
                                    color: c.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpace.lg),
                ],
              ),
            ),

            // Bottom CTA Section
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                AppSpace.lg,
              ),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Estimated fee',
                        style: AppText.body.copyWith(color: c.textSecondary),
                      ),
                      Text(
                        'LKR $totalFee',
                        style: AppText.h2.copyWith(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpace.md),

                  PrimaryButton(
                    text: widget.lot.isFull
                        ? 'Lot is Full'
                        : (_selectedSlot.isAvailable
                            ? 'Reserve ${_selectedSlot.id}'
                            : 'Slot Unavailable'),
                    onPressed: (widget.lot.isFull || !_selectedSlot.isAvailable)
                        ? null
                        : _confirmReservation,
                  ),

                  const SizedBox(height: AppSpace.sm),

                  Text(
                    'Held until $deadlineFormatted. Released automatically if you are 15 min late.',
                    textAlign: TextAlign.center,
                    style: AppText.caption.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  final ParkingSlot slot;
  final bool isSelected;
  final VoidCallback onTap;

  const _SlotTile({
    required this.slot,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isBlocked = slot.state == SlotState.blocked;
    final isTaken = slot.state == SlotState.taken;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 68,
        decoration: BoxDecoration(
          color: isSelected
              ? c.accentSoft
              : (isTaken
                  ? c.slotTaken
                  : (isBlocked ? c.slotBlocked : c.surface)),
          borderRadius: BorderRadius.circular(AppRadius.slot),
          border: isSelected
              ? Border.all(color: c.accent, width: 2)
              : (isTaken || isBlocked
                  ? null
                  : Border.all(color: c.slotFreeBorder, width: 1.2)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.slot - 1),
          child: Stack(
            children: [
              if (isBlocked) const Positioned.fill(child: _DiagonalStripes()),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isSelected) ...[
                      Icon(Icons.check_rounded, color: c.accent, size: 16),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      slot.id,
                      style: AppText.caption.copyWith(
                        color: isSelected
                            ? c.accent
                            : (isBlocked ? c.textTertiary : c.textSecondary),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final Color? fill;
  final BoxBorder? border;
  final bool isHatched;

  const _LegendItem({
    required this.label,
    this.fill,
    this.border,
    this.isHatched = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: fill ?? (isHatched ? c.slotBlocked : Colors.transparent),
            border: border,
            borderRadius: BorderRadius.circular(3),
          ),
          child: isHatched ? const _DiagonalStripes() : null,
        ),
        const SizedBox(width: AppSpace.xxs),
        Text(
          label,
          style: AppText.caption.copyWith(color: c.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

class _DashedLine extends StatelessWidget {
  final Color color;

  const _DashedLine({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: CustomPaint(
        painter: _DashedLinePainter(color: color),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, 0), Offset(startX + 4, 0), paint);
      startX += 8;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => oldDelegate.color != color;
}

class _DiagonalStripes extends StatelessWidget {
  const _DiagonalStripes();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StripesPainter(),
    );
  }
}

class _StripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 2.0;

    for (double i = -size.height; i < size.width; i += 7) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
