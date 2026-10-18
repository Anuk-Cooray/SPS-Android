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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'vehicles': vehicles.map((v) => v.toJson()).toList(),
        'preferences': preferences.toJson(),
        'paymentMethods': paymentMethods,
        'defaultPaymentMethod': defaultPaymentMethod,
      };

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String? ?? 'user-001',
        name: json['name'] as String? ?? 'Driver',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String? ?? '+94 77 123 4567',
        vehicles: (json['vehicles'] as List<dynamic>?)
                ?.map((v) => Vehicle.fromJson(v as Map<String, dynamic>))
                .toList() ??
            const [],
        preferences: json['preferences'] != null
            ? UserPreferences.fromJson(json['preferences'] as Map<String, dynamic>)
            : const UserPreferences(),
        paymentMethods: (json['paymentMethods'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const ['Visa •••• 4821'],
        defaultPaymentMethod:
            json['defaultPaymentMethod'] as String? ?? 'Visa •••• 4821',
      );

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
