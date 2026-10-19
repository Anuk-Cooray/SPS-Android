// ignore_for_file: avoid_print
// scoring_benchmark_test.dart
// Smart Parking (J26-IT-335) — Algorithmic Scoring Latency Benchmark (Flutter / Dart)

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parking/core/theme/app_theme.dart';
import 'package:smart_parking/data/models/parking_lot_model.dart';
import 'package:smart_parking/data/models/parking_slot_model.dart';
import 'package:smart_parking/data/models/user_model.dart';
import 'package:smart_parking/data/models/vehicle_model.dart';
import 'package:smart_parking/features/reoptimization/engine/reoptimization_engine.dart';

void main() {
  group('Scoring Engine Latency Benchmark (Dart)', () {
    test('measures p50, p95, p99 scoring latency over 10,000 iterations', () {
      final engine = ReoptimizationEngine();

      final slot = ParkingSlot(
        id: 'slot-bench-01',
        lotId: 'lot-colombo-01',
        row: 'A',
        number: 1,
        state: SlotState.free,
        size: VehicleSize.medium,
        type: SlotType.covered,
        walkingDistanceMeters: 45,
      );

      final lot = ParkingLot(
        id: 'lot-colombo-01',
        name: 'Colombo Central Hub',
        latitude: 6.9147,
        longitude: 79.9729,
        distanceMeters: 100,
        hourlyRate: 150,
        totalSlots: 72,
        freeSlots: 18,
      );

      final vehicle = Vehicle(
        id: 'v-01',
        plateNumber: 'CAB-1234',
        type: VehicleType.sedan,
        size: VehicleSize.medium,
      );

      final preferences = UserPreferences(
        preferNearEntrance: true,
        coveredParkingOnly: true,
      );

      const iterations = 10000;
      final latenciesMicros = List<int>.filled(iterations, 0);

      // Warm up Dart VM JIT
      for (var i = 0; i < 500; i++) {
        engine.scoreSlot(
          slot: slot,
          lot: lot,
          vehicle: vehicle,
          preferences: preferences,
        );
      }

      final sw = Stopwatch();

      // Benchmark loop with microsecond resolution
      for (var i = 0; i < iterations; i++) {
        sw.reset();
        sw.start();
        engine.scoreSlot(
          slot: slot,
          lot: lot,
          vehicle: vehicle,
          preferences: preferences,
        );
        sw.stop();
        latenciesMicros[i] = sw.elapsedMicroseconds;
      }

      latenciesMicros.sort();

      final p50Us = latenciesMicros[(iterations * 0.50).toInt()];
      final p95Us = latenciesMicros[(iterations * 0.95).toInt()];
      final p99Us = latenciesMicros[(iterations * 0.99).toInt()];
      final avgUs = latenciesMicros.reduce((a, b) => a + b) / iterations;

      print('\n--- Dart ReoptimizationEngine Latency Benchmark ---');
      print('Iterations: $iterations');
      print('Average:    ${avgUs.toStringAsFixed(2)} µs (${(avgUs / 1000).toStringAsFixed(4)} ms)');
      print('p50:        ${p50Us.toStringAsFixed(2)} µs (${(p50Us / 1000).toStringAsFixed(4)} ms)');
      print('p95:        ${p95Us.toStringAsFixed(2)} µs (${(p95Us / 1000).toStringAsFixed(4)} ms)');
      print('p99:        ${p99Us.toStringAsFixed(2)} µs (${(p99Us / 1000).toStringAsFixed(4)} ms)');
      print('---------------------------------------------------\n');

      // Assert p99 is sub-millisecond (less than 1000 µs = 1.0 ms)
      expect(p99Us, lessThan(1000), reason: 'Scoring latency p99 must be under 1 ms');
    });
  });
}
