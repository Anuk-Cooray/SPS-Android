import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parking/data/models/billing/invoice.dart';
import 'package:smart_parking/data/services/billing/http_billing_service.dart';

void main() {
  late HttpServer server;
  late HttpBillingService service;
  late Map<String, dynamic> issuedQuote;
  final requests = <Map<String, dynamic>>[];
  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    service = HttpBillingService(baseUrl: 'http://127.0.0.1:${server.port}/');
    issuedQuote = {
      'booking_id': 'BK-HTTP',
      'entry_time': '2026-10-19T04:30:00Z',
      'exit_time': '2026-10-19T05:30:00Z',
      'line_items': [
        {'label': 'Parking', 'qty': 4, 'unit': 'block', 'amount': 100},
      ],
      'subtotal': 100,
      'surge_amount': 0,
      'total': 100,
      'currency': 'LKR',
      'explanation': 'Test quote',
    };
  });
  tearDown(() async {
    service.close();
    await server.close(force: true);
  });

  test(
    'quote/invoice/pay/status use API JSON and never infer paid from a session',
    () async {
      server.listen((request) async {
        final text = await utf8.decoder.bind(request).join();
        final body = text.isEmpty ? null : jsonDecode(text);
        requests.add({
          'method': request.method,
          'path': request.uri.path,
          'body': body,
        });
        Object response;
        if (request.uri.path == '/api/v1/billing/quote') {
          response = issuedQuote;
        } else if (request.uri.path.endsWith('/pay')) {
          response = {
            'id': 'session',
            'invoice_id': 'invoice',
            'method': 'stripe',
            'provider': 'mock',
            'status': 'pending',
            'is_mock': true,
            'message': 'Mock pending',
            'checkout_url': null,
          };
        } else {
          response = {
            'id': 'invoice',
            'booking_id': 'BK-HTTP',
            'quote': issuedQuote,
            'status': 'pending',
          };
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
      });
      final quote = await service.quoteFee(
        bookingId: 'BK-HTTP',
        entryTime: DateTime.parse('2026-10-19T10:00:00+05:30'),
        exitTime: DateTime.parse('2026-10-19T11:00:00+05:30'),
        lotId: 'lot-main',
        arrivalExtensionFee: 50,
      );
      final firstBody = requests.first['body'] as Map;
      expect(firstBody['entry_time'], '2026-10-19T04:30:00.000Z');
      expect(firstBody['arrival_extension_fee'], 50);
      expect(firstBody['extension_minutes'], 0);
      final invoice = await service.createInvoice(
        bookingId: 'BK-HTTP',
        quote: quote,
      );
      final session = await service.startPayment(
        invoiceId: invoice.id,
        method: 'stripe',
      );
      expect(session.status, 'pending');
      expect((await service.getInvoice(invoice.id)).isPaid, isFalse);
      expect(
        await service.processPayment(
          bookingId: 'BK-HTTP',
          amount: 100,
          paymentMethod: 'stripe',
        ),
        isFalse,
      );
      final resumed = await service.quoteFee(
        bookingId: 'BK-HTTP',
        entryTime: quote.entryTime,
        exitTime: quote.exitTime.add(const Duration(hours: 1)),
        lotId: 'lot-main',
      );
      expect(resumed.total, 100);
      expect(
        requests.where((entry) => entry['path'] == '/api/v1/billing/quote'),
        hasLength(1),
      );
      expect(Invoice.fromJson(invoice.toJson()).toJson(), invoice.toJson());
    },
  );

  test('API error envelope is shown as a readable error', () async {
    server.listen((request) async {
      request.response.statusCode = 503;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'error': {
            'code': 'FORECAST_UNAVAILABLE',
            'message': 'Train the demo model first',
          },
        }),
      );
      await request.response.close();
    });
    await expectLater(
      service.getDemandForecast(lotId: 'lot-main'),
      throwsA(
        isA<BillingApiException>()
            .having((error) => error.code, 'code', 'FORECAST_UNAVAILABLE')
            .having(
              (error) => error.toString(),
              'message',
              'Train the demo model first',
            ),
      ),
    );
  });

  test('forecast query and fractions deserialize', () async {
    server.listen((request) async {
      expect(request.uri.queryParameters, {
        'lot_id': 'lot-main',
        'horizon_hours': '1',
      });
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode([
          {
            'ts': '2026-10-19T03:30:00Z',
            'yhat': 0.7,
            'yhat_lower': 0.6,
            'yhat_upper': 0.8,
            'demand_level': 0.7,
          },
        ]),
      );
      await request.response.close();
    });
    final points = await service.getDemandForecast(
      lotId: 'lot-main',
      horizonHours: 1,
    );
    expect(points.single.ts.isUtc, isTrue);
    expect(points.single.demandLevel, 0.7);
  });
}
