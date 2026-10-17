import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../data/models/booking_model.dart';
import '../../data/models/parking_lot_model.dart';
import '../../data/models/parking_slot_model.dart';
import '../../data/services/parking_state_manager.dart';

class BookSlotScreen extends StatefulWidget {
  final ParkingLot lot;
  final ValueChanged<Booking> onBookingConfirmed;

  const BookSlotScreen({
    super.key,
    required this.lot,
    required this.onBookingConfirmed,
  });

  @override
  State<BookSlotScreen> createState() => _BookSlotScreenState();
}

class _BookSlotScreenState extends State<BookSlotScreen> {
  late ParkingSlot _selectedSlot;
  late ParkingSlot _recommendedSlot;
  DateTime _arrivalTime = DateTime.now().add(const Duration(minutes: 15));
  int _durationHours = 2;

  @override
  void initState() {
    super.initState();
    final state = context.read<ParkingStateManager>();
    final recommended = state.getRecommendedSlot(widget.lot);

    _recommendedSlot = recommended ??
        widget.lot.slots.firstWhere(
          (s) => s.isAvailable,
          orElse: () => widget.lot.slots.first,
        );

    _selectedSlot = _recommendedSlot;
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

  void _confirmReservation() {
    final state = context.read<ParkingStateManager>();
    final booking = state.reserveSlot(
      lot: widget.lot,
      slot: _selectedSlot,
      arrivalTime: _arrivalTime,
      durationHours: _durationHours,
    );

    widget.onBookingConfirmed(booking);
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
                                  setState(() => _selectedSlot = slot);
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
                                  setState(() => _selectedSlot = slot);
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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

                  // 2. AI Recommendation Card
                  Container(
                    padding: const EdgeInsets.all(AppSpace.md),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.auto_awesome_rounded, color: c.accent, size: 22),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Recommended: ${_recommendedSlot.id}',
                                style: AppText.title.copyWith(
                                  color: c.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Closest free slot to the entrance · ${_recommendedSlot.walkingDistanceMeters} m walk · fits your sedan',
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
                    text: 'Reserve ${_selectedSlot.id}',
                    onPressed: _confirmReservation,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final dashCount = (constraints.constrainWidth() / 8).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: 4,
              height: 1,
              child: DecoratedBox(decoration: BoxDecoration(color: color)),
            );
          }),
        );
      },
    );
  }
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
