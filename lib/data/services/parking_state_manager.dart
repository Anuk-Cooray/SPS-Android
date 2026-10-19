import 'package:flutter/foundation.dart';

import 'dart:async';

import '../../core/theme/app_theme.dart';
import '../models/booking_model.dart';
import '../models/parking_event_model.dart';
import '../models/parking_lot_model.dart';
import '../models/parking_slot_model.dart';
import '../models/user_model.dart';
import '../models/vehicle_model.dart';
import 'mock_data.dart';
import 'ai_occupancy_service.dart';

class ParkingStateManager extends ChangeNotifier {
  static const aiLotId = 'lot-main';
  final AiOccupancyService _aiService;
  Timer? _aiRefreshTimer;
  final Set<String> _aiBookingIds = {};
  bool _aiRefreshing = false;
  String? _aiError;
  User _currentUser = MockData.initialUser;
  bool _isLoggedIn = true;
  final List<ParkingLot> _lots = MockData.getInitialLots();
  final List<Booking> _bookings = MockData.getInitialBookings();
  final List<ParkingEvent> _events = [];

  // Active navigation / in-transit state
  Booking? _currentActiveBooking;
  int _etaMinutes = 12;
  double _distanceKm = 4.2;
  bool _upgradeOfferAvailable = false;
  ParkingSlot? _upgradeCandidateSlot;

  ParkingStateManager({AiOccupancyService? aiService})
    : _aiService = aiService ?? AiOccupancyService() {
    _refreshActiveBooking();
    refreshAiOccupancy();
    _aiRefreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => refreshAiOccupancy(),
    );
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
  bool get isAiRefreshing => _aiRefreshing;
  String? get aiError => _aiError;

  // Active bookings list
  List<Booking> get activeBookings =>
      _bookings.where((b) => b.isActive).toList();

  List<Booking> get upcomingBookings =>
      _bookings.where((b) => b.status == BookingStatus.reserved).toList();

  List<Booking> get historyBookings => _bookings
      .where(
        (b) =>
            b.status == BookingStatus.completed ||
            b.status == BookingStatus.cancelled ||
            b.status == BookingStatus.autoCancelled,
      )
      .toList();

  void _refreshActiveBooking() {
    final active = _bookings.where((b) => b.isActive).toList();
    if (active.isNotEmpty) {
      _currentActiveBooking = active.first;
    } else {
      _currentActiveBooking = null;
    }
  }

  /// Refreshes only the explicitly mapped AI lot. Other team mock lots remain
  /// untouched until they receive their own backend integration.
  Future<void> refreshAiOccupancy() async {
    if (_aiRefreshing) return;
    _aiRefreshing = true;
    try {
      final slots = await _aiService.fetchLotSlots(aiLotId);
      _replaceAiLot(slots);
      _aiError = null;
    } catch (_) {
      _aiError = 'Live occupancy is offline. Slot availability is unverified.';
      final lotIndex = _lots.indexWhere((lot) => lot.id == aiLotId);
      if (lotIndex != -1 && _lots[lotIndex].slots.isEmpty) {
        _replaceAiLot(
          List.generate(
            195,
            (index) => ParkingSlot(
              id: '${index + 1}',
              lotId: aiLotId,
              row: String.fromCharCode(65 + index ~/ 15),
              number: index + 1,
              state: SlotState.unknown,
              size: VehicleSize.medium,
              walkingDistanceMeters: 20 + index * 2,
              cameraId: 'ai-camera-1',
            ),
          ),
        );
      }
    } finally {
      _aiRefreshing = false;
      notifyListeners();
    }
  }

  void _replaceAiLot(List<ParkingSlot> slots) {
    final index = _lots.indexWhere((lot) => lot.id == aiLotId);
    if (index == -1) return;
    final lot = _lots[index];
    _lots[index] = lot.copyWith(
      totalSlots: slots.length,
      freeSlots: slots.where((slot) => slot.state == SlotState.free).length,
      slots: slots,
    );
  }

