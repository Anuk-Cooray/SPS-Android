enum ParkingEventType {
  booked,
  offered,
  accepted,
  declined,
  extended,
  cancelled,
  autoCancelled,
  checkedIn,
  completed;

  String get displayName => switch (this) {
        ParkingEventType.booked => 'Booked',
        ParkingEventType.offered => 'Upgrade Offered',
        ParkingEventType.accepted => 'Upgrade Accepted',
        ParkingEventType.declined => 'Upgrade Declined',
        ParkingEventType.extended => 'Arrival Extended',
        ParkingEventType.cancelled => 'Cancelled by User',
        ParkingEventType.autoCancelled => 'Auto-cancelled (No-show)',
        ParkingEventType.checkedIn => 'Checked In at Barrier',
        ParkingEventType.completed => 'Completed & Paid',
      };
}

class ParkingEvent {
  final String id;
  final String bookingId;
  final ParkingEventType type;
  final DateTime timestamp;
  final String description;
  final Map<String, dynamic> metadata;

  const ParkingEvent({
    required this.id,
    required this.bookingId,
    required this.type,
    required this.timestamp,
    required this.description,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookingId': bookingId,
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'description': description,
        'metadata': metadata,
      };

  factory ParkingEvent.fromJson(Map<String, dynamic> json) => ParkingEvent(
        id: json['id'] as String,
        bookingId: json['bookingId'] as String,
        type: ParkingEventType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => ParkingEventType.booked,
        ),
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        description: json['description'] as String? ?? '',
        metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
      );
}
