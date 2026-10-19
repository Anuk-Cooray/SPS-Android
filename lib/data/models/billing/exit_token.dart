/// A paid invoice's short-lived pass. Offline passes cannot authorize a gate.
class ExitToken {
  final String invoiceId;
  final String token;
  final DateTime expiresAt;
  final bool isMock;
  const ExitToken({
    required this.invoiceId,
    required this.token,
    required this.expiresAt,
    this.isMock = false,
  });
  bool isValidAt(DateTime now) => expiresAt.isAfter(now);
  factory ExitToken.fromJson(Map<String, dynamic> json) => ExitToken(
    invoiceId: json['invoice_id'] as String,
    token: json['token'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
    isMock: json['is_mock'] as bool? ?? false,
  );
}
