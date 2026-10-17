import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'data/models/booking_model.dart';
import 'data/models/parking_lot_model.dart';
import 'data/services/parking_state_manager.dart';
import 'features/auth/login_screen.dart';
import 'features/navigation_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ParkingStateManager(),
      child: const SmartParkingApp(),
    ),
  );
}

class SmartParkingApp extends StatefulWidget {
  const SmartParkingApp({super.key});

  @override
  State<SmartParkingApp> createState() => _SmartParkingAppState();
}

class _SmartParkingAppState extends State<SmartParkingApp> {
  bool _isLoggedIn = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Parking',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: _isLoggedIn
          ? NavigationShell(
              onSelectLot: (ParkingLot lot) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Selected lot: ${lot.name}'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              onOpenActiveBooking: (Booking booking) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Active booking: ${booking.slotId}'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              onLogout: () {
                setState(() => _isLoggedIn = false);
              },
            )
          : LoginScreen(
              onLoginSuccess: () {
                setState(() => _isLoggedIn = true);
              },
            ),
    );
  }
}
