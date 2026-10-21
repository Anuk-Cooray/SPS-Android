import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../data/models/booking_model.dart';
import '../../data/services/parking_state_manager.dart';

class PayAndExitScreen extends StatefulWidget {
  final Booking booking;
  final ValueChanged<int> onPaymentCompleted;

  const PayAndExitScreen({
    super.key,
    required this.booking,
    required this.onPaymentCompleted,
  });

  @override
  State<PayAndExitScreen> createState() => _PayAndExitScreenState();
}

class _PayAndExitScreenState extends State<PayAndExitScreen> {
  int _selectedPaymentMethod = 0; // 0: Card, 1: Attendant QR
  bool _isProcessing = false;
  // Freeze the stay at the moment the driver opened checkout so the total doesn't drift
  final DateTime _exitAt = DateTime.now();

  static String _formatStay(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h $m min';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.watch<ParkingStateManager>();
    // The booking handed to this screen can predate check-in; prefer the latest copy
    final booking = state.bookings.firstWhere((b) => b.id == widget.booking.id, orElse: () => widget.booking);
    final checkedIn = booking.checkedInAt?.toLocal();
    final arrival = booking.arrivalTime.toLocal();
    final parkedFrom = checkedIn ?? (arrival.isBefore(_exitAt) ? arrival : _exitAt);
    final stay = _exitAt.isAfter(parkedFrom) ? _exitAt.difference(parkedFrom) : Duration.zero;
    final baseFee = booking.parkingFeeFor(stay);
    final extFee = booking.extensionFee;
    final totalDue = baseFee + extFee;
    final card = state.currentUser.defaultPaymentMethod;
    final hasCard = card != null && card.isNotEmpty;
    final method = hasCard ? _selectedPaymentMethod : 1;
    final timeFmt = DateFormat('h:mm a');

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpace.sm),

              // Header
              Row(
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
                      tooltip: 'Back',
                      icon: Icon(Icons.chevron_left_rounded, color: c.textPrimary, size: 24),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Text(
                    'Pay and exit',
                    style: AppText.h2.copyWith(color: c.textPrimary),
                  ),
                ],
              ),

              const SizedBox(height: AppSpace.xl),

              // Total due display
              Text(
                'Total due',
                style: AppText.caption.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                'LKR $totalDue',
                style: AppText.display.copyWith(
                  color: c.textPrimary,
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${booking.lotName} · ${timeFmt.format(parkedFrom)} – ${timeFmt.format(_exitAt)}',
                style: AppText.body.copyWith(color: c.textSecondary),
              ),

              const SizedBox(height: AppSpace.xl),

              // Invoice itemized card
              Container(
                padding: const EdgeInsets.all(AppSpace.lg),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  children: [
                    _buildInvoiceRow('Parking · ${_formatStay(stay)}', 'LKR $baseFee'),
                    if (extFee > 0) ...[
                      const SizedBox(height: AppSpace.sm),
                      _buildInvoiceRow('Hold extension', 'LKR $extFee'),
                    ],
                    if (booking.originalSlotId != null) ...[
                      const SizedBox(height: AppSpace.sm),
                      _buildInvoiceRow(
                        'Upgrade ${booking.originalSlotId} → ${booking.slotId}',
                        'Free',
                      ),
                    ],
                    const SizedBox(height: AppSpace.md),
                    const Divider(),
                    const SizedBox(height: AppSpace.md),
                    _buildInvoiceRow(
                      'Total',
                      'LKR $totalDue',
                      isBold: true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpace.xl),

              // Pay with section
              Text(
                'Pay with',
                style: AppText.label.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppSpace.xs),

              // Option 1: Saved card
              if (hasCard) ...[
              Semantics(
                inMutuallyExclusiveGroup: true,
                checked: method == 0,
                child: GestureDetector(
                  onTap: () => setState(() => _selectedPaymentMethod = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.md,
                      vertical: AppSpace.md,
                    ),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        color: method == 0 ? c.textPrimary : c.border,
                        width: method == 0 ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          method == 0
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: c.textPrimary,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Text(
                            card,
                            style: AppText.title.copyWith(color: c.textPrimary),
                          ),
                        ),
                        Text(
                          'Default',
                          style: AppText.caption.copyWith(color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppSpace.xs),
              ],

              // Option 2: Attendant QR
              Semantics(
                inMutuallyExclusiveGroup: true,
                checked: method == 1,
                child: GestureDetector(
                  onTap: () => setState(() => _selectedPaymentMethod = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.md,
                      vertical: AppSpace.md,
                    ),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        color: method == 1 ? c.textPrimary : c.border,
                        width: method == 1 ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          method == 1
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: c.textPrimary,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Text(
                            'Pay attendant with QR invoice',
                            style: AppText.title.copyWith(color: c.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Pay CTA
              PrimaryButton(
                text: 'Pay LKR $totalDue',
                isLoading: _isProcessing,
                onPressed: () {
                  setState(() => _isProcessing = true);
                  Future.delayed(const Duration(milliseconds: 700), () {
                    if (mounted) {
                      widget.onPaymentCompleted(totalDue);
                    }
                  });
                },
              ),

              const SizedBox(height: AppSpace.xs),

              Center(
                child: Text(
                  'The barrier opens once payment is confirmed.',
                  style: AppText.caption.copyWith(color: c.textSecondary),
                ),
              ),

              const SizedBox(height: AppSpace.md),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInvoiceRow(String label, String amount, {bool isBold = false}) {
    final c = context.colors;
    final style = isBold
        ? AppText.title.copyWith(
            color: c.textPrimary,
            fontWeight: FontWeight.w700,
          )
        : AppText.body.copyWith(color: c.textPrimary);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(amount, style: style),
      ],
    );
  }
}
