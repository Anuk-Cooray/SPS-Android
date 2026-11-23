// index.ts
// Smart Parking (J26-IT-335) — Firebase Cloud Functions & Server Authority Entry Point

import * as admin from 'firebase-admin';
import { onCall, onRequest, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import {
  createBookingLogic,
  cancelBookingLogic,
  checkInLogic,
  extendHoldLogic,
  acceptUpgradeLogic,
} from './bookings';
import { autoReleaseExpiredHoldsLogic } from './auto_release';
import { migrateOrSeedLots } from './migrate';
import { scoreSlot, evaluateInTransitUpgrade, scoreAndRankSlots } from './scoring';
import { evaluateArrivalFeasibility } from './feasibility';
import { authenticateDevice, hashApiKey } from './devices';
import { ingestOccupancyLogic } from './cctv';
import { validateQrLogic } from './barrier';
import { paymentCompletedLogic } from './payment';
import { hmacSecretParam, generateSignedQrToken, verifySignedQrToken } from './hmac_token';
import { resolveCaller, requireAdmin, isEmulatorOrTest } from './auth_guard';
import { requestEmailOtpLogic, verifyEmailOtpLogic, queueOtpEmail } from './otp';

// Initialize Firebase Admin
if (admin.apps.length === 0) {
  admin.initializeApp();
}
const db = admin.firestore();

// --- Internal Mobile App Callables (Auth State Inherited from Flutter Client) ---

// Caller identity is taken from the verified auth token only (demo fallback under emulator)

// 1. Create Booking (Callable with atomic transaction)
export const createBooking = onCall(
  { cors: true, secrets: [hmacSecretParam] },
  async (request) => {
    const caller = resolveCaller(request);
    return await createBookingLogic(db, caller.uid, request.data);
  }
);

// 2. Cancel Booking (Callable with atomic transaction)
export const cancelBooking = onCall({ cors: true }, async (request) => {
  const caller = resolveCaller(request);
  return await cancelBookingLogic(db, caller.uid, request.data, { isAdmin: caller.isAdmin });
});

// 3. QR Check-In (Callable fallback for client app demo; owner or admin only)
export const checkIn = onCall({ cors: true }, async (request) => {
  const caller = resolveCaller(request);
  return await checkInLogic(db, caller.uid, request.data, { isAdmin: caller.isAdmin });
});

// 4. Extend Hold Window (+15 min, max 2 extensions)
export const extendHold = onCall({ cors: true }, async (request) => {
  const caller = resolveCaller(request);
  return await extendHoldLogic(db, caller.uid, request.data, { isAdmin: caller.isAdmin });
});

// 5. Accept Dynamic In-Transit Upgrade (Atomic slot swap with signed token rotation)
export const acceptUpgrade = onCall(
  { cors: true, secrets: [hmacSecretParam] },
  async (request) => {
    const caller = resolveCaller(request);
    return await acceptUpgradeLogic(db, caller.uid, request.data, { isAdmin: caller.isAdmin });
  }
);

// 6. Scheduled Sweeper: Auto-release expired 15-minute holds every 1 minute
export const autoReleaseExpiredHolds = onSchedule(
  {
    schedule: '* * * * *',
    timeZone: 'Asia/Colombo',
    retryCount: 1,
  },
  async () => {
    const result = await autoReleaseExpiredHoldsLogic(db, new Date());
    console.log(
      `[autoReleaseExpiredHolds] Sweeper completed: ${result.releasedCount} reservations released.`
    );
  }
);

// 7. Manual trigger for auto-release (Admin only; demo fast-forward under emulator)
export const triggerAutoRelease = onCall({ cors: true }, async (request) => {
  requireAdmin(request);
  const refTime = request.data?.referenceTime
    ? new Date(request.data.referenceTime)
    : new Date();
  if (isNaN(refTime.getTime())) {
    throw new HttpsError('invalid-argument', 'Invalid referenceTime.');
  }
  return await autoReleaseExpiredHoldsLogic(db, refTime);
});

// 8. Migration utility to populate subcollections (Admin only)
export const migrateLots = onCall({ cors: true }, async (request) => {
  requireAdmin(request);
  return await migrateOrSeedLots(db);
});

// --- Email OTP Sign-In (server-issued codes, Firebase custom token on success) ---

// 8a. Issue a 6-digit code (delivered via /mail; returned in the response only under the emulator)
export const requestEmailOtp = onCall(
  { cors: true, secrets: [hmacSecretParam] },
  async (request) => {
    const demo = isEmulatorOrTest();
    const result = await requestEmailOtpLogic(db, request.data?.email, (email, code) =>
      queueOtpEmail(db, email, code)
    );
    return {
      sent: true,
      expiresAt: result.expiresAt,
      ...(demo ? { demoCode: result.code } : {}),
    };
  }
);

// 8b. Verify the code and mint a Firebase Auth custom token for signInWithCustomToken
export const verifyEmailOtp = onCall(
  { cors: true, secrets: [hmacSecretParam] },
  async (request) => {
    const { email } = await verifyEmailOtpLogic(db, request.data?.email, request.data?.code);

    let user: admin.auth.UserRecord;
    try {
      user = await admin.auth().getUserByEmail(email);
    } catch (error: any) {
      if (error?.code !== 'auth/user-not-found') throw error;
      user = await admin.auth().createUser({ email, emailVerified: true });
    }
    if (!user.emailVerified) {
      await admin.auth().updateUser(user.uid, { emailVerified: true });
    }

    const customToken = await admin.auth().createCustomToken(user.uid);
    return { uid: user.uid, customToken };
  }
);

// --- External Component Authenticated HTTPS Endpoints (onRequest) ---

// 9. Component 1: CCTV Vision Occupancy Ingestion (Header X-Camera-Api-Key)
export const ingestOccupancy = onRequest({ cors: true }, async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'method-not-allowed', message: 'POST required' });
    return;
  }

  const apiKey = (req.headers['x-camera-api-key'] as string) || (req.query.apiKey as string);
  const device = await authenticateDevice(db, apiKey, 'camera');
  if (!device) {
    res.status(401).json({
      error: 'unauthenticated',
      code: 'INVALID_API_KEY',
      message: 'Invalid or missing X-Camera-Api-Key header.',
    });
    return;
  }

  try {
    const result = await ingestOccupancyLogic(db, device.id, req.body);
    res.status(200).json(result);
  } catch (error: any) {
    const errMsg = error.message || String(error);
    const status =
      errMsg.startsWith('LOT_NOT_FOUND') || errMsg.startsWith('SLOT_NOT_FOUND') ? 404 : 400;
    res.status(status).json({
      error: 'invalid-argument',
      message: errMsg,
    });
  }
});

