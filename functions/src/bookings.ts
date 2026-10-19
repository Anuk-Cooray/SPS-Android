// bookings.ts
// Smart Parking (J26-IT-335) — Server Reservation Authority & Transaction Execution

import * as admin from 'firebase-admin';
import { HttpsError } from 'firebase-functions/v2/https';
import {
  BookingDocument,
  ParkingSlotDocument,
  ParkingLotDocument,
  ParkingEventDocument,
  CreateBookingRequest,
  CancelBookingRequest,
  CheckInRequest,
  ExtendHoldRequest,
  AcceptUpgradeRequest,
  BookingChargeDocument,
} from './types';
import { isSizeCompatible, scoreSlot } from './scoring';
import { evaluateArrivalFeasibility } from './feasibility';
import { generateSignedQrToken } from './hmac_token';

// --- Business Logic Functions (invoked by Cloud Functions & Unit Tests) ---

export async function createBookingLogic(
  db: admin.firestore.Firestore,
  authUid: string,
  request: CreateBookingRequest
): Promise<BookingDocument> {
  if (!authUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated to create a booking.');
  }

  const {
    lotId,
    slotId,
    vehiclePlate,
    vehicleSize,
    vehicleType = 'sedan',
    vehicleId = 'v-default',
    arrivalTime,
    durationHours,
    driverOrigin,
  } = request;

  if (!lotId || !slotId || !vehiclePlate || !vehicleSize || !arrivalTime || !durationHours) {
    throw new HttpsError('invalid-argument', 'Missing required booking parameters.');
  }

  const arrivalDate = new Date(arrivalTime);
  if (isNaN(arrivalDate.getTime())) {
    throw new HttpsError('invalid-argument', 'Invalid arrival time format.');
  }

  // Pre-flight feasibility check if driver coordinates are provided
  if (driverOrigin && driverOrigin.latitude && driverOrigin.longitude) {
    // We will query lot coordinates during transaction or use standard default
  }

  const bookingId = `BK-${Date.now().toString().slice(-6)}-${Math.floor(100 + Math.random() * 900)}`;
  const now = new Date();
  const holdExpiresAt = new Date(arrivalDate.getTime() + 15 * 60 * 1000);
  const qrToken = generateSignedQrToken({
    bookingId,
    slotId,
    arrivalTime: arrivalDate,
    holdExpiresAt,
  });

  const lotRef = db.collection('parking_lots').doc(lotId);
  const slotRef = lotRef.collection('slots').doc(slotId);
  const bookingRef = db.collection('bookings').doc(bookingId);
  const eventRef = db.collection('parking_events').doc(`EVT-${Date.now()}-${Math.floor(100 + Math.random() * 900)}`);

  return await db.runTransaction(async (transaction) => {
    const [lotDoc, slotDoc] = await Promise.all([
      transaction.get(lotRef),
      transaction.get(slotRef),
    ]);

    if (!lotDoc.exists) {
      throw new HttpsError('not-found', `Parking lot ${lotId} not found.`);
    }

    if (!slotDoc.exists) {
      throw new HttpsError('not-found', `Parking slot ${slotId} not found in lot ${lotId}.`);
    }

    const lotData = lotDoc.data() as ParkingLotDocument;
    const slotData = slotDoc.data() as ParkingSlotDocument;

    // Check availability
    if (slotData.state !== 'available') {
      throw new HttpsError(
        'already-exists',
        `Slot ${slotId} is no longer available (current state: ${slotData.state}). Slot just taken — please select another.`
      );
    }

    // Verify vehicle size fit
    if (!isSizeCompatible(slotData.size, vehicleSize)) {
      throw new HttpsError(
        'failed-precondition',
        `Vehicle size (${vehicleSize}) is incompatible with slot size (${slotData.size}).`
      );
    }

    // If driver origin provided, evaluate algorithmic travel feasibility
    let feasibilityData = null;
    if (driverOrigin && lotData.latitude && lotData.longitude) {
      const feasibility = evaluateArrivalFeasibility({
        originLat: driverOrigin.latitude,
        originLng: driverOrigin.longitude,
        destLat: lotData.latitude,
        destLng: lotData.longitude,
        requestedArrivalTime: arrivalDate,
        originZone: request.originZone,
        weatherFlag: request.weatherFlag,
        holidayFlag: request.holidayFlag,
        providerDurationMinutes: request.providerEtaMinutes,
      });

      if (!feasibility.isFeasible && arrivalDate.getTime() < feasibility.earliestFeasibleTime.getTime()) {
        throw new HttpsError(
          'failed-precondition',
          `Travel feasibility check failed: You cannot arrive by requested time. Earliest feasible arrival is ${feasibility.recommendedArrivalTime.toISOString()}.`
        );
      }
      feasibilityData = feasibility;
    }

    const newFreeSlots = Math.max(0, (lotData.freeSlots ?? 1) - 1);
    const hourlyRate = lotData.hourlyRate ?? 100;
    const estimatedFee = hourlyRate * durationHours;

    const booking: BookingDocument = {
      id: bookingId,
      userId: authUid,
      vehicleId,
      vehiclePlate,
      vehicleSize,
      lotId,
      lotName: lotData.name ?? 'Campus Lot',
      slotId,
      originalSlotId: null,
      distanceSavedMeters: 0,
      bookedAt: now.toISOString(),
      arrivalTime: arrivalDate.toISOString(),
      durationHours,
      status: 'reserved',
      estimatedFee,
      extensionFee: 0,
      finalFee: 0,
      charges: [
        {
          id: `CHG-${bookingId}-PARK`,
          type: 'parking',
          amount: estimatedFee,
          currency: 'LKR',
          timestamp: now.toISOString(),
          description: `Initial slot reservation fee (${durationHours}h @ LKR ${hourlyRate}/hr)`,
        },
      ],
      qrToken,
      checkedInAt: null,
      completedAt: null,
      holdExpiresAt: holdExpiresAt.toISOString(),
      extensionsCount: 0,
      predictedEtaMinBaseline: feasibilityData?.predictedEtaMinBaseline ?? 15,
      predictedEtaMinProvider: feasibilityData?.predictedEtaMinProvider ?? 12,
      predictedEtaMinCorrected: feasibilityData?.predictedEtaMinCorrected ?? 14,
      modelVersion: feasibilityData?.modelVersion ?? 'v1.0.0-linear',
      slotSwapHistory: [],
    };

    const event: ParkingEventDocument = {
      id: eventRef.id,
      bookingId,
      userId: authUid,
      lotId,
      slotId,
      eventType: 'booking_created',
      timestamp: now.toISOString(),
      description: `Server transaction reserved slot ${slotId} in ${lotData.name ?? lotId}. Hold active until ${holdExpiresAt.toISOString()}`,
      metadata: {
        vehiclePlate,
        vehicleSize,
        vehicleType,
        durationHours,
        estimatedFee,
        predictedEtaMinBaseline: booking.predictedEtaMinBaseline,
        predictedEtaMinProvider: booking.predictedEtaMinProvider,
        predictedEtaMinCorrected: booking.predictedEtaMinCorrected,
        modelVersion: booking.modelVersion,
      },
    };

    // Atomic multi-document mutations
    transaction.set(bookingRef, booking);
    transaction.update(slotRef, {
      state: 'reserved',
      bookingId,
      updatedAt: now.toISOString(),
      updatedBy: 'function',
    });
    transaction.update(lotRef, {
      freeSlots: newFreeSlots,
      updatedAt: now.toISOString(),
    });
    transaction.set(eventRef, event);

    return booking;
  });
}

