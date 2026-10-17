import 'vehicle_model.dart';

class UserPreferences {
  final bool allowUpgradeOffers;
  final bool preferNearEntrance;
  final bool coveredParkingOnly;

  const UserPreferences({
    this.allowUpgradeOffers = true,
    this.preferNearEntrance = true,
    this.coveredParkingOnly = false,
  });

  UserPreferences copyWith({
    bool? allowUpgradeOffers,
    bool? preferNearEntrance,
    bool? coveredParkingOnly,
  }) {
    return UserPreferences(
      allowUpgradeOffers: allowUpgradeOffers ?? this.allowUpgradeOffers,
      preferNearEntrance: preferNearEntrance ?? this.preferNearEntrance,
      coveredParkingOnly: coveredParkingOnly ?? this.coveredParkingOnly,
    );
  }

  Map<String, dynamic> toJson() => {
        'allowUpgradeOffers': allowUpgradeOffers,
        'preferNearEntrance': preferNearEntrance,
        'coveredParkingOnly': coveredParkingOnly,
      };

  factory UserPreferences.fromJson(Map<String, dynamic> json) =>
      UserPreferences(
        allowUpgradeOffers: json['allowUpgradeOffers'] as bool? ?? true,
        preferNearEntrance: json['preferNearEntrance'] as bool? ?? true,
        coveredParkingOnly: json['coveredParkingOnly'] as bool? ?? false,
      );
}

class User {
  final String id;
  final String name;
  final String email;
  final String phone;
  final List<Vehicle> vehicles;
  final UserPreferences preferences;
  final List<String> paymentMethods;
  final String? defaultPaymentMethod;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    this.vehicles = const [],
    this.preferences = const UserPreferences(),
    this.paymentMethods = const ['Visa •••• 4821'],
    this.defaultPaymentMethod = 'Visa •••• 4821',
  });

  Vehicle? get defaultVehicle {
    if (vehicles.isEmpty) return null;
    return vehicles.firstWhere((v) => v.isDefault, orElse: () => vehicles.first);
  }

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    List<Vehicle>? vehicles,
    UserPreferences? preferences,
    List<String>? paymentMethods,
    String? defaultPaymentMethod,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      vehicles: vehicles ?? this.vehicles,
      preferences: preferences ?? this.preferences,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      defaultPaymentMethod: defaultPaymentMethod ?? this.defaultPaymentMethod,
    );
  }
}
