import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_parking/data/services/cloud_functions_client.dart';
import 'package:smart_parking/data/services/email_otp_auth.dart';
import 'package:smart_parking/data/services/firestore_service.dart';
import 'package:smart_parking/data/services/parking_state_manager.dart';

import 'support/fake_auth_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('otpErrorFromServer', () {
    CloudFunctionsException err(String status) => CloudFunctionsException(
          code: CloudFunctionsClient.normalizeStatus(status),
          message: 'server message',
        );

    test('normalizes callable protocol statuses', () {
      expect(CloudFunctionsClient.normalizeStatus('RESOURCE_EXHAUSTED'), 'resource-exhausted');
      expect(CloudFunctionsClient.normalizeStatus('PERMISSION_DENIED'), 'permission-denied');
    });

    test('permission-denied means wrong code', () {
      final e = otpErrorFromServer(err('PERMISSION_DENIED'), verifying: true);
      expect(e.code, 'permission-denied');
      expect(e.message, contains('Incorrect code'));
    });

    test('resource-exhausted means locked when verifying and cooldown when requesting', () {
      expect(otpErrorFromServer(err('RESOURCE_EXHAUSTED'), verifying: true).message,
          contains('Too many incorrect attempts'));
      expect(otpErrorFromServer(err('RESOURCE_EXHAUSTED'), verifying: false).message,
          contains('wait'));
    });

    test('failed-precondition means expired or already used', () {
      expect(otpErrorFromServer(err('FAILED_PRECONDITION'), verifying: true).message,
          contains('expired or was already used'));
    });

    test('network failures do not succeed offline', () {
      final e = otpErrorFromServer(const SocketException('offline'), verifying: true);
      expect(e.code, 'unavailable');
    });
  });

  group('ParkingStateManager sign-in', () {
    late FakeEmailOtpAuthGateway gateway;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      gateway = FakeEmailOtpAuthGateway();
      FirestoreService().authGateway = gateway;
    });

    test('uses the server demo code and the Firebase uid as the profile id', () async {
      final state = ParkingStateManager();
      final demoCode = await state.sendVerificationOtp('Driver@SLIIT.lk');
      expect(demoCode, FakeEmailOtpAuthGateway.fixedCode);
      expect(state.activeGeneratedOtp, FakeEmailOtpAuthGateway.fixedCode);

      final result = await state.verifyOtp('driver@sliit.lk', demoCode!);
      expect(result.isValid, isTrue);
      expect(state.isLoggedIn, isTrue);
      expect(state.currentUser.id, gateway.currentUser!.uid);
      expect(state.currentUser.email, 'driver@sliit.lk');
      expect(state.activeGeneratedOtp, isNull);
    });

    test('wrong code is rejected with the mapped message', () async {
      final state = ParkingStateManager();
      await state.sendVerificationOtp('driver@sliit.lk');
      final result = await state.verifyOtp('driver@sliit.lk', '000000');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Incorrect code'));
      expect(state.isLoggedIn, isFalse);
    });

    test('bookings are streamed only for the signed-in Firebase user', () async {
      final state = ParkingStateManager();
      expect(state.canStreamUserBookings, isFalse, reason: 'signed-out placeholder profile');

      final code = await state.sendVerificationOtp('driver@sliit.lk');
      await state.verifyOtp('driver@sliit.lk', code!);
      expect(state.canStreamUserBookings, isTrue);

      await state.logout();
      expect(state.canStreamUserBookings, isFalse);
    });

    test('logout signs out of Firebase Auth', () async {
      final state = ParkingStateManager();
      final code = await state.sendVerificationOtp('driver@sliit.lk');
      await state.verifyOtp('driver@sliit.lk', code!);
      await state.logout();
      expect(gateway.signOutCount, 1);
      expect(gateway.currentUser, isNull);
      expect(state.isLoggedIn, isFalse);
    });
  });

  group('booking callables', () {
    test('send the ID token and never send userId', () async {
      // The test binding replaces HttpClient with a mock; talk to a real loopback server instead
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousOverrides);

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <Map<String, dynamic>>[];
      final authHeaders = <String?>[];
      server.listen((req) async {
        authHeaders.add(req.headers.value('authorization'));
        received.add(jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>);
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'result': {'ok': true}}));
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final client = CloudFunctionsClient()
        ..configure(useEmulator: true, emulatorHost: '127.0.0.1', emulatorPort: server.port)
        ..idTokenProvider = () async => 'id-token-123';
      addTearDown(() => client.idTokenProvider = null);

      final service = FirestoreService();
      expect(await service.cancelBookingOnServer(bookingId: 'BK-1'), isTrue);
      await service.extendHoldOnServer(bookingId: 'BK-1');
      await service.acceptUpgradeOnServer(bookingId: 'BK-1', newSlotId: 'B-01');
      await service.checkInOnServer(qrToken: 'qr', bookingId: 'BK-1');

      expect(received, hasLength(4));
      for (final body in received) {
        expect((body['data'] as Map).containsKey('userId'), isFalse);
      }
      expect(authHeaders, everyElement('Bearer id-token-123'));
    });
  });
}
