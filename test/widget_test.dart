import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_parking/data/services/parking_state_manager.dart';
import 'package:smart_parking/main.dart';

void main() {
  testWidgets('SmartParkingApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ParkingStateManager(),
        child: const SmartParkingApp(),
      ),
    );

    // Verify app renders explore screen
    expect(find.text('SLIIT Malabe Campus'), findsOneWidget);
  });

  testWidgets('Selecting lots opens BookSlotScreen safely without exceptions',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ParkingStateManager(),
        child: const SmartParkingApp(),
      ),
    );

    await tester.pumpAndSettle();

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
