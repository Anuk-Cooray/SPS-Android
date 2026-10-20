// timezone_handling_test.dart
// Server-bound timestamps must carry an explicit UTC offset, and server timestamps ('...Z')
// must be shown in the device's local time.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:smart_parking/core/theme/app_theme.dart';
import 'package:smart_parking/data/models/booking_model.dart';
import 'package:smart_parking/data/models/vehicle_model.dart';
import 'package:smart_parking/data/services/cloud_functions_client.dart';
import 'package:smart_parking/data/services/firestore_service.dart';
import 'package:smart_parking/features/barrier_checkin/parked_screen.dart';

Booking _booking({DateTime? checkedInAt}) {
  final now = DateTime.now();
  return Booking(
    id: 'BK-TZ-1',
    userId: 'uid-1',
    vehicleId: 'veh-01',
    vehiclePlate: 'CAB-4821',
    lotId: 'lot-main',
    lotName: 'Main Building Lot',
    slotId: 'A-06',
    bookedAt: now,
    arrivalTime: now.add(const Duration(minutes: 14)),
    durationHours: 2,
    status: BookingStatus.checkedIn,
    estimatedFee: 200,
    qrToken: 'QR-TZ-1',
    checkedInAt: checkedInAt,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Booking.fromJson', () {
    test('converts UTC server timestamps to local time without shifting the instant', () {
      final arrivalUtc = DateTime.utc(2026, 10, 20, 12, 58);
      final holdUtc = arrivalUtc.add(const Duration(minutes: 15));
      final json = _booking().toJson()
        ..['arrivalTime'] = arrivalUtc.toIso8601String()
        ..['holdExpiresAt'] = holdUtc.toIso8601String();

      final booking = Booking.fromJson(json);

      expect(booking.arrivalTime.isUtc, isFalse);
      expect(booking.arrivalTime, arrivalUtc.toLocal());
      expect(booking.arrivalTime.isAtSameMomentAs(arrivalUtc), isTrue);
      expect(booking.holdExpiresAt!.difference(booking.arrivalTime), const Duration(minutes: 15));
      expect(DateFormat('h:mm a').format(booking.arrivalTime),
          DateFormat('h:mm a').format(arrivalUtc.toLocal()));
    });

    test('hold countdown reflects the real remaining time', () {
      final holdUtc = DateTime.now().toUtc().add(const Duration(minutes: 29));
      final json = _booking().toJson()..['holdExpiresAt'] = holdUtc.toIso8601String();
      final booking = Booking.fromJson(json);
      expect(booking.remainingHoldDuration.inMinutes, inInclusiveRange(28, 29));
    });
  });

  test('createBooking sends arrivalTime as UTC with an explicit Z', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final bodies = <Map<String, dynamic>>[];
    server.listen((req) async {
      bodies.add(jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>);
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'result': _booking().toJson()}));
      await req.response.close();
    });

    CloudFunctionsClient().configure(useEmulator: true, emulatorHost: '127.0.0.1', emulatorPort: server.port);
    final localArrival = DateTime(2026, 10, 20, 18, 28);
    await FirestoreService().createBookingOnServer(
      lotId: 'lot-main',
      slotId: 'A-06',
      userId: 'local-only',
      vehiclePlate: 'CAB-4821',
      vehicleSize: VehicleSize.medium,
      arrivalTime: localArrival,
      durationHours: 2,
    );

    final sent = (bodies.single['data'] as Map)['arrivalTime'] as String;
    expect(sent, endsWith('Z'));
    expect(DateTime.parse(sent).isAtSameMomentAs(localArrival), isTrue);
  });

  group('ParkedScreen', () {
    Future<void> pump(WidgetTester tester, Booking booking) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: ParkedScreen(booking: booking, onExitParking: () {}),
      ));
    }

    testWidgets('shows the real check-in time, elapsed time and fee', (tester) async {
      final checkedInAt = DateTime.now().subtract(const Duration(minutes: 75));
      await pump(tester, _booking(checkedInAt: checkedInAt.toUtc()));

      expect(find.text(DateFormat('HH:mm').format(checkedInAt)), findsOneWidget);
      expect(find.text('1:15'), findsOneWidget);
      // 2 h for LKR 200 -> LKR 100/h, 1h15m billed as 2 started hours
      expect(find.text('LKR 200'), findsOneWidget);
    });

    testWidgets('falls back to now when the booking predates check-in', (tester) async {
      await pump(tester, _booking());
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('LKR 100'), findsOneWidget);
      expect(find.text(DateFormat('HH:mm').format(DateTime.now())), findsOneWidget);
    });
  });
}
