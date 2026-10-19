import 'fee_quote.dart';

class Invoice {
  final String id;
  final String bookingId;
  final FeeQuote quote;
  final String status;

  const Invoice({
    required this.id,
    required this.bookingId,
    required this.quote,
    required this.status,
  });

  bool get isPaid => status == 'paid';

  Invoice withStatus(String value) =>
      Invoice(id: id, bookingId: bookingId, quote: quote, status: value);

  factory Invoice.fromJson(Map<String, dynamic> json) => Invoice(
    id: json['id'] as String,
    bookingId: json['booking_id'] as String,
    quote: FeeQuote.fromJson(Map<String, dynamic>.from(json['quote'] as Map)),
    status: json['status'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'booking_id': bookingId,
    'quote': quote.toJson(),
    'status': status,
  };
}
