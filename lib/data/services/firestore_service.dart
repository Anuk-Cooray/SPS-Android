import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../models/admin_alert_model.dart';
import '../models/booking_model.dart';
import '../models/parking_event_model.dart';
import '../models/parking_lot_model.dart';
import '../models/parking_slot_model.dart';
import '../models/trip_telemetry_model.dart';
import '../models/user_model.dart';
import '../models/vehicle_model.dart';
import 'cloud_functions_client.dart';
import 'email_otp_auth.dart';

class OtpVerificationResult {
  final bool isValid;
  final String? errorMessage;
  final AuthenticatedUser? user;

  const OtpVerificationResult({required this.isValid, this.errorMessage, this.user});
}

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  FirebaseFirestore? _firestore;
  bool _isAvailable = false;
  final CloudFunctionsClient _functions = CloudFunctionsClient();
  final Map<String, User> _localUsers = {};
  late EmailOtpAuthGateway _auth = FirebaseEmailOtpAuthGateway(_functions);

  static const int authEmulatorPort = 9099;
  static const int firestoreEmulatorPort = 8080;

  bool get isAvailable => _isAvailable;
  CloudFunctionsClient get functions => _functions;
  EmailOtpAuthGateway get auth => _auth;

  /// Replaces the sign-in backend (tests install a fake; the app always uses Firebase Auth).
  set authGateway(EmailOtpAuthGateway gateway) => _auth = gateway;

  void initialize({
    bool useEmulator = false,
    String? emulatorHost,
    int? emulatorPort,
  }) {
    try {
      _firestore = FirebaseFirestore.instance;
      _isAvailable = true;
      _functions.configure(
        projectId: Firebase.app().options.projectId,
        useEmulator: useEmulator,
        emulatorHost: emulatorHost,
        emulatorPort: emulatorPort,
      );
      _functions.idTokenProvider = () => _auth.getIdToken();
      if (useEmulator) {
        final host = _functions.emulatorHost;
        // Host mapping is done above (127.0.0.1 -> 10.0.2.2 only on the Android emulator); the
        // plugins' own mapping would also rewrite "localhost", breaking real devices on USB
        _firestore!.useFirestoreEmulator(host, firestoreEmulatorPort, automaticHostMapping: false);
        fb.FirebaseAuth.instance.useAuthEmulator(host, authEmulatorPort, automaticHostMapping: false);
        debugPrint('[FirestoreService] Using Firebase emulators at $host');
      }
    } catch (e) {
      _isAvailable = false;
      debugPrint('[FirestoreService] Firestore unavailable (offline or desktop mode): $e');
    }
  }

  // --- Collection References ---

  CollectionReference<Map<String, dynamic>>? get _bookingsRef =>
      _isAvailable ? _firestore!.collection('bookings') : null;

  CollectionReference<Map<String, dynamic>>? get _eventsRef =>
      _isAvailable ? _firestore!.collection('parking_events') : null;

  CollectionReference<Map<String, dynamic>>? get _parkingLotsRef =>
      _isAvailable ? _firestore!.collection('parking_lots') : null;

  CollectionReference<Map<String, dynamic>>? get _legacyLotsRef =>
      _isAvailable ? _firestore!.collection('lots') : null;

  CollectionReference<Map<String, dynamic>>? get _usersRef =>
      _isAvailable ? _firestore!.collection('users') : null;

  CollectionReference<Map<String, dynamic>>? get _tripTelemetryRef =>
      _isAvailable ? _firestore!.collection('trip_telemetry') : null;

  CollectionReference<Map<String, dynamic>>? get _adminAlertsRef =>
      _isAvailable ? _firestore!.collection('admin_alerts') : null;

  // --- Cloud Functions Callable Invocations (Server Reservation Authority) ---

  /// Invokes `createBooking` callable function to run an atomic server-side reservation transaction
  Future<Booking> createBookingOnServer({
    required String lotId,
    required String slotId,
    required String userId,
    required String vehiclePlate,
    required VehicleSize vehicleSize,
    required DateTime arrivalTime,
    required int durationHours,
    String? vehicleId,
    String? vehicleType,
    double? originLat,
    double? originLng,
    double? providerEtaMinutes,
    String? originZone,
    int? weatherFlag,
    int? holidayFlag,
    double? predictedEtaMinBaseline,
    double? predictedEtaMinProvider,
    double? predictedEtaMinCorrected,
    String? modelVersion,
  }) async {
    try {
      final payload = <String, dynamic>{
        'lotId': lotId,
        'slotId': slotId,
        'vehiclePlate': vehiclePlate,
        'vehicleSize': vehicleSize.name,
        'vehicleId': vehicleId ?? 'v-default',
        'vehicleType': vehicleType ?? 'sedan',
        'arrivalTime': arrivalTime.toUtc().toIso8601String(),
        'durationHours': durationHours,
        if (originLat != null && originLng != null)
          'driverOrigin': {
            'latitude': originLat,
            'longitude': originLng,
          },
        'providerEtaMinutes': ?providerEtaMinutes,
        'originZone': ?originZone,
        'weatherFlag': ?weatherFlag,
        'holidayFlag': ?holidayFlag,
      };

      final result = await _functions.call('createBooking', payload);
      final booking = Booking.fromJson(result);
      debugPrint('[FirestoreService] Server reservation confirmed: ${booking.id} (Slot: ${booking.slotId})');
      return booking;
    } on SlotCollisionException {
      // Pass collision exception directly to UI for "Slot just taken" prompt
      rethrow;
    } catch (e) {
      // A missing or rejected session must not be masked by a fake local booking
      if (e is CloudFunctionsException && (e.code == 'unauthenticated' || e.code == 'permission-denied')) {
        rethrow;
      }
      // Outside demo mode never show a booking the server did not confirm
      if (!AppConfig.kDemoMode) {
        debugPrint('[FirestoreService] Server createBooking call failed ($e)');
        if (e is CloudFunctionsException) rethrow;
        throw CloudFunctionsException(code: 'unavailable', message: 'Booking server unreachable: $e');
      }
      debugPrint('[FirestoreService] Server createBooking call failed ($e), executing demo-mode local fallback');
      return _localFallbackBooking(
        lotId: lotId,
        slotId: slotId,
        userId: userId,
        vehiclePlate: vehiclePlate,
        arrivalTime: arrivalTime,
        durationHours: durationHours,
        vehicleId: vehicleId,
        predictedEtaMinBaseline: predictedEtaMinBaseline,
        predictedEtaMinProvider: predictedEtaMinProvider,
        predictedEtaMinCorrected: predictedEtaMinCorrected,
        modelVersion: modelVersion,
      );
    }
  }

  /// Offline fallback: generate local booking
  Booking _localFallbackBooking({
    required String lotId,
    required String slotId,
    required String userId,
    required String vehiclePlate,
    required DateTime arrivalTime,
    required int durationHours,
    String? vehicleId,
    double? predictedEtaMinBaseline,
    double? predictedEtaMinProvider,
    double? predictedEtaMinCorrected,
    String? modelVersion,
  }) {
    final holdExpiresAt = arrivalTime.add(const Duration(minutes: 15));
    return Booking(
      id: 'BK-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      userId: userId,
      vehicleId: vehicleId ?? 'v-default',
      vehiclePlate: vehiclePlate,
      lotId: lotId,
      lotName: 'Campus Lot',
      slotId: slotId,
      bookedAt: DateTime.now(),
      arrivalTime: arrivalTime,
      durationHours: durationHours,
      status: BookingStatus.reserved,
      estimatedFee: 100 * durationHours,
      qrToken: 'QR-TOKEN-$slotId-${DateTime.now().millisecondsSinceEpoch}',
      holdExpiresAt: holdExpiresAt,
      predictedEtaMinBaseline: predictedEtaMinBaseline ?? 0.0,
      predictedEtaMinProvider: predictedEtaMinProvider ?? 0.0,
      predictedEtaMinCorrected: predictedEtaMinCorrected ?? 0.0,
      modelVersion: modelVersion ?? 'v1.0.0-linear',
    );
  }

  /// Invokes `cancelBooking` callable function to atomically release slot on the server
  Future<bool> cancelBookingOnServer({
    required String bookingId,
  }) async {
    try {
      final payload = <String, dynamic>{
        'bookingId': bookingId,
      };
      await _functions.call('cancelBooking', payload);
      debugPrint('[FirestoreService] Server booking cancellation confirmed: $bookingId');
      return true;
    } catch (e) {
      debugPrint('[FirestoreService] Server cancelBooking call failed ($e), falling back');
      return false;
    }
  }

  /// Invokes `checkIn` callable function to mark barrier QR verification on server
  Future<bool> checkInOnServer({
    required String qrToken,
    String? bookingId,
    int? actualTravelMin,
  }) async {
    try {
      final payload = <String, dynamic>{
        'qrToken': qrToken,
        'bookingId': ?bookingId,
        'actualTravelMin': ?actualTravelMin,
      };
      await _functions.call('checkIn', payload);
      debugPrint('[FirestoreService] Server checkIn confirmed for QR: $qrToken');
      return true;
    } catch (e) {
      debugPrint('[FirestoreService] Server checkIn call failed: $e');
      return false;
    }
  }

  /// Streams trip telemetry records for research audit and ML model evaluation
  Stream<List<TripTelemetry>> streamTripTelemetry({String? userId, int limit = 100}) {
    if (_tripTelemetryRef == null) return Stream.value([]);
    var query = _tripTelemetryRef!.orderBy('loggedAt', descending: true).limit(limit);
    if (userId != null) {
      query = query.where('userId', isEqualTo: userId);
    }
    return query.snapshots().map((snap) =>
        snap.docs.map((doc) => TripTelemetry.fromJson(doc.data())).toList());
  }

  /// Invokes `extendHold` callable function to add +15 min grace hold
  Future<Map<String, dynamic>?> extendHoldOnServer({
    required String bookingId,
    int minutes = 15,
  }) async {
    try {
      final payload = <String, dynamic>{
        'bookingId': bookingId,
        'minutes': minutes,
      };
      final res = await _functions.call('extendHold', payload);
      debugPrint('[FirestoreService] Server extendHold confirmed for: $bookingId');
      return res;
    } catch (e) {
      debugPrint('[FirestoreService] Server extendHold call failed: $e');
      return null;
    }
  }

  /// Invokes `acceptUpgrade` callable function to perform atomic slot swap on the server
  Future<Map<String, dynamic>?> acceptUpgradeOnServer({
    required String bookingId,
    required String newSlotId,
    int currentEtaMinutes = 5,
  }) async {
    try {
      final payload = <String, dynamic>{
        'bookingId': bookingId,
        'newSlotId': newSlotId,
        'currentEtaMinutes': currentEtaMinutes,
      };
      final res = await _functions.call('acceptUpgrade', payload);
      debugPrint('[FirestoreService] Server acceptUpgrade confirmed: upgraded to $newSlotId');
      return res;
    } on SlotCollisionException {
      rethrow;
    } catch (e) {
      debugPrint('[FirestoreService] Server acceptUpgrade call failed: $e');
      return null;
    }
  }

  // --- Bookings Firestore Persistence & Streaming ---

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

  /// Saves booking locally / to Firestore (for backward-compatible offline persistence)
  Future<void> saveBooking(Booking booking) async {
    if (!_isAvailable || _bookingsRef == null) return;
    try {
      await _bookingsRef!.doc(booking.id).set(booking.toJson(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('[FirestoreService] Note: Direct booking write restricted under server authority ($e)');
    }
  }

  // --- Telemetry & Audit Events (SYS-08) ---

  Future<void> saveEvent(ParkingEvent event) async {
    if (!_isAvailable || _eventsRef == null) return;
    try {
      await _eventsRef!.doc(event.id).set(event.toJson());
    } catch (e) {
      debugPrint('[FirestoreService] Note: Direct event write restricted ($e)');
    }
  }

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

  // --- Campus Lots & Subcollection Slots Ingestion & Streaming ---

  /// Seeds default campus lots into Firestore subcollections if empty
  Future<void> seedInitialLotsIfEmpty(List<ParkingLot> defaultLots) async {
    if (!_isAvailable) return;
    final lotsCollection = _parkingLotsRef ?? _legacyLotsRef;
    if (lotsCollection == null) return;

    try {
      final snapshot = await lotsCollection.limit(1).get().timeout(const Duration(seconds: 2));
      if (snapshot.docs.isEmpty) {
        for (final lot in defaultLots) {
          // Write lot document
          await lotsCollection.doc(lot.id).set(lot.toJson());

          // Write subcollection parking_lots/{lotId}/slots/{slotId}
          final slotsSub = lotsCollection.doc(lot.id).collection('slots');
          final batch = _firestore!.batch();
          for (final slot in lot.slots) {
            batch.set(slotsSub.doc(slot.id), {
              'id': slot.id,
              'lotId': lot.id,
              'row': slot.row,
              'number': slot.number,
              'size': slot.size.name,
              'type': slot.type.name,
              'walkingDistanceMeters': slot.walkingDistanceMeters,
              'state': slot.isAvailable ? 'available' : (slot.state == SlotState.blocked ? 'blocked' : 'occupied'),
              'bookingId': slot.bookingId,
              'updatedAt': DateTime.now().toUtc().toIso8601String(),
              'updatedBy': 'system',
            });
          }
          await batch.commit();
        }
        debugPrint('[FirestoreService] Seeded ${defaultLots.length} campus lots and subcollections to Firestore');
      }
    } catch (e) {
      debugPrint('[FirestoreService] Seed lots error: $e');
    }
  }

  /// Streams real-time campus parking lots, seamlessly combining parent lot doc and subcollection slots
  Stream<List<ParkingLot>> streamLots() {
    if (!_isAvailable) {
      return const Stream.empty();
    }

    final collection = _parkingLotsRef ?? _legacyLotsRef;
    if (collection == null) return const Stream.empty();

    return collection.snapshots().asyncMap((snapshot) async {
      final lotsList = <ParkingLot>[];

      for (final doc in snapshot.docs) {
        final lotData = doc.data();
        final baseLot = ParkingLot.fromJson(lotData);

        // Fetch subcollection slots if available
        try {
          final slotsSnap = await doc.reference.collection('slots').get().timeout(const Duration(milliseconds: 1500));
          if (slotsSnap.docs.isNotEmpty) {
            final subSlots = slotsSnap.docs
                .map((sDoc) => ParkingSlot.fromJson(sDoc.data()))
                .toList();

            final freeCount = subSlots.where((s) => s.isAvailable).length;
            lotsList.add(baseLot.copyWith(
              slots: subSlots,
              freeSlots: freeCount,
              totalSlots: subSlots.length,
            ));
            continue;
          }
        } catch (_) {}

        lotsList.add(baseLot);
      }

      return lotsList;
    });
  }

  /// Updates slot state (retained for backward compatibility and mock test runners)
  Future<void> updateSlotState({
    required String lotId,
    required String slotId,
    required SlotState state,
    String? reservedBy,
  }) async {
    if (!_isAvailable) return;
    try {
      final lotsCollection = _parkingLotsRef ?? _legacyLotsRef;
      if (lotsCollection == null) return;

      // Update subcollection slot
      final slotRef = lotsCollection.doc(lotId).collection('slots').doc(slotId);
      final serverState = state == SlotState.free
          ? 'available'
          : (state == SlotState.blocked ? 'blocked' : 'reserved');

      await slotRef.set({
        'state': serverState,
        'bookingId': reservedBy,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'updatedBy': 'app',
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('[FirestoreService] Note: Direct slot mutation skipped under server authority ($e)');
    }
  }

  // --- Real Driver Profiles & Registered Vehicles ---

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

  // --- Email OTP Sign-In (M1) — issued & verified server-side only ---

  /// Asks the server to issue a code for [email]. Throws [OtpAuthException] on failure.
  Future<OtpRequestResult> sendEmailVerificationOtp(String email) {
    return _auth.requestOtp(email.trim().toLowerCase());
  }

  /// Verifies the code on the server and signs in to Firebase Auth with the returned custom token.
  Future<OtpVerificationResult> verifyEmailOtp(String email, String enteredOtp) async {
    try {
      final user = await _auth.verifyOtp(email.trim().toLowerCase(), enteredOtp.trim());
      return OtpVerificationResult(isValid: true, user: user);
    } on OtpAuthException catch (e) {
      return OtpVerificationResult(isValid: false, errorMessage: e.message);
    }
  }

  Future<void> signOut() => _auth.signOut();

  // --- Subsystem Hardware Integration Endpoints (CCTV, Barrier, Payment) ---

  /// Stream of system & hardware alerts for admin monitoring
  Stream<List<AdminAlert>> streamAdminAlerts({String? lotId}) {
    if (!_isAvailable || _adminAlertsRef == null) {
      return Stream.value([]);
    }
    Query<Map<String, dynamic>> query = _adminAlertsRef!.orderBy('timestamp', descending: true);
    if (lotId != null && lotId.isNotEmpty) {
      query = query.where('lotId', isEqualTo: lotId);
    }
    return query.snapshots().map((snap) => snap.docs
        .map((doc) => AdminAlert.fromJson({'id': doc.id, ...doc.data()}))
        .toList());
  }

  /// Ingest CCTV camera vision reading (POST /ingestOccupancy)
  Future<Map<String, dynamic>> ingestOccupancy({
    required String lotId,
    required String slotId,
    required bool occupied,
    double confidence = 0.95,
    DateTime? timestamp,
    bool? violation,
    String cameraApiKey = 'cctv-secret-key-cam-01',
  }) async {
    final payload = {
      'lotId': lotId,
      'slotId': slotId,
      'occupied': occupied,
      'confidence': confidence,
      'timestamp': (timestamp ?? DateTime.now()).toUtc().toIso8601String(),
      'violation': ?violation,
    };
    return await _functions.postRaw(
      'ingestOccupancy',
      payload,
      customHeaders: {'X-Camera-Api-Key': cameraApiKey},
    );
  }

  /// Validate signed QR token at IoT Barrier Gate (POST /validateQr)
  Future<Map<String, dynamic>> validateBarrierQr({
    required String qrToken,
    required String barrierId,
    int? actualTravelMin,
    String barrierApiKey = 'barrier-secret-key-gate-01',
  }) async {
    final payload = {
      'qrToken': qrToken,
      'barrierId': barrierId,
      'actualTravelMin': ?actualTravelMin,
    };
    return await _functions.postRaw(
      'validateQr',
      payload,
      customHeaders: {'X-Device-Api-Key': barrierApiKey},
    );
  }

  /// Finalize payment and release parking bay (POST /paymentCompleted)
  Future<Map<String, dynamic>> submitPaymentCompleted({
    required String bookingId,
    required String paymentRef,
    required int amountPaid,
    String paymentMethod = 'card',
    DateTime? timestamp,
    String paymentApiKey = 'payment-secret-key-svc-01',
  }) async {
    final payload = {
      'bookingId': bookingId,
      'paymentRef': paymentRef,
      'amountPaid': amountPaid,
      'paymentMethod': paymentMethod,
      'timestamp': (timestamp ?? DateTime.now()).toUtc().toIso8601String(),
    };
    return await _functions.postRaw(
      'paymentCompleted',
      payload,
      customHeaders: {'X-Service-Api-Key': paymentApiKey},
    );
  }
}

