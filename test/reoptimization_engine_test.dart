import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_parking/core/theme/app_theme.dart';
import 'package:smart_parking/data/models/booking_model.dart';
import 'package:smart_parking/data/models/parking_lot_model.dart';
import 'package:smart_parking/data/models/parking_slot_model.dart';
import 'package:smart_parking/data/models/user_model.dart';
import 'package:smart_parking/data/models/vehicle_model.dart';
import 'package:smart_parking/data/services/parking_state_manager.dart';
import 'package:smart_parking/features/reoptimization/engine/reoptimization_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReoptimizationEngine - Multi-Criteria Scoring (SYS-01)', () {
    late ReoptimizationEngine engine;
    late ParkingLot testLot;
    late Vehicle sedanVehicle;
    late Vehicle suvVehicle;

    setUp(() {
      engine = ReoptimizationEngine();
      sedanVehicle = const Vehicle(
        id: 'v1',
        plateNumber: 'CAB-1001',
        type: VehicleType.sedan,
        size: VehicleSize.medium,
      );
      suvVehicle = const Vehicle(
        id: 'v2',
        plateNumber: 'WP-SUV-99',
        type: VehicleType.suv,
        size: VehicleSize.large,
      );

      testLot = const ParkingLot(
        id: 'lot-1',
        name: 'Test Innovation Lot',
        latitude: 6.9147,
        longitude: 79.9733,
        totalSlots: 10,
        freeSlots: 5,
        distanceMeters: 250,
        hourlyRate: 100,
        slots: [
          ParkingSlot(
            id: 'A-01',
            lotId: 'lot-1',
            row: 'A',
            number: 1,
            state: SlotState.free,
            size: VehicleSize.medium,
            walkingDistanceMeters: 40,
          ),
          ParkingSlot(
            id: 'A-02',
            lotId: 'lot-1',
            row: 'A',
            number: 2,
            state: SlotState.free,
            size: VehicleSize.medium,
            walkingDistanceMeters: 160,
          ),
          ParkingSlot(
            id: 'A-03',
            lotId: 'lot-1',
            row: 'A',
            number: 3,
            state: SlotState.free,
            size: VehicleSize.small,
            walkingDistanceMeters: 30,
          ),
          ParkingSlot(
            id: 'A-04',
            lotId: 'lot-1',
            row: 'A',
            number: 4,
            state: SlotState.taken,
            size: VehicleSize.medium,
            walkingDistanceMeters: 20,
          ),
        ],
      );
    });

    test('Closer walking distance yields higher total score', () {
      final slotClose = testLot.slots[0]; // 40m
      final slotFar = testLot.slots[1]; // 160m

      final scoreClose = engine.scoreSlot(
        slot: slotClose,
        lot: testLot,
        vehicle: sedanVehicle,
        preferences: const UserPreferences(),
      );

      final scoreFar = engine.scoreSlot(
        slot: slotFar,
        lot: testLot,
        vehicle: sedanVehicle,
        preferences: const UserPreferences(),
      );

      expect(scoreClose.isEligible, isTrue);
      expect(scoreFar.isEligible, isTrue);
      expect(scoreClose.totalScore, greaterThan(scoreFar.totalScore));
      expect(scoreClose.distanceScore, greaterThan(scoreFar.distanceScore));
    });

    test('Incompatible slot size is marked ineligible with 0 score', () {
      final smallSlot = testLot.slots[2]; // size: small

      // SUV (large) cannot fit in small slot
      final score = engine.scoreSlot(
        slot: smallSlot,
        lot: testLot,
        vehicle: suvVehicle,
        preferences: const UserPreferences(),
      );

      expect(score.isEligible, isFalse);
      expect(score.totalScore, equals(0.0));
    });

    test('Driver covered parking preference grants positive bonus for covered slot', () {
      final slotCovered = testLot.slots[0].copyWith(type: SlotType.covered);

      final withPref = engine.scoreSlot(
        slot: slotCovered,
        lot: testLot,
        vehicle: sedanVehicle,
        preferences: const UserPreferences(coveredParkingOnly: true),
      );

      final withoutPref = engine.scoreSlot(
        slot: slotCovered,
        lot: testLot,
        vehicle: sedanVehicle,
        preferences: const UserPreferences(coveredParkingOnly: false),
      );

      expect(withPref.preferenceScore, greaterThan(withoutPref.preferenceScore));
      expect(withPref.totalScore, greaterThan(withoutPref.totalScore));
    });

    test('Slot-aware turnover penalty applies higher penalty to entrance bays during peak demand', () {
      final entranceSlot = testLot.slots[0]; // 40m
      final perimeterSlot = testLot.slots[1]; // 160m

      final busyLot = testLot.copyWith(totalSlots: 100, freeSlots: 10); // 90% occupancy >= 70%

      final scoreEntrance = engine.scoreSlot(
        slot: entranceSlot,
        lot: busyLot,
        vehicle: sedanVehicle,
        preferences: const UserPreferences(),
      );

      final scorePerimeter = engine.scoreSlot(
        slot: perimeterSlot,
        lot: busyLot,
        vehicle: sedanVehicle,
        preferences: const UserPreferences(),
      );

      // Entrance (<=50m) gets 1.20 turnover multiplier (27.0 penalty)
      // Perimeter (>150m) gets 0.80 turnover multiplier (18.0 penalty)
      expect(scoreEntrance.demandPenalty, equals(27.0));
      expect(scorePerimeter.demandPenalty, equals(18.0));
    });

    test('Rank and recommendation picks highest scoring available slot', () {
      final best = engine.scoreAndRecommendBestSlot(
        lot: testLot,
        vehicle: sedanVehicle,
        preferNearEntrance: true,
      );

      expect(best, isNotNull);
      expect(best!.id, equals('A-01')); // 40m medium slot beats 160m medium slot
    });
  });

  group('ReoptimizationEngine - In-Transit Upgrades (SYS-03, SYS-04)', () {
    late ReoptimizationEngine engine;
    late ParkingLot testLot;
    late Vehicle testVehicle;

    setUp(() {
      engine = ReoptimizationEngine();
      testVehicle = const Vehicle(
        id: 'v1',
        plateNumber: 'CAB-1001',
        type: VehicleType.sedan,
        size: VehicleSize.medium,
      );

      testLot = const ParkingLot(
        id: 'lot-1',
        name: 'Test Innovation Lot',
        latitude: 6.9147,
        longitude: 79.9733,
        totalSlots: 10,
        freeSlots: 4,
        distanceMeters: 250,
        hourlyRate: 100,
        slots: [
          ParkingSlot(
            id: 'A-01',
            lotId: 'lot-1',
            row: 'A',
            number: 1,
            state: SlotState.free,
            size: VehicleSize.medium,
            walkingDistanceMeters: 20,
          ),
          ParkingSlot(
            id: 'A-02',
            lotId: 'lot-1',
            row: 'A',
            number: 2,
            state: SlotState.taken,
            size: VehicleSize.medium,
            walkingDistanceMeters: 180,
          ),
        ],
      );
    });

    test('Suppresses upgrade if user opted out in preferences', () {
      final currentSlot = testLot.slots[1]; // A-02 (180m)

      final eval = engine.evaluateInTransitUpgrade(
        lot: testLot,
        currentSlot: currentSlot,
        vehicle: testVehicle,
        preferences: const UserPreferences(allowUpgradeOffers: false),
        currentEtaMinutes: 8,
      );

      expect(eval.isUpgradeOffered, isFalse);
      expect(eval.decisionReason, contains('turned off proactive upgrade offers'));
    });

    test('Suppresses upgrade if ETA is outside trigger window (> 10 min)', () {
      final currentSlot = testLot.slots[1]; // A-02 (180m)

      final eval = engine.evaluateInTransitUpgrade(
        lot: testLot,
        currentSlot: currentSlot,
        vehicle: testVehicle,
        preferences: const UserPreferences(allowUpgradeOffers: true),
        currentEtaMinutes: 15, // > 10 min window
      );

      expect(eval.isUpgradeOffered, isFalse);
      expect(eval.decisionReason, contains('outside upgrade window'));
    });

    test('Offers upgrade when closer candidate saves >= 50m and improves score >= 20.0 points', () {
      final currentSlot = testLot.slots[1]; // A-02 (180m)
      // A-01 is free (20m) -> saves 160m (>= 50m) and significantly improves score points

      final eval = engine.evaluateInTransitUpgrade(
        lot: testLot,
        currentSlot: currentSlot,
        vehicle: testVehicle,
        preferences: const UserPreferences(allowUpgradeOffers: true),
        currentEtaMinutes: 7, // within 10 min window
      );

      expect(eval.isUpgradeOffered, isTrue);
      expect(eval.candidateSlotScore?.slot.id, equals('A-01'));
      expect(eval.distanceSavedMeters, equals(160));
      expect(eval.scoreImprovementPoints, greaterThanOrEqualTo(20.0));
      expect(eval.scoreImprovementPercent, greaterThanOrEqualTo(20.0)); // legacy getter parity
    });

    test('ExecuteSlotSwap updates booking status to upgraded with qrToken and distance saved', () async {
      final currentBooking = Booking(
        id: 'BK-001',
        userId: 'u1',
        vehicleId: 'v1',
        vehiclePlate: 'CAB-1001',
        lotId: 'lot-1',
        lotName: 'Test Lot',
        slotId: 'A-02',
        bookedAt: DateTime.now(),
        arrivalTime: DateTime.now().add(const Duration(minutes: 10)),
        durationHours: 2,
        status: BookingStatus.reserved,
        estimatedFee: 200,
        qrToken: 'QR-INITIAL',
      );

      final newSlot = testLot.slots[0]; // A-01 (40m)
      final swapped = await engine.executeSlotSwap(
        currentBooking: currentBooking,
        newSlot: newSlot,
      );

      expect(swapped.slotId, equals('A-01'));
      expect(swapped.originalSlotId, equals('A-02'));
      expect(swapped.status, equals(BookingStatus.upgraded));
      expect(swapped.distanceSavedMeters, equals(140));
      expect(swapped.qrToken, startsWith('QR-UPGRADED-A-01'));
    });
  });

  group('In-Transit Route Movement & ETA Simulation (SYS-03)', () {
    late ParkingStateManager stateManager;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      stateManager = ParkingStateManager();
      final lot = stateManager.lots.first;
      final slot = lot.slots.firstWhere((s) => s.state == SlotState.free);
      stateManager.reserveSlot(
        lot: lot,
        slot: slot,
        arrivalTime: DateTime.now().add(const Duration(minutes: 12)),
        durationHours: 2,
      );
    });

    tearDown(() {
      stateManager.dispose();
    });

    test('setRouteProgress updates distance, ETA and maneuver instructions', () {
      expect(stateManager.routeProgress, equals(0.0));
      expect(stateManager.etaMinutes, equals(12));
      expect(stateManager.distanceKm, equals(4.2));
      expect(stateManager.currentManeuverText, equals('Turn right onto New Kandy Rd'));

      // Progress to 50%
      stateManager.setRouteProgress(0.50);
      expect(stateManager.routeProgress, equals(0.50));
      expect(stateManager.distanceKm, equals(2.1));
      expect(stateManager.etaMinutes, equals(6));
      expect(stateManager.currentManeuverText, equals('Turn left at SLIIT Campus Gate'));

      // Progress to 100% (Arrival)
      stateManager.setRouteProgress(1.0);
      expect(stateManager.hasArrivedAtDestination, isTrue);
      expect(stateManager.distanceKm, equals(0.0));
      expect(stateManager.etaMinutes, equals(0));
      expect(stateManager.currentManeuverText, equals('Arrived at barrier. Ready to scan QR.'));
    });

    test('Advancing ETA into trigger window automatically activates dynamic upgrade check', () {
      expect(stateManager.upgradeOfferAvailable, isFalse);

      // Simulating movement from 12m to 8m (progress 0.35)
      stateManager.setRouteProgress(0.35);
      expect(stateManager.etaMinutes, lessThanOrEqualTo(10));
      // Triggers candidate evaluation
      expect(stateManager.lastUpgradeEvaluation, isNotNull);
    });

    test('tickSimulation increments progress and pauses at destination', () {
      stateManager.resetMovementSimulation();
      expect(stateManager.routeProgress, equals(0.0));

      stateManager.tickSimulation(step: 0.20);
      expect(stateManager.routeProgress, closeTo(0.20, 0.001));

      stateManager.tickSimulation(step: 0.90);
      expect(stateManager.routeProgress, equals(1.0));
      expect(stateManager.hasArrivedAtDestination, isTrue);
      expect(stateManager.isSimulatingMovement, isFalse);
    });
  });
}
