import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../features/reoptimization/engine/reoptimization_engine.dart';
import '../../features/reoptimization/engine/scoring_weights.dart';
import '../../features/reoptimization/engine/slot_score_result.dart';
import '../../features/reoptimization/engine/upgrade_evaluation_result.dart';
import '../models/admin_alert_model.dart';
import '../models/booking_model.dart';
import '../models/parking_event_model.dart';
import '../models/parking_lot_model.dart';
import '../models/parking_slot_model.dart';
import '../models/user_model.dart';
import '../models/vehicle_model.dart';
import 'arrival_feasibility_service.dart';
import 'cloud_functions_client.dart';
import 'firestore_service.dart';
import 'mock_data.dart';

class ParkingStateManager extends ChangeNotifier {
  final FirestoreService _firestore = FirestoreService();
  User _currentUser = MockData.initialUser;
  bool _isLoggedIn = false;
  bool _isInitialized = false;
  final List<ParkingLot> _lots = MockData.getInitialLots();
  final List<Booking> _bookings = [];
  final List<ParkingEvent> _events = [];

  // Mathematical scoring engine & re-optimization (SYS-01, SYS-03)
  final ReoptimizationEngine _engine = ReoptimizationEngine();
  UpgradeEvaluationResult? _lastUpgradeEvaluation;

  // Active navigation / in-transit state (SYS-03)
  Booking? _currentActiveBooking;
  String? _lastCollisionError;
  static const double _initialDistanceKm = 4.2;
  static const int _initialEtaMinutes = 12;
  int _etaMinutes = _initialEtaMinutes;
  double _distanceKm = _initialDistanceKm;
  double _routeProgress = 0.0;
  bool _isSimulatingMovement = false;
  Timer? _simulationTimer;
  bool _hasTriggeredAutoUpgrade = false;
  bool _hasArrivedAtDestination = false;
  bool _upgradeOfferAvailable = false;
  ParkingSlot? _upgradeCandidateSlot;

  ParkingStateManager() {
    _initSession();
  }

  Future<void> _initSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loggedIn = prefs.getBool('sp_is_logged_in') ?? false;
      final userJson = prefs.getString('sp_user_profile');
      final bookingsJson = prefs.getString('sp_bookings');
      final eventsJson = prefs.getString('sp_events');

      if (loggedIn && userJson != null) {
        final decoded = jsonDecode(userJson) as Map<String, dynamic>;
        _currentUser = User.fromJson(decoded);
        _isLoggedIn = true;
      } else {
        _isLoggedIn = false;
      }

      if (bookingsJson != null && bookingsJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(bookingsJson) as List<dynamic>;
        _bookings.clear();
        _bookings.addAll(list.map((m) => Booking.fromJson(m as Map<String, dynamic>)));
      } else {
        _bookings.clear();
      }

      if (eventsJson != null && eventsJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(eventsJson) as List<dynamic>;
        _events.clear();
        _events.addAll(list.map((m) => ParkingEvent.fromJson(m as Map<String, dynamic>)));
      } else {
        _events.clear();
      }

      _refreshActiveBooking();

