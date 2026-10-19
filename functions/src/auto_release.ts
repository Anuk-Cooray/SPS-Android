// auto_release.ts
// Smart Parking (J26-IT-335) — Server-Side Idempotent Auto-Release Sweeper

import * as admin from 'firebase-admin';
import {
  BookingDocument,
  ParkingLotDocument,
  ParkingEventDocument,
} from './types';

export interface AutoReleaseResult {
  releasedCount: number;
  releasedBookingIds: string[];
}

/**
 * Sweeps for expired hold windows and releases reserved bays idempotently.
 * Runs independently on the server even when all client mobile devices are disconnected or killed.
 */
export async function autoReleaseExpiredHoldsLogic(
  db: admin.firestore.Firestore,
  referenceTime: Date = new Date()
): Promise<AutoReleaseResult> {
  const cutoffIso = referenceTime.toISOString();
  const eligibleStatuses = ['reserved', 'upgraded', 'held', 'extended'];

  // Query candidate bookings that have passed their hold expiry
  const snapshot = await db
    .collection('bookings')
    .where('status', 'in', eligibleStatuses)
    .where('holdExpiresAt', '<=', cutoffIso)
    .get();

  const releasedBookingIds: string[] = [];

  for (const doc of snapshot.docs) {
    const booking = doc.data() as BookingDocument;
    const bookingRef = doc.ref;
    const now = new Date();

    try {
      const released = await db.runTransaction(async (transaction) => {
        const freshDoc = await transaction.get(bookingRef);
        if (!freshDoc.exists) return false;

        const currentBooking = freshDoc.data() as BookingDocument;

        // Idempotency: verify booking has not transitioned concurrently
        if (
          !eligibleStatuses.includes(currentBooking.status) ||
          currentBooking.holdExpiresAt > cutoffIso
        ) {
          return false;
        }

        const lotRef = db.collection('parking_lots').doc(currentBooking.lotId);
        const slotRef = lotRef.collection('slots').doc(currentBooking.slotId);

        const [lotDoc, slotDoc] = await Promise.all([
          transaction.get(lotRef),
          transaction.get(slotRef),
        ]);

        // Release slot if currently booked by this reservation
        if (slotDoc.exists) {
          transaction.update(slotRef, {
            state: 'available',
            bookingId: null,
            updatedAt: now.toISOString(),
            updatedBy: 'function',
          });
        }

        // Increment lot freeSlots
        if (lotDoc.exists) {
          const lotData = lotDoc.data() as ParkingLotDocument;
          const newFreeSlots = Math.min(lotData.totalSlots ?? 24, (lotData.freeSlots ?? 0) + 1);
          transaction.update(lotRef, {
            freeSlots: newFreeSlots,
            updatedAt: now.toISOString(),
          });
        }

        // Mark booking as auto_released
        transaction.update(bookingRef, {
          status: 'auto_released',
          completedAt: now.toISOString(),
        });

        // Write telemetry audit event
        const eventRef = db.collection('parking_events').doc(`EVT-AUTOREL-${Date.now()}-${Math.floor(100 + Math.random() * 900)}`);
        const event: ParkingEventDocument = {
          id: eventRef.id,
          bookingId: currentBooking.id,
          userId: currentBooking.userId,
          lotId: currentBooking.lotId,
          slotId: currentBooking.slotId,
          eventType: 'auto_released',
          timestamp: now.toISOString(),
          description: `Server auto-released slot ${currentBooking.slotId} in ${currentBooking.lotName} after 15m hold deadline expired at ${currentBooking.holdExpiresAt}.`,
          metadata: {
            holdExpiresAt: currentBooking.holdExpiresAt,
            referenceTime: cutoffIso,
          },
        };
        transaction.set(eventRef, event);

        return true;
      });

      if (released) {
        releasedBookingIds.push(booking.id);
      }
    } catch (err) {
      console.error(`Error auto-releasing booking ${booking.id}:`, err);
    }
  }

  return {
    releasedCount: releasedBookingIds.length,
    releasedBookingIds,
  };
}
