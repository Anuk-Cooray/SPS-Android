/// Amounts are whole LKR; quantity is an integer count of units.
class InvoiceLineItem {
  final String label;
  final int qty;
  final String unit;
  final int amount;

  const InvoiceLineItem({
    required this.label,
    required this.qty,
    required this.unit,
    required this.amount,
  });

  factory InvoiceLineItem.fromJson(Map<String, dynamic> json) =>
      InvoiceLineItem(
        label: json['label'] as String,
        qty: json['qty'] as int,
        unit: json['unit'] as String,
        amount: json['amount'] as int,
      );

  Map<String, dynamic> toJson() => {
    'label': label,
    'qty': qty,
    'unit': unit,
    'amount': amount,
  };
}
