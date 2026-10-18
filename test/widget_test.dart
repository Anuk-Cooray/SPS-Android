import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_parking/data/services/mock_data.dart';
import 'package:smart_parking/data/services/parking_state_manager.dart';
import 'package:smart_parking/main.dart';

void main() {
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

    // Verify first screen is LoginScreen
    expect(find.text('Park smarter.\nBook in seconds.'), findsOneWidget);
    expect(find.text('Verify & Continue'), findsOneWidget);

    // Tap Verify & Continue with prefilled demo credentials
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

    // Tap "Test New User"
    await tester.tap(find.text('Test New User'));
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
}
