import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../models/parking_slot_model.dart';
import '../models/vehicle_model.dart';
import 'service_contracts.dart';

/// LAN address is supplied at build/run time, never committed as a personal IP.
/// Example: --dart-define=AI_API_BASE_URL=http://192.168.1.20:8000
class AiOccupancyService implements LotOccupancyService {
  AiOccupancyService({http.Client? client}) : _client = client ?? http.Client();

  static const baseUrl = String.fromEnvironment(
    'AI_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
  final http.Client _client;

  @override
  Stream<Map<String, SlotState>> get liveOccupancyStream =>
      const Stream.empty();

  @override
  Future<List<ParkingSlot>> fetchLotSlots(String lotId) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/api/board?lot_id=$lotId'))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      throw AiApiException(
        'Parking board is unavailable (${response.statusCode}).',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final slots = (body['slots'] as List<dynamic>? ?? const []);
    return slots
        .asMap()
        .entries
        .map((entry) {
          final data = entry.value as Map<String, dynamic>;
          final slotId = data['id'].toString();
          return ParkingSlot(
            id: slotId,
            lotId: lotId,
            row: String.fromCharCode(65 + (entry.key ~/ 15)),
            number: entry.key + 1,
            state: _state(data['state']?.toString()),
            size: VehicleSize.medium,
            walkingDistanceMeters: 20 + entry.key * 2,
            cameraId: 'ai-camera-1',
          );
        })
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> reserve({
    required String lotId,
    required String slotId,
    required String userId,
    required String vehicleId,
    required String vehiclePlate,
    required DateTime arrivalTime,
    required int durationHours,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/book/$slotId?lot_id=$lotId'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'vehicle_id': vehicleId,
            'vehicle_plate': vehiclePlate,
            'arrival_time': arrivalTime.toIso8601String(),
            'duration_hours': durationHours,
          }),
        )
        .timeout(const Duration(seconds: 7));
    final message = _message(response.body);
    if (response.statusCode == 409) throw AiConflictException(message);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiApiException(message);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> cancel(String bookingReference) async {
    final response = await _client
        .post(Uri.parse('$baseUrl/api/bookings/$bookingReference/cancel'))
        .timeout(const Duration(seconds: 7));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiApiException(_message(response.body));
    }
  }

  SlotState _state(String? value) => switch (value) {
    'available' => SlotState.free,
    'occupied' || 'booked' => SlotState.taken,
    _ => SlotState.unknown,
  };

  String _message(String value) {
    try {
      final body = jsonDecode(value) as Map<String, dynamic>;
      return body['detail']?.toString() ??
          'The parking service rejected the request.';
    } catch (_) {
      return 'The parking service is unavailable.';
    }
  }
}

class AiApiException implements Exception {
  AiApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiConflictException extends AiApiException {
  AiConflictException(super.message);
}