export async function cancelBookingLogic(
  db: admin.firestore.Firestore,
  authUid: string,
  request: CancelBookingRequest
): Promise<{ success: boolean; bookingId: string }> {
  const { bookingId } = request;
  if (!bookingId) {
    throw new HttpsError('invalid-argument', 'Missing bookingId.');
  }

  const bookingRef = db.collection('bookings').doc(bookingId);
  const now = new Date();

  return await db.runTransaction(async (transaction) => {
    const bookingDoc = await transaction.get(bookingRef);
    if (!bookingDoc.exists) {
      throw new HttpsError('not-found', `Booking ${bookingId} not found.`);
    }

    const booking = bookingDoc.data() as BookingDocument;

    // Verify authorization
    if (booking.userId !== authUid && authUid !== 'admin' && authUid !== 'system') {
      throw new HttpsError('permission-denied', 'You do not have permission to cancel this booking.');
    }

    if (booking.status === 'cancelled' || booking.status === 'auto_released' || booking.status === 'completed') {
      throw new HttpsError('failed-precondition', `Booking is already ${booking.status}.`);
    }

    const lotRef = db.collection('parking_lots').doc(booking.lotId);
    const slotRef = lotRef.collection('slots').doc(booking.slotId);

    const [lotDoc, slotDoc] = await Promise.all([
      transaction.get(lotRef),
      transaction.get(slotRef),
    ]);

    if (lotDoc.exists) {
      const lotData = lotDoc.data() as ParkingLotDocument;
      const newFreeSlots = Math.min(lotData.totalSlots ?? 24, (lotData.freeSlots ?? 0) + 1);
      transaction.update(lotRef, {
        freeSlots: newFreeSlots,
        updatedAt: now.toISOString(),
      });
    }

    if (slotDoc.exists) {
      transaction.update(slotRef, {
        state: 'available',
        bookingId: null,
        updatedAt: now.toISOString(),
        updatedBy: 'function',
      });
    }

    transaction.update(bookingRef, {
      status: 'cancelled',
      completedAt: now.toISOString(),
    });

    const eventRef = db.collection('parking_events').doc(`EVT-${Date.now()}-${Math.floor(100 + Math.random() * 900)}`);
    const event: ParkingEventDocument = {
      id: eventRef.id,
      bookingId,
      userId: authUid,
      lotId: booking.lotId,
      slotId: booking.slotId,
      eventType: 'booking_cancelled',
      timestamp: now.toISOString(),
      description: `Booking ${bookingId} cancelled by ${authUid}. Slot ${booking.slotId} released.`,
    };
    transaction.set(eventRef, event);

    return { success: true, bookingId };
  });
}

