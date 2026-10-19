class PaymentSession {
  final String id;
  final String invoiceId;
  final String method;
  final String status;
  final bool isMock;
  final String provider;
  final String? checkoutUrl;
  final String message;

  const PaymentSession({
    required this.id,
    required this.invoiceId,
    required this.method,
    required this.status,
    required this.isMock,
    this.provider = 'mock',
    this.checkoutUrl,
    this.message = '',
  });

  factory PaymentSession.fromJson(Map<String, dynamic> json) => PaymentSession(
    id: json['id'] as String,
    invoiceId: json['invoice_id'] as String,
    method: json['method'] as String,
    status: json['status'] as String,
    isMock: json['is_mock'] as bool,
    provider: json['provider'] as String,
    checkoutUrl: json['checkout_url'] as String?,
    message: json['message'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'invoice_id': invoiceId,
    'method': method,
    'status': status,
    'is_mock': isMock,
    'provider': provider,
    'checkout_url': checkoutUrl,
    'message': message,
  };
}
