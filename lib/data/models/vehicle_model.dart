enum VehicleType {
  sedan,
  suv,
  van,
  threeWheeler,
  motorbike,
  lorry;

  String get displayName => switch (this) {
        VehicleType.sedan => 'Sedan',
        VehicleType.suv => 'SUV',
        VehicleType.van => 'Van',
        VehicleType.threeWheeler => 'Three-Wheeler',
        VehicleType.motorbike => 'Motorbike',
        VehicleType.lorry => 'Lorry',
      };
}

enum VehicleSize {
  small,
  medium,
  large;

  String get displayName => switch (this) {
        VehicleSize.small => 'Small',
        VehicleSize.medium => 'Medium',
        VehicleSize.large => 'Large',
      };
}

class Vehicle {
  final String id;
  final String plateNumber;
  final VehicleType type;
  final VehicleSize size;
  final bool isDefault;

  const Vehicle({
    required this.id,
    required this.plateNumber,
    required this.type,
    required this.size,
    this.isDefault = false,
  });

  Vehicle copyWith({
    String? id,
    String? plateNumber,
    VehicleType? type,
    VehicleSize? size,
    bool? isDefault,
  }) {
    return Vehicle(
      id: id ?? this.id,
      plateNumber: plateNumber ?? this.plateNumber,
      type: type ?? this.type,
      size: size ?? this.size,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'plateNumber': plateNumber,
        'type': type.name,
        'size': size.name,
        'isDefault': isDefault,
      };

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
        id: json['id'] as String,
        plateNumber: json['plateNumber'] as String,
        type: VehicleType.values.byName(json['type'] as String),
        size: VehicleSize.values.byName(json['size'] as String),
        isDefault: json['isDefault'] as bool? ?? false,
      );
}