export async function checkInLogic(
  db: admin.firestore.Firestore,
  authUid: string,
  request: CheckInRequest
): Promise<{ success: boolean; bookingId: string; slotId: string }> {
  const { bookingId, qrToken } = request;
  if (!qrToken && !bookingId) {
    throw new HttpsError('invalid-argument', 'Missing qrToken or bookingId.');
  }

  const now = new Date();

  return await db.runTransaction(async (transaction) => {
    let bookingRef: admin.firestore.DocumentReference;
    let bookingData: BookingDocument;

    if (bookingId) {
      bookingRef = db.collection('bookings').doc(bookingId);
      const doc = await transaction.get(bookingRef);
      if (!doc.exists) {
        throw new HttpsError('not-found', `Booking ${bookingId} not found.`);
      }
      bookingData = doc.data() as BookingDocument;
      if (qrToken && bookingData.qrToken !== qrToken) {
        throw new HttpsError('permission-denied', 'Invalid QR token for this booking.');
      }
    } else {
      // Find booking by qrToken
      const querySnap = await db.collection('bookings').where('qrToken', '==', qrToken).limit(1).get();
      if (querySnap.empty) {
        throw new HttpsError('not-found', 'No active reservation matches this QR token.');
      }
      bookingRef = querySnap.docs[0].ref;
      bookingData = querySnap.docs[0].data() as BookingDocument;
    }

    if (bookingData.status === 'checkedIn' || bookingData.status === 'completed') {
      return { success: true, bookingId: bookingData.id, slotId: bookingData.slotId };
    }

    if (bookingData.status === 'cancelled' || bookingData.status === 'auto_released') {
      throw new HttpsError('failed-precondition', `Cannot check in. Booking is ${bookingData.status}.`);
    }

    const slotRef = db.collection('parking_lots').doc(bookingData.lotId).collection('slots').doc(bookingData.slotId);

    transaction.update(slotRef, {
      state: 'occupied',
      updatedAt: now.toISOString(),
      updatedBy: 'cctv',
    });

    transaction.update(bookingRef, {
      status: 'checkedIn',
      checkedInAt: now.toISOString(),
    });

    const eventRef = db.collection('parking_events').doc(`EVT-${Date.now()}-${Math.floor(100 + Math.random() * 900)}`);
    const event: ParkingEventDocument = {
      id: eventRef.id,
      bookingId: bookingData.id,
      userId: bookingData.userId,
      lotId: bookingData.lotId,
      slotId: bookingData.slotId,
      eventType: 'checked_in',
      timestamp: now.toISOString(),
      description: `Barrier check-in confirmed for slot ${bookingData.slotId}.`,
    };
    transaction.set(eventRef, event);

    // Record trip telemetry for learned ETA model logging
    const bookedAtDate = new Date(bookingData.bookedAt);
    const actualTravelMinutes = request.actualTravelMin ??
      Math.max(3, Math.round((now.getTime() - bookedAtDate.getTime()) / (60 * 1000)));

    const telemetryRef = db.collection('trip_telemetry').doc(`TRIP-${bookingData.id}`);
    transaction.set(telemetryRef, {
      id: telemetryRef.id,
      tripId: `TRIP-${bookingData.id}`,
      bookingId: bookingData.id,
      userId: bookingData.userId,
      lotId: bookingData.lotId,
      predictedEtaMinBaseline: bookingData.predictedEtaMinBaseline ?? 15,
      predictedEtaMinProvider: bookingData.predictedEtaMinProvider ?? 12,
      predictedEtaMinCorrected: bookingData.predictedEtaMinCorrected ?? 14,
      actualTravelMin: actualTravelMinutes,
      departureTime: bookingData.bookedAt,
      arrivalTime: now.toISOString(),
      dayOfWeek: bookedAtDate.getDay() === 0 ? 7 : bookedAtDate.getDay(),
      hour: bookedAtDate.getHours(),
      distanceKm: 5.0,
      originZone: 'Malabe_Kaduwela',
      weatherFlag: 0,
      holidayFlag: 0,
      modelVersion: bookingData.modelVersion ?? 'v1.0.0-linear',
      loggedAt: now.toISOString(),
    });

    return { success: true, bookingId: bookingData.id, slotId: bookingData.slotId };
  });
}