  Future<Booking> reserveAiSlot({
    required ParkingLot lot,
    required ParkingSlot slot,
    required DateTime arrivalTime,
    required int durationHours,
  }) async {
    final vehicle =
        _currentUser.defaultVehicle ??
        const Vehicle(
          id: 'veh-temp',
          plateNumber: 'CAB-4821',
          type: VehicleType.sedan,
          size: VehicleSize.medium,
        );
    final response = await _aiService.reserve(
      lotId: lot.id,
      slotId: slot.id,
      userId: _currentUser.id,
      vehicleId: vehicle.id,
      vehiclePlate: vehicle.plateNumber,
      arrivalTime: arrivalTime,
      durationHours: durationHours,
    );
    final booking = Booking(
      id: response['id'].toString(),
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
      qrToken: 'QR-${response['id']}-${slot.id}',
    );
    _aiBookingIds.add(booking.id);
    _bookings.insert(0, booking);
    _currentActiveBooking = booking;
    await refreshAiOccupancy();
    return booking;
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

  // AI Slot Scoring & Recommendation (SYS-01)
  ParkingSlot? getRecommendedSlot(ParkingLot lot) {
    final availableSlots = lot.slots.where((s) => s.isAvailable).toList();
    if (availableSlots.isEmpty) return null;

    final defaultVeh = _currentUser.defaultVehicle;
    final userSize = defaultVeh?.size ?? VehicleSize.medium;
    final preferEntrance = _currentUser.preferences.preferNearEntrance;

    // Multi-criteria scoring:
    // Score = w_dist * DistScore + w_size * SizeFit + w_pref * PrefBonus
    // Lower walking distance is better, matching size has highest fit
    availableSlots.sort((a, b) {
      double scoreA = 0;
      double scoreB = 0;

      // Distance factor (lower walking distance = higher score)
      scoreA += (200 - a.walkingDistanceMeters).clamp(0, 200) * 0.5;
      scoreB += (200 - b.walkingDistanceMeters).clamp(0, 200) * 0.5;

      // Size match
      if (a.size == userSize) scoreA += 50;
      if (b.size == userSize) scoreB += 50;

      // Entrance preference
      if (preferEntrance && a.walkingDistanceMeters <= 50) scoreA += 30;
      if (preferEntrance && b.walkingDistanceMeters <= 50) scoreB += 30;

      return scoreB.compareTo(scoreA); // descending
    });

    return availableSlots.first;
  }

  // Booking Flow (M5)
  Booking reserveSlot({
    required ParkingLot lot,
    required ParkingSlot slot,
    required DateTime arrivalTime,
    required int durationHours,
  }) {
    final vehicle =
        _currentUser.defaultVehicle ??
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
    if (_currentActiveBooking == null ||
        !_currentUser.preferences.allowUpgradeOffers) {
      return;
    }

    final lot = _lots.firstWhere(
      (l) => l.id == _currentActiveBooking!.lotId,
      orElse: () => _lots.first,
    );

    // Find candidate slot that has lower walking distance
    final candidates = lot.slots
        .where((s) => s.isAvailable && s.id != _currentActiveBooking!.slotId)
        .toList();

    if (candidates.isNotEmpty) {
      candidates.sort(
        (a, b) => a.walkingDistanceMeters.compareTo(b.walkingDistanceMeters),
      );
      final bestCandidate = candidates.first;

      _upgradeCandidateSlot = bestCandidate;
      _upgradeOfferAvailable = true;

      _logEvent(
        bookingId: _currentActiveBooking!.id,
        type: ParkingEventType.offered,
        description:
            'Upgrade offered: ${bestCandidate.id} (walk ${bestCandidate.walkingDistanceMeters}m)',
      );

      notifyListeners();
    }
  }

  // Accept Upgrade (M7 / SYS-04)
  void acceptUpgrade() {
    if (_currentActiveBooking == null || _upgradeCandidateSlot == null) return;

    final oldSlotId = _currentActiveBooking!.slotId;
    final newSlot = _upgradeCandidateSlot!;
    final savedMeters = 120; // 160m - 40m

    final updatedBooking = _currentActiveBooking!.copyWith(
      slotId: newSlot.id,
      originalSlotId: oldSlotId,
      status: BookingStatus.upgraded,
      distanceSavedMeters: savedMeters,
      qrToken: 'QR-UPGRADED-${newSlot.id}',
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

    final bookingIndex = _bookings.indexWhere((b) => b.id == updatedBooking.id);
    if (bookingIndex != -1) {
      _bookings[bookingIndex] = updatedBooking;
    }

    _currentActiveBooking = updatedBooking;
    _upgradeOfferAvailable = false;
    _upgradeCandidateSlot = null;

    _logEvent(
      bookingId: updatedBooking.id,
      type: ParkingEventType.accepted,
      description: 'Accepted upgrade to ${newSlot.id} (Saved ${savedMeters}m)',
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
      description:
          'Declined upgrade offer. Kept ${_currentActiveBooking!.slotId}',
    );

    notifyListeners();
  }

  // Late Arrival Extension (M8)
  void extendBooking({int minutes = 15, int fee = 50}) {
    if (_currentActiveBooking == null) return;

    final updated = _currentActiveBooking!.copyWith(
      arrivalTime: _currentActiveBooking!.arrivalTime.add(
        Duration(minutes: minutes),
      ),
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
  Future<void> cancelBooking({bool autoCancelled = false}) async {
    if (_currentActiveBooking == null) return;

    final booking = _currentActiveBooking!;
    if (_aiBookingIds.contains(booking.id)) {
      try {
        await _aiService.cancel(booking.id);
      } catch (_) {
        return;
      }
      _aiBookingIds.remove(booking.id);
    }
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
    if (booking.lotId == aiLotId) await refreshAiOccupancy();
  }

  @override
  void dispose() {
    _aiRefreshTimer?.cancel();
    super.dispose();
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
