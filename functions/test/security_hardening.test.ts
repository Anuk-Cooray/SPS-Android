// security_hardening.test.ts
// Smart Parking (J26-IT-335) — Regression tests for caller identity, booking ownership,
// admin-only operations, and server-side email OTP verification.

import { expect } from 'chai';
import * as admin from 'firebase-admin';
import { resolveCaller, requireAdmin } from '../src/auth_guard';
import {
  createBookingLogic,
  cancelBookingLogic,
  checkInLogic,
  extendHoldLogic,
  acceptUpgradeLogic,
} from '../src/bookings';
import {
  requestEmailOtpLogic,
  verifyEmailOtpLogic,
  OTP_MAX_ATTEMPTS,
  OTP_RESEND_COOLDOWN_MS,
  OTP_TTL_MS,
} from '../src/otp';
import { BookingDocument, ParkingLotDocument, ParkingSlotDocument } from '../src/types';

async function expectHttpsError(promise: Promise<unknown>, code: string): Promise<void> {
  try {
    await promise;
  } catch (err: any) {
    expect(err.code, err.message).to.equal(code);
    return;
  }
  expect.fail(`Expected HttpsError '${code}' but call succeeded`);
}

function expectThrowsCode(fn: () => unknown, code: string): void {
  try {
    fn();
  } catch (err: any) {
    expect(err.code, err.message).to.equal(code);
    return;
  }
  expect.fail(`Expected HttpsError '${code}' but call succeeded`);
}

describe('Security Hardening: Caller Identity Guard', () => {
  it('rejects unauthenticated callers in deployed mode', () => {
    expectThrowsCode(() => resolveCaller({ data: { userId: 'victim' } }, false), 'unauthenticated');
  });

  it('ignores a caller-supplied userId when an auth token is present', () => {
    const caller = resolveCaller({ auth: { uid: 'alice', token: {} }, data: { userId: 'bob' } }, false);
    expect(caller).to.deep.equal({ uid: 'alice', isAdmin: false });
  });

  it('never grants admin through the demo fallback userId', () => {
    for (const reserved of ['admin', 'system', 'cctv-gate', 'emulator-admin']) {
      const caller = resolveCaller({ data: { userId: reserved } }, true);
      expect(caller).to.deep.equal({ uid: 'demo-user', isAdmin: false });
    }
  });

  it('recognises admin only from verified token claims', () => {
    expect(resolveCaller({ auth: { uid: 'u1', token: { admin: true } } }, false).isAdmin).to.be.true;
    expect(resolveCaller({ auth: { uid: 'u2', token: { role: 'admin' } } }, false).isAdmin).to.be.true;
    expect(resolveCaller({ auth: { uid: 'u3', token: { admin: 'true' } } }, false).isAdmin).to.be.false;
  });

  it('requireAdmin blocks anonymous and non-admin callers in deployed mode', () => {
    expectThrowsCode(() => requireAdmin({}, false), 'unauthenticated');
    expectThrowsCode(() => requireAdmin({ auth: { uid: 'driver', token: {} } }, false), 'permission-denied');
    expect(requireAdmin({ auth: { uid: 'ops', token: { admin: true } } }, false).isAdmin).to.be.true;
  });
});

describe('Security Hardening: Booking Ownership & Check-In', () => {
  let db: admin.firestore.Firestore;

  before(async () => {
    process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
    if (admin.apps.length === 0) {
      admin.initializeApp({ projectId: 'demo-sps-concurrency' });
    }
    db = admin.firestore();
  });

  beforeEach(async () => {
    for (const name of ['bookings', 'parking_events', 'trip_telemetry']) {
      const snap = await db.collection(name).get();
      await Promise.all(snap.docs.map((d) => d.ref.delete()));
    }
    const lotRef = db.collection('parking_lots').doc('lot-sec');
    const slots = await lotRef.collection('slots').get();
    await Promise.all(slots.docs.map((d) => d.ref.delete()));

    const lot: ParkingLotDocument = {
      id: 'lot-sec',
      name: 'Security Test Lot',
      latitude: 6.9147,
      longitude: 79.9729,
      hourlyRate: 100,
      totalSlots: 2,
      freeSlots: 2,
    } as ParkingLotDocument;
    await lotRef.set(lot);

    const slotBase = {
      lotId: 'lot-sec',
      row: 'A',
      size: 'medium',
      type: 'normal',
      state: 'available',
      bookingId: null,
      updatedAt: new Date().toISOString(),
      updatedBy: 'system',
    };
    await lotRef.collection('slots').doc('A-01').set({ ...slotBase, id: 'A-01', number: 1, walkingDistanceMeters: 40 } as ParkingSlotDocument);
    await lotRef.collection('slots').doc('A-02').set({ ...slotBase, id: 'A-02', number: 2, walkingDistanceMeters: 120 } as ParkingSlotDocument);
  });

  async function bookAsAlice(): Promise<BookingDocument> {
    return createBookingLogic(db, 'alice', {
      lotId: 'lot-sec',
      slotId: 'A-02',
      vehiclePlate: 'CAB-0001',
      vehicleSize: 'medium',
      arrivalTime: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
      durationHours: 1,
    });
  }

  it('prevents another user from cancelling, extending, or upgrading a booking', async () => {
    const booking = await bookAsAlice();

    await expectHttpsError(cancelBookingLogic(db, 'mallory', { bookingId: booking.id }), 'permission-denied');
    await expectHttpsError(extendHoldLogic(db, 'mallory', { bookingId: booking.id }), 'permission-denied');
    await expectHttpsError(
      acceptUpgradeLogic(db, 'mallory', { bookingId: booking.id, newSlotId: 'A-01' }),
      'permission-denied'
    );

    // Legacy magic identities no longer carry admin rights
    await expectHttpsError(cancelBookingLogic(db, 'admin', { bookingId: booking.id }), 'permission-denied');
    await expectHttpsError(cancelBookingLogic(db, 'system', { bookingId: booking.id }), 'permission-denied');

    const stored = (await db.collection('bookings').doc(booking.id).get()).data() as BookingDocument;
    expect(stored.status).to.equal('reserved');
    expect(stored.slotId).to.equal('A-02');
  });

  it('allows a verified admin to cancel another user\'s booking', async () => {
    const booking = await bookAsAlice();
    const res = await cancelBookingLogic(db, 'ops-admin', { bookingId: booking.id }, { isAdmin: true });
    expect(res.success).to.be.true;
  });

  it('rejects check-in by bookingId alone, with a wrong token, or by a non-owner', async () => {
    const booking = await bookAsAlice();

    await expectHttpsError(checkInLogic(db, 'alice', { bookingId: booking.id } as any), 'invalid-argument');
    await expectHttpsError(
      checkInLogic(db, 'alice', { bookingId: booking.id, qrToken: 'SPS.v1.forged' }),
      'permission-denied'
    );
    await expectHttpsError(
      checkInLogic(db, 'mallory', { bookingId: booking.id, qrToken: booking.qrToken }),
      'permission-denied'
    );
    await expectHttpsError(checkInLogic(db, 'mallory', { qrToken: booking.qrToken }), 'permission-denied');

    const stored = (await db.collection('bookings').doc(booking.id).get()).data() as BookingDocument;
    expect(stored.status).to.equal('reserved');
  });

  it('lets the owner check in with their valid QR token', async () => {
    const booking = await bookAsAlice();
    const res = await checkInLogic(db, 'alice', { bookingId: booking.id, qrToken: booking.qrToken });
    expect(res.success).to.be.true;
  });
});