// 10. Component 2: IoT Barrier Gate QR Token Validation (Header X-Device-Api-Key + HMAC)
export const validateQr = onRequest(
  { cors: true, secrets: [hmacSecretParam] },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'method-not-allowed', message: 'POST required' });
      return;
    }

    const apiKey = (req.headers['x-device-api-key'] as string) || (req.query.apiKey as string);
    const device = await authenticateDevice(db, apiKey, 'barrier');
    if (!device) {
      res.status(401).json({
        error: 'unauthenticated',
        code: 'INVALID_API_KEY',
        message: 'Invalid or missing X-Device-Api-Key header.',
      });
      return;
    }

    try {
      const result = await validateQrLogic(db, device, req.body);
      const status = result.allow ? 200 : 403;
      res.status(status).json(result);
    } catch (error: any) {
      res.status(400).json({
        allow: false,
        error: 'invalid-argument',
        message: error.message || String(error),
      });
    }
  }
);

// 11. Component 3: Smart Billing & Payment Settlement (Header X-Service-Api-Key)
export const paymentCompleted = onRequest({ cors: true }, async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'method-not-allowed', message: 'POST required' });
    return;
  }

  const apiKey = (req.headers['x-service-api-key'] as string) || (req.query.apiKey as string);
  const device = await authenticateDevice(db, apiKey, 'payment_gateway');
  if (!device) {
    res.status(401).json({
      error: 'unauthenticated',
      code: 'INVALID_API_KEY',
      message: 'Invalid or missing X-Service-Api-Key header.',
    });
    return;
  }

  try {
    const result = await paymentCompletedLogic(db, device.id, req.body);
    res.status(200).json(result);
  } catch (error: any) {
    const errMsg = error.message || String(error);
    const status = errMsg.startsWith('BOOKING_NOT_FOUND')
      ? 404
      : errMsg.startsWith('ALREADY_SETTLED')
      ? 409
      : 400;
    res.status(status).json({
      error: 'invalid-argument',
      message: errMsg,
    });
  }
});

// Export internal libraries for test suites
export {
  db,
  createBookingLogic,
  cancelBookingLogic,
  checkInLogic,
  extendHoldLogic,
  acceptUpgradeLogic,
  autoReleaseExpiredHoldsLogic,
  migrateOrSeedLots,
  scoreSlot,
  evaluateInTransitUpgrade,
  scoreAndRankSlots,
  evaluateArrivalFeasibility,
  authenticateDevice,
  hashApiKey,
  ingestOccupancyLogic,
  validateQrLogic,
  paymentCompletedLogic,
  generateSignedQrToken,
  verifySignedQrToken,
};
