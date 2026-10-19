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
  final String? bookingId;
  final String? updatedAt;
  final String? updatedBy;

  const ParkingSlot({
    required this.id,
    required this.lotId,
    required this.row,
    required this.number,
    required this.state,
    required this.size,
    this.type = SlotType.normal,
    required this.walkingDistanceMeters,
    this.cameraId = '',
    this.bookingId,
    this.updatedAt,
    this.updatedBy,
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
    String? bookingId,
    String? updatedAt,
    String? updatedBy,
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
      bookingId: bookingId ?? this.bookingId,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'lotId': lotId,
        'row': row,
        'number': number,
        'state': state.name,
        'size': size.name,
        'type': type.name,
        'walkingDistanceMeters': walkingDistanceMeters,
        'cameraId': cameraId,
        if (bookingId != null) 'bookingId': bookingId,
        if (updatedAt != null) 'updatedAt': updatedAt,
        if (updatedBy != null) 'updatedBy': updatedBy,
      };

  factory ParkingSlot.fromJson(Map<String, dynamic> json) {
    final rawState = json['state'] as String? ?? 'available';
    final parsedState = switch (rawState) {
      'available' || 'free' => SlotState.free,
      'blocked' => SlotState.blocked,
      'yours' => SlotState.yours,
      _ => SlotState.taken, // 'reserved', 'held', 'occupied', 'taken'
    };

    return ParkingSlot(
      id: json['id'] as String,
      lotId: json['lotId'] as String? ?? 'lot-main',
      row: json['row'] as String? ?? 'A',
      number: json['number'] as int? ?? 1,
      state: parsedState,
      size: VehicleSize.values.firstWhere(
        (s) => s.name == json['size'],
        orElse: () => VehicleSize.medium,
      ),
      type: SlotType.values.firstWhere(
        (s) => s.name == json['type'],
        orElse: () => SlotType.normal,
      ),
      walkingDistanceMeters: json['walkingDistanceMeters'] as int? ?? 100,
      cameraId: json['cameraId'] as String? ?? '',
      bookingId: json['bookingId'] as String?,
      updatedAt: json['updatedAt'] as String?,
      updatedBy: json['updatedBy'] as String?,
    );
  }
}