export async function extendHoldLogic(
  db: admin.firestore.Firestore,
  authUid: string,
  request: ExtendHoldRequest
): Promise<{ success: boolean; holdExpiresAt: string; extensionsCount: number; extensionFee: number }> {
  const { bookingId, minutes = 15 } = request;
  if (!bookingId) {
    throw new HttpsError('invalid-argument', 'Missing bookingId.');
  }

  const now = new Date();
  const bookingRef = db.collection('bookings').doc(bookingId);

  return await db.runTransaction(async (transaction) => {
    const bookingDoc = await transaction.get(bookingRef);
    if (!bookingDoc.exists) {
      throw new HttpsError('not-found', `Booking ${bookingId} not found.`);
    }

    const booking = bookingDoc.data() as BookingDocument;
    if (booking.userId !== authUid && authUid !== 'admin') {
      throw new HttpsError('permission-denied', 'Permission denied.');
    }

    const currentExtensions = booking.extensionsCount ?? 0;
    if (currentExtensions >= 2) {
      throw new HttpsError('failed-precondition', 'Maximum of 2 hold extensions reached.');
    }

    if (booking.status === 'cancelled' || booking.status === 'auto_released' || booking.status === 'completed') {
      throw new HttpsError('failed-precondition', `Cannot extend a ${booking.status} booking.`);
    }

    const currentExpiry = new Date(booking.holdExpiresAt);
    const baseTime = currentExpiry.getTime() > now.getTime() ? currentExpiry : now;
    const newHoldExpiresAt = new Date(baseTime.getTime() + minutes * 60 * 1000);
    const newExtensionsCount = currentExtensions + 1;
    const feeAddition = 50; // LKR 50 per extension
    const newExtensionFee = (booking.extensionFee ?? 0) + feeAddition;

    const updatedCharges: BookingChargeDocument[] = [...(booking.charges || [])];
    updatedCharges.push({
      id: `CHG-${bookingId}-EXT-${newExtensionsCount}`,
      type: 'extension',
      amount: feeAddition,
      currency: 'LKR',
      timestamp: now.toISOString(),
      description: `Hold arrival extension (+${minutes} min)`,
    });

    transaction.update(bookingRef, {
      holdExpiresAt: newHoldExpiresAt.toISOString(),
      extensionsCount: newExtensionsCount,
      extensionFee: newExtensionFee,
      charges: updatedCharges,
      status: 'extended',
    });

    const eventRef = db.collection('parking_events').doc(`EVT-${Date.now()}-${Math.floor(100 + Math.random() * 900)}`);
    const event: ParkingEventDocument = {
      id: eventRef.id,
      bookingId,
      userId: authUid,
      lotId: booking.lotId,
      slotId: booking.slotId,
      eventType: 'hold_extended',
      timestamp: now.toISOString(),
      description: `Hold extended by ${minutes} min (Fee +LKR ${feeAddition}). New expiry: ${newHoldExpiresAt.toISOString()}`,
      metadata: {
        extensionsCount: newExtensionsCount,
        extensionFee: newExtensionFee,
      },
    };
    transaction.set(eventRef, event);

    return {
      success: true,
      holdExpiresAt: newHoldExpiresAt.toISOString(),
      extensionsCount: newExtensionsCount,
      extensionFee: newExtensionFee,
    };
  });
}

