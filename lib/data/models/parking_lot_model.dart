import 'parking_slot_model.dart';

class ParkingLot {
  final String id;
  final String name;
  final String campusZone;
  final double latitude;
  final double longitude;
  final int distanceMeters;
  final int hourlyRate; // In LKR
  final int totalSlots;
  final int freeSlots;
  final String openingHours;
  final List<ParkingSlot> slots;

  const ParkingLot({
    required this.id,
    required this.name,
    this.campusZone = 'SLIIT Malabe Campus',
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.hourlyRate,
    required this.totalSlots,
    required this.freeSlots,
    this.openingHours = '06:00 AM - 10:00 PM',
    this.slots = const [],
  });

  bool get isFull => freeSlots <= 0;

  ParkingLot copyWith({
    String? id,
    String? name,
    String? campusZone,
    double? latitude,
    double? longitude,
    int? distanceMeters,
    int? hourlyRate,
    int? totalSlots,
    int? freeSlots,
    String? openingHours,
    List<ParkingSlot>? slots,
  }) {
    return ParkingLot(
      id: id ?? this.id,
      name: name ?? this.name,
      campusZone: campusZone ?? this.campusZone,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      totalSlots: totalSlots ?? this.totalSlots,
      freeSlots: freeSlots ?? this.freeSlots,
      openingHours: openingHours ?? this.openingHours,
      slots: slots ?? this.slots,
    );
  }
}
