import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_buttons.dart';
import '../../data/models/booking_model.dart';
import '../../data/services/billing/mock_pricing.dart' show colomboTime;
import 'state/billing_state_manager.dart';
import 'widgets/demand_forecast_chart.dart';
import 'widgets/invoice_breakdown_card.dart';

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
  String _method = 'stripe';
  bool _didComplete = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    final state = context.read<BillingStateManager>();
    await state.loadBooking(widget.booking);
  }

  Future<void> _payOrRefresh(bool refresh) async {
    final state = context.read<BillingStateManager>();
    if (refresh) {
      await state.refreshInvoice();
    } else {
      await state.pay(_method);
    }
  }

  void _finishIfPaid(BillingStateManager state) {
    final invoice = state.invoice;
    if (mounted &&
        !_didComplete &&
        invoice != null &&
        invoice.isPaid &&
        state.exitToken?.invoiceId == invoice.id &&
        (state.exitToken?.isValidAt(DateTime.now()) ?? false) &&
        invoice.bookingId == widget.booking.id) {
      _didComplete = true;
      widget.onPaymentCompleted(invoice.quote.total);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.watch<BillingStateManager>();
    final quote = state.quote?.bookingId == widget.booking.id
        ? state.quote
        : null;
    final invoice = state.invoice?.bookingId == widget.booking.id
        ? state.invoice
        : null;
    final session = invoice == null ? null : state.session;
    final refresh =
        invoice != null &&
        ((invoice.status == 'pending' && session != null) ||
            (invoice.status == 'awaiting_guard' && _method == 'guard'));
    final exitToken = invoice?.isPaid == true ? state.exitToken : null;
    final canConfirmMock =
        refresh &&
        session?.provider == 'mock' &&
        session?.mockWebhookToken != null;
    final date = DateFormat('d MMM, HH:mm');
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.lg),
                children: [
                  Row(
                    children: [
                      Container(
                        width: AppSize.iconButton,
                        height: AppSize.iconButton,
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(AppRadius.input),
                          border: Border.all(color: c.border),
                        ),
                        child: IconButton(
                          tooltip: 'Back',
                          icon: Icon(
                            Icons.chevron_left_rounded,
                            color: c.textPrimary,
                          ),
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
                  Text(
                    'Sandbox billing · no real charges',
                    style: AppText.caption.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'Total due',
                    style: AppText.caption.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: AppSpace.xxs),
                  Text(
                    quote == null ? '—' : 'LKR ${quote.total}',
                    style: AppText.display.copyWith(
                      color: c.textPrimary,
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    widget.booking.lotName,
                    style: AppText.body.copyWith(color: c.textSecondary),
                  ),
                  if (quote != null) ...[
                    Text(
                      '${date.format(colomboTime(quote.entryTime))} – '
                      '${date.format(colomboTime(quote.exitTime))} · Colombo',
                      style: AppText.caption.copyWith(color: c.textSecondary),
                    ),
                    Text(
                      _duration(quote.exitTime.difference(quote.entryTime)),
                      style: AppText.body.copyWith(color: c.textSecondary),
                    ),
                    const SizedBox(height: AppSpace.xl),
                    InvoiceBreakdownCard(quote: quote),
                    const SizedBox(height: AppSpace.xs),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        'How this fee was calculated',
                        style: AppText.caption.copyWith(color: c.textSecondary),
                      ),
                      children: [
                        Text(
                          quote.explanation,
                          style: AppText.caption.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ] else if (state.error == null) ...[
                    const SizedBox(height: AppSpace.xl),
                    Center(
                      child: CircularProgressIndicator(color: c.textPrimary),
                    ),
                  ],
                  if (state.error != null) ...[
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      state.error!,
                      key: const Key('billing_error'),
                      style: AppText.body.copyWith(color: c.textPrimary),
                    ),
                    if (quote == null)
                      TertiaryButton(
                        text: 'Retry quote',
                        onPressed: state.isBusy ? null : _load,
                      ),
                  ],
                  if (quote != null) ...[
                    const SizedBox(height: AppSpace.xl),
                    Text(
                      'Pay with',
                      style: AppText.label.copyWith(color: c.textSecondary),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    _option('stripe', 'Visa •••• 4821 · Sandbox', state.isBusy),
                    const SizedBox(height: AppSpace.xs),
                    _option('payhere', 'PayHere · Sandbox', state.isBusy),
                    const SizedBox(height: AppSpace.xs),
                    _option('guard', 'Pay at booth (guard)', state.isBusy),
                  ],
                  if (invoice != null && !invoice.isPaid) ...[
                    const SizedBox(height: AppSpace.lg),
                    Text(
                      invoice.status == 'awaiting_guard'
                          ? 'Awaiting guard confirmation'
                          : invoice.status == 'failed'
                          ? 'Payment failed. Try again.'
                          : 'Awaiting sandbox payment confirmation',
                      style: AppText.title.copyWith(color: c.textPrimary),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    SelectableText(
                      'Invoice ${invoice.id}',
                      style: AppText.caption.copyWith(color: c.textSecondary),
                    ),
                    if (invoice.status == 'awaiting_guard') ...[
                      const SizedBox(height: AppSpace.sm),
                      Center(
                        child: QrImageView(
                          size: 150,
                          backgroundColor: Colors.white,
                          data: jsonEncode({
                            'type': 'parking_invoice',
                            'invoice_id': invoice.id,
                            'booking_id': invoice.bookingId,
                            'amount': invoice.quote.total,
                            'currency': 'LKR',
                          }),
                        ),
                      ),
                      Text(
                        'Invoice reference only · not an exit QR',
                        textAlign: TextAlign.center,
                        style: AppText.caption.copyWith(color: c.textSecondary),
                      ),
                    ],
                    if (session?.isMock ?? false)
                      Text(
                        'Mock session · no funds charged',
                        style: AppText.caption.copyWith(color: c.textSecondary),
                      ),
                  ],
                  if (invoice?.isPaid == true) ...[
                    const SizedBox(height: AppSpace.lg),
                    Text(
                      'Payment confirmed',
                      style: AppText.title.copyWith(color: c.textPrimary),
                    ),
                    if (exitToken != null) ...[
                      Center(
                        child: QrImageView(
                          size: 180,
                          backgroundColor: Colors.white,
                          data: exitToken.token,
                        ),
                      ),
                      Text(
                        exitToken.isMock
                            ? 'Offline demo pass · cannot open a gate'
                            : 'Paid exit pass · single use',
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        'Expires ${date.format(colomboTime(exitToken.expiresAt))} · Colombo',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                  if (state.isForecastLoading) ...[
                    const SizedBox(height: AppSpace.xl),
                    Text(
                      'Loading synthetic demand…',
                      style: AppText.caption.copyWith(color: c.textSecondary),
                    ),
                  ] else if (state.forecast.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xl),
                    DemandForecastChart(points: state.forecast),
                  ] else if (state.forecastError != null) ...[
                    const SizedBox(height: AppSpace.xl),
                    Text(
                      state.forecastError!,
                      style: AppText.caption.copyWith(color: c.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.sm,
                AppSpace.lg,
                AppSpace.md,
              ),
              child: Column(
                children: [
                  PrimaryButton(
                    text: invoice?.isPaid == true
                        ? (exitToken?.isValidAt(DateTime.now()) == true
                              ? 'Finish demo exit'
                              : 'Get exit pass')
                        : canConfirmMock
                        ? 'Confirm mock'
                        : refresh
                        ? 'Check status'
                        : _method == 'guard'
                        ? 'Pay at booth'
                        : 'Pay LKR ${quote?.total ?? '—'}',
                    isLoading: state.isBusy,
                    onPressed: quote == null || _didComplete
                        ? null
                        : () async {
                            if (invoice?.isPaid == true) {
                              if (state.exitToken?.isValidAt(DateTime.now()) ==
                                  true) {
                                _finishIfPaid(state);
                              } else {
                                await state.refreshInvoice();
                              }
                            } else if (canConfirmMock) {
                              await state.confirmMockPayment();
                            } else {
                              await _payOrRefresh(refresh);
                            }
                          },
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    'Payment must be confirmed before exit. Barrier integration is pending.',
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

  String _duration(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes == 0) return 'Parked less than 1 min';
    return 'Parked ${minutes ~/ 60} h ${minutes % 60} min';
  }

  Widget _option(String method, String label, bool busy) {
    final c = context.colors;
    final selected = _method == method;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: busy ? null : () => setState(() => _method = method),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: selected ? c.textPrimary : c.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: c.textPrimary,
                size: 20,
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Text(
                  label,
                  style: AppText.title.copyWith(color: c.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
