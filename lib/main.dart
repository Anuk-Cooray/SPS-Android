import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'data/models/booking_model.dart';
import 'data/models/parking_lot_model.dart';
import 'data/models/parking_slot_model.dart';
import 'data/models/vehicle_model.dart';
import 'data/services/parking_state_manager.dart';
import 'features/admin/admin_dashboard_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/vehicle_onboarding_screen.dart';
import 'features/barrier_checkin/check_in_screen.dart';
import 'features/barrier_checkin/parked_screen.dart';
import 'features/billing/pay_and_exit_screen.dart';
import 'features/navigation_shell.dart';
import 'features/reoptimization/book_slot_screen.dart';
import 'features/reoptimization/late_arrival_screen.dart';
import 'features/reoptimization/navigation_screen.dart';
import 'features/reoptimization/upgrade_offer_screen.dart';

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
  void _openLotBooking(BuildContext context, ParkingLot lot) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => BookSlotScreen(
          lot: lot,
          onBookingConfirmed: (booking) {
            Navigator.pop(ctx);
            _openNavigation(context, booking);
          },
        ),
      ),
    );
  }

  void _openNavigation(BuildContext context, Booking booking) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => NavigationScreen(
          booking: booking,
          onCancelBooking: () {
            context.read<ParkingStateManager>().cancelBooking();
            Navigator.pop(ctx);
          },
          onShowQr: () {
            _openCheckIn(context, booking);
          },
          onTriggerUpgradeOffer: () {
            final state = context.read<ParkingStateManager>();
            state.triggerUpgradeOfferCheck();
            final candidate = state.upgradeCandidateSlot ??
                const ParkingSlot(
                  id: 'B-01',
                  lotId: 'lot-main',
                  row: 'B',
                  number: 1,
                  state: SlotState.free,
                  size: VehicleSize.medium,
                  walkingDistanceMeters: 40,
                );

            UpgradeOfferModal.show(
              context: ctx,
              booking: booking,
              newSlot: candidate,
              evaluationResult: state.lastUpgradeEvaluation,
              onAccept: () {
                state.acceptUpgrade();
                Navigator.pop(ctx);
              },
              onDecline: () {
                state.declineUpgrade();
                Navigator.pop(ctx);
              },
            );
          },
          onTriggerLateArrival: () {
            LateArrivalModal.show(
              context: ctx,
              booking: booking,
              onExtend: () {
                context.read<ParkingStateManager>().extendBooking();
                Navigator.pop(ctx);
              },
              onRelease: () {
                context.read<ParkingStateManager>().cancelBooking(autoCancelled: true);
                Navigator.pop(ctx); // close modal
                Navigator.pop(ctx); // back to home
              },
            );
          },
        ),
      ),
    );
  }

  void _openCheckIn(BuildContext context, Booking booking) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => CheckInScreen(
          booking: booking,
          onParkedConfirmed: () {
            context.read<ParkingStateManager>().checkIn();
            Navigator.pop(ctx); // close check in
            _openParked(context, booking);
          },
        ),
      ),
    );
  }

  void _openParked(BuildContext context, Booking booking) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ParkedScreen(
          booking: booking,
          onExitParking: () {
            _openPayAndExit(context, booking);
          },
        ),
      ),
    );
  }

  void _openPayAndExit(BuildContext context, Booking booking) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => PayAndExitScreen(
          booking: booking,
          onPaymentCompleted: (amount) {
            context.read<ParkingStateManager>().completePayment(amount);
            Navigator.pop(ctx); // pop pay
            Navigator.pop(ctx); // pop parked
            Navigator.pop(ctx); // pop nav
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Parking',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routes: {
        '/admin': (_) => const AdminDashboardScreen(),
      },
      home: Consumer<ParkingStateManager>(
        builder: (context, state, _) {
          if (!state.isInitialized) {
            return const Scaffold(
              body: SizedBox.shrink(),
            );
          }

          if (!state.isLoggedIn) {
            return LoginScreen(
              onLoginSuccess: () {},
            );
          }

          if (!state.hasRegisteredVehicle) {
            return VehicleOnboardingScreen(
              onOnboardingComplete: () {},
            );
          }

          return Builder(
            builder: (ctx) => NavigationShell(
              onSelectLot: (lot) => _openLotBooking(ctx, lot),
              onOpenActiveBooking: (booking) {
                if (booking.status == BookingStatus.checkedIn) {
                  _openParked(ctx, booking);
                } else {
                  _openNavigation(ctx, booking);
                }
              },
              onLogout: () {
                state.logout();
              },
            ),
          );
        },
      ),
    );
  }
}
