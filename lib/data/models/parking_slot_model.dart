import '../../core/theme/app_theme.dart';
import 'vehicle_model.dart';

enum SlotType {
  normal,
  disabled,
  ev,
  covered;

  String get displayName => switch (this) {
        SlotType.normal => 'Standard',
        SlotType.disabled => 'Accessible',
        SlotType.ev => 'EV Charging',
        SlotType.covered => 'Covered',
      };
}

class ParkingSlot {
  final String id;
  final String lotId;
  final String row;
  final int number;
  final SlotState state;
  final VehicleSize size;
  final SlotType type;
  final int walkingDistanceMeters;
  final String cameraId;
  final int sector;

  const ParkingSlot({
    required this.id,
    required this.lotId,
    required this.row,
    required this.number,
    required this.state,
    required this.size,
    required this.walkingDistanceMeters,
    this.type = SlotType.normal,
    this.cameraId = '',
    this.sector = 1,
  });

  bool get isAvailable => state == SlotState.free;

  ParkingSlot copyWith({
    String? id,
    String? lotId,
    String? row,
    int? number,
    SlotState? state,
    VehicleSize? size,
    SlotType? type,
    int? walkingDistanceMeters,
    String? cameraId,
    int? sector,
  }) {
    return ParkingSlot(
      id: id ?? this.id,
      lotId: lotId ?? this.lotId,
      row: row ?? this.row,
      number: number ?? this.number,
      state: state ?? this.state,
      size: size ?? this.size,
      type: type ?? this.type,
      walkingDistanceMeters:
          walkingDistanceMeters ?? this.walkingDistanceMeters,
      cameraId: cameraId ?? this.cameraId,
      sector: sector ?? this.sector,
    );
  }
}