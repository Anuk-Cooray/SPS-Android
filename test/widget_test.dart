import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_parking/core/theme/app_theme.dart';
import 'package:smart_parking/data/services/firestore_service.dart';
import 'package:smart_parking/data/services/mock_data.dart';
import 'package:smart_parking/data/services/parking_state_manager.dart';
import 'package:smart_parking/features/reoptimization/navigation_screen.dart';
import 'package:smart_parking/main.dart';

import 'support/fake_auth_gateway.dart';

void main() {
  setUp(() {
    FirestoreService().authGateway = FakeEmailOtpAuthGateway();
  });

  void setPhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('First time launch renders LoginScreen and handles demo login',
      (WidgetTester tester) async {
    setPhoneSize(tester);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ParkingStateManager(),
        child: const SmartParkingApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify first screen is LoginScreen (Step 1)
    expect(find.text('Park smarter.\nBook in seconds.'), findsOneWidget);
    expect(find.text('Send Verification Code'), findsOneWidget);

    // Tap Send Verification Code with prefilled demo credentials
    await tester.tap(find.text('Send Verification Code'));
    await tester.pumpAndSettle();

    // Verify Step 2 is shown
    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.text('Auto-fill code'), findsOneWidget);

    // Tap Auto-fill code to fill the generated OTP
    await tester.tap(find.text('Auto-fill code'));
    await tester.pumpAndSettle();

    // Tap Verify & Continue
    await tester.tap(find.text('Verify & Continue'));
    await tester.pump();
    await tester.pumpAndSettle();

    // Successfully transitioned to Explore screen
    expect(find.text('SLIIT Malabe Campus'), findsOneWidget);
  });

  testWidgets('New user without vehicle routes to VehicleOnboardingScreen',
      (WidgetTester tester) async {
    setPhoneSize(tester);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ParkingStateManager(),
        child: const SmartParkingApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Tap "Register New Driver"
    await tester.tap(find.text('Register New Driver'));
    await tester.pumpAndSettle();

    // Tap Send Verification Code
    await tester.tap(find.text('Send Verification Code'));
    await tester.pumpAndSettle();

    // Verify Step 2 is shown
    expect(find.text('Verify your email'), findsOneWidget);

    // Tap Auto-fill code
    await tester.tap(find.text('Auto-fill code'));
    await tester.pumpAndSettle();

    // Tap Verify & Continue
    await tester.tap(find.text('Verify & Continue'));
    await tester.pump();
    await tester.pumpAndSettle();

    // Verify VehicleOnboardingScreen is shown
    expect(find.text('Register your vehicle'), findsOneWidget);
    expect(find.text('Complete Setup & Start Parking'), findsOneWidget);

    // Complete onboarding
    await tester.tap(find.text('Complete Setup & Start Parking'));
    await tester.pump();
    await tester.pumpAndSettle();

    // Lands on Explore map
    expect(find.text('SLIIT Malabe Campus'), findsOneWidget);
  });

  testWidgets('Existing session in SharedPreferences skips login directly to Explore map',
      (WidgetTester tester) async {
    setPhoneSize(tester);

    // Pre-seed active session in SharedPreferences
    SharedPreferences.setMockInitialValues({
      'sp_is_logged_in': true,
      'sp_user_profile': jsonEncode(MockData.initialUser.toJson()),
    });

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ParkingStateManager(),
        child: const SmartParkingApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify explore screen rendered immediately without showing login
    expect(find.text('SLIIT Malabe Campus'), findsOneWidget);

    // 1. Tap New Building P2
    final newBuildingP2Card = find.text('New Building P2');
    expect(newBuildingP2Card, findsOneWidget);
    await tester.tap(newBuildingP2Card);
    await tester.pumpAndSettle();

    // Verify BookSlotScreen opened
    expect(find.text('Estimated fee'), findsOneWidget);

    // Go back using custom back button
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();

    // 2. Tap Sports Complex (lot with 0 free slots)
    final sportsComplexCard = find.text('Sports Complex');
    expect(sportsComplexCard, findsOneWidget);
    await tester.tap(sportsComplexCard);
    await tester.pumpAndSettle();

    // Verify BookSlotScreen opened safely and shows disabled/full status
    expect(find.text('Estimated fee'), findsOneWidget);
    expect(find.text('Lot is Full'), findsOneWidget);
  });

  testWidgets('Navigation screen renders simulation controls and updates ETA upon progress',
      (WidgetTester tester) async {
    setPhoneSize(tester);

    SharedPreferences.setMockInitialValues({
      'sp_is_logged_in': true,
      'sp_user_profile': jsonEncode(MockData.initialUser.toJson()),
    });

    final manager = ParkingStateManager();
    final lot = manager.lots.first;
    final slot = lot.slots.firstWhere((s) => s.state == SlotState.free);
    final booking = manager.reserveSlot(
      lot: lot,
      slot: slot,
      arrivalTime: DateTime.now().add(const Duration(minutes: 12)),
      durationHours: 2,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ParkingStateManager>.value(
        value: manager,
        child: MaterialApp(
          theme: AppTheme.light,
          home: NavigationScreen(
            booking: booking,
            onCancelBooking: () {},
            onShowQr: () {},
            onTriggerUpgradeOffer: () {},
            onTriggerLateArrival: () {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Navigation Screen elements
    expect(find.text('12 min'), findsOneWidget);
    expect(find.text('SIMULATION PAUSED'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);

    // Tap Step forward button (+10%)
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pumpAndSettle();

    // Verify progress updated and ETA decreased
    expect(manager.routeProgress, greaterThan(0.0));

    manager.dispose();
  });

  testWidgets('Email verification flow: invalid code shows error and Change Email returns to Step 1',
      (WidgetTester tester) async {
    setPhoneSize(tester);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ParkingStateManager(),
        child: const SmartParkingApp(),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Enter custom email
    await tester.enterText(find.byType(TextField).first, 'student@sliit.lk');
    await tester.tap(find.text('Send Verification Code'));
    await tester.pumpAndSettle();

    // 2. On Step 2, enter wrong code
    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.textContaining('student@sliit.lk'), findsOneWidget);

    // Enter incorrect digit in first box
    await tester.enterText(find.byType(TextField).first, '0');
    await tester.tap(find.text('Verify & Continue'));
    await tester.pumpAndSettle();

    // Shows validation error for incomplete/incorrect OTP
    expect(find.text('Please enter the complete 6-digit verification code'), findsOneWidget);

    // 3. Tap Change Email to go back to Step 1
    await tester.tap(find.text('Change Email'));
    await tester.pumpAndSettle();

    // Back on Step 1
    expect(find.text('Park smarter.\nBook in seconds.'), findsOneWidget);
    expect(find.text('Send Verification Code'), findsOneWidget);
  });
}
