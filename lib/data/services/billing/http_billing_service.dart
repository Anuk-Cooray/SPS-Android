import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/billing/demand_forecast_point.dart';
import '../../models/billing/fee_quote.dart';
import '../../models/billing/invoice.dart';
import '../../models/billing/payment_session.dart';
import '../service_contracts.dart';

class BillingApiException implements Exception {
  final String code;
  final String message;
  const BillingApiException(this.code, this.message);
  @override
  String toString() => message;
}

/// Android/desktop transport using the Dart SDK, with no extra dependencies.
class HttpBillingService implements BillingService {
  final Uri baseUrl;
  final HttpClient _client;
  final Duration timeout;
  final Map<String, FeeQuote> _quotes = {};
  final Map<String, Invoice> _invoicesByBooking = {};

  HttpBillingService({
    String baseUrl = 'http://10.0.2.2:8000/',
    HttpClient? client,
    this.timeout = const Duration(seconds: 15),
  }) : baseUrl = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
       _client = client ?? HttpClient();

  void close() => _client.close(force: true);

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final uri = baseUrl.resolve('api/v1/$path').replace(queryParameters: query);
    try {
      final request = await _client.openUrl(method, uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      final decoded = jsonDecode(text);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (decoded is Map && decoded['error'] is Map) {
          final error = decoded['error'] as Map;
          throw BillingApiException(
            error['code'] as String,
            error['message'] as String,
          );
        }
        throw const BillingApiException(
          'HTTP_ERROR',
          'Billing request failed. Try again.',
        );
      }
      return decoded;
    } on TimeoutException {
      throw const BillingApiException(
        'TIMEOUT',
        'Billing server took too long. Please try again.',
      );
    } on HttpException {
      throw const BillingApiException(
        'HTTP_ERROR',
        'Billing connection failed. Please try again.',
      );
    } on SocketException {
      throw const BillingApiException(
        'CONNECTION',
        'Cannot reach billing server. Check its address and connection.',
      );
    } on FormatException {
      throw const BillingApiException(
        'INVALID_RESPONSE',
        'Billing server returned an invalid response.',
      );
    }
  }

  Map<String, dynamic> _object(Object? value) =>
      Map<String, dynamic>.from(value as Map);

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
  }) async {
    // Resume an existing invoice, including after the screen is reopened.
    final existing = _invoicesByBooking[bookingId];
    if (existing != null) {
      final latest = await getInvoice(existing.id);
      _quotes[bookingId] = latest.quote;
      return latest.quote;
    }
    final quote = FeeQuote.fromJson(
      _object(
        await _request(
          'POST',
          'billing/quote',
          body: {
            'booking_id': bookingId,
            'entry_time': entryTime.toUtc().toIso8601String(),
            'exit_time': exitTime.toUtc().toIso8601String(),
            'lot_id': lotId,
            'extension_minutes': extensionMinutes,
            'arrival_extension_fee': arrivalExtensionFee,
            'upgrade_from_slot_id': upgradeFromSlotId,
            'upgrade_to_slot_id': upgradeToSlotId,
          },
        ),
      ),
    );
    _quotes[bookingId] = quote;
    return quote;
  }

  @override
  Future<Invoice> createInvoice({
    required String bookingId,
    required FeeQuote quote,
  }) async {
    final existing = _invoicesByBooking[bookingId];
    if (existing != null) return getInvoice(existing.id);
    final invoice = Invoice.fromJson(
      _object(
        await _request(
          'POST',
          'billing/invoices',
          body: {'booking_id': bookingId, 'quote': quote.toJson()},
        ),
      ),
    );
    _invoicesByBooking[bookingId] = invoice;
    return invoice;
  }

  @override
  Future<PaymentSession> startPayment({
    required String invoiceId,
    required String method,
  }) async => PaymentSession.fromJson(
    _object(
      await _request(
        'POST',
        'billing/invoices/${Uri.encodeComponent(invoiceId)}/pay',
        body: {'method': method},
      ),
    ),
  );

  @override
  Future<Invoice> getInvoice(String invoiceId) async {
    final invoice = Invoice.fromJson(
      _object(
        await _request(
          'GET',
          'billing/invoices/${Uri.encodeComponent(invoiceId)}',
        ),
      ),
    );
    _invoicesByBooking[invoice.bookingId] = invoice;
    return invoice;
  }

  @override
  Future<List<DemandForecastPoint>> getDemandForecast({
    required String lotId,
    int horizonHours = 24,
  }) async {
    final data = await _request(
      'GET',
      'forecast/demand',
      query: {'lot_id': lotId, 'horizon_hours': '$horizonHours'},
    );
    return (data as List)
        .map((point) => DemandForecastPoint.fromJson(_object(point)))
        .toList();
  }

  @override
  Future<int> calculateFee({
    required String bookingId,
    required int parkedMinutes,
    required int extensionFee,
  }) async {
    // Legacy signature cannot identify lot or entry; use its already issued quote.
    final quote = _quotes[bookingId];
    if (quote == null) {
      throw StateError(
        'Request a quote first; legacy API has no lot or timestamps',
      );
    }
    return quote.total;
  }

  @override
  Future<bool> processPayment({
    required String bookingId,
    required int amount,
    required String paymentMethod,
  }) async {
    final quote = _quotes[bookingId];
    if (quote == null || quote.total != amount) {
      throw StateError('Request a matching quote first');
    }
    final invoice = await createInvoice(bookingId: bookingId, quote: quote);
    await startPayment(invoiceId: invoice.id, method: paymentMethod);
    return (await getInvoice(invoice.id)).isPaid;
  }
}
