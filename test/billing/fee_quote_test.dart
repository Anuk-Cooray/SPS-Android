import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parking/data/models/billing/fee_quote.dart';
import 'package:smart_parking/data/models/billing/invoice.dart';
import 'package:smart_parking/data/models/billing/payment_session.dart';
import 'package:smart_parking/data/models/billing/demand_forecast_point.dart';
import 'package:smart_parking/data/services/billing/mock_billing_service.dart';

void main() {
  final entry = DateTime.parse('2026-10-19T10:00:00+05:30');
  late MockBillingService service;
  setUp(() => service = MockBillingService());

  Future<FeeQuote> quote(int minutes, {String lot = 'lot-main'}) =>
      service.quoteFee(
        bookingId: 'booking',
        entryTime: entry,
        exitTime: entry.add(Duration(minutes: minutes)),
        lotId: lot,
      );

  test(
    'mock grace and block rounding use whole LKR and selected lot rate',
    () async {
      expect((await quote(10)).total, 0);
      expect((await quote(60)).total, 100);
      expect((await quote(61)).total, 125);
      expect((await quote(60, lot: 'lot-new-p2')).total, 80);
      expect((await quote(60, lot: 'lot-sports')).total, 50);
    },
  );

  test(
    'quote and nested invoice round trip with UTC and immutable items',
    () async {
      final original = await quote(60);
      final restored = FeeQuote.fromJson(original.toJson());
      expect(restored.toJson(), original.toJson());
      expect(restored.entryTime.isUtc, isTrue);
      expect(() => restored.lineItems.clear(), throwsUnsupportedError);
      final invoice = await service.createInvoice(
        bookingId: 'booking',
        quote: original,
      );
      expect(Invoice.fromJson(invoice.toJson()).toJson(), invoice.toJson());
    },
  );

  test('invalid duration and unknown lot are rejected', () async {
    await expectLater(quote(0), throwsArgumentError);
    await expectLater(quote(-1), throwsArgumentError);
    await expectLater(quote(60, lot: 'missing'), throwsArgumentError);
  });

  test('extension uses integer half-up rounding', () async {
    final result = await service.quoteFee(
      bookingId: 'booking',
      entryTime: entry,
      exitTime: entry.add(const Duration(hours: 1)),
      lotId: 'lot-sports',
      extensionMinutes: 20,
    );
    expect(result.total, 58); // 50 + round-half-up(20/60 * 50 * 0.5).
  });

  test('forecast points and payment sessions round trip', () async {
    final points = await service.getDemandForecast(lotId: 'lot-main');
    expect(points, hasLength(24));
    expect(
      DemandForecastPoint.fromJson(points.first.toJson()).toJson(),
      points.first.toJson(),
    );
    final invoice = await service.createInvoice(
      bookingId: 'booking',
      quote: await quote(60),
    );
    final session = await service.startPayment(
      invoiceId: invoice.id,
      method: 'stripe',
    );
    expect(
      PaymentSession.fromJson(session.toJson()).toJson(),
      session.toJson(),
    );
    expect(session.isMock, isTrue);
  });
}
