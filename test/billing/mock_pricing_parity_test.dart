import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parking/data/services/billing/mock_pricing.dart';

void main() {
  final cases = jsonDecode(
    File('test/billing/pricing_cases.json').readAsStringSync(),
  ) as List;
  for (final value in cases) {
    final data = value as Map<String, dynamic>;
    test('backend pricing parity: ${data['name']}', () {
      final quote = mockQuote(
        bookingId: 'parity',
        entryTime: DateTime.parse(data['entry'] as String),
        exitTime: DateTime.parse(data['exit'] as String),
        rate: data['rate'] as int,
        extensionMinutes: data['extension_minutes'] as int,
        arrivalExtensionFee: data['arrival_fee'] as int,
      );
      expect(quote.total, data['total']);
      expect(quote.subtotal, data['subtotal']);
      expect(quote.surgeAmount, data['surge_amount']);
      expect(
        quote.lineItems.fold<int>(0, (sum, item) => sum + item.amount),
        quote.total,
      );
    });
  }
}
