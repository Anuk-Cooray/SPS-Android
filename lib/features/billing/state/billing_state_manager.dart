import 'package:flutter/foundation.dart';

import '../../../data/models/booking_model.dart';
import '../../../data/models/billing/demand_forecast_point.dart';
import '../../../data/models/billing/fee_quote.dart';
import '../../../data/models/billing/invoice.dart';
import '../../../data/models/billing/payment_session.dart';
import '../../../data/services/service_contracts.dart';
import '../../../data/services/billing/http_billing_service.dart';

/// Billing owns quotes/settlement; the caller alone finalizes a parking booking.
class BillingStateManager extends ChangeNotifier {
  final BillingService service;
  FeeQuote? _quote;
  Invoice? _invoice;
  PaymentSession? _session;
  List<DemandForecastPoint> _forecast = const [];
  bool _isBusy = false;
  bool _isForecastLoading = false;
  bool _disposed = false;
  String? _error;
  String? _forecastError;
  int _forecastRequest = 0;

  BillingStateManager({required this.service});

  FeeQuote? get quote => _quote;
  Invoice? get invoice => _invoice;
  PaymentSession? get session => _session;
  List<DemandForecastPoint> get forecast => _forecast;
  bool get isBusy => _isBusy;
  bool get isForecastLoading => _isForecastLoading;
  String? get error => _error;
  String? get forecastError => _forecastError;
  bool get isPaid => _invoice?.isPaid ?? false;

  Future<void> loadBooking(Booking booking, {DateTime? now}) async {
    if (_isBusy || _disposed) return;
    final entry = booking.checkedInAt;
    if (entry == null) {
      _quote = null;
      _invoice = null;
      _session = null;
      _forecast = const [];
      _forecastRequest++;
      _isForecastLoading = false;
      _forecastError = null;
      _error = 'Check in before paying for parking.';
      _notify();
      return;
    }
    // A previously invoiced visit resumes that invoice; do not silently reprice it.
    if (_invoice?.bookingId == booking.id) {
      await refreshInvoice();
    } else {
      await prepareQuote(
        bookingId: booking.id,
        entryTime: entry,
        exitTime: now ?? DateTime.now(),
        lotId: booking.lotId,
        arrivalExtensionFee: booking.extensionFee,
        upgradeFromSlotId: booking.originalSlotId,
        upgradeToSlotId: booking.originalSlotId == null ? null : booking.slotId,
      );
    }
    if (!_disposed) await loadForecast(booking.lotId);
  }

  Future<void> prepareQuote({
    required String bookingId,
    required DateTime entryTime,
    required DateTime exitTime,
    required String lotId,
    int extensionMinutes = 0,
    int arrivalExtensionFee = 0,
    String? upgradeFromSlotId,
    String? upgradeToSlotId,
  }) async {
    if (_isBusy || _disposed) return;
    _quote = null;
    _invoice = null;
    _session = null;
    _forecast = const [];
    _forecastError = null;
    _isForecastLoading = false;
    _forecastRequest++;
    await _run(() async {
      _quote = await service.quoteFee(
        bookingId: bookingId,
        entryTime: entryTime,
        exitTime: exitTime,
        lotId: lotId,
        extensionMinutes: extensionMinutes,
        arrivalExtensionFee: arrivalExtensionFee,
        upgradeFromSlotId: upgradeFromSlotId,
        upgradeToSlotId: upgradeToSlotId,
      );
    });
  }

  Future<void> loadForecast(String lotId) async {
    if (_disposed) return;
    final request = ++_forecastRequest;
    _isForecastLoading = true;
    _forecastError = null;
    _notify();
    try {
      final points = await service.getDemandForecast(lotId: lotId);
      if (!_disposed && request == _forecastRequest) {
        _forecast = List.unmodifiable(points);
      }
    } catch (_) {
      if (!_disposed && request == _forecastRequest) {
        _forecastError = 'Demand forecast unavailable. Your quote is still shown separately.';
      }
    } finally {
      if (!_disposed && request == _forecastRequest) {
        _isForecastLoading = false;
        _notify();
      }
    }
  }

  Future<void> pay(String method) async {
    if (_isBusy || _disposed) return;
    await _run(() async {
      final current = _quote;
      if (current == null) throw StateError('Request a quote first');
      _invoice ??= await service.createInvoice(
        bookingId: current.bookingId,
        quote: current,
      );
      _session = await service.startPayment(
        invoiceId: _invoice!.id,
        method: method,
      );
      // A checkout session (including a backend mock session) is not proof of payment.
      _invoice = await service.getInvoice(_invoice!.id);
    });
  }

  Future<void> refreshInvoice() async {
    if (_isBusy || _disposed) return;
    await _run(() async {
      final current = _invoice;
      if (current == null) throw StateError('Create an invoice first');
      _invoice = await service.getInvoice(current.id);
      _quote = _invoice!.quote;
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    _isBusy = true;
    _error = null;
    _notify();
    try {
      await action();
    } catch (error) {
      _error = error.toString();
    } finally {
      _isBusy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (service is HttpBillingService) (service as HttpBillingService).close();
    super.dispose();
  }
}
