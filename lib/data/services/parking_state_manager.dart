import 'package:flutter/foundation.dart';
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
import 'mock_data.dart';

class ParkingStateManager extends ChangeNotifier {
  User _currentUser = MockData.initialUser;
  bool _isLoggedIn = true;
  final List<ParkingLot> _lots = MockData.getInitialLots();
  final List<Booking> _bookings = MockData.getInitialBookings();
  final List<ParkingEvent> _events = [];

  // Mathematical scoring engine & re-optimization (SYS-01, SYS-03)
  final ReoptimizationEngine _engine = ReoptimizationEngine();
  UpgradeEvaluationResult? _lastUpgradeEvaluation;

  // Active navigation / in-transit state
  Booking? _currentActiveBooking;
  int _etaMinutes = 12;
  double _distanceKm = 4.2;
  bool _upgradeOfferAvailable = false;
  ParkingSlot? _upgradeCandidateSlot;

  ParkingStateManager() {
    _refreshActiveBooking();
    _initializeMockEvents();
  }

  void _initializeMockEvents() {
    final now = DateTime.now();
    _events.addAll([
      ParkingEvent(
        id: 'EV-1005',
        bookingId: 'BK-2041',
        type: ParkingEventType.booked,
        timestamp: now.subtract(const Duration(minutes: 8)),
        description: 'Multi-criteria recommendation allocated slot A-03 (Score: 88.5)',
      ),
      ParkingEvent(
        id: 'EV-1004',
        bookingId: 'BK-2035',
        type: ParkingEventType.checkedIn,
        timestamp: now.subtract(const Duration(minutes: 38)),
        description: 'Vehicle NB-5532 verified and barrier raised for slot B-04',
      ),
      ParkingEvent(
        id: 'EV-1003',
        bookingId: 'BK-1980',
        type: ParkingEventType.accepted,
        timestamp: now.subtract(const Duration(hours: 3)),
        description: 'Accepted upgrade to C-11: Saved 80m walking (Score improved +25.0%)',
      ),
      ParkingEvent(
        id: 'EV-1002',
        bookingId: 'BK-1980',
        type: ParkingEventType.offered,
        timestamp: now.subtract(const Duration(hours: 3, minutes: 1)),
        description: 'Found superior slot C-11 in New Building P2 (ETA: 8 min)',
      ),
      ParkingEvent(
        id: 'EV-1001',
        bookingId: 'BK-1950',
        type: ParkingEventType.autoCancelled,
        timestamp: now.subtract(const Duration(days: 6)),
        description: 'Auto-cancelled after 15 min grace window expired without check-in',
      ),
    ]);
  }

  // Getters
  User get currentUser => _currentUser;
  bool get isLoggedIn => _isLoggedIn;
  List<ParkingLot> get lots => _lots;
  List<Booking> get bookings => _bookings;
  List<ParkingEvent> get events => _events;
  Booking? get currentActiveBooking => _currentActiveBooking;
  int get etaMinutes => _etaMinutes;
  double get distanceKm => _distanceKm;
  bool get upgradeOfferAvailable => _upgradeOfferAvailable;
  ParkingSlot? get upgradeCandidateSlot => _upgradeCandidateSlot;
  ReoptimizationEngine get engine => _engine;
  ScoringWeights get scoringWeights => _engine.weights;
  UpgradeEvaluationResult? get lastUpgradeEvaluation => _lastUpgradeEvaluation;

  void updateScoringWeights(ScoringWeights newWeights) {
    _engine.weights = newWeights;
    notifyListeners();
  }

  // Active bookings list
  List<Booking> get activeBookings =>
      _bookings.where((b) => b.isActive).toList();

  List<Booking> get upcomingBookings =>
      _bookings.where((b) => b.status == BookingStatus.reserved).toList();

  List<Booking> get historyBookings => _bookings
      .where((b) =>
          b.status == BookingStatus.completed ||
          b.status == BookingStatus.cancelled ||
          b.status == BookingStatus.autoCancelled)
      .toList();

  void _refreshActiveBooking() {
    final active = _bookings.where((b) => b.isActive).toList();
    if (active.isNotEmpty) {
      _currentActiveBooking = active.first;
    } else {
      _currentActiveBooking = null;
    }
  }

  // Auth & Profile
  void login(String email) {
    _isLoggedIn = true;
    _currentUser = _currentUser.copyWith(email: email);
    notifyListeners();
  }

  void logout() {
    _isLoggedIn = false;
    notifyListeners();
  }

  void addVehicle(Vehicle vehicle) {
    final updated = List<Vehicle>.from(_currentUser.vehicles);
    if (vehicle.isDefault) {
      for (int i = 0; i < updated.length; i++) {
        updated[i] = updated[i].copyWith(isDefault: false);
      }
    }
    updated.add(vehicle);
    _currentUser = _currentUser.copyWith(vehicles: updated);
    notifyListeners();
  }

  void setDefaultVehicle(String vehicleId) {
    final updated = _currentUser.vehicles.map((v) {
      return v.copyWith(isDefault: v.id == vehicleId);
    }).toList();
    _currentUser = _currentUser.copyWith(vehicles: updated);
    notifyListeners();
  }

  void updatePreferences(UserPreferences prefs) {
    _currentUser = _currentUser.copyWith(preferences: prefs);
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
    _etaMinutes = 12;
    _distanceKm = 4.2;

    _logEvent(
      bookingId: newBooking.id,
      type: ParkingEventType.booked,
      description: 'Booked slot ${slot.id} in ${lot.name}',
    );

    notifyListeners();
    return newBooking;
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

    _logEvent(
      bookingId: updated.id,
      type: ParkingEventType.checkedIn,
      description: 'Vehicle checked in at barrier for slot ${updated.slotId}',
    );

    notifyListeners();
  }

  // Cancel Booking (M6 / M8)
  void cancelBooking({bool autoCancelled = false}) {
    if (_currentActiveBooking == null) return;

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

    _logEvent(
      bookingId: updated.id,
      type: ParkingEventType.completed,
      description: 'Paid LKR $finalAmount and exited parking',
    );

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
  }
}
