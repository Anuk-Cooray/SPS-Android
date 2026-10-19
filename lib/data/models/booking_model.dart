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

class BookingCharge {
  final String id;
  final String type; // 'parking' | 'extension' | 'upgrade'
  final int amount;
  final String currency;
  final DateTime timestamp;
  final String description;

  const BookingCharge({
    required this.id,
    required this.type,
    required this.amount,
    this.currency = 'LKR',
    required this.timestamp,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'amount': amount,
        'currency': currency,
        'timestamp': timestamp.toIso8601String(),
        'description': description,
      };

  factory BookingCharge.fromJson(Map<String, dynamic> json) => BookingCharge(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? 'parking',
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        currency: json['currency'] as String? ?? 'LKR',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        description: json['description'] as String? ?? '',
      );
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
  final List<BookingCharge> charges;
  final bool reallocatedDueToConflict;
  final String? reallocatedFromSlotId;
  final String qrToken;
  final DateTime? checkedInAt;
  final DateTime? completedAt;
  final DateTime? holdExpiresAt;
  final double predictedEtaMinBaseline;
  final double predictedEtaMinProvider;
  final double predictedEtaMinCorrected;
  final String modelVersion;
  final String weightsVersion;

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
    this.charges = const [],
    this.reallocatedDueToConflict = false,
    this.reallocatedFromSlotId,
    required this.qrToken,
    this.checkedInAt,
    this.completedAt,
    this.holdExpiresAt,
    this.predictedEtaMinBaseline = 0.0,
    this.predictedEtaMinProvider = 0.0,
    this.predictedEtaMinCorrected = 0.0,
    this.modelVersion = 'v1.0.0-linear',
    this.weightsVersion = 'v1.0.0',
  });

  DateTime get cancelDeadline => arrivalTime.add(const Duration(minutes: 15));
  DateTime get lateWarningTime => arrivalTime.add(const Duration(minutes: 10));

  DateTime get effectiveHoldDeadline => holdExpiresAt ?? cancelDeadline;

  /// True if the driver is currently driving toward the parking lot before scheduled arrival
  bool get isInTransit => DateTime.now().isBefore(arrivalTime);

  /// Duration remaining until the driver is scheduled to arrive at the parking facility
  Duration get timeUntilArrival {
    final diff = arrivalTime.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// True if the scheduled arrival time has been reached and the 15m barrier hold is actively ticking
  bool get isHoldWindowActive => !isInTransit && !isHoldExpired;

  /// Remaining duration of the guaranteed 15m barrier hold window
  Duration get remainingHoldDuration {
    // If in transit and no custom accelerated hold expiration is active, hold window has not started
    if (isInTransit && holdExpiresAt == null) {
      return const Duration(minutes: 15);
    }
    final diff = effectiveHoldDeadline.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// True if hold deadline has elapsed after scheduled arrival (triggering auto-release)
  bool get isHoldExpired {
    // In-transit bookings never expire before their arrival time unless explicitly fast-forwarded
    if (isInTransit && holdExpiresAt == null) {
      return false;
    }
    return DateTime.now().isAfter(effectiveHoldDeadline);
  }

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
    List<BookingCharge>? charges,
    bool? reallocatedDueToConflict,
    String? reallocatedFromSlotId,
    String? qrToken,
    DateTime? checkedInAt,
    DateTime? completedAt,
    DateTime? holdExpiresAt,
    double? predictedEtaMinBaseline,
    double? predictedEtaMinProvider,
    double? predictedEtaMinCorrected,
    String? modelVersion,
    String? weightsVersion,
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
      charges: charges ?? this.charges,
      reallocatedDueToConflict:
          reallocatedDueToConflict ?? this.reallocatedDueToConflict,
      reallocatedFromSlotId:
          reallocatedFromSlotId ?? this.reallocatedFromSlotId,
      qrToken: qrToken ?? this.qrToken,
      checkedInAt: checkedInAt ?? this.checkedInAt,
      completedAt: completedAt ?? this.completedAt,
      holdExpiresAt: holdExpiresAt ?? this.holdExpiresAt,
      predictedEtaMinBaseline:
          predictedEtaMinBaseline ?? this.predictedEtaMinBaseline,
      predictedEtaMinProvider:
          predictedEtaMinProvider ?? this.predictedEtaMinProvider,
      predictedEtaMinCorrected:
          predictedEtaMinCorrected ?? this.predictedEtaMinCorrected,
      modelVersion: modelVersion ?? this.modelVersion,
      weightsVersion: weightsVersion ?? this.weightsVersion,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'vehicleId': vehicleId,
        'vehiclePlate': vehiclePlate,
        'lotId': lotId,
        'lotName': lotName,
        'slotId': slotId,
        'bookedAt': bookedAt.toIso8601String(),
        'arrivalTime': arrivalTime.toIso8601String(),
        'durationHours': durationHours,
        'status': status.name,
        'originalSlotId': originalSlotId,
        'distanceSavedMeters': distanceSavedMeters,
        'estimatedFee': estimatedFee,
        'extensionFee': extensionFee,
        'finalFee': finalFee,
        'charges': charges.map((c) => c.toJson()).toList(),
        'reallocatedDueToConflict': reallocatedDueToConflict,
        'reallocatedFromSlotId': reallocatedFromSlotId,
        'qrToken': qrToken,
        'checkedInAt': checkedInAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'holdExpiresAt': holdExpiresAt?.toIso8601String(),
        'predictedEtaMinBaseline': predictedEtaMinBaseline,
        'predictedEtaMinProvider': predictedEtaMinProvider,
        'predictedEtaMinCorrected': predictedEtaMinCorrected,
        'modelVersion': modelVersion,
        'weightsVersion': weightsVersion,
      };

  static DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is DateTime) return val;
    if (val is String && val.isNotEmpty) return DateTime.tryParse(val);
    try {
      return (val as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  factory Booking.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'] as String? ?? 'reserved';
    final status = switch (rawStatus) {
      'auto_released' || 'autoCancelled' => BookingStatus.autoCancelled,
      'upgraded' => BookingStatus.upgraded,
      'checkedIn' => BookingStatus.checkedIn,
      'extended' => BookingStatus.extended,
      'completed' => BookingStatus.completed,
      'cancelled' => BookingStatus.cancelled,
      _ => BookingStatus.reserved,
    };

    final rawCharges = json['charges'] as List<dynamic>? ?? [];
    final charges = rawCharges
        .whereType<Map<String, dynamic>>()
        .map((c) => BookingCharge.fromJson(c))
        .toList();

    return Booking(
      id: json['id'] as String,
      userId: json['userId'] as String? ?? 'user-001',
      vehicleId: json['vehicleId'] as String? ?? 'v-default',
      vehiclePlate: json['vehiclePlate'] as String? ?? 'CAB-4821',
      lotId: json['lotId'] as String,
      lotName: json['lotName'] as String,
      slotId: json['slotId'] as String,
      bookedAt: _parseDate(json['bookedAt']) ?? DateTime.now(),
      arrivalTime: _parseDate(json['arrivalTime']) ?? DateTime.now(),
      durationHours: json['durationHours'] as int? ?? 1,
      status: status,
      originalSlotId: json['originalSlotId'] as String?,
      distanceSavedMeters: json['distanceSavedMeters'] as int? ?? 0,
      estimatedFee: json['estimatedFee'] as int? ?? 0,
      extensionFee: json['extensionFee'] as int? ?? 0,
      finalFee: json['finalFee'] as int? ?? 0,
      charges: charges,
      reallocatedDueToConflict:
          json['reallocatedDueToConflict'] as bool? ?? false,
      reallocatedFromSlotId: json['reallocatedFromSlotId'] as String?,
      qrToken: json['qrToken'] as String? ?? '',
      checkedInAt: _parseDate(json['checkedInAt']),
      completedAt: _parseDate(json['completedAt']),
      holdExpiresAt: _parseDate(json['holdExpiresAt']),
      predictedEtaMinBaseline:
          (json['predictedEtaMinBaseline'] as num?)?.toDouble() ?? 0.0,
      predictedEtaMinProvider:
          (json['predictedEtaMinProvider'] as num?)?.toDouble() ?? 0.0,
      predictedEtaMinCorrected:
          (json['predictedEtaMinCorrected'] as num?)?.toDouble() ?? 0.0,
      modelVersion: json['modelVersion'] as String? ?? 'v1.0.0-linear',
      weightsVersion: json['weightsVersion'] as String? ?? 'v1.0.0',
    );
  }
}
