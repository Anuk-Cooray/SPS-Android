import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/theme/app_theme.dart';
import '../models/booking_model.dart';
import '../models/parking_event_model.dart';

class OtpVerificationResult {
  final bool isValid;
  final String? errorMessage;

  const OtpVerificationResult({required this.isValid, this.errorMessage});
}

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  FirebaseFirestore? _firestore;
  bool _isAvailable = false;
  final Map<String, Map<String, dynamic>> _localVerifications = {};

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

  // --- Collections ---

  CollectionReference<Map<String, dynamic>>? get _bookingsRef =>
      _isAvailable ? _firestore!.collection('bookings') : null;

  CollectionReference<Map<String, dynamic>>? get _eventsRef =>
      _isAvailable ? _firestore!.collection('telemetry_events') : null;

  CollectionReference<Map<String, dynamic>>? get _lotsRef =>
      _isAvailable ? _firestore!.collection('lots') : null;

  CollectionReference<Map<String, dynamic>>? get _verificationsRef =>
      _isAvailable ? _firestore!.collection('email_verifications') : null;

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

  // --- Email OTP Verification Collection (M1) ---

  /// Generates a real 6-digit OTP code, persists it to Firestore with a 5-minute expiry,
  /// and stores it in the local memory cache for guaranteed offline reliability.
  Future<String> sendEmailVerificationOtp(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    final random = Random();
    final code = (100000 + random.nextInt(900000)).toString();
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(minutes: 5));

    final data = <String, dynamic>{
      'email': cleanEmail,
      'otp': code,
      'createdAt': now.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'isVerified': false,
      'attempts': 0,
    };

    _localVerifications[cleanEmail] = data;

    if (_isAvailable && _verificationsRef != null) {
      // Persist in background with timeout so network delays never block the driver
      _verificationsRef!
          .doc(cleanEmail)
          .set(data)
          .timeout(const Duration(seconds: 2))
          .catchError((e) {
        debugPrint('[FirestoreService] Offline or sync error for OTP: $e');
      });
    }

    return code;
  }

  /// Verifies the entered 6-digit code against Firestore / local cache.
  /// Enforces expiration and a 5-attempt limit to prevent brute force attacks.
  Future<OtpVerificationResult> verifyEmailOtp(String email, String enteredOtp) async {
    final cleanEmail = email.trim().toLowerCase();
    Map<String, dynamic>? record;

    if (_isAvailable && _verificationsRef != null) {
      try {
        final doc = await _verificationsRef!
            .doc(cleanEmail)
            .get()
            .timeout(const Duration(milliseconds: 1500));
        if (doc.exists && doc.data() != null) {
          record = doc.data();
        }
      } catch (e) {
        debugPrint('[FirestoreService] Firestore get verification timeout, falling back to local: $e');
      }
    }

    record ??= _localVerifications[cleanEmail];

    if (record == null) {
      return const OtpVerificationResult(
        isValid: false,
        errorMessage: 'No verification record found. Please request a new code.',
      );
    }

    final expiresAtStr = record['expiresAt'] as String?;
    final expiresAt = expiresAtStr != null ? DateTime.tryParse(expiresAtStr) : null;
    if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
      return const OtpVerificationResult(
        isValid: false,
        errorMessage: 'Verification code has expired. Please request a new code.',
      );
    }

    final attempts = (record['attempts'] as int? ?? 0) + 1;
    record['attempts'] = attempts;

    if (attempts > 5) {
      return const OtpVerificationResult(
        isValid: false,
        errorMessage: 'Too many incorrect attempts. Please request a fresh code.',
      );
    }

    final expectedOtp = record['otp'] as String? ?? '';
    if (expectedOtp != enteredOtp.trim()) {
      if (_isAvailable && _verificationsRef != null) {
        _verificationsRef!
            .doc(cleanEmail)
            .update({'attempts': attempts})
            .timeout(const Duration(seconds: 2))
            .catchError((_) {});
      }
      final remaining = 5 - attempts;
      return OtpVerificationResult(
        isValid: false,
        errorMessage: 'Incorrect code. $remaining attempt${remaining == 1 ? '' : 's'} remaining.',
      );
    }

    record['isVerified'] = true;
    if (_isAvailable && _verificationsRef != null) {
      _verificationsRef!
          .doc(cleanEmail)
          .update({
            'isVerified': true,
            'verifiedAt': DateTime.now().toIso8601String(),
          })
          .timeout(const Duration(seconds: 2))
          .catchError((_) {});
    }

    return const OtpVerificationResult(isValid: true);
  }
}
