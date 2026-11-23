// integration_contracts_test.dart
// Smart Parking (J26-IT-335) — Flutter Integration Models & Contracts Test Suite

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_parking/core/config/app_config.dart';
import 'package:smart_parking/core/theme/app_theme.dart';
import 'package:smart_parking/data/models/admin_alert_model.dart';
import 'package:smart_parking/data/models/booking_model.dart';
import 'package:smart_parking/data/services/parking_state_manager.dart';
import 'package:smart_parking/features/admin/hardware_integration_simulator_modal.dart';

void main() {
  group('Subsystem Integration Models & Contracts (Flutter)', () {
    test('BookingCharge serializes and deserializes correctly', () {
      final charge = BookingCharge(
        id: 'CHG-001',
        type: 'parking',
        amount: 300,
        currency: 'LKR',
        timestamp: DateTime(2026, 10, 19, 10, 0),
        description: 'Parking duration charge: 2 hours',
      );

      final json = charge.toJson();
      expect(json['id'], equals('CHG-001'));
      expect(json['type'], equals('parking'));
      expect(json['amount'], equals(300));
      expect(json['currency'], equals('LKR'));

      final restored = BookingCharge.fromJson(json);
      expect(restored.id, equals(charge.id));
      expect(restored.type, equals(charge.type));
      expect(restored.amount, equals(charge.amount));
      expect(restored.currency, equals('LKR'));
      expect(restored.description, equals(charge.description));
    });

    test('Booking model parses charges array and conflict reallocation fields', () {
      final json = {
        'id': 'BK-100',
        'userId': 'user-1',
        'vehicleId': 'v-1',
        'vehiclePlate': 'WP-CAR-1111',
        'lotId': 'lot-1',
        'lotName': 'Colombo Central Hub',
        'slotId': 'A-02',
        'originalSlotId': 'A-01',
        'bookedAt': '2026-10-19T08:00:00.000Z',
        'arrivalTime': '2026-10-19T08:30:00.000Z',
        'durationHours': 2,
        'status': 'reserved',
        'estimatedFee': 300,
        'extensionFee': 50,
        'finalFee': 350,
        'qrToken': 'SPS.v1.BK-100.A-02.1792426913.1792427813.abcdef.12345678',
        'reallocatedDueToConflict': true,
        'reallocatedFromSlotId': 'A-01',
        'charges': [
          {
            'id': 'CHG-100-PARK',
            'type': 'parking',
            'amount': 300,
            'currency': 'LKR',
            'timestamp': '2026-10-19T10:30:00.000Z',
            'description': 'Base parking fee',
          },
          {
            'id': 'CHG-100-EXT',
            'type': 'extension',
            'amount': 50,
            'currency': 'LKR',
            'timestamp': '2026-10-19T08:45:00.000Z',
            'description': 'Hold extension fee',
          }
        ],
      };

      final booking = Booking.fromJson(json);
      expect(booking.id, equals('BK-100'));
      expect(booking.slotId, equals('A-02'));
      expect(booking.originalSlotId, equals('A-01'));
      expect(booking.reallocatedDueToConflict, isTrue);
      expect(booking.reallocatedFromSlotId, equals('A-01'));
      expect(booking.charges.length, equals(2));
      expect(booking.charges[0].type, equals('parking'));
      expect(booking.charges[0].amount, equals(300));
      expect(booking.charges[1].type, equals('extension'));
      expect(booking.charges[1].amount, equals(50));

      final serialized = booking.toJson();
      expect(serialized['reallocatedDueToConflict'], isTrue);
      expect(serialized['reallocatedFromSlotId'], equals('A-01'));
      expect((serialized['charges'] as List).length, equals(2));
    });

    test('AdminAlert serializes and deserializes properly', () {
      final alert = AdminAlert(
        id: 'ALT-101',
        lotId: 'lot-colombo-01',
        slotId: 'A-01',
        bookingId: 'BK-100',
        type: 'slot_conflict',
        severity: 'critical',
        timestamp: DateTime(2026, 10, 19, 12, 30),
        description: 'Unauthorized vehicle in reserved bay',
        resolved: false,
        metadata: {'camera': 'cam-01'},
      );

      final json = alert.toJson();
      expect(json['id'], equals('ALT-101'));
      expect(json['type'], equals('slot_conflict'));
      expect(json['severity'], equals('critical'));

      final restored = AdminAlert.fromJson(json);
      expect(restored.id, equals('ALT-101'));
      expect(restored.type, equals('slot_conflict'));
      expect(restored.severity, equals('critical'));
      expect(restored.resolved, isFalse);
      expect(restored.metadata?['camera'], equals('cam-01'));
    });

    testWidgets('HardwareIntegrationSimulatorModal renders all 3 tabs in demo mode',
        (WidgetTester tester) async {
      AppConfig.demoModeOverride = true;
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: ChangeNotifierProvider(
            create: (_) => ParkingStateManager(),
            child: const Scaffold(
              body: HardwareIntegrationSimulatorModal(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check header and tabs
      expect(find.text('Hardware Integration Stubs'), findsOneWidget);
      expect(find.text('CCTV Vision'), findsOneWidget);
      expect(find.text('IoT Barrier Gate'), findsOneWidget);
      expect(find.text('Smart Payment'), findsOneWidget);

      // Verify CCTV initial reading action
      expect(find.text('1. Send Initial Reading (t=0s, Pending Debounce)'), findsOneWidget);
      expect(find.text('3. Inject Conflict (Unauthorized Bay Intrusion)'), findsOneWidget);

      // Tap IoT Barrier Gate tab
      await tester.tap(find.text('IoT Barrier Gate'));
      await tester.pumpAndSettle();
      expect(find.text('Barrier Hardware Device'), findsOneWidget);

      // Tap Smart Payment tab
      await tester.tap(find.text('Smart Payment'));
      await tester.pumpAndSettle();
      expect(find.text('Billing Summary'), findsOneWidget);

      AppConfig.resetOverride();
    });
  });
}
