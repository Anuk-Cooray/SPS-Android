// scoring_test_vectors_test.dart
// Smart Parking (J26-IT-335) — Shared Scoring Engine Parity Tests (Dart Side)

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parking/core/theme/app_theme.dart';
import 'package:smart_parking/data/models/parking_lot_model.dart';
import 'package:smart_parking/data/models/parking_slot_model.dart';
import 'package:smart_parking/data/models/user_model.dart';
import 'package:smart_parking/data/models/vehicle_model.dart';
import 'package:smart_parking/features/reoptimization/engine/reoptimization_engine.dart';

void main() {
  group('Scoring Engine Shared Test Vectors Parity (Dart)', () {
    late List<dynamic> testVectors;
    final engine = ReoptimizationEngine();

    setUpAll(() {
      final file = File('test_vectors/scoring_test_vectors.json');
      expect(file.existsSync(), isTrue, reason: 'Test vector file must exist');
      final jsonString = file.readAsStringSync();
      testVectors = jsonDecode(jsonString) as List<dynamic>;
    });

    test('Verifies all shared test vectors match ReoptimizationEngine calculations', () {
      for (final raw in testVectors) {
        final vec = raw as Map<String, dynamic>;
        final id = vec['id'] as String;
        final slotMap = vec['slot'] as Map<String, dynamic>;
        final lotMap = vec['lot'] as Map<String, dynamic>;
        final vehMap = vec['vehicle'] as Map<String, dynamic>;
        final prefMap = vec['preferences'] as Map<String, dynamic>;
        final exp = vec['expected'] as Map<String, dynamic>;

        final slot = ParkingSlot(
          id: slotMap['id'] as String,
          lotId: 'lot-test',
          row: slotMap['row'] as String,
          number: slotMap['number'] as int,
          state: SlotState.free,
          size: VehicleSize.values.byName(slotMap['size'] as String),
          type: SlotType.values.byName(slotMap['type'] as String),
          walkingDistanceMeters: slotMap['walkingDistanceMeters'] as int,
        );

        final lot = ParkingLot(
          id: 'lot-test',
          name: 'Test Lot',
          latitude: 6.9147,
          longitude: 79.9729,
          distanceMeters: 100,
          hourlyRate: 100,
          totalSlots: lotMap['totalSlots'] as int,
          freeSlots: lotMap['freeSlots'] as int,
        );

        final vehicle = Vehicle(
          id: 'veh-test',
          plateNumber: 'CAB-1234',
          type: VehicleType.values.byName(vehMap['type'] as String),
          size: VehicleSize.values.byName(vehMap['size'] as String),
        );

        final preferences = UserPreferences(
          preferNearEntrance: prefMap['preferNearEntrance'] as bool,
          coveredParkingOnly: prefMap['coveredParkingOnly'] as bool,
        );

        final result = engine.scoreSlot(
          slot: slot,
          lot: lot,
          vehicle: vehicle,
          preferences: preferences,
        );

        final bool expectedEligible = exp['isEligible'] as bool;
        expect(result.isEligible, equals(expectedEligible), reason: '[$id] isEligible mismatch');

        if (expectedEligible) {
          expect(result.distanceScore, closeTo((exp['distanceScore'] as num).toDouble(), 0.001),
              reason: '[$id] distanceScore mismatch');
          expect(result.sizeFitScore, closeTo((exp['sizeFitScore'] as num).toDouble(), 0.001),
              reason: '[$id] sizeFitScore mismatch');
          expect(result.preferenceScore, closeTo((exp['preferenceScore'] as num).toDouble(), 0.001),
              reason: '[$id] preferenceScore mismatch');
          expect(result.demandPenalty, closeTo((exp['demandPenalty'] as num).toDouble(), 0.001),
              reason: '[$id] demandPenalty mismatch');
          expect(result.totalScore, closeTo((exp['totalScore'] as num).toDouble(), 0.001),
              reason: '[$id] totalScore mismatch');
        }
      }
    });
  });
}
