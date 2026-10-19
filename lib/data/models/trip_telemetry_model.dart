// trip_telemetry_model.dart
// Smart Parking (J26-IT-335) — Trip Telemetry Data Model for ETA Learning & Audit

class TripTelemetry {
  final String id;
  final String tripId;
  final String bookingId;
  final String userId;
  final String lotId;
  final double predictedEtaMinBaseline;
  final double predictedEtaMinProvider;
  final double predictedEtaMinCorrected;
  final int actualTravelMin;
  final DateTime departureTime;
  final DateTime arrivalTime;
  final int dayOfWeek; // 1 = Monday .. 7 = Sunday
  final int hour; // 0 .. 23
  final double distanceKm;
  final String originZone;
  final int weatherFlag; // 0 = clear, 1 = rain
  final int holidayFlag; // 0 = regular, 1 = holiday
  final String modelVersion;
  final DateTime loggedAt;

  const TripTelemetry({
    required this.id,
    required this.tripId,
    required this.bookingId,
    required this.userId,
    required this.lotId,
    required this.predictedEtaMinBaseline,
    required this.predictedEtaMinProvider,
    required this.predictedEtaMinCorrected,
    required this.actualTravelMin,
    required this.departureTime,
    required this.arrivalTime,
    required this.dayOfWeek,
    required this.hour,
    required this.distanceKm,
    required this.originZone,
    required this.weatherFlag,
    required this.holidayFlag,
    required this.modelVersion,
    required this.loggedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'tripId': tripId,
        'bookingId': bookingId,
        'userId': userId,
        'lotId': lotId,
        'predictedEtaMinBaseline': predictedEtaMinBaseline,
        'predictedEtaMinProvider': predictedEtaMinProvider,
        'predictedEtaMinCorrected': predictedEtaMinCorrected,
        'actualTravelMin': actualTravelMin,
        'departureTime': departureTime.toIso8601String(),
        'arrivalTime': arrivalTime.toIso8601String(),
        'dayOfWeek': dayOfWeek,
        'hour': hour,
        'distanceKm': distanceKm,
        'originZone': originZone,
        'weatherFlag': weatherFlag,
        'holidayFlag': holidayFlag,
        'modelVersion': modelVersion,
        'loggedAt': loggedAt.toIso8601String(),
      };

  factory TripTelemetry.fromJson(Map<String, dynamic> json) => TripTelemetry(
        id: (json['id'] ?? json['tripId'] ?? '') as String,
        tripId: (json['tripId'] ?? json['id'] ?? '') as String,
        bookingId: (json['bookingId'] ?? '') as String,
        userId: (json['userId'] ?? '') as String,
        lotId: (json['lotId'] ?? '') as String,
        predictedEtaMinBaseline: (json['predictedEtaMinBaseline'] as num?)?.toDouble() ?? 15.0,
        predictedEtaMinProvider: (json['predictedEtaMinProvider'] as num?)?.toDouble() ?? 12.0,
        predictedEtaMinCorrected: (json['predictedEtaMinCorrected'] as num?)?.toDouble() ?? 14.0,
        actualTravelMin: (json['actualTravelMin'] as num?)?.toInt() ?? 15,
        departureTime: DateTime.tryParse(json['departureTime'] as String? ?? '') ?? DateTime.now(),
        arrivalTime: DateTime.tryParse(json['arrivalTime'] as String? ?? '') ?? DateTime.now(),
        dayOfWeek: (json['dayOfWeek'] as num?)?.toInt() ?? 1,
        hour: (json['hour'] as num?)?.toInt() ?? 8,
        distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 5.0,
        originZone: (json['originZone'] ?? 'Malabe_Kaduwela') as String,
        weatherFlag: (json['weatherFlag'] as num?)?.toInt() ?? 0,
        holidayFlag: (json['holidayFlag'] as num?)?.toInt() ?? 0,
        modelVersion: (json['modelVersion'] ?? 'v1.0.0-linear') as String,
        loggedAt: DateTime.tryParse(json['loggedAt'] as String? ?? '') ?? DateTime.now(),
      );
}
