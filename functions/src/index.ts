// index.ts
// Smart Parking (J26-IT-335) — Firebase Cloud Functions & Server Authority Entry Point

import * as admin from 'firebase-admin';
import { onCall } from 'firebase-functions/v2/https';
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

// Initialize Firebase Admin
if (admin.apps.length === 0) {
  admin.initializeApp();
}
const db = admin.firestore();

// 1. Create Booking (Callable with atomic transaction)
export const createBooking = onCall({ cors: true }, async (request) => {
  const authUid = request.auth?.uid || (request.data?.userId as string) || 'demo-user';
  return await createBookingLogic(db, authUid, request.data);
});

// 2. Cancel Booking (Callable with atomic transaction)
export const cancelBooking = onCall({ cors: true }, async (request) => {
  const authUid = request.auth?.uid || (request.data?.userId as string) || 'demo-user';
  return await cancelBookingLogic(db, authUid, request.data);
});

// 3. Barrier QR Check-In (Callable with atomic transaction)
export const checkIn = onCall({ cors: true }, async (request) => {
  const authUid = request.auth?.uid || 'cctv-gate';
  return await checkInLogic(db, authUid, request.data);
});

// 4. Extend Hold Window (+15 min, max 2 extensions)
export const extendHold = onCall({ cors: true }, async (request) => {
  const authUid = request.auth?.uid || (request.data?.userId as string) || 'demo-user';
  return await extendHoldLogic(db, authUid, request.data);
});

// 5. Accept Dynamic In-Transit Upgrade (Atomic slot swap)
export const acceptUpgrade = onCall({ cors: true }, async (request) => {
  const authUid = request.auth?.uid || (request.data?.userId as string) || 'demo-user';
  return await acceptUpgradeLogic(db, authUid, request.data);
});

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
};
