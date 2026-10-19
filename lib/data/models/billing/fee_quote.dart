import 'invoice_line_item.dart';

class FeeQuote {
  final String bookingId;
  final DateTime entryTime;
  final DateTime exitTime;
  final List<InvoiceLineItem> lineItems;
  final int subtotal;
  final int surgeAmount;
  final int total;
  final String currency;
  final String explanation;

  FeeQuote({
    required this.bookingId,
    required DateTime entryTime,
    required DateTime exitTime,
    required List<InvoiceLineItem> lineItems,
    required this.subtotal,
    required this.surgeAmount,
    required this.total,
    this.currency = 'LKR',
    required this.explanation,
  }) : entryTime = entryTime.toUtc(),
       exitTime = exitTime.toUtc(),
       lineItems = List.unmodifiable(lineItems);

  factory FeeQuote.fromJson(Map<String, dynamic> json) => FeeQuote(
    bookingId: json['booking_id'] as String,
    entryTime: DateTime.parse(json['entry_time'] as String),
    exitTime: DateTime.parse(json['exit_time'] as String),
    lineItems: (json['line_items'] as List)
        .map(
          (item) =>
              InvoiceLineItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    subtotal: json['subtotal'] as int,
    surgeAmount: json['surge_amount'] as int,
    total: json['total'] as int,
    currency: json['currency'] as String,
    explanation: json['explanation'] as String,
  );

  Map<String, dynamic> toJson() => {
    'booking_id': bookingId,
    'entry_time': entryTime.toIso8601String(),
    'exit_time': exitTime.toIso8601String(),
    'line_items': lineItems.map((item) => item.toJson()).toList(),
    'subtotal': subtotal,
    'surge_amount': surgeAmount,
    'total': total,
    'currency': currency,
    'explanation': explanation,
  };
}
