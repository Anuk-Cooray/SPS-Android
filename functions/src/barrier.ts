// barrier.ts
// Smart Parking (J26-IT-335) — IoT Barrier Gate QR Token Validation & Access Control
// Cryptographic HMAC-SHA256 signature verification, device-slot geofencing, single-use check

import * as admin from 'firebase-admin';
import {
  ValidateQrRequest,
  ValidateQrResponse,
  BookingDocument,
  DeviceDocument,
  ParkingEventDocument,
} from './types';
import { verifySignedQrToken } from './hmac_token';

export async function validateQrLogic(
  db: admin.firestore.Firestore,
  device: DeviceDocument,
  request: ValidateQrRequest
): Promise<ValidateQrResponse> {
  const { qrToken, barrierId } = request;

  if (!qrToken || typeof qrToken !== 'string') {
    return {
      allow: false,
      code: 'INVALID_SIGNATURE',
      reason: 'QR token is missing or malformed.',
    };
  }

  const now = new Date();

  // 1. Cryptographic HMAC Token Verification (timing-safe)
  const verification = verifySignedQrToken(qrToken, { referenceTime: now });
  if (!verification.valid || !verification.payload) {
    if (verification.code === 'EXPIRED_OR_PREMATURE') {
      return {
        allow: false,
        code: 'EXPIRED_OR_PREMATURE',
        reason: verification.reason || 'Token is outside valid arrival/hold window.',
      };
    }
    return {
      allow: false,
      code: 'INVALID_SIGNATURE',
      reason: verification.reason || 'Cryptographic HMAC signature mismatch.',
    };
  }

  const { bookingId, slotId: tokenSlotId } = verification.payload;

  // 2. Geofencing: Check if barrier's designated lotId/slotId matches token
  if (device.slotId && device.slotId !== tokenSlotId) {
    return {
      allow: false,
      code: 'WRONG_SLOT',
      bookingId,
      slotId: tokenSlotId,
      reason: `Barrier ${barrierId} controls bay ${device.slotId}, but token is allocated for bay ${tokenSlotId}.`,
    };
  }

  // 3. Database Execution inside Transaction
  const bookingRef = db.collection('bookings').doc(bookingId);

  return await db.runTransaction(async (transaction) => {
    const bookingDoc = await transaction.get(bookingRef);
    if (!bookingDoc.exists) {
      return {
        allow: false,
        code: 'BOOKING_NOT_FOUND',
        reason: `Booking ${bookingId} does not exist in the reservation database.`,
      };
    }

    const bookingData = bookingDoc.data() as BookingDocument;

    // Check device lot match
    if (device.lotId && device.lotId !== bookingData.lotId) {
      return {
        allow: false,
        code: 'WRONG_SLOT',
        bookingId,
        slotId: bookingData.slotId,
        reason: `Barrier ${barrierId} is situated at lot ${device.lotId}, but booking is for lot ${bookingData.lotId}.`,
      };
    }

    // Check token slot match against current active slot in booking
    if (bookingData.slotId !== tokenSlotId) {
      return {
        allow: false,
        code: 'WRONG_SLOT',
        bookingId,
        slotId: bookingData.slotId,
        reason: `Token corresponds to outdated bay ${tokenSlotId}. Active bay is ${bookingData.slotId}.`,
      };
    }

    // Check single-use
    if (bookingData.status === 'checkedIn' || bookingData.status === 'completed') {
      return {
        allow: false,
        code: 'TOKEN_ALREADY_USED',
        bookingId,
        slotId: bookingData.slotId,
        reason: 'This QR token has already been validated and marked checked-in.',
      };
    }

    // Check active status
    if (bookingData.status === 'cancelled' || bookingData.status === 'auto_released') {
      return {
        allow: false,
        code: 'BOOKING_INACTIVE',
        bookingId,
        slotId: bookingData.slotId,
        reason: `Reservation is no longer active (Status: ${bookingData.status}).`,
      };
    }

    const slotRef = db
      .collection('parking_lots')
      .doc(bookingData.lotId)
      .collection('slots')
      .doc(bookingData.slotId);

    // Commit atomic check-in
    transaction.update(bookingRef, {
      status: 'checkedIn',
      checkedInAt: now.toISOString(),
    });

    transaction.update(slotRef, {
      state: 'occupied',
      updatedAt: now.toISOString(),
      updatedBy: 'cctv',
    });

    // Log checked-in parking event
    const eventRef = db.collection('parking_events').doc(`EVT-${Date.now()}`);
    const eventDoc: ParkingEventDocument = {
      id: eventRef.id,
      bookingId: bookingData.id,
      userId: bookingData.userId,
      lotId: bookingData.lotId,
      slotId: bookingData.slotId,
      eventType: 'checked_in',
      timestamp: now.toISOString(),
      description: `Barrier ${barrierId} verified HMAC QR token. Vehicle checked in for bay ${bookingData.slotId}.`,
      metadata: { barrierId, vehiclePlate: bookingData.vehiclePlate },
    };
    transaction.set(eventRef, eventDoc);

    // Record trip telemetry
    const bookedAtDate = new Date(bookingData.bookedAt);
    const actualTravelMinutes =
      request.actualTravelMin ??
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

    return {
      allow: true,
      code: 'OK',
      bookingId: bookingData.id,
      lotId: bookingData.lotId,
      slotId: bookingData.slotId,
      vehiclePlate: bookingData.vehiclePlate,
      message: `Access granted at barrier ${barrierId}. Proceed to Bay ${bookingData.slotId}.`,
    };
  });
}