describe('Security Hardening: Booking Timestamps', () => {
  const base = {
    lotId: 'lot-main',
    slotId: 'A-02',
    vehiclePlate: 'CAB-4821',
    vehicleSize: 'medium',
    durationHours: 1,
  };
  // Validation runs before any Firestore access, so no database is needed
  const noDb = {} as unknown as admin.firestore.Firestore;

  it('rejects an arrivalTime without a UTC offset', async () => {
    await expectHttpsError(
      createBookingLogic(noDb, 'uid-1', { ...base, arrivalTime: '2026-10-20T18:28:00.000' } as any),
      'invalid-argument'
    );
  });

  it('rejects a non-string arrivalTime', async () => {
    await expectHttpsError(
      createBookingLogic(noDb, 'uid-1', { ...base, arrivalTime: 1792519080000 } as any),
      'invalid-argument'
    );
  });
});

describe('Security Hardening: Server-Side Email OTP', () => {
  let db: admin.firestore.Firestore;
  const EMAIL = 'driver@sliit.lk';

  before(async () => {
    process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
    if (admin.apps.length === 0) {
      admin.initializeApp({ projectId: 'demo-sps-concurrency' });
    }
    db = admin.firestore();
  });

  beforeEach(async () => {
    const snap = await db.collection('email_verifications').get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  });

  async function issue(now: Date = new Date()): Promise<string> {
    let delivered = '';
    await requestEmailOtpLogic(db, EMAIL, async (_email, code) => {
      delivered = code;
    }, now);
    return delivered;
  }

  it('stores only a hash of the code, never the plaintext', async () => {
    const code = await issue();
    expect(code).to.match(/^\d{6}$/);

    const record = (await db.collection('email_verifications').doc(EMAIL).get()).data()!;
    expect(record).to.not.have.property('otp');
    expect(JSON.stringify(record)).to.not.include(code);
    expect(record.otpHash).to.match(/^[0-9a-f]{64}$/);
  });

  it('verifies the correct code once and rejects reuse', async () => {
    const code = await issue();
    const res = await verifyEmailOtpLogic(db, EMAIL.toUpperCase(), code);
    expect(res.email).to.equal(EMAIL);
    await expectHttpsError(verifyEmailOtpLogic(db, EMAIL, code), 'failed-precondition');
  });

  it('locks the code after too many wrong guesses, even if the right code follows', async () => {
    const code = await issue();
    const wrong = code === '000000' ? '111111' : '000000';
    for (let i = 0; i < OTP_MAX_ATTEMPTS; i++) {
      await expectHttpsError(verifyEmailOtpLogic(db, EMAIL, wrong), 'permission-denied');
    }
    await expectHttpsError(verifyEmailOtpLogic(db, EMAIL, code), 'resource-exhausted');
  });

  it('rejects expired codes', async () => {
    const issuedAt = new Date(Date.now() - OTP_TTL_MS - 1000);
    const code = await issue(issuedAt);
    await expectHttpsError(verifyEmailOtpLogic(db, EMAIL, code), 'failed-precondition');
  });

  it('enforces a resend cooldown', async () => {
    const now = new Date();
    await issue(now);
    await expectHttpsError(
      requestEmailOtpLogic(db, EMAIL, async () => {}, new Date(now.getTime() + OTP_RESEND_COOLDOWN_MS / 2)),
      'resource-exhausted'
    );
  });

  it('rejects malformed emails and codes', async () => {
    await expectHttpsError(requestEmailOtpLogic(db, 'not-an-email', async () => {}), 'invalid-argument');
    await expectHttpsError(verifyEmailOtpLogic(db, EMAIL, '12ab56'), 'invalid-argument');
  });
});
