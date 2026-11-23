// hold_countdown_test.dart
// Unit tests for Live Hold-Time Countdown & Auto-Release feature (SYS-01 / SYS-08)

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parking/core/theme/app_theme.dart';
import 'package:smart_parking/data/models/booking_model.dart';
import 'package:smart_parking/data/models/parking_event_model.dart';
import 'package:smart_parking/data/services/parking_state_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Live Hold-Time & Auto-Release Lifecycle (Option 1)', () {
    test('Booking calculates effectiveHoldDeadline and remainingHoldDuration correctly', () {
      final now = DateTime.now();
      final expiry = now.add(const Duration(minutes: 15));

      final booking = Booking(
        id: 'BK-TEST-1',
        userId: 'user-001',
        vehicleId: 'veh-001',
        vehiclePlate: 'CAB-4821',
        lotId: 'lot-01',
        lotName: 'Main Building Lot',
        slotId: 'A1',
        bookedAt: now,
        arrivalTime: now,
        durationHours: 2,
        status: BookingStatus.reserved,
        estimatedFee: 200,
        qrToken: 'QR-TEST-1',
        holdExpiresAt: expiry,
      );

      expect(booking.effectiveHoldDeadline, equals(expiry));
      expect(booking.remainingHoldDuration.inMinutes, inInclusiveRange(14, 15));
      expect(booking.isHoldExpired, isFalse);
    });

    test('Booking detects expired hold window when holdExpiresAt has passed', () {
      final now = DateTime.now();
      final expiredTime = now.subtract(const Duration(minutes: 1));

      final booking = Booking(
        id: 'BK-TEST-2',
        userId: 'user-001',
        vehicleId: 'veh-001',
        vehiclePlate: 'CAB-4821',
        lotId: 'lot-01',
        lotName: 'Main Building Lot',
        slotId: 'A2',
        bookedAt: now.subtract(const Duration(minutes: 16)),
        arrivalTime: now.subtract(const Duration(minutes: 16)),
        durationHours: 2,
        status: BookingStatus.reserved,
        estimatedFee: 200,
        qrToken: 'QR-TEST-2',
        holdExpiresAt: expiredTime,
      );

      expect(booking.remainingHoldDuration, equals(Duration.zero));
      expect(booking.isHoldExpired, isTrue);
    });

    test('reserveSlot initializes 15-minute hold window and sets slot state to taken', () {
      final manager = ParkingStateManager();
      final lot = manager.lots.first;
      final slot = lot.slots.firstWhere((s) => s.state == SlotState.free);
      final initialFreeSlots = lot.freeSlots;

      final booking = manager.reserveSlot(
        lot: lot,
        slot: slot,
        arrivalTime: DateTime.now().add(const Duration(minutes: 5)),
        durationHours: 1,
      );

      expect(booking.holdExpiresAt, isNotNull);
      expect(booking.status, equals(BookingStatus.reserved));
      expect(manager.currentActiveBooking?.id, equals(booking.id));

      final updatedLot = manager.lots.firstWhere((l) => l.id == lot.id);
      expect(updatedLot.freeSlots, equals(initialFreeSlots - 1));

      manager.dispose();
    });

    test('fastForwardHoldTimer accelerates hold countdown for quick evaluation', () {
      final manager = ParkingStateManager();
      final lot = manager.lots.first;
      final slot = lot.slots.firstWhere((s) => s.state == SlotState.free);

      manager.reserveSlot(
        lot: lot,
        slot: slot,
        arrivalTime: DateTime.now(),
        durationHours: 1,
      );

      // Accelerate to 10 seconds
      manager.fastForwardHoldTimer(remaining: const Duration(seconds: 10));

      final active = manager.currentActiveBooking;
      expect(active, isNotNull);
      expect(active!.remainingHoldDuration.inSeconds, inInclusiveRange(8, 11));

      manager.dispose();
    });

    test('extendHoldDuration adds grace period and records extension audit event', () {
      final manager = ParkingStateManager();
      final lot = manager.lots.first;
      final slot = lot.slots.firstWhere((s) => s.state == SlotState.free);

      manager.reserveSlot(
        lot: lot,
        slot: slot,
        arrivalTime: DateTime.now(),
        durationHours: 1,
      );

      final initialDeadline = manager.currentActiveBooking!.effectiveHoldDeadline;
      manager.extendHoldDuration(extension: const Duration(minutes: 5));

      final active = manager.currentActiveBooking;
      expect(active!.effectiveHoldDeadline.difference(initialDeadline).inMinutes, equals(5));
      expect(active.status, equals(BookingStatus.extended));

      // Verify audit log
      expect(manager.events.first.type, equals(ParkingEventType.extended));

      manager.dispose();
    });

    test('checkAndAutoReleaseExpiredBookings triggers auto-cancellation and frees slot', () {
      final manager = ParkingStateManager();
      final lot = manager.lots.first;
      final slot = lot.slots.firstWhere((s) => s.state == SlotState.free);
      final initialFreeSlots = lot.freeSlots;

      final booking = manager.reserveSlot(
        lot: lot,
        slot: slot,
        arrivalTime: DateTime.now(),
        durationHours: 1,
      );

      // Force past expiry
      manager.fastForwardHoldTimer(remaining: const Duration(seconds: -1));

      // Check auto-release
      manager.checkAndAutoReleaseExpiredBookings();

      expect(manager.currentActiveBooking, isNull);

      final cancelledBooking = manager.allBookings.firstWhere((b) => b.id == booking.id);
      expect(cancelledBooking.status, equals(BookingStatus.autoCancelled));

      // Verify slot is returned to free
      final updatedLot = manager.lots.firstWhere((l) => l.id == lot.id);
      expect(updatedLot.freeSlots, equals(initialFreeSlots));

      // Verify audit event
      expect(manager.events.first.type, equals(ParkingEventType.autoCancelled));

      manager.dispose();
    });

    test('checkIn stops hold window, locks reservation, and marks status checkedIn', () {
      final manager = ParkingStateManager();
      final lot = manager.lots.first;
      final slot = lot.slots.firstWhere((s) => s.state == SlotState.free);

      manager.reserveSlot(
        lot: lot,
        slot: slot,
        arrivalTime: DateTime.now(),
        durationHours: 1,
      );

      manager.checkIn();

      expect(manager.currentActiveBooking?.status, equals(BookingStatus.checkedIn));
      expect(manager.currentActiveBooking?.checkedInAt, isNotNull);

      // Verify audit event
      expect(manager.events.first.type, equals(ParkingEventType.checkedIn));

      manager.dispose();
    });
  });
}
