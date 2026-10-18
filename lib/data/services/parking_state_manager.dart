import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../features/reoptimization/engine/reoptimization_engine.dart';
import '../../features/reoptimization/engine/scoring_weights.dart';
import '../../features/reoptimization/engine/slot_score_result.dart';
import '../../features/reoptimization/engine/upgrade_evaluation_result.dart';
import '../models/booking_model.dart';
import '../models/parking_event_model.dart';
import '../models/parking_lot_model.dart';
import '../models/parking_slot_model.dart';
import '../models/user_model.dart';
import '../models/vehicle_model.dart';
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
    } catch (_) {
      _isLoggedIn = false;
    } finally {
      _isInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
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

  void updateScoringWeights(ScoringWeights newWeights) {
    _engine.weights = newWeights;
    notifyListeners();
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
    } else {
      _currentActiveBooking = null;
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
    _isLoggedIn = true;
    if (email.toLowerCase() == 'anuk@example.com' || email.toLowerCase() == 'demo@example.com') {
      _currentUser = MockData.initialUser.copyWith(email: email);
    } else {
      _currentUser = User(
        id: 'user-${DateTime.now().millisecondsSinceEpoch}',
        name: email.split('@').first,
        email: email,
        phone: '+94 77 123 4567',
        vehicles: const [],
        preferences: const UserPreferences(),
      );
    }
    await _persistSession();
    notifyListeners();
  }

  Future<void> completeVehicleOnboarding(Vehicle vehicle) async {
    final updatedVehicles = [vehicle.copyWith(isDefault: true)];
    _currentUser = _currentUser.copyWith(vehicles: updatedVehicles);
    await _persistSession();
    notifyListeners();
  }

  Future<void> logout() async {
    _isLoggedIn = false;
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
    notifyListeners();
  }

  Future<void> setDefaultVehicle(String vehicleId) async {
    final updated = _currentUser.vehicles.map((v) {
      return v.copyWith(isDefault: v.id == vehicleId);
    }).toList();
    _currentUser = _currentUser.copyWith(vehicles: updated);
    await _persistSession();
    notifyListeners();
  }

  Future<void> updatePreferences(UserPreferences prefs) async {
    _currentUser = _currentUser.copyWith(preferences: prefs);
    await _persistSession();
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

  // Booking Flow (M5)
  Booking reserveSlot({
    required ParkingLot lot,
    required ParkingSlot slot,
    required DateTime arrivalTime,
    required int durationHours,
  }) {
    final vehicle = _currentUser.defaultVehicle ??
        const Vehicle(
          id: 'veh-temp',
          plateNumber: 'CAB-4821',
          type: VehicleType.sedan,
          size: VehicleSize.medium,
        );

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
    );

    // Update slot state to taken/yours in lot
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
    _firestore.saveBooking(newBooking);
    _etaMinutes = _initialEtaMinutes;
    _distanceKm = _initialDistanceKm;
    _routeProgress = 0.0;
    _hasTriggeredAutoUpgrade = false;
    _hasArrivedAtDestination = false;
    pauseMovementSimulation();

    _logEvent(
      bookingId: newBooking.id,
      type: ParkingEventType.booked,
      description: 'Booked slot ${slot.id} in ${lot.name}',
    );

    notifyListeners();
    return newBooking;
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
    _currentActiveBooking = updated;
    _firestore.saveBooking(updated);

    _logEvent(
      bookingId: updated.id,
      type: ParkingEventType.checkedIn,
      description: 'Vehicle checked in at barrier for slot ${updated.slotId}',
    );

    pauseMovementSimulation();
    notifyListeners();
  }

  // Cancel Booking (M6 / M8)
  void cancelBooking({bool autoCancelled = false}) {
    if (_currentActiveBooking == null) return;
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

    _logEvent(
      bookingId: updated.id,
      type: ParkingEventType.completed,
      description: 'Paid LKR $finalAmount and exited parking',
    );

    pauseMovementSimulation();
    notifyListeners();
  }

  // Telemetry logger (SYS-08)
  void _logEvent({
    required String bookingId,
    required ParkingEventType type,
    required String description,
  }) {
    final event = ParkingEvent(
      id: 'EV-${DateTime.now().millisecondsSinceEpoch}',
      bookingId: bookingId,
      type: type,
      timestamp: DateTime.now(),
      description: description,
    );
    _events.insert(0, event);
    _persistBookings();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    super.dispose();
  }
}
