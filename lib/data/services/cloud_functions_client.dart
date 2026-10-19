// cloud_functions_client.dart
// Smart Parking (J26-IT-335) — Lightweight Firebase Cloud Functions HTTPS Client

import 'dart:convert';
import 'dart:io' show HttpClient, Platform;
import 'package:flutter/foundation.dart';

class CloudFunctionsException implements Exception {
  final String code;
  final String message;
  final dynamic details;

  const CloudFunctionsException({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  String toString() => 'CloudFunctionsException($code): $message';
}

class SlotCollisionException extends CloudFunctionsException {
  final String? nextBestSlotId;

  const SlotCollisionException({
    required super.message,
    this.nextBestSlotId,
    super.details,
  }) : super(code: 'already-exists');
}

class CloudFunctionsClient {
  static final CloudFunctionsClient _instance = CloudFunctionsClient._internal();
  factory CloudFunctionsClient() => _instance;
  CloudFunctionsClient._internal();

  String _projectId = 'demo-sps-concurrency';
  String _region = 'us-central1';
  bool _useEmulator = true;
  String _emulatorHost = '127.0.0.1';
  int _emulatorPort = 5001;

  void configure({
    String? projectId,
    String? region,
    bool? useEmulator,
    String? emulatorHost,
    int? emulatorPort,
  }) {
    if (projectId != null) _projectId = projectId;
    if (region != null) _region = region;
    if (useEmulator != null) _useEmulator = useEmulator;
    if (emulatorHost != null) _emulatorHost = emulatorHost;
    if (emulatorPort != null) _emulatorPort = emulatorPort;
  }

  String get baseUrl {
    if (_useEmulator) {
      // In Android Emulator, localhost is 10.0.2.2. On Windows/Desktop/iOS it is 127.0.0.1.
      String host = _emulatorHost;
      try {
        if (!kIsWeb && Platform.isAndroid && host == '127.0.0.1') {
          host = '10.0.2.2';
        }
      } catch (_) {}
      return 'http://$host:$_emulatorPort/$_projectId/$_region';
    }
    return 'https://$_region-$_projectId.cloudfunctions.net';
  }

  Future<Map<String, dynamic>> call(String functionName, Map<String, dynamic> data) async {
    if (kIsWeb) {
      throw const CloudFunctionsException(
        code: 'unimplemented',
        message: 'Web runtime not configured for direct HttpClient',
      );
    }

    final url = Uri.parse('$baseUrl/$functionName');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);

    try {
      final request = await client.postUrl(url);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Accept', 'application/json');

      final bodyBytes = utf8.encode(jsonEncode({'data': data}));
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
        final result = decoded['result'];
        if (result is Map<String, dynamic>) {
          return result;
        }
        return {'data': result};
      } else {
        Map<String, dynamic>? errorJson;
        try {
          final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
          errorJson = decoded['error'] as Map<String, dynamic>?;
        } catch (_) {}

        final message = errorJson?['message'] as String? ?? 'Cloud function invocation failed: ${response.statusCode}';
        final status = errorJson?['status'] as String? ?? 'internal';

        if (message.contains('Slot just taken') || message.contains('no longer available') || status == 'ALREADY_EXISTS') {
          throw SlotCollisionException(
            message: "Slot just taken — here's the next best",
            details: errorJson,
          );
        }

        throw CloudFunctionsException(
          code: status,
          message: message,
          details: errorJson,
        );
      }
    } finally {
      client.close();
    }
  }

  /// Sends a raw HTTP POST request to an onRequest HTTPS Cloud Function (e.g. hardware integrations)
  Future<Map<String, dynamic>> postRaw(
    String endpointName,
    Map<String, dynamic> body, {
    Map<String, String>? customHeaders,
  }) async {
    if (kIsWeb) {
      throw const CloudFunctionsException(
        code: 'unimplemented',
        message: 'Web runtime not configured for direct HttpClient',
      );
    }

    final url = Uri.parse('$baseUrl/$endpointName');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);

    try {
      final request = await client.postUrl(url);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Accept', 'application/json');

      if (customHeaders != null) {
        customHeaders.forEach((key, val) {
          request.headers.set(key, val);
        });
      }

      final bodyBytes = utf8.encode(jsonEncode(body));
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      Map<String, dynamic> decoded = {};
      try {
        if (responseBody.isNotEmpty) {
          decoded = jsonDecode(responseBody) as Map<String, dynamic>;
        }
      } catch (_) {}

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      } else {
        final errorMsg = decoded['error'] ??
            decoded['message'] ??
            'Endpoint $endpointName failed with HTTP ${response.statusCode}';
        throw CloudFunctionsException(
          code: 'http_${response.statusCode}',
          message: errorMsg.toString(),
          details: decoded,
        );
      }
    } finally {
      client.close();
    }
  }
}

