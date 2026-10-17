enum BookingStatus {
  reserved,
  upgraded,
  checkedIn,
  extended,
  completed,
  autoCancelled,
  cancelled;

  String get displayName => switch (this) {
        BookingStatus.reserved => 'Reserved',
        BookingStatus.upgraded => 'Upgraded',
        BookingStatus.checkedIn => 'Checked In',
        BookingStatus.extended => 'Extended',
        BookingStatus.completed => 'Completed',
        BookingStatus.autoCancelled => 'Auto-cancelled',
        BookingStatus.cancelled => 'Cancelled',
      };
}

class Booking {
  final String id;
  final String userId;
  final String vehicleId;
  final String vehiclePlate;
  final String lotId;
  final String lotName;
  final String slotId;
  final DateTime bookedAt;
  final DateTime arrivalTime;
  final int durationHours;
  final BookingStatus status;
  final String? originalSlotId;
  final int distanceSavedMeters;
  final int estimatedFee;
  final int extensionFee;
  final int finalFee;
  final String qrToken;
  final DateTime? checkedInAt;
  final DateTime? completedAt;

  const Booking({
    required this.id,
    required this.userId,
    required this.vehicleId,
    required this.vehiclePlate,
    required this.lotId,
    required this.lotName,
    required this.slotId,
    required this.bookedAt,
    required this.arrivalTime,
    required this.durationHours,
    required this.status,
    this.originalSlotId,
    this.distanceSavedMeters = 0,
    required this.estimatedFee,
    this.extensionFee = 0,
    this.finalFee = 0,
    required this.qrToken,
    this.checkedInAt,
    this.completedAt,
  });

  DateTime get cancelDeadline => arrivalTime.add(const Duration(minutes: 15));
  DateTime get lateWarningTime => arrivalTime.add(const Duration(minutes: 10));

  bool get isActive =>
      status == BookingStatus.reserved ||
      status == BookingStatus.upgraded ||
      status == BookingStatus.extended ||
      status == BookingStatus.checkedIn;

  Booking copyWith({
    String? id,
    String? userId,
    String? vehicleId,
    String? vehiclePlate,
    String? lotId,
    String? lotName,
    String? slotId,
    DateTime? bookedAt,
    DateTime? arrivalTime,
    int? durationHours,
    BookingStatus? status,
    String? originalSlotId,
    int? distanceSavedMeters,
    int? estimatedFee,
    int? extensionFee,
    int? finalFee,
    String? qrToken,
    DateTime? checkedInAt,
    DateTime? completedAt,
  }) {
    return Booking(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      vehicleId: vehicleId ?? this.vehicleId,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
      lotId: lotId ?? this.lotId,
      lotName: lotName ?? this.lotName,
      slotId: slotId ?? this.slotId,
      bookedAt: bookedAt ?? this.bookedAt,
      arrivalTime: arrivalTime ?? this.arrivalTime,
      durationHours: durationHours ?? this.durationHours,
      status: status ?? this.status,
      originalSlotId: originalSlotId ?? this.originalSlotId,
      distanceSavedMeters: distanceSavedMeters ?? this.distanceSavedMeters,
      estimatedFee: estimatedFee ?? this.estimatedFee,
      extensionFee: extensionFee ?? this.extensionFee,
      finalFee: finalFee ?? this.finalFee,
      qrToken: qrToken ?? this.qrToken,
      checkedInAt: checkedInAt ?? this.checkedInAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
