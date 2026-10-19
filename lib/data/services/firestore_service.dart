import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/theme/app_theme.dart';
import '../models/booking_model.dart';
import '../models/parking_event_model.dart';
import '../models/parking_lot_model.dart';
import '../models/parking_slot_model.dart';
import '../models/user_model.dart';
import '../models/vehicle_model.dart';

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
  final Map<String, User> _localUsers = {};

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

  CollectionReference<Map<String, dynamic>>? get _usersRef =>
      _isAvailable ? _firestore!.collection('users') : null;

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

  // --- Campus Lots & Real-Time Bay Occupancy ---

  /// Seeds default campus lots into Firestore if the 'lots' collection is empty
  Future<void> seedInitialLotsIfEmpty(List<ParkingLot> defaultLots) async {
    if (!_isAvailable || _lotsRef == null) return;
    try {
      final snapshot = await _lotsRef!.limit(1).get().timeout(const Duration(seconds: 2));
      if (snapshot.docs.isEmpty) {
        for (final lot in defaultLots) {
          await _lotsRef!.doc(lot.id).set(lot.toJson());
        }
        debugPrint('[FirestoreService] Seeded ${defaultLots.length} campus lots to Firestore');
      }
    } catch (e) {
      debugPrint('[FirestoreService] Seed lots error: $e');
    }
  }

  /// Updates the occupancy state of a specific parking slot in a lot in Firestore
  Future<void> updateSlotState({
    required String lotId,
    required String slotId,
    required SlotState state,
    String? reservedBy,
  }) async {
    if (!_isAvailable || _lotsRef == null) return;
    try {
      final docRef = _lotsRef!.doc(lotId);
      final doc = await docRef.get().timeout(const Duration(seconds: 2));
      if (doc.exists && doc.data() != null) {
        final lot = ParkingLot.fromJson(doc.data()!);
        final updatedSlots = lot.slots.map((s) {
          if (s.id == slotId) {
            return s.copyWith(state: state);
          }
          return s;
        }).toList();
        final freeCount = updatedSlots.where((s) => s.state == SlotState.free).length;
        await docRef.update({
          'slots': updatedSlots.map((s) => s.toJson()).toList(),
          'freeSlots': freeCount,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('[FirestoreService] Error updating slot $slotId: $e');
    }
  }

  /// Streams real-time campus parking lots and slot states
  Stream<List<ParkingLot>> streamLots() {
    if (!_isAvailable || _lotsRef == null) {
      return const Stream.empty();
    }
    return _lotsRef!.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => ParkingLot.fromJson(doc.data()))
          .toList();
    });
  }

  /// Streams live lot slot states updated by CCTV vision pipeline
  Stream<Map<String, SlotState>> streamSlotOccupancy(String lotId) {
    if (!_isAvailable || _lotsRef == null) {
      return const Stream.empty();
    }
    return _lotsRef!.doc(lotId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null || !data.containsKey('slots')) return {};
      final slotsList = data['slots'] as List<dynamic>? ?? [];
      final result = <String, SlotState>{};
      for (final s in slotsList) {
        if (s is Map<String, dynamic>) {
          final slotId = s['id'] as String? ?? '';
          final stateString = s['state'] as String? ?? 'free';
          result[slotId] = (stateString == 'occupied' || stateString == 'taken')
              ? SlotState.taken
              : SlotState.free;
        }
      }
      return result;
    });
  }

  // --- Real Driver Profiles & Registered Vehicles ---

  /// Saves or updates a real user profile and vehicle fleet in Firestore
  Future<void> saveUser(User user) async {
    final cleanEmail = user.email.trim().toLowerCase();
    _localUsers[cleanEmail] = user;
    if (!_isAvailable || _usersRef == null) return;
    try {
      await _usersRef!
          .doc(cleanEmail)
          .set(user.toJson(), SetOptions(merge: true))
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('[FirestoreService] Failed to save user $cleanEmail: $e');
    }
  }

  /// Fetches an existing user from Firestore, with fallback to local cache
  Future<User?> fetchUser(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    if (_isAvailable && _usersRef != null) {
      try {
        final doc = await _usersRef!
            .doc(cleanEmail)
            .get()
            .timeout(const Duration(milliseconds: 1500));
        if (doc.exists && doc.data() != null) {
          final user = User.fromJson(doc.data()!);
          _localUsers[cleanEmail] = user;
          return user;
        }
      } catch (e) {
        debugPrint('[FirestoreService] Firestore get user timeout: $e');
      }
    }
    return _localUsers[cleanEmail];
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
