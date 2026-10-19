class AdminAlert {
  final String id;
  final String lotId;
  final String slotId;
  final String? bookingId;
  final String type; // 'slot_conflict' | 'vacated_without_payment' | 'unauthorized_parking'
  final String severity; // 'warning' | 'critical' | 'info'
  final DateTime timestamp;
  final String description;
  final bool resolved;
  final Map<String, dynamic>? metadata;

  const AdminAlert({
    required this.id,
    required this.lotId,
    required this.slotId,
    this.bookingId,
    required this.type,
    required this.severity,
    required this.timestamp,
    required this.description,
    this.resolved = false,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'lotId': lotId,
        'slotId': slotId,
        'bookingId': bookingId,
        'type': type,
        'severity': severity,
        'timestamp': timestamp.toIso8601String(),
        'description': description,
        'resolved': resolved,
        'metadata': metadata,
      };

  factory AdminAlert.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val is DateTime) return val;
      if (val is String && val.isNotEmpty) {
        return DateTime.tryParse(val) ?? DateTime.now();
      }
      try {
        return (val as dynamic).toDate() as DateTime;
      } catch (_) {
        return DateTime.now();
      }
    }

    return AdminAlert(
      id: json['id'] as String? ?? '',
      lotId: json['lotId'] as String? ?? '',
      slotId: json['slotId'] as String? ?? '',
      bookingId: json['bookingId'] as String?,
      type: json['type'] as String? ?? 'slot_conflict',
      severity: json['severity'] as String? ?? 'warning',
      timestamp: parseDate(json['timestamp']),
      description: json['description'] as String? ?? '',
      resolved: json['resolved'] as bool? ?? false,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  AdminAlert copyWith({
    String? id,
    String? lotId,
    String? slotId,
    String? bookingId,
    String? type,
    String? severity,
    DateTime? timestamp,
    String? description,
    bool? resolved,
    Map<String, dynamic>? metadata,
  }) {
    return AdminAlert(
      id: id ?? this.id,
      lotId: lotId ?? this.lotId,
      slotId: slotId ?? this.slotId,
      bookingId: bookingId ?? this.bookingId,
      type: type ?? this.type,
      severity: severity ?? this.severity,
      timestamp: timestamp ?? this.timestamp,
      description: description ?? this.description,
      resolved: resolved ?? this.resolved,
      metadata: metadata ?? this.metadata,
    );
  }
}
