// cctv.ts
// Smart Parking (J26-IT-335) — CCTV Vision Occupancy Ingestion Logic
// Features 30s temporal debounce, conflict detection & automatic slot re-allocation

import * as admin from 'firebase-admin';
import {
  IngestOccupancyRequest,
  IngestOccupancyResponse,
  ParkingSlotDocument,
  ParkingLotDocument,
  BookingDocument,
  AdminAlertDocument,
  ParkingEventDocument,
  SlotState,
} from './types';
import { scoreAndRankSlots } from './scoring';
import { generateSignedQrToken } from './hmac_token';

export async function ingestOccupancyLogic(
  db: admin.firestore.Firestore,
  cameraDeviceId: string,
  request: IngestOccupancyRequest
): Promise<IngestOccupancyResponse> {
  const { lotId, slotId, occupied, confidence, timestamp, violation } = request;

  if (!lotId || !slotId || occupied === undefined || confidence === undefined || !timestamp) {
    throw new Error('INVALID_PAYLOAD: Missing required parameters in CCTV occupancy packet.');
  }

  if (confidence < 0.70) {
    throw new Error('LOW_CONFIDENCE: Vision detection confidence is below 0.70 threshold.');
  }

  const packetDate = new Date(timestamp);
  if (isNaN(packetDate.getTime())) {
    throw new Error('INVALID_TIMESTAMP: Malformed ISO-8601 timestamp string.');
  }

  const lotRef = db.collection('parking_lots').doc(lotId);
  const slotRef = lotRef.collection('slots').doc(slotId);

  return await db.runTransaction(async (transaction) => {
    const [lotDoc, slotDoc] = await Promise.all([
      transaction.get(lotRef),
      transaction.get(slotRef),
    ]);

    if (!lotDoc.exists) {
      throw new Error(`LOT_NOT_FOUND: Lot ${lotId} does not exist.`);
    }

    if (!slotDoc.exists) {
      throw new Error(`SLOT_NOT_FOUND: Slot ${slotId} does not exist in lot ${lotId}.`);
    }

    const lotData = lotDoc.data() as ParkingLotDocument;
    const slotData = slotDoc.data() as ParkingSlotDocument;

    // 1. Check outdated packets
    if (slotData.lastCctvAt) {
      const lastCctvDate = new Date(slotData.lastCctvAt);
      if (packetDate.getTime() < lastCctvDate.getTime()) {
        throw new Error(
          `OUTDATED_PACKET: Packet timestamp (${packetDate.toISOString()}) is older than last processed timestamp (${lastCctvDate.toISOString()}).`
        );
      }
    }

    // 2. Vacated Without Payment Check
    // If CCTV says empty, but booking is currently checked-in at barrier
    if (!occupied && slotData.state === 'occupied' && slotData.bookingId) {
      const bookingRef = db.collection('bookings').doc(slotData.bookingId);
      const bookingDoc = await transaction.get(bookingRef);
      if (bookingDoc.exists) {
        const bookingData = bookingDoc.data() as BookingDocument;
        if (bookingData.status === 'checkedIn') {
          // Do not free the slot; emit alert & event
          const alertRef = db.collection('admin_alerts').doc(`ALT-${Date.now()}`);
          const alertDoc: AdminAlertDocument = {
            id: alertRef.id,
            lotId,
            slotId,
            bookingId: bookingData.id,
            type: 'vacated_without_payment',
            severity: 'critical',
            timestamp: packetDate.toISOString(),
            description: `Vehicle in slot ${slotId} departed without payment settlement (Booking: ${bookingData.id}).`,
            resolved: false,
            metadata: { vehiclePlate: bookingData.vehiclePlate, cameraDeviceId },
          };
          transaction.set(alertRef, alertDoc);

          const eventRef = db.collection('parking_events').doc(`EVT-${Date.now()}`);
          const eventDoc: ParkingEventDocument = {
            id: eventRef.id,
            bookingId: bookingData.id,
            userId: bookingData.userId,
            lotId,
            slotId,
            eventType: 'vacated_without_payment',
            timestamp: packetDate.toISOString(),
            description: `Security Alert: Vehicle vacated bay ${slotId} without exit payment verification.`,
          };
          transaction.set(eventRef, eventDoc);

          transaction.update(slotRef, {
            lastCctvAt: packetDate.toISOString(),
            updatedBy: 'cctv',
          });

          return {
            success: true,
            slotId,
            state: slotData.state,
            conflictDetected: false,
            message: 'Vehicle departed without payment. Alert logged to security.',
            timestamp: packetDate.toISOString(),
          };
        }
      }
    }

    // 3. Conflict Detection & Dynamic Re-allocation
    // CCTV reports occupied=true while slot is reserved/held and not checked in
    if (occupied && (slotData.state === 'reserved' || slotData.state === 'held')) {
      let isUncheckedInReservation = false;
      let activeBooking: BookingDocument | null = null;
      let bookingRef: admin.firestore.DocumentReference | null = null;

      if (slotData.bookingId) {
        bookingRef = db.collection('bookings').doc(slotData.bookingId);
        const bookingDoc = await transaction.get(bookingRef);
        if (bookingDoc.exists) {
          activeBooking = bookingDoc.data() as BookingDocument;
          if (
            (activeBooking.status === 'reserved' ||
              activeBooking.status === 'extended' ||
              activeBooking.status === 'upgraded') &&
            !activeBooking.checkedInAt
          ) {
            isUncheckedInReservation = true;
          }
        }
      }

      if (isUncheckedInReservation && activeBooking && bookingRef) {
        // Read candidate slots FIRST (all reads must precede writes in Firestore transactions)
        const slotsSnap = await transaction.get(lotRef.collection('slots'));
        const candidateSlots = slotsSnap.docs
          .map((d) => d.data() as ParkingSlotDocument)
          .filter((s) => s.id !== slotId && s.state === 'available');

        // Trigger conflict protocol
        const alertRef = db.collection('admin_alerts').doc(`ALT-${Date.now()}`);
        const alertDoc: AdminAlertDocument = {
          id: alertRef.id,
          lotId,
          slotId,
          bookingId: activeBooking.id,
          type: 'slot_conflict',
          severity: 'critical',
          timestamp: packetDate.toISOString(),
          description: `Conflict in slot ${slotId}: Unauthorized vehicle parked in bay reserved for ${activeBooking.vehiclePlate}.`,
          resolved: false,
          metadata: {
            vehiclePlate: activeBooking.vehiclePlate,
            cameraDeviceId,
            confidence,
            violation,
          },
        };
        transaction.set(alertRef, alertDoc);

        const conflictEventRef = db.collection('parking_events').doc(`EVT-${Date.now()}-1`);
        transaction.set(conflictEventRef, {
          id: conflictEventRef.id,
          bookingId: activeBooking.id,
          userId: activeBooking.userId,
          lotId,
          slotId,
          eventType: 'slot_conflict',
          timestamp: packetDate.toISOString(),
          description: `Unauthorized vehicle detected in reserved bay ${slotId}. Initiating dynamic re-allocation.`,
        });

        // Keep slot reserved, set conflictFlag=true
        transaction.update(slotRef, {
          conflictFlag: true,
          lastCctvAt: packetDate.toISOString(),
          updatedBy: 'cctv',
        });

        let reallocated = false;
        let reallocatedToSlotId: string | undefined;

        if (candidateSlots.length > 0) {
          // Rank candidate slots for vehicle size fit & walking distance
          const rankedCandidates = scoreAndRankSlots(
            candidateSlots,
            lotData,
            { size: activeBooking.vehicleSize },
            { preferNearEntrance: true, coveredParkingOnly: false }
          );

          if (rankedCandidates.length > 0) {
            const bestCandidate = rankedCandidates[0];
            const newSlotId = bestCandidate.slot.id;
            const newSlotRef = lotRef.collection('slots').doc(newSlotId);

            // Rotate driver's QR token for the new slot
            const newSignedQrToken = generateSignedQrToken({
              bookingId: activeBooking.id,
              slotId: newSlotId,
              arrivalTime: new Date(activeBooking.arrivalTime),
              holdExpiresAt: new Date(activeBooking.holdExpiresAt),
            });

            const distanceDelta =
              bestCandidate.slot.walkingDistanceMeters - slotData.walkingDistanceMeters;

            // Update booking with new slot & rotated token
            transaction.update(bookingRef, {
              slotId: newSlotId,
              originalSlotId: slotId,
              qrToken: newSignedQrToken,
              reallocatedDueToConflict: true,
              reallocatedFromSlotId: slotId,
            });

            // Reserve the new slot
            transaction.update(newSlotRef, {
              state: 'reserved',
              bookingId: activeBooking.id,
              updatedAt: packetDate.toISOString(),
              updatedBy: 'function',
            });

            // Relieve old slot from active booking
            transaction.update(slotRef, {
              bookingId: null,
            });

            // Log re-allocation event
            const reallocEventRef = db.collection('parking_events').doc(`EVT-${Date.now()}-2`);
            transaction.set(reallocEventRef, {
              id: reallocEventRef.id,
              bookingId: activeBooking.id,
              userId: activeBooking.userId,
              lotId,
              slotId: newSlotId,
              eventType: 'reallocated_due_to_conflict',
              timestamp: packetDate.toISOString(),
              description: `Booking reallocated from conflicting slot ${slotId} to optimal candidate ${newSlotId} (Distance delta: ${distanceDelta} m).`,
              metadata: {
                previousSlotId: slotId,
                newSlotId,
                distanceDeltaMeters: distanceDelta,
              },
            });

            reallocated = true;
            reallocatedToSlotId = newSlotId;
          }
        }

        return {
          success: true,
          slotId,
          state: 'reserved',
          conflictDetected: true,
          reallocated,
          reallocatedToSlotId,
          alertId: alertRef.id,
          message: reallocated
            ? `Unauthorized vehicle detected in reserved bay. Booking automatically reallocated to ${reallocatedToSlotId}.`
            : 'Unauthorized vehicle detected in reserved bay. No available candidate bay in lot.',
          timestamp: packetDate.toISOString(),
        };
      }
    }

    // 4. Normal Occupancy Synchronization with 30s Debounce
    const targetState: SlotState = occupied ? 'occupied' : 'available';

    // If slot is already in the target state, just update last seen timestamp
    if (slotData.state === targetState) {
      transaction.update(slotRef, {
        lastCctvAt: packetDate.toISOString(),
        pendingCctvState: null,
        pendingCctvSince: null,
        conflictFlag: false,
        updatedBy: 'cctv',
      });

      return {
        success: true,
        slotId,
        state: targetState,
        conflictDetected: false,
        debounceStatus: 'applied',
        timestamp: packetDate.toISOString(),
      };
    }

    // Debounce check: reading must remain stable for >= 30 seconds
    const isDebounceOverride = process.env.TEST_DEBOUNCE_OVERRIDE === 'true';

    if (slotData.pendingCctvState === targetState && slotData.pendingCctvSince) {
      const pendingSinceDate = new Date(slotData.pendingCctvSince);
      const elapsedSeconds = (packetDate.getTime() - pendingSinceDate.getTime()) / 1000;

      if (elapsedSeconds >= 30 || isDebounceOverride) {
        // Debounce threshold met -> Commit state transition
        const oldState = slotData.state;
        let newFreeSlots = lotData.freeSlots;

        if (oldState === 'available' && targetState === 'occupied') {
          newFreeSlots = Math.max(0, lotData.freeSlots - 1);
        } else if (oldState === 'occupied' && targetState === 'available') {
          newFreeSlots = Math.min(lotData.totalSlots, lotData.freeSlots + 1);
        }

        transaction.update(slotRef, {
          state: targetState,
          conflictFlag: false,
          pendingCctvState: null,
          pendingCctvSince: null,
          lastCctvAt: packetDate.toISOString(),
          updatedAt: packetDate.toISOString(),
          updatedBy: 'cctv',
        });

        if (newFreeSlots !== lotData.freeSlots) {
          transaction.update(lotRef, {
            freeSlots: newFreeSlots,
            updatedAt: packetDate.toISOString(),
          });
        }

        return {
          success: true,
          slotId,
          state: targetState,
          conflictDetected: false,
          debounceStatus: 'applied',
          timestamp: packetDate.toISOString(),
        };
      } else {
        // Still pending debounce period
        transaction.update(slotRef, {
          lastCctvAt: packetDate.toISOString(),
          updatedBy: 'cctv',
        });

        return {
          success: true,
          slotId,
          state: slotData.state,
          conflictDetected: false,
          debounceStatus: 'pending',
          message: `State change to ${targetState} is pending 30s stability debounce (${elapsedSeconds.toFixed(
            1
          )}s elapsed).`,
          timestamp: packetDate.toISOString(),
        };
      }
    } else {
      // First observation of candidate new state -> Begin debounce clock
      transaction.update(slotRef, {
        pendingCctvState: targetState,
        pendingCctvSince: packetDate.toISOString(),
        lastCctvAt: packetDate.toISOString(),
        updatedBy: 'cctv',
      });

      return {
        success: true,
        slotId,
        state: slotData.state,
        conflictDetected: false,
        debounceStatus: 'pending',
        message: `State change to ${targetState} initiated. Waiting 30s stability debounce.`,
        timestamp: packetDate.toISOString(),
      };
    }
  });
}
