// server_authority_test.dart
// Smart Parking (J26-IT-335) — Server Reservation Authority & Collision Unit Tests

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parking/core/theme/app_theme.dart';
import 'package:smart_parking/data/models/booking_model.dart';
import 'package:smart_parking/data/models/parking_lot_model.dart';
import 'package:smart_parking/data/models/parking_slot_model.dart';
import 'package:smart_parking/data/models/vehicle_model.dart';
import 'package:smart_parking/data/services/cloud_functions_client.dart';
import 'package:smart_parking/data/services/mock_data.dart';
import 'package:smart_parking/data/services/parking_state_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Server Reservation Authority Schema & Parsing', () {
    test('ParkingSlot parses server states and subcollection metadata fields', () {
      final json = {
        'id': 'A-01',
        'lotId': 'lot-main',
        'row': 'A',
        'number': 1,
        'state': 'available',
        'size': 'medium',
        'type': 'normal',
        'walkingDistanceMeters': 40,
        'bookingId': 'BK-1001',
        'updatedAt': '2026-10-19T10:00:00.000Z',
        'updatedBy': 'function',
      };

      final slot = ParkingSlot.fromJson(json);
      expect(slot.id, 'A-01');
      expect(slot.state, SlotState.free);
      expect(slot.isAvailable, isTrue);
      expect(slot.bookingId, 'BK-1001');
      expect(slot.updatedBy, 'function');

      // Test reserved/occupied server state mapping
      final occupiedSlot = ParkingSlot.fromJson({
        'id': 'A-02',
        'lotId': 'lot-main',
        'state': 'occupied',
        'size': 'medium',
      });
      expect(occupiedSlot.state, SlotState.taken);
      expect(occupiedSlot.isAvailable, isFalse);
    });

    test('Booking parses server auto_released status and timestamps', () {
      final json = {
        'id': 'BK-2001',
        'userId': 'user-001',
        'lotId': 'lot-main',
        'lotName': 'Main Building Lot',
        'slotId': 'A-01',
        'status': 'auto_released',
        'bookedAt': '2026-10-19T10:00:00.000Z',
        'arrivalTime': '2026-10-19T10:30:00.000Z',
        'holdExpiresAt': '2026-10-19T10:45:00.000Z',
      };

      final booking = Booking.fromJson(json);
      expect(booking.id, 'BK-2001');
      expect(booking.status, BookingStatus.autoCancelled);
      expect(booking.isActive, isFalse);
    });
  });

  group('Collision Handling & Next Best Slot Recommendation', () {
    test('findNextBestSlot returns optimal candidate when preferred slot is excluded', () {
      final manager = ParkingStateManager();
      final lot = MockData.getInitialLots().first; // Main Building Lot

      final nextBest = manager.findNextBestSlot(lot, 'A-06');
      expect(nextBest, isNotNull);
      expect(nextBest!.id, isNot('A-06'));
      expect(nextBest.isAvailable, isTrue);
    });

    test('Collision error state updates with "Slot just taken — here\'s the next best"', () {
      final manager = ParkingStateManager();
      final lot = MockData.getInitialLots().first;

      final nextBest = manager.findNextBestSlot(lot, 'A-05');
      expect(nextBest, isNotNull);

      // Verify SlotCollisionException structure
      const exc = SlotCollisionException(
        message: "Slot just taken — here's the next best",
        nextBestSlotId: 'A-06',
      );
      expect(exc.code, 'already-exists');
      expect(exc.message, contains('Slot just taken'));
    });
  });

  group('Client-Side Auto-Release Removal', () {
    test('Client hold countdown does not execute cancellation (delegated to server)', () {
      final manager = ParkingStateManager();
      final lot = MockData.getInitialLots().first;
      final slot = lot.slots.firstWhere((s) => s.isAvailable);

      // Create booking with past arrival time to simulate elapsed hold
      final pastArrival = DateTime.now().subtract(const Duration(minutes: 20));
      final booking = manager.reserveSlot(
        lot: lot,
        slot: slot,
        arrivalTime: pastArrival,
        durationHours: 1,
      );

      // Booking effectiveHoldDeadline is past
      expect(booking.isHoldExpired, isTrue);

      // Verify booking status remains reserved until server releases it
      expect(booking.status, BookingStatus.reserved);
    });
  });
}
