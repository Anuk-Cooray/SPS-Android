// integration_contracts.test.ts
// Smart Parking (J26-IT-335) — Subsystem Integration Contracts Test Suite
// Rigorous verification for CCTV Occupancy, IoT Barrier Gate, and Smart Payment contracts

import { expect } from 'chai';
import * as admin from 'firebase-admin';
import { generateSignedQrToken, verifySignedQrToken } from '../src/hmac_token';
import { hashApiKey, authenticateDevice } from '../src/devices';
import { ingestOccupancyLogic } from '../src/cctv';
import { validateQrLogic } from '../src/barrier';
import { paymentCompletedLogic } from '../src/payment';
import { ParkingLotDocument, ParkingSlotDocument, BookingDocument, DeviceDocument } from '../src/types';

describe('Subsystem Integration Contracts Acceptance Tests', () => {
  let db: admin.firestore.Firestore;

  before(async () => {
    process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
    if (admin.apps.length === 0) {
      admin.initializeApp({ projectId: 'demo-sps-integration' });
    }
    db = admin.firestore();
  });

  beforeEach(async () => {
    // Clear test collections
    const collections = ['parking_lots', 'bookings', 'devices', 'admin_alerts', 'processed_payments', 'parking_events'];
    for (const col of collections) {
      const snap = await db.collection(col).get();
      for (const doc of snap.docs) {
        if (col === 'parking_lots') {
          const slots = await doc.ref.collection('slots').get();
          for (const s of slots.docs) {
            await s.ref.delete();
          }
        }
        await doc.ref.delete();
      }
    }

    // Seed test lot
    await db.collection('parking_lots').doc('lot-colombo-01').set({
      id: 'lot-colombo-01',
      name: 'Colombo Central Hub',
      totalSlots: 5,
      freeSlots: 5,
      hourlyRate: 150,
      latitude: 6.9271,
      longitude: 79.8612,
      updatedAt: new Date().toISOString(),
    });

    // Seed slots
    const slots: ParkingSlotDocument[] = [
      {
        id: 'A-01',
        lotId: 'lot-colombo-01',
        row: 'A',
        number: 1,
        size: 'medium',
        type: 'normal',
        walkingDistanceMeters: 40,
        state: 'available',
        bookingId: null,
        conflictFlag: false,
        updatedAt: new Date().toISOString(),
        updatedBy: 'system',
      },
      {
        id: 'A-02',
        lotId: 'lot-colombo-01',
        row: 'A',
        number: 2,
        size: 'medium',
        type: 'normal',
        walkingDistanceMeters: 60,
        state: 'available',
        bookingId: null,
        conflictFlag: false,
        updatedAt: new Date().toISOString(),
        updatedBy: 'system',
      },
      {
        id: 'A-03',
        lotId: 'lot-colombo-01',
        row: 'A',
        number: 3,
        size: 'large',
        type: 'normal',
        walkingDistanceMeters: 80,
        state: 'available',
        bookingId: null,
        conflictFlag: false,
        updatedAt: new Date().toISOString(),
        updatedBy: 'system',
      },
    ];

    for (const slot of slots) {
      await db.collection('parking_lots').doc('lot-colombo-01').collection('slots').doc(slot.id).set(slot);
    }
  });

  describe('1. Device Authentication & Cryptographic HMAC Verification', () => {
    it('authenticates registered devices and rejects invalid or missing API keys', async () => {
      // Seed a device
      const rawKey = 'cctv-secret-cam-99';
      const keyHash = hashApiKey(rawKey);
      await db.collection('devices').doc('cam-99').set({
        id: 'cam-99',
        type: 'camera',
        name: 'Bay Camera 99',
        lotId: 'lot-colombo-01',
        slotId: null,
        apiKeyHash: keyHash,
        isActive: true,
      } as DeviceDocument);

      // Successful auth
      const authSuccess = await authenticateDevice(db, rawKey, 'camera');
      expect(authSuccess).to.not.be.null;
      expect(authSuccess?.id).to.equal('cam-99');

      // Failed auth with wrong key
      const authBadKey = await authenticateDevice(db, 'wrong-key-value', 'camera');
      expect(authBadKey).to.be.null;

      // Failed auth with wrong device type
      const authWrongType = await authenticateDevice(db, rawKey, 'barrier');
      expect(authWrongType).to.be.null;
    });

    it('generates and verifies signed HMAC QR tokens with time-window validation', () => {
      const now = new Date();
      const arrival = new Date(now.getTime() + 10 * 60 * 1000);
      const holdExpires = new Date(now.getTime() + 25 * 60 * 1000);

      const token = generateSignedQrToken({
        bookingId: 'BK-TEST-001',
        slotId: 'A-01',
        arrivalTime: arrival,
        holdExpiresAt: holdExpires,
      });

      expect(token).to.match(/^SPS\.v1\.BK-TEST-001\.A-01\.\d+\.\d+\.[a-f0-9]+\.[a-f0-9]{64}$/);

      // Valid token check
      const verification = verifySignedQrToken(token);
      expect(verification.valid).to.be.true;
      expect(verification.payload?.bookingId).to.equal('BK-TEST-001');
      expect(verification.payload?.slotId).to.equal('A-01');

      // Tampered token check (altering slot ID)
      const tamperedToken = token.replace('A-01', 'A-02');
      const tamperedVerification = verifySignedQrToken(tamperedToken);
      expect(tamperedVerification.valid).to.be.false;
      expect(tamperedVerification.reason).to.include('signature mismatch');

      // Expired token check
      const pastToken = generateSignedQrToken({
        bookingId: 'BK-EXPIRED',
        slotId: 'A-01',
        arrivalTime: new Date(now.getTime() - 60 * 60 * 1000),
        holdExpiresAt: new Date(now.getTime() - 30 * 60 * 1000),
      });
      const expiredVerification = verifySignedQrToken(pastToken);
      expect(expiredVerification.valid).to.be.false;
      expect(expiredVerification.reason).to.include('outside valid window');
    });
  });

  describe('2. CCTV Vision Occupancy Integration Contract', () => {
    it('rejects low confidence detections and stale timestamps', async () => {
      // Low confidence (< 0.70)
      try {
        await ingestOccupancyLogic(db, 'cam-01', {
          lotId: 'lot-colombo-01',
          slotId: 'A-01',
          occupied: true,
          confidence: 0.65,
          timestamp: new Date().toISOString(),
        });
        expect.fail('Should have thrown LOW_CONFIDENCE error');
      } catch (err: any) {
        expect(err.message).to.include('LOW_CONFIDENCE');
      }

      // Establish initial timestamp
      const t0 = new Date('2026-10-19T10:00:00Z');
      await ingestOccupancyLogic(db, 'cam-01', {
        lotId: 'lot-colombo-01',
        slotId: 'A-01',
        occupied: false,
        confidence: 0.95,
        timestamp: t0.toISOString(),
      });

      // Stale timestamp (older than lastCctvAt)
      const tStale = new Date('2026-10-19T09:55:00Z');
      try {
        await ingestOccupancyLogic(db, 'cam-01', {
          lotId: 'lot-colombo-01',
          slotId: 'A-01',
          occupied: true,
          confidence: 0.90,
          timestamp: tStale.toISOString(),
        });
        expect.fail('Should have thrown STALE_DATA error');
      } catch (err: any) {
        expect(err.message).to.include('OUTDATED_PACKET');
      }
    });

    it('enforces 30-second debounce before committing state transitions', async () => {
      const slotRef = db.collection('parking_lots').doc('lot-colombo-01').collection('slots').doc('A-01');

      // t = 0s: Vehicle begins pulling in
      const t0 = new Date('2026-10-19T12:00:00Z');
      const res1 = await ingestOccupancyLogic(db, 'cam-01', {
        lotId: 'lot-colombo-01',
        slotId: 'A-01',
        occupied: true,
        confidence: 0.92,
        timestamp: t0.toISOString(),
      });

      expect(res1.debounceStatus).to.equal('pending');
      const slotAfterT0 = (await slotRef.get()).data() as ParkingSlotDocument;
      expect(slotAfterT0.state).to.equal('available'); // Has not changed yet!
      expect(slotAfterT0.pendingCctvState).to.equal('occupied');

      // t = 15s: Still within 30s debounce window
      const t15 = new Date('2026-10-19T12:00:15Z');
      const res2 = await ingestOccupancyLogic(db, 'cam-01', {
        lotId: 'lot-colombo-01',
        slotId: 'A-01',
        occupied: true,
        confidence: 0.94,
        timestamp: t15.toISOString(),
      });

      expect(res2.debounceStatus).to.equal('pending');
      const slotAfterT15 = (await slotRef.get()).data() as ParkingSlotDocument;
      expect(slotAfterT15.state).to.equal('available');

      // t = 35s: Exceeds 30s threshold (stable)
      const t35 = new Date('2026-10-19T12:00:35Z');
      const res3 = await ingestOccupancyLogic(db, 'cam-01', {
        lotId: 'lot-colombo-01',
        slotId: 'A-01',
        occupied: true,
        confidence: 0.95,
        timestamp: t35.toISOString(),
      });

      expect(res3.debounceStatus).to.equal('applied');
      const slotAfterT35 = (await slotRef.get()).data() as ParkingSlotDocument;
      expect(slotAfterT35.state).to.equal('occupied');
      expect(slotAfterT35.pendingCctvState).to.be.null;

      // Check lot freeSlots counter decremented
      const lotDoc = await db.collection('parking_lots').doc('lot-colombo-01').get();
      expect((lotDoc.data() as ParkingLotDocument).freeSlots).to.equal(4);
    });

    it('detects slot conflict on reserved bay, keeps bay reserved, alerts admin, and dynamically reallocates driver', async () => {
      // 1. Create a reservation on slot A-01
      const bookingId = 'BK-CONF-001';
      const slotRef = db.collection('parking_lots').doc('lot-colombo-01').collection('slots').doc('A-01');
      await slotRef.update({
        state: 'reserved',
        bookingId,
        conflictFlag: false,
      });

      const now = new Date();
      const arrivalTime = new Date(now.getTime() + 10 * 60 * 1000);
      const holdExpiresAt = new Date(now.getTime() + 25 * 60 * 1000);
      const bookingDoc: Partial<BookingDocument> = {
        id: bookingId,
        userId: 'driver-victim',
        vehicleId: 'veh-01',
        lotId: 'lot-colombo-01',
        lotName: 'Colombo Central Hub',
        slotId: 'A-01',
        status: 'reserved',
        bookedAt: now.toISOString(),
        arrivalTime: arrivalTime.toISOString(),
        holdExpiresAt: holdExpiresAt.toISOString(),
        durationHours: 2,
        estimatedFee: 300,
        extensionFee: 0,
        finalFee: 300,
        extensionsCount: 0,
        vehiclePlate: 'CAB-9999',
        vehicleSize: 'medium',
        qrToken: generateSignedQrToken({ bookingId, slotId: 'A-01', arrivalTime, holdExpiresAt }),
      };
      await db.collection('bookings').doc(bookingId).set(bookingDoc);

      // 2. CCTV reports bay A-01 is occupied before driver checked in
      const conflictPacketTime = new Date(now.getTime() + 2 * 60 * 1000);
      const conflictRes = await ingestOccupancyLogic(db, 'cam-01', {
        lotId: 'lot-colombo-01',
        slotId: 'A-01',
        occupied: true,
        confidence: 0.93,
        timestamp: conflictPacketTime.toISOString(),
        violation: true,
      });

      expect(conflictRes.conflictDetected).to.be.true;
      expect(conflictRes.reallocated).to.be.true;
      expect(conflictRes.reallocatedToSlotId).to.equal('A-02'); // Next best available slot

      // Verify original slot is still reserved with conflictFlag=true
      const slotAfter = (await slotRef.get()).data() as ParkingSlotDocument;
      expect(slotAfter.state).to.equal('reserved');
      expect(slotAfter.conflictFlag).to.be.true;

      // Verify new slot is now reserved for the booking
      const newSlot = (
        await db.collection('parking_lots').doc('lot-colombo-01').collection('slots').doc('A-02').get()
      ).data() as ParkingSlotDocument;
      expect(newSlot.state).to.equal('reserved');
      expect(newSlot.bookingId).to.equal(bookingId);

      // Verify booking document updated with rotated HMAC token and reallocated slot
      const updatedBooking = (await db.collection('bookings').doc(bookingId).get()).data() as BookingDocument;
      expect(updatedBooking.slotId).to.equal('A-02');
      expect(updatedBooking.reallocatedDueToConflict).to.be.true;
      expect(updatedBooking.reallocatedFromSlotId).to.equal('A-01');

      // Verify new QR token is valid and targeted for A-02
      const tokenCheck = verifySignedQrToken(updatedBooking.qrToken);
      expect(tokenCheck.valid).to.be.true;
      expect(tokenCheck.payload?.slotId).to.equal('A-02');

      // Verify alert logged in admin_alerts
      const alerts = await db.collection('admin_alerts').where('type', '==', 'slot_conflict').get();
      expect(alerts.size).to.be.greaterThan(0);
      expect(alerts.docs[0].data().slotId).to.equal('A-01');
    });

    it('triggers vacated_without_payment alert when CCTV reports empty on checked-in bay without freeing it', async () => {
      // Set slot to occupied with checked-in booking
      const bookingId = 'BK-LEAVER-01';
      await db.collection('parking_lots').doc('lot-colombo-01').collection('slots').doc('A-01').update({
        state: 'occupied',
        bookingId,
      });

      await db.collection('bookings').doc(bookingId).set({
        id: bookingId,
        userId: 'driver-skater',
        vehicleId: 'veh-skater',
        lotId: 'lot-colombo-01',
        lotName: 'Colombo Central Hub',
        slotId: 'A-01',
        status: 'checkedIn',
        bookedAt: new Date().toISOString(),
        arrivalTime: new Date().toISOString(),
        holdExpiresAt: new Date().toISOString(),
        checkedInAt: new Date().toISOString(),
        vehiclePlate: 'WP-CAD-1234',
        vehicleSize: 'medium',
        durationHours: 2,
        estimatedFee: 300,
        extensionFee: 0,
        finalFee: 300,
        extensionsCount: 0,
        qrToken: 'SPS.v1.placeholder',
      } as BookingDocument);

      const packetTime = new Date('2026-10-19T16:00:00Z');
      const res = await ingestOccupancyLogic(db, 'cam-01', {
        lotId: 'lot-colombo-01',
        slotId: 'A-01',
        occupied: false,
        confidence: 0.95,
        timestamp: packetTime.toISOString(),
      });

      expect(res.success).to.be.true;
      // Slot state must NOT be freed!
      const slotAfter = (
        await db.collection('parking_lots').doc('lot-colombo-01').collection('slots').doc('A-01').get()
      ).data() as ParkingSlotDocument;
      expect(slotAfter.state).to.equal('occupied');

      // Security alert created
      const alerts = await db.collection('admin_alerts').where('type', '==', 'vacated_without_payment').get();
      expect(alerts.size).to.be.greaterThan(0);
      expect(alerts.docs[0].data().bookingId).to.equal(bookingId);
    });
  });

  describe('3. IoT Barrier Gate QR Token Validation Contract', () => {
    it('authenticates, checks geofencing, single-use, and admits matching vehicle', async () => {
      const now = new Date();
      const arrival = new Date(now.getTime() - 2 * 60 * 1000); // 2 min ago
      const holdExpires = new Date(now.getTime() + 13 * 60 * 1000);

      const bookingId = 'BK-BARRIER-01';
      const validToken = generateSignedQrToken({
        bookingId,
        slotId: 'A-01',
        arrivalTime: arrival,
        holdExpiresAt: holdExpires,
      });

      await db.collection('parking_lots').doc('lot-colombo-01').collection('slots').doc('A-01').update({
        state: 'reserved',
        bookingId,
      });

      await db.collection('bookings').doc(bookingId).set({
        id: bookingId,
        userId: 'driver-gate',
        vehicleId: 'veh-gate',
        lotId: 'lot-colombo-01',
        lotName: 'Colombo Central Hub',
        slotId: 'A-01',
        status: 'reserved',
        bookedAt: new Date().toISOString(),
        arrivalTime: arrival.toISOString(),
        holdExpiresAt: holdExpires.toISOString(),
        vehiclePlate: 'WP-CAR-7777',
        vehicleSize: 'medium',
        durationHours: 2,
        estimatedFee: 300,
        extensionFee: 0,
        finalFee: 300,
        extensionsCount: 0,
        qrToken: validToken,
      } as BookingDocument);

      const barrierDevice: DeviceDocument = {
        id: 'barrier-gate-01',
        type: 'barrier',
        name: 'Entry Gate 1',
        lotId: 'lot-colombo-01',
        slotId: null,
        apiKeyHash: 'hash',
        isActive: true,
      };

      // 1. Wrong slot geofencing check
      const wrongSlotBarrier: DeviceDocument = {
        ...barrierDevice,
        slotId: 'A-03', // Designated specifically for A-03
      };
      const wrongSlotRes = await validateQrLogic(db, wrongSlotBarrier, {
        qrToken: validToken,
        barrierId: 'barrier-gate-01',
      });
      expect(wrongSlotRes.allow).to.be.false;
      expect(wrongSlotRes.code).to.equal('WRONG_SLOT');

      // 2. Successful check-in at general lot barrier
      const successRes = await validateQrLogic(db, barrierDevice, {
        qrToken: validToken,
        barrierId: 'barrier-gate-01',
      });
      expect(successRes.allow).to.be.true;
      expect(successRes.bookingId).to.equal(bookingId);
      expect(successRes.slotId).to.equal('A-01');

      // Verify slot is occupied and booking is checkedIn
      const slotAfter = (
        await db.collection('parking_lots').doc('lot-colombo-01').collection('slots').doc('A-01').get()
      ).data() as ParkingSlotDocument;
      expect(slotAfter.state).to.equal('occupied');

      const bookingAfter = (await db.collection('bookings').doc(bookingId).get()).data() as BookingDocument;
      expect(bookingAfter.status).to.equal('checkedIn');
      expect(bookingAfter.checkedInAt).to.not.be.undefined;

      // 3. Single-use enforcement: re-presenting the same QR token is denied
      const replayRes = await validateQrLogic(db, barrierDevice, {
        qrToken: validToken,
        barrierId: 'barrier-gate-01',
      });
      expect(replayRes.allow).to.be.false;
      expect(replayRes.code).to.equal('TOKEN_ALREADY_USED');
    });
  });

  describe('4. Smart Payment Settlement Contract', () => {
    it('calculates exit fee server-side, validates idempotency, and frees parking bay', async () => {
      const bookingId = 'BK-PAY-001';
      const checkInTime = new Date('2026-10-19T08:00:00Z');
      const exitTime = new Date('2026-10-19T09:30:00Z'); // 1.5 hours -> rounded up to 2 hours @ 150/hr = 300 LKR

      await db.collection('parking_lots').doc('lot-colombo-01').update({
        freeSlots: 4,
      });

      await db.collection('parking_lots').doc('lot-colombo-01').collection('slots').doc('A-01').update({
        state: 'occupied',
        bookingId,
      });

      await db.collection('bookings').doc(bookingId).set({
        id: bookingId,
        userId: 'driver-paid',
        vehicleId: 'veh-paid',
        lotId: 'lot-colombo-01',
        lotName: 'Colombo Central Hub',
        slotId: 'A-01',
        status: 'checkedIn',
        bookedAt: new Date('2026-10-19T07:45:00Z').toISOString(),
        arrivalTime: new Date('2026-10-19T08:00:00Z').toISOString(),
        holdExpiresAt: new Date('2026-10-19T08:15:00Z').toISOString(),
        checkedInAt: checkInTime.toISOString(),
        vehiclePlate: 'WP-ABC-1122',
        vehicleSize: 'medium',
        durationHours: 2,
        estimatedFee: 300,
        extensionFee: 50, // 1 extension previously charged
        finalFee: 350,
        extensionsCount: 1,
        qrToken: 'SPS.v1.placeholder',
      } as BookingDocument);

      // Expected total: 2 hours * 150 + 50 = 350 LKR.
      // Underpayment test: paying 200 LKR
      try {
        await paymentCompletedLogic(db, 'payment-gateway-svc-01', {
          bookingId,
          paymentRef: 'PAY-TXN-001',
          amountPaid: 200,
          paymentMethod: 'card',
          timestamp: exitTime.toISOString(),
        });
        expect.fail('Should have failed on underpayment');
      } catch (err: any) {
        expect(err.message).to.include('INSUFFICIENT_PAYMENT');
      }

      // Exact payment test: paying 350 LKR
      const payRes = await paymentCompletedLogic(db, 'payment-gateway-svc-01', {
        bookingId,
        paymentRef: 'PAY-TXN-001',
        amountPaid: 350,
        paymentMethod: 'card',
        timestamp: exitTime.toISOString(),
      });

      expect(payRes.success).to.be.true;
      expect(payRes.totalCharged).to.equal(350);
      expect(payRes.isIdempotentReplay).to.be.undefined;

      // Slot is freed to available
      const slotAfter = (
        await db.collection('parking_lots').doc('lot-colombo-01').collection('slots').doc('A-01').get()
      ).data() as ParkingSlotDocument;
      expect(slotAfter.state).to.equal('available');
      expect(slotAfter.bookingId).to.be.null;

      // Lot counter incremented
      const lotAfter = (
        await db.collection('parking_lots').doc('lot-colombo-01').get()
      ).data() as ParkingLotDocument;
      expect(lotAfter.freeSlots).to.equal(5);

      // Verify booking updated with status 'completed' and charges array
      const bookingAfter = (await db.collection('bookings').doc(bookingId).get()).data() as BookingDocument;
      expect(bookingAfter.status).to.equal('completed');
      expect(bookingAfter.charges).to.be.an('array').with.lengthOf(2); // parking (300) + extension (50)

      // Idempotency test: submitting repeat payment with same paymentRef
      const repeatRes = await paymentCompletedLogic(db, 'payment-gateway-svc-01', {
        bookingId,
        paymentRef: 'PAY-TXN-001',
        amountPaid: 350,
        paymentMethod: 'card',
        timestamp: exitTime.toISOString(),
      });

      expect(repeatRes.success).to.be.true;
      expect(repeatRes.isIdempotentReplay).to.be.true;
      expect(repeatRes.totalCharged).to.equal(350);

      // Verify freeSlots was NOT incremented again
      const lotAfterRepeat = (
        await db.collection('parking_lots').doc('lot-colombo-01').get()
      ).data() as ParkingLotDocument;
      expect(lotAfterRepeat.freeSlots).to.equal(5);
    });
  });
});
