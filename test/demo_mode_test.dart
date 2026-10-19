// demo_mode_test.dart
// Smart Parking (J26-IT-335) — AppConfig.kDemoMode Simulation Gating Unit & Widget Tests

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_parking/core/config/app_config.dart';
import 'package:smart_parking/core/theme/app_theme.dart';
import 'package:smart_parking/core/widgets/hold_countdown_timer_widget.dart';
import 'package:smart_parking/data/models/booking_model.dart';
import 'package:smart_parking/data/services/parking_state_manager.dart';
import 'package:smart_parking/features/auth/login_screen.dart';
import 'package:smart_parking/features/reoptimization/navigation_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void setPhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  final sampleInTransitBooking = Booking(
    id: 'BK-DEMO-1',
    userId: 'user-001',
    vehicleId: 'veh-001',
    vehiclePlate: 'CAB-4821',
    lotId: 'lot-01',
    lotName: 'Main Building Lot',
    slotId: 'A1',
    bookedAt: DateTime.now(),
    arrivalTime: DateTime.now().add(const Duration(minutes: 20)),
    durationHours: 2,
    status: BookingStatus.reserved,
    estimatedFee: 200,
    qrToken: 'QR-TEST-1',
  );

  final sampleArrivedBooking = Booking(
    id: 'BK-DEMO-2',
    userId: 'user-001',
    vehicleId: 'veh-001',
    vehiclePlate: 'CAB-4821',
    lotId: 'lot-01',
    lotName: 'Main Building Lot',
    slotId: 'A1',
    bookedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    arrivalTime: DateTime.now().subtract(const Duration(minutes: 1)),
    durationHours: 2,
    status: BookingStatus.reserved,
    estimatedFee: 200,
    qrToken: 'QR-TEST-2',
    holdExpiresAt: DateTime.now().add(const Duration(minutes: 14)),
  );

  setUp(() {
    AppConfig.resetOverride();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    AppConfig.resetOverride();
  });

  group('AppConfig Environment & Override Tests', () {
    test('kDemoMode defaults to true for evaluation & defense environment', () {
      expect(AppConfig.kDemoMode, isTrue);
    });

    test('demoModeOverride allows toggling to false and resetting', () {
      expect(AppConfig.kDemoMode, isTrue);

      AppConfig.demoModeOverride = false;
      expect(AppConfig.kDemoMode, isFalse);

      AppConfig.demoModeOverride = true;
      expect(AppConfig.kDemoMode, isTrue);

      AppConfig.resetOverride();
      expect(AppConfig.kDemoMode, isTrue);
    });
  });

  group('LoginScreen Demo Mode Gating', () {
    testWidgets('shows preset demo chips when kDemoMode is true', (WidgetTester tester) async {
      setPhoneSize(tester);
      AppConfig.demoModeOverride = true;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LoginScreen(onLoginSuccess: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ActionChip, 'anuk@example.com'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'driver@sliit.lk'), findsOneWidget);
    });

    testWidgets('hides preset demo chips when kDemoMode is false', (WidgetTester tester) async {
      setPhoneSize(tester);
      AppConfig.demoModeOverride = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LoginScreen(onLoginSuccess: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ActionChip, 'anuk@example.com'), findsNothing);
      expect(find.widgetWithText(ActionChip, 'driver@sliit.lk'), findsNothing);
    });
  });

  group('NavigationScreen Simulation Gating', () {
    testWidgets('shows route scrubber and test triggers when kDemoMode is true', (WidgetTester tester) async {
      setPhoneSize(tester);
      AppConfig.demoModeOverride = true;
      final state = ParkingStateManager();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: NavigationScreen(
                booking: sampleInTransitBooking,
                onCancelBooking: () {},
                onShowQr: () {},
                onTriggerUpgradeOffer: () {},
                onTriggerLateArrival: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('SIMULATION PAUSED'), findsOneWidget);
      expect(find.text('Test 10m Upgrade'), findsOneWidget);
      expect(find.text('Test Late (+10m)'), findsOneWidget);
    });

    testWidgets('hides route scrubber and test triggers when kDemoMode is false', (WidgetTester tester) async {
      setPhoneSize(tester);
      AppConfig.demoModeOverride = false;
      final state = ParkingStateManager();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: NavigationScreen(
                booking: sampleInTransitBooking,
                onCancelBooking: () {},
                onShowQr: () {},
                onTriggerUpgradeOffer: () {},
                onTriggerLateArrival: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsNothing);
      expect(find.text('SIMULATION PAUSED'), findsNothing);
      expect(find.text('Test 10m Upgrade'), findsNothing);
      expect(find.text('Test Late (+10m)'), findsNothing);
    });
  });

  group('HoldCountdownTimerWidget Demo Gating', () {
    testWidgets('shows simulation controls in compact mode when kDemoMode is true', (WidgetTester tester) async {
      setPhoneSize(tester);
      AppConfig.demoModeOverride = true;
      final state = ParkingStateManager();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: HoldCountdownTimerWidget(
                booking: sampleInTransitBooking,
                compact: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('To Arrival'), findsOneWidget);
    });

    testWidgets('hides simulation controls in compact mode when kDemoMode is false', (WidgetTester tester) async {
      setPhoneSize(tester);
      AppConfig.demoModeOverride = false;
      final state = ParkingStateManager();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: HoldCountdownTimerWidget(
                booking: sampleInTransitBooking,
                compact: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('To Arrival'), findsNothing);
    });

    testWidgets('shows simulation controls in expanded mode when kDemoMode is true', (WidgetTester tester) async {
      setPhoneSize(tester);
      AppConfig.demoModeOverride = true;
      final state = ParkingStateManager();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: HoldCountdownTimerWidget(
                    booking: sampleArrivedBooking,
                    compact: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Test Auto-Release (10s)'), findsOneWidget);
      expect(find.text('+5m'), findsOneWidget);
    });

    testWidgets('hides simulation controls in expanded mode when kDemoMode is false', (WidgetTester tester) async {
      setPhoneSize(tester);
      AppConfig.demoModeOverride = false;
      final state = ParkingStateManager();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: HoldCountdownTimerWidget(
                    booking: sampleArrivedBooking,
                    compact: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Test Auto-Release (10s)'), findsNothing);
      expect(find.text('+5m'), findsNothing);
    });
  });
}
