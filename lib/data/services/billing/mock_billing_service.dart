import '../../models/billing/demand_forecast_point.dart';
import '../../models/billing/fee_quote.dart';
import '../../models/billing/invoice.dart';
import 'mock_pricing.dart';
import '../../models/billing/payment_session.dart';
import '../service_contracts.dart';

/// Offline synthetic demo. Rules mirror the backend; digital settlement is simulated.
class MockBillingService implements BillingService {
  static const _rates = {'lot-main': 100, 'lot-new-p2': 80, 'lot-sports': 50};
  final Map<String, Invoice> _invoices = {};
  int _sequence = 0;

  int _rate(String lotId) =>
      _rates[lotId] ??
      (throw ArgumentError.value(lotId, 'lotId', 'Unknown lot'));

  int _baseFee(int minutes, int rate) {
    if (minutes <= 10) return 0;
    // Round duration up to 15-minute blocks, then round half up to LKR.
    return (((minutes + 14) ~/ 15) * rate + 2) ~/ 4;
  }

  @override
  Future<int> calculateFee({
    required String bookingId,
    required int parkedMinutes,
    required int extensionFee,
  }) async {
    if (parkedMinutes < 0 || extensionFee < 0) {
      throw ArgumentError('Duration and extension fee must be non-negative');
    }
    // Legacy API has no lot ID: explicitly use the main-lot rate.
    return _baseFee(parkedMinutes, 100) + extensionFee;
  }

  @override
  Future<FeeQuote> quoteFee({
    required String bookingId,
    required DateTime entryTime,
    required DateTime exitTime,
    required String lotId,
    int extensionMinutes = 0,
    int arrivalExtensionFee = 0,
    String? upgradeFromSlotId,
    String? upgradeToSlotId,
  }) async => mockQuote(
    bookingId: bookingId,
    entryTime: entryTime,
    exitTime: exitTime,
    rate: _rate(lotId),
    extensionMinutes: extensionMinutes,
    arrivalExtensionFee: arrivalExtensionFee,
    upgradeFromSlotId: upgradeFromSlotId,
    upgradeToSlotId: upgradeToSlotId,
  );

  @override
  Future<Invoice> createInvoice({
    required String bookingId,
    required FeeQuote quote,
  }) async {
    if (quote.bookingId != bookingId) throw ArgumentError('Booking mismatch');
    final invoice = Invoice(
      id: 'mock-invoice-${++_sequence}',
      bookingId: bookingId,
      quote: quote,
      status: 'pending',
    );
    _invoices[invoice.id] = invoice;
    return invoice;
  }

  @override
  Future<Invoice> getInvoice(String invoiceId) async =>
      _invoices[invoiceId] ?? (throw StateError('Invoice not found'));

  @override
  Future<PaymentSession> startPayment({
    required String invoiceId,
    required String method,
  }) async {
    if (!{'payhere', 'stripe', 'guard'}.contains(method)) {
      throw ArgumentError.value(method, 'method', 'Unsupported payment method');
    }
    final invoice = await getInvoice(invoiceId);
    // Digital payments simulate confirmation in this explicitly mock provider.
    // A guard selection can never downgrade an already paid invoice.
    final status = invoice.isPaid
        ? 'paid'
        : method == 'guard'
        ? 'awaiting_guard'
        : 'paid';
    _invoices[invoiceId] = invoice.withStatus(status);
    return PaymentSession(
      id: 'mock-payment-${++_sequence}',
      invoiceId: invoiceId,
      method: method,
      status: status,
      isMock: true,
      provider: 'mock',
      message: method == 'guard'
          ? 'Awaiting guard confirmation; no funds charged.'
          : 'Offline simulation only; no funds charged.',
    );
  }

  @override
  Future<bool> processPayment({
    required String bookingId,
    required int amount,
    required String paymentMethod,
  }) async {
    final matches = _invoices.values
        .where(
          (invoice) =>
              invoice.bookingId == bookingId && invoice.quote.total == amount,
        )
        .toList();
    if (matches.isEmpty) throw StateError('Create a matching invoice first');
    final session = await startPayment(
      invoiceId: matches.last.id,
      method: paymentMethod,
    );
    return session.status == 'paid';
  }

  @override
  Future<List<DemandForecastPoint>> getDemandForecast({
    required String lotId,
    int horizonHours = 24,
  }) async {
    _rate(lotId);
    if (horizonHours < 1 || horizonHours > 168) {
      throw ArgumentError('Horizon must be between 1 and 168 hours');
    }
    final now = DateTime.now().toUtc();
    final local = colomboTime(now);
    final start = DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour,
    ).add(const Duration(hours: 1)).subtract(colomboOffset);
    return List.generate(horizonHours, (index) {
      final ts = start.add(Duration(hours: index));
      final level = mockDemandPermille(ts) / 1000;
      return DemandForecastPoint(
        ts: ts,
        yhat: level,
        yhatLower: level - 0.1,
        yhatUpper: level + 0.1,
        demandLevel: level,
      );
    });
  }
}
