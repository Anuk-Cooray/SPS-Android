// booking_fallback_test.dart
// Outside demo mode a failed createBooking must surface an error instead of a booking the
// server never confirmed; demo mode keeps the offline placeholder for examiner walkthroughs.

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parking/core/config/app_config.dart';
import 'package:smart_parking/data/models/vehicle_model.dart';
import 'package:smart_parking/data/services/cloud_functions_client.dart';
import 'package:smart_parking/data/services/firestore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;

  setUp(() async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    addTearDown(AppConfig.resetOverride);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      await utf8.decoder.bind(req).join();
      req.response
        ..statusCode = 503
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'error': {'status': 'UNAVAILABLE', 'message': 'backend down'}
        }));
      await req.response.close();
    });
    CloudFunctionsClient().configure(useEmulator: true, emulatorHost: '127.0.0.1', emulatorPort: server.port);
  });

  Future<Object> book() => FirestoreService().createBookingOnServer(
        lotId: 'lot-main',
        slotId: 'A-02',
        userId: 'uid-1',
        vehiclePlate: 'CAB-4821',
        vehicleSize: VehicleSize.medium,
        arrivalTime: DateTime.now().add(const Duration(minutes: 20)),
        durationHours: 1,
      );

  test('production mode surfaces the failure instead of a placeholder booking', () async {
    AppConfig.demoModeOverride = false;
    await expectLater(
      book(),
      throwsA(isA<CloudFunctionsException>().having((e) => e.code, 'code', 'unavailable')),
    );
  });

  test('demo mode still falls back to a local placeholder booking', () async {
    AppConfig.demoModeOverride = true;
    final booking = await book();
    expect(booking, isNotNull);
  });
}