export async function acceptUpgradeLogic(
  db: admin.firestore.Firestore,
  authUid: string,
  request: AcceptUpgradeRequest
): Promise<{
  success: boolean;
  bookingId: string;
  newSlotId: string;
  oldSlotId: string;
  distanceSavedMeters: number;
  qrToken: string;
}> {
  const { bookingId, newSlotId, currentEtaMinutes = 5 } = request;
  if (!bookingId || !newSlotId) {
    throw new HttpsError('invalid-argument', 'Missing bookingId or newSlotId.');
  }

  if (currentEtaMinutes > 10) {
    throw new HttpsError(
      'failed-precondition',
      `Upgrade window closed: In-transit dynamic upgrades are only offered within 10 minutes of arrival (Current ETA: ${currentEtaMinutes}m).`
    );
  }

  const now = new Date();
  const bookingRef = db.collection('bookings').doc(bookingId);

  return await db.runTransaction(async (transaction) => {
    const bookingDoc = await transaction.get(bookingRef);
    if (!bookingDoc.exists) {
      throw new HttpsError('not-found', `Booking ${bookingId} not found.`);
    }

    const booking = bookingDoc.data() as BookingDocument;
    if (booking.userId !== authUid && authUid !== 'admin') {
      throw new HttpsError('permission-denied', 'Permission denied.');
    }

    if (booking.status !== 'reserved' && booking.status !== 'upgraded' && booking.status !== 'extended') {
      throw new HttpsError('failed-precondition', `Cannot upgrade booking with status ${booking.status}.`);
    }

    const oldSlotId = booking.slotId;
    if (oldSlotId === newSlotId) {
      throw new HttpsError('invalid-argument', 'New slot cannot be the same as current slot.');
    }

    const lotRef = db.collection('parking_lots').doc(booking.lotId);
    const oldSlotRef = lotRef.collection('slots').doc(oldSlotId);
    const newSlotRef = lotRef.collection('slots').doc(newSlotId);

    const [oldSlotDoc, newSlotDoc, lotDoc] = await Promise.all([
      transaction.get(oldSlotRef),
      transaction.get(newSlotRef),
      transaction.get(lotRef),
    ]);

    if (!newSlotDoc.exists) {
      throw new HttpsError('not-found', `Upgrade slot ${newSlotId} not found.`);
    }

    const newSlot = newSlotDoc.data() as ParkingSlotDocument;
    if (newSlot.state !== 'available') {
      throw new HttpsError(
        'already-exists',
        `Upgrade slot ${newSlotId} is no longer available (taken by another driver).`
      );
    }

    // Vehicle compatibility
    if (!isSizeCompatible(newSlot.size, booking.vehicleSize)) {
      throw new HttpsError(
        'failed-precondition',
        `Upgrade slot size (${newSlot.size}) is incompatible with vehicle size (${booking.vehicleSize}).`
      );
    }

    const oldSlot = oldSlotDoc.exists ? (oldSlotDoc.data() as ParkingSlotDocument) : null;
    const oldWalking = oldSlot?.walkingDistanceMeters ?? 160;
    const distanceSaved = Math.max(0, oldWalking - newSlot.walkingDistanceMeters);

    // Verify improvement threshold (>= 50m walk saved or score threshold)
    if (distanceSaved < 50) {
      // Allow if score calculation confirms threshold
      const lot = lotDoc.data() as ParkingLotDocument;
      const oldScore = scoreSlot(
        oldSlot ?? {
          id: oldSlotId,
          size: booking.vehicleSize,
          type: 'normal',
          walkingDistanceMeters: oldWalking,
          state: 'reserved',
        },
        lot,
        { size: booking.vehicleSize },
        { preferNearEntrance: true, coveredParkingOnly: false }
      );
      const newScore = scoreSlot(
        newSlot,
        lot,
        { size: booking.vehicleSize },
        { preferNearEntrance: true, coveredParkingOnly: false }
      );

      const improvementPercent = oldScore.totalScore > 0
        ? ((newScore.totalScore - oldScore.totalScore) / oldScore.totalScore) * 100.0
        : 0;

      if (distanceSaved < 50 && improvementPercent < 20.0) {
        throw new HttpsError(
          'failed-precondition',
          `Upgrade candidate does not satisfy minimum threshold (Saved: ${distanceSaved}m, Score +${improvementPercent.toFixed(1)}%).`
        );
      }
    }

    // Rotate QR Token for the new slot using signed HMAC token
    const newQrToken = generateSignedQrToken({
      bookingId,
      slotId: newSlotId,
      arrivalTime: new Date(booking.arrivalTime),
      holdExpiresAt: new Date(booking.holdExpiresAt),
    });

    // Update old slot -> available
    transaction.update(oldSlotRef, {
      state: 'available',
      bookingId: null,
      updatedAt: now.toISOString(),
      updatedBy: 'function',
    });

    // Update new slot -> reserved
    transaction.update(newSlotRef, {
      state: 'reserved',
      bookingId: booking.id,
      updatedAt: now.toISOString(),
      updatedBy: 'function',
    });

    // Update booking document
    const history = booking.slotSwapHistory ?? [];
    history.push({
      previousSlotId: oldSlotId,
      newSlotId,
      timestamp: now.toISOString(),
      distanceSavedMeters: distanceSaved,
      scoreImprovementPercent: 25.0,
    });

    transaction.update(bookingRef, {
      slotId: newSlotId,
      originalSlotId: booking.originalSlotId || oldSlotId,
      status: 'upgraded',
      distanceSavedMeters: (booking.distanceSavedMeters ?? 0) + distanceSaved,
      qrToken: newQrToken,
      slotSwapHistory: history,
    });

    // Record audit event
    const eventRef = db.collection('parking_events').doc(`EVT-${Date.now()}-${Math.floor(100 + Math.random() * 900)}`);
    const event: ParkingEventDocument = {
      id: eventRef.id,
      bookingId: booking.id,
      userId: authUid,
      lotId: booking.lotId,
      slotId: newSlotId,
      eventType: 'slot_upgraded',
      timestamp: now.toISOString(),
      description: `Atomic swap: Driver upgraded from ${oldSlotId} to ${newSlotId} (saved ${distanceSaved}m walk).`,
      metadata: {
        oldSlotId,
        newSlotId,
        distanceSavedMeters: distanceSaved,
      },
    };
    transaction.set(eventRef, event);

    return {
      success: true,
      bookingId: booking.id,
      newSlotId,
      oldSlotId,
      distanceSavedMeters: distanceSaved,
      qrToken: newQrToken,
    };
  });
}
