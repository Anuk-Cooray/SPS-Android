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

    // Verify app renders explore or login screen
    expect(find.text('SLIIT Malabe Campus'), findsOneWidget);
  });
}