      if (!_isTestRuntime) {
        unawaited(_firestore.seedInitialLotsIfEmpty(_lots));
        _subscribeToFirestoreStreams();
      }
    } catch (_) {
      _isLoggedIn = false;
    } finally {
      _isInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  StreamSubscription<List<ParkingLot>>? _lotsSubscription;
  StreamSubscription<List<Booking>>? _bookingsSubscription;

  void _subscribeToFirestoreStreams() {
    if (_isTestRuntime) return;
    _lotsSubscription?.cancel();
    _lotsSubscription = _firestore.streamLots().listen((cloudLots) {
      if (cloudLots.isNotEmpty) {
        for (final cloudLot in cloudLots) {
          final idx = _lots.indexWhere((l) => l.id == cloudLot.id);
          if (idx != -1) {
            _lots[idx] = cloudLot;
          } else {
            _lots.add(cloudLot);
          }
        }
        notifyListeners();
      }
    });

    if (_currentUser.email.isNotEmpty) {
      _bookingsSubscription?.cancel();
      _bookingsSubscription = _firestore.streamUserBookings(_currentUser.id).listen((cloudBookings) {
        if (cloudBookings.isNotEmpty) {
          for (final b in cloudBookings) {
            final idx = _bookings.indexWhere((x) => x.id == b.id);
            if (idx != -1) {
              _bookings[idx] = b;
            } else {
              _bookings.insert(0, b);
            }
          }
          _refreshActiveBooking();
          notifyListeners();
        }
      });
    }
  }

  Future<void> _persistSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sp_is_logged_in', _isLoggedIn);
      await prefs.setString('sp_user_profile', jsonEncode(_currentUser.toJson()));
    } catch (_) {}
  }

  Future<void> _persistBookings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'sp_bookings',
        jsonEncode(_bookings.map((b) => b.toJson()).toList()),
      );
      await prefs.setString(
        'sp_events',
        jsonEncode(_events.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  void clearAllBookings() {
    _bookings.clear();
    _currentActiveBooking = null;
    _events.clear();
    _persistBookings();
    notifyListeners();
  }

  // Getters
  User get currentUser => _currentUser;
  bool get isLoggedIn => _isLoggedIn;
  bool get isInitialized => _isInitialized;
  bool get hasRegisteredVehicle => _currentUser.vehicles.isNotEmpty;
  List<ParkingLot> get lots => _lots;
  List<Booking> get bookings => _bookings;
  List<ParkingEvent> get events => _events;
  Booking? get currentActiveBooking => _currentActiveBooking;
  int get etaMinutes => _etaMinutes;
  double get distanceKm => _distanceKm;
  double get routeProgress => _routeProgress;
  bool get isSimulatingMovement => _isSimulatingMovement;
  bool get hasArrivedAtDestination => _hasArrivedAtDestination;

  String get currentManeuverText {
    if (_routeProgress >= 1.0) {
      return 'Arrived at barrier. Ready to scan QR.';
    } else if (_routeProgress >= 0.75) {
      final lotName = _currentActiveBooking?.lotName ?? 'SLIIT Parking';
      final slotId = _currentActiveBooking?.slotId ?? 'bay';
      return 'Enter $lotName and proceed to $slotId';
    } else if (_routeProgress >= 0.35) {
      return 'Turn left at SLIIT Campus Gate';
    } else {
      return 'Turn right onto New Kandy Rd';
    }
  }

  String get currentManeuverDistance {
    if (_routeProgress >= 1.0) return '0 m';
    if (_routeProgress < 0.35) {
      final remainingM = ((0.35 - _routeProgress) * 4200).round();
      return '$remainingM m';
    } else if (_routeProgress < 0.75) {
      final remainingM = ((0.75 - _routeProgress) * 4200).round();
      return '$remainingM m';
    } else {
      final remainingM = ((1.0 - _routeProgress) * 4200).round();
      return '$remainingM m';
    }
  }

  IconData get currentManeuverIcon {
    if (_routeProgress >= 1.0) {
      return Icons.check_circle_rounded;
    } else if (_routeProgress >= 0.75) {
      return Icons.straight_rounded;
    } else if (_routeProgress >= 0.35) {
      return Icons.turn_left_rounded;
    } else {
      return Icons.turn_right_rounded;
    }
  }

  bool get upgradeOfferAvailable => _upgradeOfferAvailable;
  ParkingSlot? get upgradeCandidateSlot => _upgradeCandidateSlot;
  ReoptimizationEngine get engine => _engine;
  ScoringWeights get scoringWeights => _engine.weights;
  UpgradeEvaluationResult? get lastUpgradeEvaluation => _lastUpgradeEvaluation;
  int _weightsVersionCounter = 1;
  String get weightsVersion => _engine.weights.version;

  void updateScoringWeights(ScoringWeights newWeights) {
    if (!newWeights.isValidSum) {
      throw ArgumentError(
        'Weights must sum to 1.0 (±0.001). Current sum: ${newWeights.weightSum.toStringAsFixed(3)}',
      );
    }
    _weightsVersionCounter++;
    final versioned = newWeights.copyWith(version: 'v1.$_weightsVersionCounter.0');
    _engine.weights = versioned;

    // Log audited telemetry event
    final auditEvent = ParkingEvent(
      id: 'weight-audit-${DateTime.now().millisecondsSinceEpoch}',
      bookingId: '',
      type: ParkingEventType.weightsTuned,
      timestamp: DateTime.now(),
      description:
          'Weights tuned (${versioned.version}): dist=${(versioned.distanceWeight * 100).toInt()}%, size=${(versioned.sizeFitWeight * 100).toInt()}%, pref=${(versioned.preferenceWeight * 100).toInt()}%, dem=${(versioned.demandWeight * 100).toInt()}%',
      metadata: versioned.toJson(),
    );
    _events.insert(0, auditEvent);

    notifyListeners();
  }

  String? get lastCollisionError => _lastCollisionError;
  void clearCollisionError() {
    _lastCollisionError = null;
    notifyListeners();
  }

  ParkingSlot? findNextBestSlot(ParkingLot lot, String excludedSlotId) {
    final vehicle = _currentUser.defaultVehicle ??
        const Vehicle(
          id: 'veh-temp',
          plateNumber: 'CAB-4821',
          type: VehicleType.sedan,
          size: VehicleSize.medium,
        );

    final ranked = _engine.scoreAndRankSlots(
      lot: lot,
      vehicle: vehicle,
      preferences: _currentUser.preferences,
    );

    for (final r in ranked) {
      if (r.slot.id != excludedSlotId && r.slot.isAvailable) {
        return r.slot;
      }
    }
    return null;
  }

  // Driver-specific active & history bookings
  List<Booking> get activeBookings =>
      _bookings.where((b) => b.userId == _currentUser.id && b.isActive).toList();

  List<Booking> get upcomingBookings =>
      _bookings.where((b) => b.userId == _currentUser.id && b.status == BookingStatus.reserved).toList();

  List<Booking> get historyBookings => _bookings
      .where((b) =>
          b.userId == _currentUser.id &&
          (b.status == BookingStatus.completed ||
              b.status == BookingStatus.cancelled ||
              b.status == BookingStatus.autoCancelled))
      .toList();

  // Admin visibility (all campus reservations across users)
  List<Booking> get allBookings => _bookings;
  List<Booking> get allActiveBookings => _bookings.where((b) => b.isActive).toList();

  void _refreshActiveBooking() {
    final active = _bookings.where((b) => b.userId == _currentUser.id && b.isActive).toList();
    if (active.isNotEmpty) {
      _currentActiveBooking = active.first;
      if ((_currentActiveBooking!.status == BookingStatus.reserved ||
              _currentActiveBooking!.status == BookingStatus.upgraded) &&
          _currentActiveBooking!.isHoldExpired) {
        cancelBooking(autoCancelled: true);
      } else if (_currentActiveBooking!.status == BookingStatus.reserved ||
          _currentActiveBooking!.status == BookingStatus.upgraded) {
        _startHoldTimer();
      }
    } else {
      _currentActiveBooking = null;
      _stopHoldTimer();
    }
  }

  // Auth & Profile (M1)
  String? _activeVerificationEmail;
  String? _activeGeneratedOtp;
  DateTime? _otpExpiresAt;

  String? get activeVerificationEmail => _activeVerificationEmail;
  String? get activeGeneratedOtp => _activeGeneratedOtp;
  DateTime? get otpExpiresAt => _otpExpiresAt;

  /// Requests a real 6-digit OTP code for the given email, persisted to Firestore
  Future<String> sendVerificationOtp(String email) async {
    final cleanEmail = email.trim();
    _activeVerificationEmail = cleanEmail;
    final otp = await _firestore.sendEmailVerificationOtp(cleanEmail);
    _activeGeneratedOtp = otp;
    _otpExpiresAt = DateTime.now().add(const Duration(minutes: 5));
    debugPrint('[Auth] Generated 6-digit verification code for $cleanEmail');
    notifyListeners();
    return otp;
  }

  /// Verifies the entered OTP and logs the driver in on success
  Future<OtpVerificationResult> verifyOtp(String email, String enteredOtp) async {
    final result = await _firestore.verifyEmailOtp(email, enteredOtp);
    if (result.isValid) {
      await login(email);
      debugPrint('[Auth] Email $email verified successfully');
    }
    return result;
  }

  Future<void> login(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    _isLoggedIn = true;

    // Check Cloud Firestore for existing driver profile
    User? cloudUser;
    try {
      cloudUser = await _firestore.fetchUser(cleanEmail);
    } catch (_) {}

    if (cloudUser != null) {
      _currentUser = cloudUser;
    } else if (cleanEmail == 'anuk@example.com' || cleanEmail == 'anuk@sliit.lk') {
      _currentUser = MockData.initialUser.copyWith(email: cleanEmail);
      unawaited(_firestore.saveUser(_currentUser));
    } else {
      _currentUser = User(
        id: 'usr-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
        name: cleanEmail.split('@').first.replaceAll('.', ' ').toUpperCase(),
        email: cleanEmail,
        phone: '+94 77 123 4567',
        vehicles: const [],
        preferences: const UserPreferences(),
      );
      unawaited(_firestore.saveUser(_currentUser));
    }

    await _persistSession();
    _subscribeToFirestoreStreams();
    notifyListeners();
  }

  Future<void> completeVehicleOnboarding(Vehicle vehicle) async {
    final updatedVehicles = [vehicle.copyWith(isDefault: true)];
    _currentUser = _currentUser.copyWith(vehicles: updatedVehicles);
    await _persistSession();
    unawaited(_firestore.saveUser(_currentUser));
    notifyListeners();
  }

  Future<void> logout() async {
    _isLoggedIn = false;
    _lotsSubscription?.cancel();
    _bookingsSubscription?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('sp_is_logged_in');
      await prefs.remove('sp_user_profile');
    } catch (_) {}
    notifyListeners();
  }

  Future<void> addVehicle(Vehicle vehicle) async {
    final updated = List<Vehicle>.from(_currentUser.vehicles);
    if (vehicle.isDefault) {
      for (int i = 0; i < updated.length; i++) {
        updated[i] = updated[i].copyWith(isDefault: false);
      }
    }
    updated.add(vehicle);
    _currentUser = _currentUser.copyWith(vehicles: updated);
    await _persistSession();
    unawaited(_firestore.saveUser(_currentUser));
    notifyListeners();
  }

  Future<void> setDefaultVehicle(String vehicleId) async {
    final updated = _currentUser.vehicles.map((v) {
      return v.copyWith(isDefault: v.id == vehicleId);
    }).toList();
    _currentUser = _currentUser.copyWith(vehicles: updated);
    await _persistSession();
    unawaited(_firestore.saveUser(_currentUser));
    notifyListeners();
  }

  Future<void> updatePreferences(UserPreferences prefs) async {
    _currentUser = _currentUser.copyWith(preferences: prefs);
    await _persistSession();
    unawaited(_firestore.saveUser(_currentUser));
    notifyListeners();
  }

  // Mathematical Slot Scoring & Multi-Criteria Recommendation (SYS-01)
  ParkingSlot? getRecommendedSlot(ParkingLot lot) {
    final vehicle = _currentUser.defaultVehicle ??
        const Vehicle(
          id: 'veh-temp',
          plateNumber: 'CAB-4821',
          type: VehicleType.sedan,
          size: VehicleSize.medium,
        );

    final ranked = _engine.scoreAndRankSlots(
      lot: lot,
      vehicle: vehicle,
      preferences: _currentUser.preferences,
    );

    if (ranked.isEmpty) return null;
    return ranked.first.slot;
  }

  SlotScoreResult? getRecommendedSlotScore(ParkingLot lot) {
    final vehicle = _currentUser.defaultVehicle ??
        const Vehicle(
          id: 'veh-temp',
          plateNumber: 'CAB-4821',
          type: VehicleType.sedan,
          size: VehicleSize.medium,
        );

    final ranked = _engine.scoreAndRankSlots(
      lot: lot,
      vehicle: vehicle,
      preferences: _currentUser.preferences,
    );

    if (ranked.isEmpty) return null;
    return ranked.first;
  }

  List<SlotScoreResult> getRankedSlotScores(ParkingLot lot) {
    final vehicle = _currentUser.defaultVehicle ??
        const Vehicle(
          id: 'veh-temp',
          plateNumber: 'CAB-4821',
          type: VehicleType.sedan,
          size: VehicleSize.medium,
        );

    return _engine.scoreAndRankSlots(
      lot: lot,
      vehicle: vehicle,
      preferences: _currentUser.preferences,
    );
  }

  SlotScoreResult scoreSlot(ParkingLot lot, ParkingSlot slot) {
    final vehicle = _currentUser.defaultVehicle ??
        const Vehicle(
          id: 'veh-temp',
          plateNumber: 'CAB-4821',
          type: VehicleType.sedan,
          size: VehicleSize.medium,
        );

    return _engine.scoreSlot(
      slot: slot,
      lot: lot,
      vehicle: vehicle,
      preferences: _currentUser.preferences,
    );
  }

  void _applyLocalBooking(Booking newBooking, ParkingLot lot, ParkingSlot slot) {
    final updatedSlots = lot.slots.map((s) {
      if (s.id == slot.id) {
        return s.copyWith(state: SlotState.taken);
      }
      return s;
    }).toList();

    final updatedLot = lot.copyWith(
      freeSlots: (lot.freeSlots - 1).clamp(0, lot.totalSlots),
      slots: updatedSlots,
    );

    final lotIndex = _lots.indexWhere((l) => l.id == lot.id);
    if (lotIndex != -1) {
      _lots[lotIndex] = updatedLot;
    }

    _bookings.insert(0, newBooking);
    _currentActiveBooking = newBooking;
    final initialEta = newBooking.predictedEtaMinCorrected > 0
        ? newBooking.predictedEtaMinCorrected.round()
        : _initialEtaMinutes;
    _etaMinutes = initialEta;
    _distanceKm = _initialDistanceKm;
    _routeProgress = 0.0;
    _hasTriggeredAutoUpgrade = false;
    _hasArrivedAtDestination = false;
    pauseMovementSimulation();
    _startHoldTimer();

    _logEvent(
      bookingId: newBooking.id,
      type: ParkingEventType.booked,
      description: 'Booked slot ${slot.id} in ${lot.name} · Hold expires in 15 mins',
      metadata: {
        'lotId': lot.id,
        'slotId': slot.id,
        'predictedEtaMinBaseline': newBooking.predictedEtaMinBaseline,
        'predictedEtaMinProvider': newBooking.predictedEtaMinProvider,
        'predictedEtaMinCorrected': newBooking.predictedEtaMinCorrected,
        'modelVersion': newBooking.modelVersion,
      },
    );

    notifyListeners();
  }

  // Booking Flow (M5) — Server Authority with Local Fallback
  Booking reserveSlot({
    required ParkingLot lot,
    required ParkingSlot slot,
    required DateTime arrivalTime,
    required int durationHours,
    double? originLat,
    double? originLng,
  }) {
    final vehicle = _currentUser.defaultVehicle ??
        const Vehicle(
          id: 'veh-temp',
          plateNumber: 'CAB-4821',
          type: VehicleType.sedan,
          size: VehicleSize.medium,
        );

    final feasibility = (originLat != null && originLng != null)
        ? ArrivalFeasibilityService.evaluate(
            originLat: originLat,
            originLng: originLng,
            targetLot: lot,
            requestedTime: arrivalTime,
          )
        : null;

    final holdExpiry = arrivalTime.add(const Duration(minutes: 15));
    final newBooking = Booking(
      id: 'BK-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      userId: _currentUser.id,
      vehicleId: vehicle.id,
      vehiclePlate: vehicle.plateNumber,
      lotId: lot.id,
      lotName: lot.name,
      slotId: slot.id,
      bookedAt: DateTime.now(),
      arrivalTime: arrivalTime,
      durationHours: durationHours,
      status: BookingStatus.reserved,
      estimatedFee: lot.hourlyRate * durationHours,
      qrToken: 'QR-TOKEN-${slot.id}-${DateTime.now().millisecondsSinceEpoch}',
      holdExpiresAt: holdExpiry,
      predictedEtaMinBaseline: feasibility?.predictedEtaMinBaseline ?? 0.0,
      predictedEtaMinProvider: feasibility?.predictedEtaMinProvider ?? 0.0,
      predictedEtaMinCorrected: feasibility?.predictedEtaMinCorrected ?? 0.0,
      modelVersion: feasibility?.modelVersion ?? 'v1.0.0-linear',
      weightsVersion: _engine.weights.version,
    );

    _applyLocalBooking(newBooking, lot, slot);

    // Call server callable in background to enforce server authority
    if (!_isTestRuntime) {
      _firestore.createBookingOnServer(
        lotId: lot.id,
        slotId: slot.id,
        userId: _currentUser.id,
        vehiclePlate: vehicle.plateNumber,
        vehicleSize: vehicle.size,
        vehicleId: vehicle.id,
        arrivalTime: arrivalTime,
        durationHours: durationHours,
        originLat: originLat,
        originLng: originLng,
        providerEtaMinutes: feasibility?.predictedEtaMinProvider,
        predictedEtaMinBaseline: feasibility?.predictedEtaMinBaseline,
        predictedEtaMinProvider: feasibility?.predictedEtaMinProvider,
        predictedEtaMinCorrected: feasibility?.predictedEtaMinCorrected,
        modelVersion: feasibility?.modelVersion ?? 'v1.0.0-linear',
      ).then((serverBooking) {
        final idx = _bookings.indexWhere((b) => b.id == newBooking.id);
        if (idx != -1) {
          _bookings[idx] = serverBooking;
        }
        if (_currentActiveBooking?.id == newBooking.id) {
          _currentActiveBooking = serverBooking;
        }
        notifyListeners();
      }).catchError((e) {
        if (e is SlotCollisionException) {
          final nextBest = findNextBestSlot(lot, slot.id);
          _lastCollisionError = "Slot just taken — here's the next best: ${nextBest?.id ?? 'another bay'}";
          notifyListeners();
        }
        return null;
      });
    }

    return newBooking;
  }

  Future<Booking> reserveSlotAsync({
    required ParkingLot lot,
    required ParkingSlot slot,
    required DateTime arrivalTime,
    required int durationHours,
    double? driverOriginLat,
    double? driverOriginLng,
  }) async {
    final vehicle = _currentUser.defaultVehicle ??
        const Vehicle(
          id: 'veh-temp',
          plateNumber: 'CAB-4821',
          type: VehicleType.sedan,
          size: VehicleSize.medium,
        );

    final feasibility = (driverOriginLat != null && driverOriginLng != null)
        ? ArrivalFeasibilityService.evaluate(
            originLat: driverOriginLat,
            originLng: driverOriginLng,
            targetLot: lot,
            requestedTime: arrivalTime,
          )
        : null;

    try {
      Booking booking;
      if (!_isTestRuntime && _firestore.isAvailable) {
        booking = await _firestore.createBookingOnServer(
          lotId: lot.id,
          slotId: slot.id,
          userId: _currentUser.id,
          vehiclePlate: vehicle.plateNumber,
          vehicleSize: vehicle.size,
          vehicleId: vehicle.id,
          arrivalTime: arrivalTime,
          durationHours: durationHours,
          originLat: driverOriginLat,
          originLng: driverOriginLng,
          providerEtaMinutes: feasibility?.predictedEtaMinProvider,
          predictedEtaMinBaseline: feasibility?.predictedEtaMinBaseline,
          predictedEtaMinProvider: feasibility?.predictedEtaMinProvider,
          predictedEtaMinCorrected: feasibility?.predictedEtaMinCorrected,
          modelVersion: feasibility?.modelVersion ?? 'v1.0.0-linear',
        );
      } else {
        final holdExpiry = arrivalTime.add(const Duration(minutes: 15));
        booking = Booking(
          id: 'BK-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
          userId: _currentUser.id,
          vehicleId: vehicle.id,
          vehiclePlate: vehicle.plateNumber,
          lotId: lot.id,
          lotName: lot.name,
          slotId: slot.id,
          bookedAt: DateTime.now(),
          arrivalTime: arrivalTime,
          durationHours: durationHours,
          status: BookingStatus.reserved,
          estimatedFee: lot.hourlyRate * durationHours,
          qrToken: 'QR-TOKEN-${slot.id}-${DateTime.now().millisecondsSinceEpoch}',
          holdExpiresAt: holdExpiry,
          predictedEtaMinBaseline: feasibility?.predictedEtaMinBaseline ?? 0.0,
          predictedEtaMinProvider: feasibility?.predictedEtaMinProvider ?? 0.0,
          predictedEtaMinCorrected: feasibility?.predictedEtaMinCorrected ?? 0.0,
          modelVersion: feasibility?.modelVersion ?? 'v1.0.0-linear',
        );
      }

      _applyLocalBooking(booking, lot, slot);
      return booking;
    } on SlotCollisionException {
      final nextBest = findNextBestSlot(lot, slot.id);
      _lastCollisionError = "Slot just taken — here's the next best: ${nextBest?.id ?? 'another bay'}";
      notifyListeners();
      rethrow;
    }
  }

  // In-Transit Route Movement Simulation (SYS-03)
  void setRouteProgress(double progress) {
    _routeProgress = progress.clamp(0.0, 1.0);
    _distanceKm = double.parse((_initialDistanceKm * (1.0 - _routeProgress)).toStringAsFixed(1));
    _etaMinutes = ((_initialEtaMinutes * (1.0 - _routeProgress)).ceil()).clamp(0, _initialEtaMinutes);

    if (_routeProgress >= 1.0) {
      _hasArrivedAtDestination = true;
      pauseMovementSimulation();
    } else {
      _hasArrivedAtDestination = false;
    }

    // Dynamic upgrade trigger: check when ETA drops into trigger window (<= 10 min)
    if (_etaMinutes <= 10 &&
        !_hasTriggeredAutoUpgrade &&
        _currentActiveBooking != null &&
        _currentUser.preferences.allowUpgradeOffers) {
      _hasTriggeredAutoUpgrade = true;
      triggerUpgradeOfferCheck();
    }

    notifyListeners();
  }

  void tickSimulation({double step = 0.08}) {
    final nextProgress = (_routeProgress + step).clamp(0.0, 1.0);
    setRouteProgress(nextProgress);
  }

  void startMovementSimulation() {
    if (_routeProgress >= 1.0) {
      _routeProgress = 0.0;
      _hasArrivedAtDestination = false;
      _hasTriggeredAutoUpgrade = false;
    }
    _isSimulatingMovement = true;
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (_routeProgress >= 1.0) {
        timer.cancel();
        _isSimulatingMovement = false;
        _hasArrivedAtDestination = true;
        notifyListeners();
        return;
      }
      tickSimulation(step: 0.06);
    });
    notifyListeners();
  }

  void pauseMovementSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _isSimulatingMovement = false;
    notifyListeners();
  }

  void resetMovementSimulation() {
    pauseMovementSimulation();
    _hasTriggeredAutoUpgrade = false;
    _hasArrivedAtDestination = false;
    _routeProgress = 0.0;
    _distanceKm = _initialDistanceKm;
    _etaMinutes = _initialEtaMinutes;
    notifyListeners();
  }

  // Upgrade Offer Trigger (M7 / SYS-03)
  void triggerUpgradeOfferCheck() {
    if (_currentActiveBooking == null) return;

    final lot = _lots.firstWhere(
      (l) => l.id == _currentActiveBooking!.lotId,
      orElse: () => _lots.first,
    );

    final currentSlot = lot.slots.firstWhere(
      (s) => s.id == _currentActiveBooking!.slotId,
      orElse: () => ParkingSlot(
        id: _currentActiveBooking!.slotId,
        lotId: lot.id,
        row: 'A',
        number: 1,
        state: SlotState.taken,
        size: VehicleSize.medium,
        walkingDistanceMeters: 160,
      ),
    );

    final vehicle = _currentUser.defaultVehicle ??
        const Vehicle(
          id: 'veh-temp',
          plateNumber: 'CAB-4821',
          type: VehicleType.sedan,
          size: VehicleSize.medium,
        );

    final eval = _engine.evaluateInTransitUpgrade(
      lot: lot,
      currentSlot: currentSlot,
      vehicle: vehicle,
      preferences: _currentUser.preferences,
      currentEtaMinutes: _etaMinutes,
    );

    _lastUpgradeEvaluation = eval;

    if (eval.isUpgradeOffered && eval.candidateSlotScore != null) {
      _upgradeCandidateSlot = eval.candidateSlotScore!.slot;
      _upgradeOfferAvailable = true;

      _logEvent(
        bookingId: _currentActiveBooking!.id,
        type: ParkingEventType.offered,
        description: eval.decisionReason,
      );

      notifyListeners();
    }
  }

  // Accept Upgrade (M7 / SYS-04)
  void acceptUpgrade() {
    if (_currentActiveBooking == null || _upgradeCandidateSlot == null) return;

    final oldSlotId = _currentActiveBooking!.slotId;
    final newSlot = _upgradeCandidateSlot!;

    final lot = _lots.firstWhere(
      (l) => l.id == _currentActiveBooking!.lotId,
      orElse: () => _lots.first,
    );

    final oldSlot = lot.slots.firstWhere(
      (s) => s.id == oldSlotId,
      orElse: () => ParkingSlot(
        id: oldSlotId,
        lotId: lot.id,
        row: 'A',
        number: 1,
        state: SlotState.taken,
        size: VehicleSize.medium,
        walkingDistanceMeters: 160,
      ),
    );

    final savedMeters = (oldSlot.walkingDistanceMeters - newSlot.walkingDistanceMeters)
        .clamp(0, 500);

    final updatedBooking = _currentActiveBooking!.copyWith(
      slotId: newSlot.id,
      originalSlotId: oldSlotId,
      status: BookingStatus.upgraded,
      distanceSavedMeters: savedMeters,
      qrToken: 'QR-UPGRADED-${newSlot.id}-${DateTime.now().millisecondsSinceEpoch}',
    );

    // Update in lot
    final lotIndex = _lots.indexWhere((l) => l.id == updatedBooking.lotId);
    if (lotIndex != -1) {
      final lot = _lots[lotIndex];
      final updatedSlots = lot.slots.map((s) {
        if (s.id == oldSlotId) return s.copyWith(state: SlotState.free);
        if (s.id == newSlot.id) return s.copyWith(state: SlotState.taken);
        return s;
      }).toList();
      _lots[lotIndex] = lot.copyWith(slots: updatedSlots);
    }

    final bookingIndex =
        _bookings.indexWhere((b) => b.id == updatedBooking.id);
    if (bookingIndex != -1) {
      _bookings[bookingIndex] = updatedBooking;
    }

    _currentActiveBooking = updatedBooking;
    _upgradeOfferAvailable = false;
    _upgradeCandidateSlot = null;
    _firestore.saveBooking(updatedBooking);

    if (!_isTestRuntime) {
      unawaited(_firestore.acceptUpgradeOnServer(
        bookingId: updatedBooking.id,
        newSlotId: newSlot.id,
        userId: _currentUser.id,
        currentEtaMinutes: _etaMinutes,
      ).catchError((e) {
        if (e is SlotCollisionException) {
          _lastCollisionError = "Upgrade slot just taken by another driver.";
          _upgradeOfferAvailable = false;
          _upgradeCandidateSlot = null;
          notifyListeners();
        }
        return null;
      }));
    }

    unawaited(_firestore.updateSlotState(
      lotId: lot.id,
      slotId: oldSlotId,
      state: SlotState.free,
    ));
    unawaited(_firestore.updateSlotState(
      lotId: lot.id,
      slotId: newSlot.id,
      state: SlotState.taken,
      reservedBy: _currentUser.id,
    ));

    _logEvent(
      bookingId: updatedBooking.id,
      type: ParkingEventType.accepted,
      description: 'Accepted upgrade to ${newSlot.id} (Saved ${savedMeters}m walk)',
    );

    notifyListeners();
  }

  void declineUpgrade() {
    if (_currentActiveBooking == null) return;
    _upgradeOfferAvailable = false;
    _upgradeCandidateSlot = null;

    _logEvent(
      bookingId: _currentActiveBooking!.id,
      type: ParkingEventType.declined,
      description: 'Declined upgrade offer. Kept ${_currentActiveBooking!.slotId}',
    );

    notifyListeners();
  }

  // Late Arrival Extension (M8)
  void extendBooking({int minutes = 15, int fee = 50}) {
    if (_currentActiveBooking == null) return;

    final updated = _currentActiveBooking!.copyWith(
      arrivalTime: _currentActiveBooking!.arrivalTime.add(Duration(minutes: minutes)),
      status: BookingStatus.extended,
      extensionFee: _currentActiveBooking!.extensionFee + fee,
    );

    final idx = _bookings.indexWhere((b) => b.id == updated.id);
    if (idx != -1) {
      _bookings[idx] = updated;
    }
    _currentActiveBooking = updated;
    _firestore.saveBooking(updated);

    if (!_isTestRuntime) {
      unawaited(_firestore.extendHoldOnServer(
        bookingId: updated.id,
        userId: _currentUser.id,
        minutes: minutes,
      ));
    }

    _logEvent(
      bookingId: updated.id,
      type: ParkingEventType.extended,
      description: 'Extended arrival deadline by $minutes min for LKR $fee',
    );

    notifyListeners();
  }

  // QR Check-in (M9)
  void checkIn() {
    if (_currentActiveBooking == null) return;

    final updated = _currentActiveBooking!.copyWith(
      status: BookingStatus.checkedIn,
      checkedInAt: DateTime.now(),
    );

    final idx = _bookings.indexWhere((b) => b.id == updated.id);
    if (idx != -1) {
      _bookings[idx] = updated;
    }
    final actualTravelMin = updated.checkedInAt != null
        ? updated.checkedInAt!.difference(updated.bookedAt).inMinutes
        : 0;

    _currentActiveBooking = updated;
    _firestore.saveBooking(updated);

    if (!_isTestRuntime) {
      unawaited(_firestore.checkInOnServer(
        qrToken: updated.qrToken,
        bookingId: updated.id,
        actualTravelMin: actualTravelMin,
      ));
    }

    _logEvent(
      bookingId: updated.id,
      type: ParkingEventType.checkedIn,
      description: 'Vehicle checked in at barrier for slot ${updated.slotId}',
      metadata: {
        'slotId': updated.slotId,
        'lotId': updated.lotId,
        'predictedEtaMinBaseline': updated.predictedEtaMinBaseline,
        'predictedEtaMinProvider': updated.predictedEtaMinProvider,
        'predictedEtaMinCorrected': updated.predictedEtaMinCorrected,
        'actualTravelMin': actualTravelMin,
        'modelVersion': updated.modelVersion,
      },
    );

    _stopHoldTimer();
    pauseMovementSimulation();
    notifyListeners();
  }

  // Cancel Booking (M6 / M8)
  void cancelBooking({bool autoCancelled = false}) {
    if (_currentActiveBooking == null) return;
    _stopHoldTimer();
    pauseMovementSimulation();

    final booking = _currentActiveBooking!;
    final updated = booking.copyWith(
      status: autoCancelled
          ? BookingStatus.autoCancelled
          : BookingStatus.cancelled,
    );

    // Free the slot
    final lotIndex = _lots.indexWhere((l) => l.id == booking.lotId);
    if (lotIndex != -1) {
      final lot = _lots[lotIndex];
      final updatedSlots = lot.slots.map((s) {
        if (s.id == booking.slotId) {
          return s.copyWith(state: SlotState.free);
        }
        return s;
      }).toList();

      _lots[lotIndex] = lot.copyWith(
        freeSlots: (lot.freeSlots + 1).clamp(0, lot.totalSlots),
        slots: updatedSlots,
      );
    }

    final idx = _bookings.indexWhere((b) => b.id == updated.id);
    if (idx != -1) {
      _bookings[idx] = updated;
    }
    _currentActiveBooking = null;
    _firestore.saveBooking(updated);

    if (!_isTestRuntime && !autoCancelled) {
      unawaited(_firestore.cancelBookingOnServer(
        bookingId: booking.id,
        userId: _currentUser.id,
      ));
    }

    unawaited(_firestore.updateSlotState(
      lotId: booking.lotId,
      slotId: booking.slotId,
      state: SlotState.free,
    ));

    _logEvent(
      bookingId: updated.id,
      type: autoCancelled
          ? ParkingEventType.autoCancelled
          : ParkingEventType.cancelled,
      description: autoCancelled
          ? 'Auto-cancelled after 15 min grace expiry'
          : 'User cancelled reservation',
    );

    notifyListeners();
  }

  // Complete Payment & Exit (M11)
  void completePayment(int finalAmount) {
    if (_currentActiveBooking == null) return;
    _stopHoldTimer();

    final booking = _currentActiveBooking!;
    final updated = booking.copyWith(
      status: BookingStatus.completed,
      finalFee: finalAmount,
      completedAt: DateTime.now(),
    );

    // Free the slot
    final lotIndex = _lots.indexWhere((l) => l.id == booking.lotId);
    if (lotIndex != -1) {
      final lot = _lots[lotIndex];
      final updatedSlots = lot.slots.map((s) {
        if (s.id == booking.slotId) {
          return s.copyWith(state: SlotState.free);
        }
        return s;
      }).toList();

      _lots[lotIndex] = lot.copyWith(
        freeSlots: (lot.freeSlots + 1).clamp(0, lot.totalSlots),
        slots: updatedSlots,
      );
    }

    final idx = _bookings.indexWhere((b) => b.id == updated.id);
    if (idx != -1) {
      _bookings[idx] = updated;
    }
    _currentActiveBooking = null;
    _firestore.saveBooking(updated);

    unawaited(_firestore.updateSlotState(
      lotId: booking.lotId,
      slotId: booking.slotId,
      state: SlotState.free,
    ));

    _logEvent(
      bookingId: updated.id,
      type: ParkingEventType.completed,
      description: 'Paid LKR $finalAmount and exited parking',
    );

    pauseMovementSimulation();
    notifyListeners();
  }

  // Hold-Time & Countdown Display (UI Only - Server handles auto-release)
  Timer? _holdCountdownTimer;

  bool get _isTestRuntime {
    try {
      return !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  void _startHoldTimer() {
    _stopHoldTimer();
    if (_isTestRuntime) return;
    // UI countdown ticker only; client DOES NOT cancel reservations.
    // Autonomous server sweeper autoReleaseExpiredHolds handles releases idempotently.
    _holdCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_currentActiveBooking == null ||
          _currentActiveBooking!.status == BookingStatus.checkedIn ||
          _currentActiveBooking!.status == BookingStatus.completed ||
          _currentActiveBooking!.status == BookingStatus.cancelled ||
          _currentActiveBooking!.status == BookingStatus.autoCancelled) {
        _stopHoldTimer();
        return;
      }

      notifyListeners();
    });
  }

  void _stopHoldTimer() {
    _holdCountdownTimer?.cancel();
    _holdCountdownTimer = null;
  }

  Duration get remainingHoldDuration {
    if (_currentActiveBooking == null) return Duration.zero;
    return _currentActiveBooking!.remainingHoldDuration;
  }

  void checkAndAutoReleaseExpiredBookings() {
    if (_currentActiveBooking != null &&
        (_currentActiveBooking!.status == BookingStatus.reserved ||
         _currentActiveBooking!.status == BookingStatus.upgraded) &&
        _currentActiveBooking!.isHoldExpired) {
      cancelBooking(autoCancelled: true);
    }
  }

  /// Fast-forwards the simulation to the scheduled arrival time so examiners can observe
  /// the 15-minute barrier arrival countdown start immediately.
  void fastForwardToArrivalTime() {
    if (_currentActiveBooking == null) return;
    final now = DateTime.now();
    final updated = _currentActiveBooking!.copyWith(
      arrivalTime: now,
      holdExpiresAt: now.add(const Duration(minutes: 15)),
    );
    final idx = _bookings.indexWhere((b) => b.id == updated.id);
    if (idx != -1) {
      _bookings[idx] = updated;
    }
    _currentActiveBooking = updated;
    _firestore.saveBooking(updated);
    _logEvent(
      bookingId: updated.id,
      type: ParkingEventType.booked,
      description: 'Trip fast-forwarded to arrival time (15m barrier hold activated)',
    );
    notifyListeners();
  }

  /// Fast-forwards the hold deadline to remaining duration (default 10s) for live evaluation testing
  void fastForwardHoldTimer({Duration remaining = const Duration(seconds: 10)}) {
    if (_currentActiveBooking == null) return;
    final updated = _currentActiveBooking!.copyWith(
      holdExpiresAt: DateTime.now().add(remaining),
    );
    final idx = _bookings.indexWhere((b) => b.id == updated.id);
    if (idx != -1) {
      _bookings[idx] = updated;
    }
    _currentActiveBooking = updated;
    _firestore.saveBooking(updated);
    _logEvent(
      bookingId: updated.id,
      type: ParkingEventType.booked,
      description: 'Hold timer accelerated to ${remaining.inSeconds}s (Evaluation Simulation)',
    );
    notifyListeners();
  }

  /// Extends the hold window by the specified duration (default +5m)
  void extendHoldDuration({Duration extension = const Duration(minutes: 5)}) {
    if (_currentActiveBooking == null) return;
    final currentDeadline = _currentActiveBooking!.effectiveHoldDeadline;
    final updated = _currentActiveBooking!.copyWith(
      holdExpiresAt: currentDeadline.add(extension),
      status: BookingStatus.extended,
      extensionFee: _currentActiveBooking!.extensionFee + 50,
    );
    final idx = _bookings.indexWhere((b) => b.id == updated.id);
    if (idx != -1) {
      _bookings[idx] = updated;
    }
    _currentActiveBooking = updated;
    _firestore.saveBooking(updated);
    _logEvent(
      bookingId: updated.id,
      type: ParkingEventType.extended,
      description: 'Hold time extended by ${extension.inMinutes} mins',
    );
    notifyListeners();
  }

  // Telemetry logger (SYS-08)
  void _logEvent({
    required String bookingId,
    required ParkingEventType type,
    required String description,
    Map<String, dynamic> metadata = const {},
  }) {
    final event = ParkingEvent(
      id: 'EV-${DateTime.now().millisecondsSinceEpoch}',
      bookingId: bookingId,
      type: type,
      timestamp: DateTime.now(),
      description: description,
      metadata: metadata,
    );
    _events.insert(0, event);
    _persistBookings();
  }

  // --- Subsystem Hardware Integrations & Simulation (SYS-09) ---

  Stream<List<AdminAlert>> streamAdminAlerts({String? lotId}) {
    return _firestore.streamAdminAlerts(lotId: lotId);
  }

  Future<Map<String, dynamic>> simulateCctvReading({
    required String lotId,
    required String slotId,
    required bool occupied,
    double confidence = 0.95,
    DateTime? timestamp,
    bool? violation,
    String cameraApiKey = 'cctv-secret-key-cam-01',
  }) async {
    return await _firestore.ingestOccupancy(
      lotId: lotId,
      slotId: slotId,
      occupied: occupied,
      confidence: confidence,
      timestamp: timestamp,
      violation: violation,
      cameraApiKey: cameraApiKey,
    );
  }

  Future<Map<String, dynamic>> simulateBarrierValidation({
    required String qrToken,
    required String barrierId,
    int? actualTravelMin,
    String barrierApiKey = 'barrier-secret-key-gate-01',
  }) async {
    return await _firestore.validateBarrierQr(
      qrToken: qrToken,
      barrierId: barrierId,
      actualTravelMin: actualTravelMin,
      barrierApiKey: barrierApiKey,
    );
  }

  Future<Map<String, dynamic>> simulatePaymentSettlement({
    required String bookingId,
    required String paymentRef,
    required int amountPaid,
    String paymentMethod = 'card',
    DateTime? timestamp,
    String paymentApiKey = 'payment-secret-key-svc-01',
  }) async {
    return await _firestore.submitPaymentCompleted(
      bookingId: bookingId,
      paymentRef: paymentRef,
      amountPaid: amountPaid,
      paymentMethod: paymentMethod,
      timestamp: timestamp,
      paymentApiKey: paymentApiKey,
    );
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _stopHoldTimer();
    super.dispose();
  }
}
