import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parking/core/theme/app_theme.dart';
import 'package:smart_parking/data/models/parking_event_model.dart';
import 'package:smart_parking/data/models/parking_lot_model.dart';
import 'package:smart_parking/data/models/parking_slot_model.dart';
import 'package:smart_parking/data/models/user_model.dart';
import 'package:smart_parking/data/models/vehicle_model.dart';
import 'package:smart_parking/features/admin/telemetry_export_modal.dart';
import 'package:smart_parking/features/admin/telemetry_exporter.dart';
import 'package:smart_parking/features/reoptimization/engine/reoptimization_engine.dart';
import 'package:smart_parking/features/reoptimization/engine/scoring_weights.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TelemetryExporter (Research Data Export)', () {
    late List<ParkingEvent> sampleEvents;
    late List<ParkingLot> sampleLots;
    late Vehicle sampleVehicle;
    late UserPreferences samplePreferences;
    late ScoringWeights weights;
    late ReoptimizationEngine engine;

    setUp(() {
      engine = ReoptimizationEngine();
      sampleEvents = [
        ParkingEvent(
          id: 'ev-1',
          bookingId: 'bk-100',
          timestamp: DateTime.parse('2026-10-18T14:30:00Z'),
          type: ParkingEventType.booked,
          description: 'Reservation created for Bay B-04',
        ),
        ParkingEvent(
          id: 'ev-2',
          bookingId: 'bk-100',
          timestamp: DateTime.parse('2026-10-18T14:35:10Z'),
          type: ParkingEventType.offered,
          description: 'Upgrade offered: score 0.88 -> recommended B-01 (score 0.94)',
        ),
        ParkingEvent(
          id: 'ev-3',
          bookingId: 'bk-100',
          timestamp: DateTime.parse('2026-10-18T14:35:45Z'),
          type: ParkingEventType.accepted,
          description: 'Upgraded slot to B-01 ("closer to entrance")',
        ),
      ];

      sampleLots = [
        const ParkingLot(
          id: 'lot-main',
          name: 'Main Campus Lot',
          latitude: 6.9147,
          longitude: 79.9733,
          distanceMeters: 100,
          hourlyRate: 50,
          totalSlots: 2,
          freeSlots: 2,
          slots: [
            ParkingSlot(
              id: 'slot-1',
              lotId: 'lot-main',
              row: 'A',
              number: 1,
              state: SlotState.free,
              size: VehicleSize.medium,
              walkingDistanceMeters: 45,
            ),
            ParkingSlot(
              id: 'slot-2',
              lotId: 'lot-main',
              row: 'A',
              number: 2,
              state: SlotState.free,
              size: VehicleSize.large,
              walkingDistanceMeters: 90,
            ),
          ],
        ),
      ];

      sampleVehicle = const Vehicle(
        id: 'v-test',
        plateNumber: 'CAB-9999',
        type: VehicleType.sedan,
        size: VehicleSize.medium,
      );

      samplePreferences = const UserPreferences(
        allowUpgradeOffers: true,
        preferNearEntrance: true,
        coveredParkingOnly: false,
      );

      weights = const ScoringWeights(
        distanceWeight: 0.40,
        sizeFitWeight: 0.25,
        preferenceWeight: 0.20,
        demandWeight: 0.15,
      );
    });

    test('eventsToCsv generates valid RFC-4180 CSV with correct headers and quotes', () {
      final csv = TelemetryExporter.eventsToCsv(sampleEvents);
      expect(csv, isNotEmpty);

      final lines = csv.trim().split('\n');
      expect(lines.length, 4); // 1 header + 3 rows
      expect(lines[0].trim(), 'event_id,timestamp_iso,timestamp_formatted,booking_id,event_type,description');

      // Check second line
      expect(lines[1], contains('ev-1'));
      expect(lines[1], contains('bk-100'));
      expect(lines[1], contains('booked'));
      expect(lines[1], contains('Reservation created for Bay B-04'));

      // Check quote escaping in third event
      expect(lines[3], contains('""closer to entrance""'));
    });

    test('eventsToJson outputs structured research benchmark payload', () {
      final jsonString = TelemetryExporter.eventsToJson(
        events: sampleEvents,
        weights: weights,
      );

      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      expect(data.containsKey('system'), isTrue);
      expect(data['project_code'], 'J26-IT-335');
      expect(data['dataset_type'], contains('SYS-08'));

      expect(data.containsKey('model_hyperparameters'), isTrue);
      final hp = data['model_hyperparameters'] as Map<String, dynamic>;
      final w = hp['weights'] as Map<String, dynamic>;
      expect(w['distance_weight'], 0.40);
      expect(w['size_fit_weight'], 0.25);
      expect(w['driver_preference_weight'], 0.20);
      expect(w['demand_pressure_weight'], 0.15);

      final thresholds = hp['upgrade_thresholds'] as Map<String, dynamic>;
      expect(thresholds['min_distance_improvement_meters'], 50);
      expect(thresholds['upgrade_trigger_eta_minutes'], 10);

      expect(data['record_count'], 3);

      final eventsList = data['events'] as List<dynamic>;
      expect(eventsList.length, 3);
      expect(eventsList[0]['id'], 'ev-1');
      expect(eventsList[0]['type'], 'booked');
    });

    test('slotScoresToCsv generates full multi-criteria scoring matrix', () {
      final csv = TelemetryExporter.slotScoresToCsv(
        lots: sampleLots,
        vehicle: sampleVehicle,
        preferences: samplePreferences,
        engine: engine,
      );

      expect(csv, isNotEmpty);
      final lines = csv.trim().split('\n');
      expect(lines.length, 3); // 1 header + 2 slot rows

      final header = lines[0].trim();
      expect(header, contains('lot_id'));
      expect(header, contains('slot_id'));
      expect(header, contains('distance_score'));
      expect(header, contains('size_fit_score'));
      expect(header, contains('composite_score'));
      expect(header, contains('is_recommended'));

      // Check slot 1 row
      expect(lines[1], contains('slot-1'));
      expect(lines[1], contains('Main Campus Lot'));
      expect(lines[1], contains('Medium'));
    });

    test('ExportDatasetType enum provides correct titles, extensions and descriptions', () {
      expect(ExportDatasetType.eventsCsv.title, 'Events (CSV)');
      expect(ExportDatasetType.eventsCsv.fileExtension, 'csv');
      expect(ExportDatasetType.benchmarkJson.title, 'System (JSON)');
      expect(ExportDatasetType.benchmarkJson.fileExtension, 'json');
      expect(ExportDatasetType.scoresMatrixCsv.title, 'Bay Scores (CSV)');
      expect(ExportDatasetType.scoresMatrixCsv.fileExtension, 'csv');
    });
  });
}
