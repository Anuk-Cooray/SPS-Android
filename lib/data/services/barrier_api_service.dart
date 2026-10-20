
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'service_contracts.dart';

class BarrierApiException implements Exception {
  final String message;

  const BarrierApiException(this.message);

  @override
  String toString() => message;
}

class BarrierApiService implements BarrierService {
  // Android emulator -> host computer.
  // Use http://127.0.0.1:8000 for requests made on the host itself.
  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  BarrierApiService({
    this.baseUrl = 'http://10.0.2.2:8000',
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  Uri _buildUri(String path) {
    final base = baseUrl.replaceFirst(RegExp(r'/$'), '');
    return Uri.parse('$base$path');
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client
          .post(
            _buildUri(path),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);

      final dynamic decoded;

      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        throw BarrierApiException(
          'Invalid server response (HTTP ${response.statusCode}).',
        );
      }

      if (decoded is! Map<String, dynamic>) {
        throw const BarrierApiException(
          'The server returned an unexpected response.',
        );
      }

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        throw BarrierApiException(
          decoded['detail']?.toString() ??
              decoded['message']?.toString() ??
              'Request failed (HTTP ${response.statusCode}).',
        );
      }

      return decoded;
    } on BarrierApiException {
      rethrow;
    } on http.ClientException {
      throw const BarrierApiException(
        'Cannot connect to the backend. Check its address and status.',
      );
    } on Exception catch (error) {
      throw BarrierApiException('Request failed: $error');
    }
  }

  // QR barrier verification.
  @override
  Future<bool> verifyAndOpenBarrier({
    required String bookingId,
    required String qrToken,
  }) async {
    if (bookingId.trim().isEmpty || qrToken.trim().isEmpty) {
      throw const BarrierApiException(
        'Booking ID and QR token are required.',
      );
    }

    final response = await _postJson(
      '/api/barrier/verify',
      {
        'booking_id': bookingId,
        'qr_token': qrToken,
      },
    );

    return response['authorized'] == true &&
        response['barrier_opened'] == true;
  }

  // Walking directions.
  @override
  Future<Map<String, dynamic>> getWalkingDirectionsToCar({
    required String slotId,
    required double userLat,
    required double userLng,
  }) async {
    if (slotId.trim().isEmpty) {
      throw const BarrierApiException('Slot ID is required.');
    }

    return _postJson(
      '/api/navigation/walking-directions',
      {
        'slot_id': slotId,
        'user_lat': userLat,
        'user_lng': userLng,
      },
    );
  }

  // Find My Car: predict the first-floor sector from six BLE RSSI values.
  Future<int> predictSector({
    required double b1,
    required double b2,
    required double b3,
    required double b4,
    required double b5,
    required double b6,
  }) async {
    final response = await _postJson(
      '/api/navigation/predict-sector',
      {
        'B1': b1,
        'B2': b2,
        'B3': b3,
        'B4': b4,
        'B5': b5,
        'B6': b6,
      },
    );

    final prediction = response['predicted_sector'];

    if (prediction is num) {
      return prediction.toInt();
    }

    throw const BarrierApiException(
      'The backend response did not contain a valid sector prediction.',
    );
  }

  void dispose() {
    _client.close();
  }
}
