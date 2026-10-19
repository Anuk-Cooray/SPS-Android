import 'dart:convert';
import 'package:intl/intl.dart';
import '../../data/models/parking_event_model.dart';
import '../../data/models/parking_lot_model.dart';
import '../../data/models/trip_telemetry_model.dart';
import '../../data/models/user_model.dart';
import '../../data/models/vehicle_model.dart';
import '../../features/reoptimization/engine/reoptimization_engine.dart';
import '../../features/reoptimization/engine/scoring_weights.dart';

abstract final class TelemetryExporter {
  /// Converts telemetry event audit stream to standard RFC-4180 CSV
  static String eventsToCsv(List<ParkingEvent> events) {
    final buffer = StringBuffer();
    buffer.writeln('event_id,timestamp_iso,timestamp_formatted,booking_id,event_type,description');

    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    for (final event in events) {
      final id = _escapeCsv(event.id);
      final iso = event.timestamp.toIso8601String();
      final formatted = _escapeCsv(dateFormat.format(event.timestamp));
      final bookingId = _escapeCsv(event.bookingId);
      final type = _escapeCsv(event.type.name);
      final desc = _escapeCsv(event.description);
      buffer.writeln('$id,$iso,$formatted,$bookingId,$type,$desc');
    }

    return buffer.toString();
  }

  /// Converts telemetry stream and current optimization hyperparameters to structured research JSON
  static String eventsToJson({
    required List<ParkingEvent> events,
    required ScoringWeights weights,
  }) {
    final payload = {
      'system': 'Smart Parking System (SPS)',
      'project_code': 'J26-IT-335',
      'dataset_type': 'Telemetry & Decision Audit Stream (SYS-08)',
      'exported_at': DateTime.now().toIso8601String(),
      'record_count': events.length,
      'model_hyperparameters': {
        'weights': {
          'distance_weight': weights.distanceWeight,
          'size_fit_weight': weights.sizeFitWeight,
          'driver_preference_weight': weights.preferenceWeight,
          'demand_pressure_weight': weights.demandWeight,
        },
        'upgrade_thresholds': {
          'min_distance_improvement_meters': weights.minImprovementMeters,
          'min_score_improvement_points': weights.minScoreImprovementPoints,
          'min_score_improvement_percent': weights.minScoreImprovementPoints,
          'offer_timeout_seconds': weights.offerTimeoutSeconds,
          'upgrade_trigger_eta_minutes': weights.upgradeTriggerEtaMinutes,
        },
      },
      'events': events.map((e) => {
        'id': e.id,
        'timestamp': e.timestamp.toIso8601String(),
        'booking_id': e.bookingId,
        'type': e.type.name,
        'type_label': e.type.displayName,
        'description': e.description,
        'metadata': e.metadata,
      }).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Generates multi-criteria scoring matrix CSV for all slots across parking lots (SYS-01)
  static String slotScoresToCsv({
    required List<ParkingLot> lots,
    required Vehicle vehicle,
    required UserPreferences preferences,
    required ReoptimizationEngine engine,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(
      'lot_id,lot_name,slot_id,row,bay_number,slot_size,walking_distance_meters,distance_score,size_fit_score,pref_score,demand_penalty,composite_score,eligible,is_recommended',
    );

    for (final lot in lots) {
      final ranked = engine.scoreAndRankSlots(
        lot: lot,
        vehicle: vehicle,
        preferences: preferences,
      );
      final bestSlotId = ranked.isNotEmpty ? ranked.first.slot.id : null;

      for (final slot in lot.slots) {
        final score = engine.scoreSlot(
          slot: slot,
          lot: lot,
          vehicle: vehicle,
          preferences: preferences,
        );

        final isRecommended = (slot.id == bestSlotId) ? 1 : 0;
        final eligible = score.isEligible ? 1 : 0;

        buffer.writeln(
          '${_escapeCsv(lot.id)},${_escapeCsv(lot.name)},${_escapeCsv(slot.id)},'
          '${_escapeCsv(slot.row)},${slot.number},${_escapeCsv(slot.size.displayName)},'
          '${slot.walkingDistanceMeters},'
          '${score.distanceScore.toStringAsFixed(3)},'
          '${score.sizeFitScore.toStringAsFixed(3)},'
          '${score.preferenceScore.toStringAsFixed(3)},'
          '${score.demandPenalty.toStringAsFixed(3)},'
          '${score.totalScore.toStringAsFixed(2)},'
          '$eligible,$isRecommended',
        );
      }
    }

    return buffer.toString();
  }

  /// Converts completed trip telemetry audit records to standard CSV for offline ML model training
  static String tripsToCsv(List<TripTelemetry> trips) {
    final buffer = StringBuffer();
    buffer.writeln(
      'trip_id,booking_id,user_id,lot_id,predicted_eta_baseline,predicted_eta_provider,'
      'predicted_eta_corrected,actual_travel_min,departure_time,arrival_time,day_of_week,'
      'hour,distance_km,origin_zone,weather_flag,holiday_flag,model_version,logged_at',
    );

    for (final trip in trips) {
      buffer.writeln(
        '${_escapeCsv(trip.tripId)},${_escapeCsv(trip.bookingId)},${_escapeCsv(trip.userId)},'
        '${_escapeCsv(trip.lotId)},${trip.predictedEtaMinBaseline.toStringAsFixed(1)},'
        '${trip.predictedEtaMinProvider.toStringAsFixed(1)},'
        '${trip.predictedEtaMinCorrected.toStringAsFixed(1)},${trip.actualTravelMin},'
        '${trip.departureTime.toIso8601String()},${trip.arrivalTime.toIso8601String()},'
        '${trip.dayOfWeek},${trip.hour},${trip.distanceKm.toStringAsFixed(2)},'
        '${_escapeCsv(trip.originZone)},${trip.weatherFlag},${trip.holidayFlag},'
        '${_escapeCsv(trip.modelVersion)},${trip.loggedAt.toIso8601String()}',
      );
    }

    return buffer.toString();
  }

  static String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
