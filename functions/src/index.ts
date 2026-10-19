// index.ts
// Smart Parking (J26-IT-335) — Firebase Cloud Functions & Server Authority Entry Point

import * as admin from 'firebase-admin';
import { onCall, onRequest } from 'firebase-functions/v2/https';
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

// Initialize Firebase Admin
if (admin.apps.length === 0) {
  admin.initializeApp();
}
const db = admin.firestore();

// --- Internal Mobile App Callables (Auth State Inherited from Flutter Client) ---

// 1. Create Booking (Callable with atomic transaction)
export const createBooking = onCall(
  { cors: true, secrets: [hmacSecretParam] },
  async (request) => {
    const authUid = request.auth?.uid || (request.data?.userId as string) || 'demo-user';
    return await createBookingLogic(db, authUid, request.data);
  }
);

// 2. Cancel Booking (Callable with atomic transaction)
export const cancelBooking = onCall({ cors: true }, async (request) => {
  const authUid = request.auth?.uid || (request.data?.userId as string) || 'demo-user';
  return await cancelBookingLogic(db, authUid, request.data);
});

// 3. Barrier QR Check-In (Callable fallback for client app demo)
export const checkIn = onCall({ cors: true }, async (request) => {
  const authUid = request.auth?.uid || 'cctv-gate';
  return await checkInLogic(db, authUid, request.data);
});

// 4. Extend Hold Window (+15 min, max 2 extensions)
export const extendHold = onCall({ cors: true }, async (request) => {
  const authUid = request.auth?.uid || (request.data?.userId as string) || 'demo-user';
  return await extendHoldLogic(db, authUid, request.data);
});

// 5. Accept Dynamic In-Transit Upgrade (Atomic slot swap with signed token rotation)
export const acceptUpgrade = onCall(
  { cors: true, secrets: [hmacSecretParam] },
  async (request) => {
    const authUid = request.auth?.uid || (request.data?.userId as string) || 'demo-user';
    return await acceptUpgradeLogic(db, authUid, request.data);
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

// 7. Manual trigger for auto-release (Callable, for test verification and demo fast-forward)
export const triggerAutoRelease = onCall({ cors: true }, async (request) => {
  const refTime = request.data?.referenceTime
    ? new Date(request.data.referenceTime)
    : new Date();
  return await autoReleaseExpiredHoldsLogic(db, refTime);
});

// 8. Migration utility to populate subcollections
export const migrateLots = onCall({ cors: true }, async () => {
  return await migrateOrSeedLots(db);
});

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
