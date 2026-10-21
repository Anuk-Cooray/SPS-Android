import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../data/models/booking_model.dart';

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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final baseFee = widget.booking.estimatedFee;
    final extFee = widget.booking.extensionFee > 0 ? widget.booking.extensionFee : 50;
    final totalDue = baseFee + extFee;

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
                '${widget.booking.lotName} · 10:21 AM – 12:35 PM',
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
                    _buildInvoiceRow('Parking · 2 h 14 min', 'LKR $baseFee'),
                    const SizedBox(height: AppSpace.sm),
                    _buildInvoiceRow('Extension · 15 min', 'LKR $extFee'),
                    const SizedBox(height: AppSpace.sm),
                    _buildInvoiceRow(
                      'Upgrade ${widget.booking.originalSlotId ?? 'A-06'} → ${widget.booking.slotId}',
                      'LKR 0',
                    ),
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
              GestureDetector(
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
                      color: _selectedPaymentMethod == 0 ? c.textPrimary : c.border,
                      width: _selectedPaymentMethod == 0 ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedPaymentMethod == 0
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: c.textPrimary,
                        size: 20,
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Text(
                          'Visa •••• 4821',
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

              const SizedBox(height: AppSpace.xs),

              // Option 2: Attendant QR
              GestureDetector(
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
                      color: _selectedPaymentMethod == 1 ? c.textPrimary : c.border,
                      width: _selectedPaymentMethod == 1 ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedPaymentMethod == 1
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
