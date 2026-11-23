import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/glass_card.dart';
import '../core/widgets/active_booking_mini_banner.dart';
import '../data/models/booking_model.dart';
import '../data/models/parking_lot_model.dart';
import '../data/services/parking_state_manager.dart';
import 'home_map/home_map_screen.dart';
import 'profile/profile_screen.dart';
import 'reoptimization_booking/bookings_list_screen.dart';

class NavigationShell extends StatefulWidget {
  final ValueChanged<ParkingLot> onSelectLot;
  final ValueChanged<Booking>? onOpenActiveBooking;
  final VoidCallback onLogout;

  const NavigationShell({
    super.key,
    required this.onSelectLot,
    this.onOpenActiveBooking,
    required this.onLogout,
  });

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.watch<ParkingStateManager>();
    final active = state.currentActiveBooking;
    ParkingLot? activeLot;
    if (active != null) {
      try {
        activeLot = state.lots.firstWhere((l) => l.id == active.lotId);
      } catch (_) {
        activeLot = state.lots.isNotEmpty ? state.lots.first : null;
      }
    }

    // List screens keep a readable width on tablets; the map stays full screen
    Widget readable(Widget child) => ColoredBox(
          color: c.background,
          child: Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: child),
          ),
        );

    final screens = [
      HomeMapScreen(onSelectLot: widget.onSelectLot),
      readable(BookingsListScreen(onOpenActiveBooking: widget.onOpenActiveBooking)),
      readable(const _AlertsPlaceholderView()),
      readable(ProfileScreen(onLogout: widget.onLogout)),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.surface, c.background],
          ),
          border: Border(top: BorderSide(color: c.accent.withValues(alpha: 0.25), width: 1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active != null)
              ActiveBookingMiniBanner(
                booking: active,
                lot: activeLot,
                onTap: () {
                  widget.onOpenActiveBooking?.call(active);
                },
              ),
            NavigationBar(
              selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() => _currentIndex = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.location_on_outlined),
              selectedIcon: Icon(Icons.location_on_rounded),
              label: 'Explore',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_today_outlined),
              selectedIcon: Icon(Icons.calendar_today_rounded),
              label: 'Bookings',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_none_rounded),
              selectedIcon: Icon(Icons.notifications_rounded),
              label: 'Alerts',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
          ],
        ),
      ),
    );
  }
}

class _AlertsPlaceholderView extends StatelessWidget {
  const _AlertsPlaceholderView();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = context.watch<ParkingStateManager>();
    final active = state.currentActiveBooking;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text('Alerts', style: AppText.h2.copyWith(color: c.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          if (active != null)
            Container(
              padding: const EdgeInsets.all(AppSpace.md),
              margin: const EdgeInsets.only(bottom: AppSpace.sm),
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: c.accent, width: 1.2),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: c.accent),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Active Booking ${active.slotId}',
                          style: AppText.title.copyWith(color: c.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Arrive by 10:30 AM at ${active.lotName}',
                          style: AppText.caption.copyWith(color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: glassDecoration(c),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: c.textSecondary),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome to Smart Parking',
                        style: AppText.title.copyWith(color: c.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Dynamic slot re-optimization is active for your account.',
                        style: AppText.caption.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
