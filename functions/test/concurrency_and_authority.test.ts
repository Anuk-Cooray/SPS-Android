// concurrency_and_authority.test.ts
// Smart Parking (J26-IT-335) — Concurrency & Server Authority Acceptance Test Suite

import { expect } from 'chai';
import * as admin from 'firebase-admin';
import {
  createBookingLogic,
  cancelBookingLogic,
  checkInLogic,
  extendHoldLogic,
  acceptUpgradeLogic,
} from '../src/bookings';
import { autoReleaseExpiredHoldsLogic } from '../src/auto_release';
import { ParkingLotDocument, ParkingSlotDocument, BookingDocument } from '../src/types';

describe('Server Reservation Authority & Concurrency Tests', () => {
  let db: admin.firestore.Firestore;

  before(async () => {
    // Ensure emulator host is set for local testing
    process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
    if (admin.apps.length === 0) {
      admin.initializeApp({ projectId: 'demo-sps-concurrency' });
    }
    db = admin.firestore();
  });

  beforeEach(async () => {
    // Clear collections for clean test state
    const lots = await db.collection('parking_lots').get();
    for (const doc of lots.docs) {
      const slots = await doc.ref.collection('slots').get();
      for (const s of slots.docs) {
        await s.ref.delete();
      }
      await doc.ref.delete();
    }

    const bookings = await db.collection('bookings').get();
    for (const doc of bookings.docs) {
      await doc.ref.delete();
    }

    const events = await db.collection('parking_events').get();
    for (const doc of events.docs) {
      await doc.ref.delete();
    }
  });

  async function seedTestLotAndSlots(
    lotId: string = 'lot-test',
    totalSlots: number = 3,
    freeSlots: number = 3
  ) {
    const lotRef = db.collection('parking_lots').doc(lotId);
    const lotData: ParkingLotDocument = {
      id: lotId,
      name: 'Test Facility',
      latitude: 6.9147,
      longitude: 79.9729,
      hourlyRate: 100,
      totalSlots,
      freeSlots,
    };
    await lotRef.set(lotData);

    const slotConfigs: ParkingSlotDocument[] = [
      {
        id: 'A-01',
        lotId,
        row: 'A',
        number: 1,
        size: 'medium',
        type: 'normal',
        walkingDistanceMeters: 40,
        state: 'available',
        bookingId: null,
        updatedAt: new Date().toISOString(),
        updatedBy: 'system',
      },
      {
        id: 'A-02',
        lotId,
        row: 'A',
        number: 2,
        size: 'medium',
        type: 'normal',
        walkingDistanceMeters: 120,
        state: 'available',
        bookingId: null,
        updatedAt: new Date().toISOString(),
        updatedBy: 'system',
      },
      {
        id: 'A-03',
        lotId,
        row: 'A',
        number: 3,
        size: 'large',
        type: 'normal',
        walkingDistanceMeters: 180,
        state: 'available',
        bookingId: null,
        updatedAt: new Date().toISOString(),
        updatedBy: 'system',
      },
    ];

    for (const sc of slotConfigs) {
      await lotRef.collection('slots').doc(sc.id).set(sc);
    }
  }

  describe('Acceptance Criterion 1: Concurrency Race Resolution', () => {
    it('two simulated clients booking the same slot concurrently -> exactly one succeeds', async () => {
      await seedTestLotAndSlots('lot-test', 3, 3);

      const client1Payload = {
        lotId: 'lot-test',
        slotId: 'A-01',
        vehiclePlate: 'CAB-1001',
        vehicleSize: 'medium' as const,
        arrivalTime: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
        durationHours: 2,
      };

      const client2Payload = {
        lotId: 'lot-test',
        slotId: 'A-01',
        vehiclePlate: 'CAB-2002',
        vehicleSize: 'medium' as const,
        arrivalTime: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
        durationHours: 2,
      };

      // Execute concurrent requests to the exact same slot
      const [res1, res2] = await Promise.allSettled([
        createBookingLogic(db, 'driver-alice', client1Payload),
        createBookingLogic(db, 'driver-bob', client2Payload),
      ]);

      const fulfilled = [res1, res2].filter((r) => r.status === 'fulfilled');
      const rejected = [res1, res2].filter((r) => r.status === 'rejected');

      // Exactly ONE must succeed and ONE must fail
      expect(fulfilled.length).to.equal(1, 'Exactly one concurrent booking must succeed');
      expect(rejected.length).to.equal(1, 'Exactly one concurrent booking must fail');

      const winningBooking = (fulfilled[0] as PromiseFulfilledResult<BookingDocument>).value;
      const error = (rejected[0] as PromiseRejectedResult).reason;

      expect(error.message).to.include('Slot just taken');

      // Verify database state integrity
      const slotSnap = await db
        .collection('parking_lots')
        .doc('lot-test')
        .collection('slots')
        .doc('A-01')
        .get();
      const slot = slotSnap.data() as ParkingSlotDocument;

      expect(slot.state).to.equal('reserved');
      expect(slot.bookingId).to.equal(winningBooking.id);

      const lotSnap = await db.collection('parking_lots').doc('lot-test').get();
      const lot = lotSnap.data() as ParkingLotDocument;
      expect(lot.freeSlots).to.equal(2, 'freeSlots must decrement by exactly 1');
    });
  });

  describe('Acceptance Criterion 2: Server-Side Autonomous Auto-Release', () => {
    it('auto-release fires with the app killed and resets slot to available', async () => {
      await seedTestLotAndSlots('lot-test', 3, 3);

      // Create a booking whose 15m hold has expired
      const pastHoldTime = new Date(Date.now() - 5 * 60 * 1000); // 5 mins ago
      const booking = await createBookingLogic(db, 'driver-late', {
        lotId: 'lot-test',
        slotId: 'A-01',
        vehiclePlate: 'LATE-999',
        vehicleSize: 'medium',
        arrivalTime: new Date(Date.now() - 20 * 60 * 1000).toISOString(),
        durationHours: 1,
      });

      // Manually set holdExpiresAt to past time to simulate hold expiry
      await db.collection('bookings').doc(booking.id).update({
        holdExpiresAt: pastHoldTime.toISOString(),
      });

      // Confirm initial slot state is reserved
      let slotDoc = await db
        .collection('parking_lots')
        .doc('lot-test')
        .collection('slots')
        .doc('A-01')
        .get();
      expect(slotDoc.data()?.state).to.equal('reserved');

      // App is killed -> Server autonomous sweeper triggers
      const sweepResult = await autoReleaseExpiredHoldsLogic(db, new Date());

      expect(sweepResult.releasedCount).to.equal(1);
      expect(sweepResult.releasedBookingIds).to.include(booking.id);

      // Verify slot was released to available
      slotDoc = await db
        .collection('parking_lots')
        .doc('lot-test')
        .collection('slots')
        .doc('A-01')
        .get();
      expect(slotDoc.data()?.state).to.equal('available');
      expect(slotDoc.data()?.bookingId).to.be.null;

      // Verify lot counter restored
      const lotDoc = await db.collection('parking_lots').doc('lot-test').get();
      expect(lotDoc.data()?.freeSlots).to.equal(3);

      // Verify booking status is auto_released
      const bookingDoc = await db.collection('bookings').doc(booking.id).get();
      expect(bookingDoc.data()?.status).to.equal('auto_released');

      // Verify idempotency: second sweep releases 0
      const secondSweep = await autoReleaseExpiredHoldsLogic(db, new Date());
      expect(secondSweep.releasedCount).to.equal(0);
    });
  });

  describe('Atomic In-Transit Dynamic Upgrade', () => {
    it('atomically swaps old slot to available and claims superior candidate slot', async () => {
      await seedTestLotAndSlots('lot-test', 3, 3);

      // Reserve slot A-02 (120m away)
      const booking = await createBookingLogic(db, 'driver-upgrade', {
        lotId: 'lot-test',
        slotId: 'A-02',
        vehiclePlate: 'CAB-4821',
        vehicleSize: 'medium',
        arrivalTime: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
        durationHours: 2,
      });

      // Candidate slot A-01 is 40m away (saves 80m > 50m threshold)
      const upgradeRes = await acceptUpgradeLogic(db, 'driver-upgrade', {
        bookingId: booking.id,
        newSlotId: 'A-01',
        currentEtaMinutes: 5,
      });

      expect(upgradeRes.success).to.be.true;
      expect(upgradeRes.newSlotId).to.equal('A-01');
      expect(upgradeRes.distanceSavedMeters).to.equal(80);
      expect(upgradeRes.qrToken).to.include('SPS.v1.');

      // Check slot A-02 is released
      const oldSlotDoc = await db
        .collection('parking_lots')
        .doc('lot-test')
        .collection('slots')
        .doc('A-02')
        .get();
      expect(oldSlotDoc.data()?.state).to.equal('available');
      expect(oldSlotDoc.data()?.bookingId).to.be.null;

      // Check slot A-01 is reserved
      const newSlotDoc = await db
        .collection('parking_lots')
        .doc('lot-test')
        .collection('slots')
        .doc('A-01')
        .get();
      expect(newSlotDoc.data()?.state).to.equal('reserved');
      expect(newSlotDoc.data()?.bookingId).to.equal(booking.id);

      // Check booking updated
      const updatedBookingDoc = await db.collection('bookings').doc(booking.id).get();
      const updatedBooking = updatedBookingDoc.data() as BookingDocument;
      expect(updatedBooking.status).to.equal('upgraded');
      expect(updatedBooking.slotId).to.equal('A-01');
      expect(updatedBooking.originalSlotId).to.equal('A-02');
    });

    it('rejects upgrade when proposed candidate slot is already taken', async () => {
      await seedTestLotAndSlots('lot-test', 3, 3);

      const booking = await createBookingLogic(db, 'driver-upgrade-fail', {
        lotId: 'lot-test',
        slotId: 'A-02',
        vehiclePlate: 'CAB-4821',
        vehicleSize: 'medium',
        arrivalTime: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
        durationHours: 2,
      });

      // Mark A-01 as occupied by another vehicle
      await db
        .collection('parking_lots')
        .doc('lot-test')
        .collection('slots')
        .doc('A-01')
        .update({ state: 'occupied', bookingId: 'BK-OTHER' });

      try {
        await acceptUpgradeLogic(db, 'driver-upgrade-fail', {
          bookingId: booking.id,
          newSlotId: 'A-01',
          currentEtaMinutes: 5,
        });
        expect.fail('Should have thrown already-exists error');
      } catch (err: any) {
        expect(err.message).to.include('no longer available');
      }

      // Verify original slot is still reserved by original driver
      const oldSlotDoc = await db
        .collection('parking_lots')
        .doc('lot-test')
        .collection('slots')
        .doc('A-02')
        .get();
      expect(oldSlotDoc.data()?.state).to.equal('reserved');
      expect(oldSlotDoc.data()?.bookingId).to.equal(booking.id);
    });
  });

  describe('Hold Extension & Barrier Check-In Lifecycle', () => {
    it('extends hold window (+15 min) up to maximum 2 times and charges fee', async () => {
      await seedTestLotAndSlots('lot-test', 3, 3);

      const booking = await createBookingLogic(db, 'driver-ext', {
        lotId: 'lot-test',
        slotId: 'A-01',
        vehiclePlate: 'CAB-4821',
        vehicleSize: 'medium',
        arrivalTime: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
        durationHours: 1,
      });

      // Extension 1
      const ext1 = await extendHoldLogic(db, 'driver-ext', {
        bookingId: booking.id,
        minutes: 15,
      });
      expect(ext1.extensionsCount).to.equal(1);
      expect(ext1.extensionFee).to.equal(50);

      // Extension 2
      const ext2 = await extendHoldLogic(db, 'driver-ext', {
        bookingId: booking.id,
        minutes: 15,
      });
      expect(ext2.extensionsCount).to.equal(2);
      expect(ext2.extensionFee).to.equal(100);

      // Extension 3 -> Rejection
      try {
        await extendHoldLogic(db, 'driver-ext', {
          bookingId: booking.id,
          minutes: 15,
        });
        expect.fail('Should have thrown maximum extensions reached');
      } catch (err: any) {
        expect(err.message).to.include('Maximum of 2 hold extensions reached');
      }
    });

    it('processes barrier QR check-in and updates slot state to occupied', async () => {
      await seedTestLotAndSlots('lot-test', 3, 3);

      const booking = await createBookingLogic(db, 'driver-qr', {
        lotId: 'lot-test',
        slotId: 'A-01',
        vehiclePlate: 'CAB-4821',
        vehicleSize: 'medium',
        arrivalTime: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
        durationHours: 1,
      });

      const checkInRes = await checkInLogic(db, 'cctv-gate', {
        bookingId: booking.id,
        qrToken: booking.qrToken,
      });
      expect(checkInRes.success).to.be.true;

      const slotDoc = await db
        .collection('parking_lots')
        .doc('lot-test')
        .collection('slots')
        .doc('A-01')
        .get();
      expect(slotDoc.data()?.state).to.equal('occupied');

      const bookingDoc = await db.collection('bookings').doc(booking.id).get();
      expect(bookingDoc.data()?.status).to.equal('checkedIn');
    });

    it('cancels booking and releases slot back to available', async () => {
      await seedTestLotAndSlots('lot-test', 3, 3);

      const booking = await createBookingLogic(db, 'driver-cancel', {
        lotId: 'lot-test',
        slotId: 'A-01',
        vehiclePlate: 'CAB-4821',
        vehicleSize: 'medium',
        arrivalTime: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
        durationHours: 1,
      });

      const cancelRes = await cancelBookingLogic(db, 'driver-cancel', {
        bookingId: booking.id,
      });
      expect(cancelRes.success).to.be.true;

      const slotDoc = await db
        .collection('parking_lots')
        .doc('lot-test')
        .collection('slots')
        .doc('A-01')
        .get();
      expect(slotDoc.data()?.state).to.equal('available');
      expect(slotDoc.data()?.bookingId).to.be.null;

      const lotDoc = await db.collection('parking_lots').doc('lot-test').get();
      expect(lotDoc.data()?.freeSlots).to.equal(3);
    });
  });
});
