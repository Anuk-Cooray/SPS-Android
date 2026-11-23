// arrival_feasibility_test.dart
// Unit tests for Predictive Arrival Time Validation, In-Transit Lifecycle, and Post-Booking Flow

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parking/core/theme/app_theme.dart';
import 'package:smart_parking/data/models/booking_model.dart';
import 'package:smart_parking/data/models/parking_lot_model.dart';
import 'package:smart_parking/data/models/parking_slot_model.dart';
import 'package:smart_parking/data/models/vehicle_model.dart';
import 'package:smart_parking/data/services/arrival_feasibility_service.dart';
import 'package:smart_parking/data/services/colombo_location_service.dart';
import 'package:smart_parking/data/services/parking_state_manager.dart';
import 'package:smart_parking/data/services/routing/eta_correction_model.dart';
import 'package:smart_parking/data/services/routing/heuristic_route_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockLot = ParkingLot(
    id: 'test-lot-1',
    name: 'Colombo Fort Central Lot',
    campusZone: 'Colombo Central',
    latitude: 6.9344,
    longitude: 79.8428,
    totalSlots: 20,
    freeSlots: 8,
    hourlyRate: 200,
    distanceMeters: 45,
    slots: [
      const ParkingSlot(
        id: 'A-01',
        lotId: 'test-lot-1',
        row: 'A',
        number: 1,
        state: SlotState.free,
        size: VehicleSize.medium,
        walkingDistanceMeters: 25,
      ),
    ],
  );

  group('Predictive Arrival Time & Traffic Validation (SYS-01 / SYS-03)', () {
    test('Calculates infeasible arrival when requested time is earlier than driving duration', () {
      final now = DateTime.now();
      // User asks for arrival 10 minutes from now, but distance from SLIIT Malabe to Colombo Fort (~18 km)
      // takes ~45 minutes in city traffic.
      final requestedTime = now.add(const Duration(minutes: 10));

      final landmark = ColomboLocationService.getLandmarkById('colombo-fort');
      final result = ArrivalFeasibilityService.evaluate(
        originLat: 6.9147, // SLIIT Malabe
        originLng: 79.9729,
        targetLot: mockLot,
        requestedTime: requestedTime,
        landmarkContext: landmark,
      );

      expect(result.isFeasible, isFalse);
      expect(result.drivingDurationMinutes, greaterThan(20));
      expect(result.recommendedArrivalTime.isAfter(requestedTime), isTrue);
      expect(result.lateByMinutes, greaterThan(0));
    });

    test('Confirms feasible arrival when requested time provides sufficient transit buffer', () {
      final now = DateTime.now();
      // User books 2 hours in advance (sufficient for any Colombo transit)
      final requestedTime = now.add(const Duration(hours: 2));

      final result = ArrivalFeasibilityService.evaluate(
        originLat: 6.9147,
        originLng: 79.9729,
        targetLot: mockLot,
        requestedTime: requestedTime,
      );

      expect(result.isFeasible, isTrue);
      expect(result.lateByMinutes, equals(0));
      expect(result.recommendedArrivalTime, equals(requestedTime));
    });

    test('Rounds recommended arrival time to nearest 5-minute interval', () {
      final now = DateTime.now();
      final requestedTime = now.add(const Duration(minutes: 5));

      final result = ArrivalFeasibilityService.evaluate(
        originLat: 6.9147,
        originLng: 79.9729,
        targetLot: mockLot,
        requestedTime: requestedTime,
      );

      expect(result.recommendedArrivalTime.minute % 5, equals(0));
      expect(result.recommendedArrivalTime.second, equals(0));
    });

    test('evaluateAsync queries RouteProvider and applies learned ETA correction', () async {
      final now = DateTime.now();
      final requestedTime = now.add(const Duration(hours: 2));

      final result = await ArrivalFeasibilityService.evaluateAsync(
        originLat: 6.9147,
        originLng: 79.9729,
        targetLot: mockLot,
        requestedTime: requestedTime,
        routeProvider: const HeuristicRouteProvider(),
        originZone: 'Malabe_Kaduwela',
      );

      expect(result.isFeasible, isTrue);
      expect(result.route, isNotNull);
      expect(result.modelVersion, equals('v1.0.0-linear'));
      expect(result.predictedEtaMinBaseline, greaterThan(0));
      expect(result.predictedEtaMinProvider, greaterThan(0));
      expect(result.predictedEtaMinCorrected, greaterThan(0));
    });

    test('EtaCorrectionModel scales up for peak hour and monsoon rain', () {
      const model = EtaCorrectionModel();
      final mondayPeak = DateTime(2026, 10, 20, 8, 30); // 8:30 AM Monday

      final clearRatio = model.predictResidualRatio(
        distanceKm: 12.0,
        departureTime: mondayPeak,
        originZone: 'Malabe_Kaduwela',
        isRain: false,
      );

      final rainRatio = model.predictResidualRatio(
        distanceKm: 12.0,
        departureTime: mondayPeak,
        originZone: 'Malabe_Kaduwela',
        isRain: true,
      );

      expect(clearRatio, greaterThan(1.0)); // Peak hour delay
      expect(rainRatio, greaterThan(clearRatio)); // Rain delay adds ~28%
    });
  });

  group('Two-Phase In-Transit and Arrival-Based Auto-Release Lifecycle', () {
    test('Booking in transit does NOT count down towards auto-release before arrival time', () {
      final now = DateTime.now();
      final arrivalTime = now.add(const Duration(minutes: 45)); // 45 mins in future

      final booking = Booking(
        id: 'BK-TEST-1',
        userId: 'usr-1',
        vehicleId: 'veh-1',
        vehiclePlate: 'WP CAB-1234',
        slotId: 'A-01',
        lotId: 'test-lot-1',
        lotName: 'Colombo Fort Central Lot',
        bookedAt: now,
        arrivalTime: arrivalTime,
        durationHours: 2,
        estimatedFee: 400,
        status: BookingStatus.reserved,
        qrToken: 'QR-TEST',
      );

      expect(booking.isInTransit, isTrue);
      expect(booking.isHoldWindowActive, isFalse);
      expect(booking.isHoldExpired, isFalse);
      // Remaining hold duration during transit is the full 15-minute barrier guarantee
      expect(booking.remainingHoldDuration, equals(const Duration(minutes: 15)));
      // Effective hold deadline is arrivalTime + 15 minutes
      expect(booking.effectiveHoldDeadline, equals(arrivalTime.add(const Duration(minutes: 15))));
    });

    test('ParkingStateManager fastForwardToArrivalTime activates hold countdown window', () {
      final manager = ParkingStateManager();
      final lot = manager.lots.first;
      final slot = lot.slots.firstWhere((s) => s.isAvailable);

      final now = DateTime.now();
      final arrivalTime = now.add(const Duration(minutes: 40));

      manager.reserveSlot(
        lot: lot,
        slot: slot,
        arrivalTime: arrivalTime,
        durationHours: 2,
      );

      expect(manager.currentActiveBooking, isNotNull);
      expect(manager.currentActiveBooking!.isInTransit, isTrue);

      // Fast-forward to arrival time for evaluation
      manager.fastForwardToArrivalTime();

      final updatedBooking = manager.currentActiveBooking!;
      expect(updatedBooking.holdExpiresAt, isNotNull);
      expect(updatedBooking.isHoldWindowActive, isTrue);
      expect(updatedBooking.remainingHoldDuration.inMinutes, lessThanOrEqualTo(15));
    });
  });
}
