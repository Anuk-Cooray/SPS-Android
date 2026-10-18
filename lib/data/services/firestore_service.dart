import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/theme/app_theme.dart';
import '../models/booking_model.dart';
import '../models/parking_event_model.dart';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  FirebaseFirestore? _firestore;
  bool _isAvailable = false;

  bool get isAvailable => _isAvailable;

  void initialize() {
    try {
      _firestore = FirebaseFirestore.instance;
      _isAvailable = true;
    } catch (e) {
      _isAvailable = false;
      debugPrint('[FirestoreService] Firestore unavailable (offline or desktop mode): $e');
    }
  }

  // --- Bookings Collection ---

  CollectionReference<Map<String, dynamic>>? get _bookingsRef =>
      _isAvailable ? _firestore!.collection('bookings') : null;

  CollectionReference<Map<String, dynamic>>? get _eventsRef =>
      _isAvailable ? _firestore!.collection('telemetry_events') : null;

  CollectionReference<Map<String, dynamic>>? get _lotsRef =>
      _isAvailable ? _firestore!.collection('lots') : null;

  /// Creates or overwrites a booking document in Firestore
  Future<void> saveBooking(Booking booking) async {
    if (!_isAvailable || _bookingsRef == null) return;
    try {
      await _bookingsRef!.doc(booking.id).set(booking.toJson(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('[FirestoreService] Failed to save booking ${booking.id}: $e');
    }
  }

  /// Updates booking state (e.g. upgraded slot, check-in timestamp, final payment)
  Future<void> updateBookingStatus({
    required String bookingId,
    required BookingStatus status,
    String? newSlotId,
    int? distanceSavedMeters,
    DateTime? checkedInAt,
    DateTime? completedAt,
    int? finalFee,
  }) async {
    if (!_isAvailable || _bookingsRef == null) return;
    try {
      final updates = <String, dynamic>{
        'status': status.name,
      };
      if (newSlotId != null) updates['slotId'] = newSlotId;
      if (distanceSavedMeters != null) updates['distanceSavedMeters'] = distanceSavedMeters;
      if (checkedInAt != null) updates['checkedInAt'] = checkedInAt.toIso8601String();
      if (completedAt != null) updates['completedAt'] = completedAt.toIso8601String();
      if (finalFee != null) updates['finalFee'] = finalFee;

      await _bookingsRef!.doc(bookingId).update(updates);
    } catch (e) {
      debugPrint('[FirestoreService] Failed to update booking $bookingId: $e');
    }
  }

  /// Streams active and historical bookings for a specific driver
  Stream<List<Booking>> streamUserBookings(String userId) {
    if (!_isAvailable || _bookingsRef == null) {
      return const Stream.empty();
    }
    return _bookingsRef!
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Booking.fromJson(doc.data()))
          .toList();
    });
  }

  /// Streams all reservations across all campus lots for admin monitoring
  Stream<List<Booking>> streamAllBookings() {
    if (!_isAvailable || _bookingsRef == null) {
      return const Stream.empty();
    }
    return _bookingsRef!.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Booking.fromJson(doc.data()))
          .toList();
    });
  }

  // --- Telemetry & Lifecycle Events (SYS-08) ---

  /// Logs an algorithmic decision or lifecycle transition event to Firestore
  Future<void> saveEvent(ParkingEvent event) async {
    if (!_isAvailable || _eventsRef == null) return;
    try {
      await _eventsRef!.doc(event.id).set(event.toJson());
    } catch (e) {
      debugPrint('[FirestoreService] Failed to save telemetry event ${event.id}: $e');
    }
  }

  /// Streams real-time telemetry events for the research audit log
  Stream<List<ParkingEvent>> streamTelemetryEvents() {
    if (!_isAvailable || _eventsRef == null) {
      return const Stream.empty();
    }
    return _eventsRef!
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ParkingEvent.fromJson(doc.data()))
          .toList();
    });
  }

  // --- Campus Lots & CCTV Camera Occupancy Updates ---

  /// Streams live lot slot states updated by CCTV vision pipeline (Samudi's module)
  Stream<Map<String, SlotState>> streamSlotOccupancy(String lotId) {
    if (!_isAvailable || _lotsRef == null) {
      return const Stream.empty();
    }
    return _lotsRef!.doc(lotId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null || !data.containsKey('slots')) return {};
      final slotsMap = data['slots'] as Map<String, dynamic>;
      final result = <String, SlotState>{};
      slotsMap.forEach((slotId, stateString) {
        result[slotId] = (stateString == 'occupied' || stateString == 'taken')
            ? SlotState.taken
            : SlotState.free;
      });
      return result;
    });
  }
}
