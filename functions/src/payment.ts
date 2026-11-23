// payment.ts
// Smart Parking (J26-IT-335) — Smart Billing & Exit Payment Settlement
// Enforces paymentRef idempotency, server-side exit fee computation, and atomic slot release

import * as admin from 'firebase-admin';
import {
  PaymentCompletedRequest,
  PaymentCompletedResponse,
  BookingDocument,
  ParkingLotDocument,
  ParkingSlotDocument,
  ProcessedPaymentDocument,
  BookingChargeDocument,
  ParkingEventDocument,
} from './types';

export async function paymentCompletedLogic(
  db: admin.firestore.Firestore,
  serviceDeviceId: string,
  request: PaymentCompletedRequest
): Promise<PaymentCompletedResponse> {
  const { bookingId, paymentRef, amountPaid, paymentMethod, timestamp } = request;

  if (!bookingId || !paymentRef || amountPaid === undefined || !paymentMethod) {
    throw new Error('INVALID_PAYLOAD: Missing required payment fields.');
  }

  const exitDate = timestamp ? new Date(timestamp) : new Date();
  if (isNaN(exitDate.getTime())) {
    throw new Error('INVALID_TIMESTAMP: Malformed payment timestamp.');
  }

  // 1. Idempotency Check: return original response if paymentRef already processed
  const processedRef = db.collection('processed_payments').doc(paymentRef);
  const existingPayment = await processedRef.get();
  if (existingPayment.exists) {
    const data = existingPayment.data() as ProcessedPaymentDocument;
    const bookingDoc = await db.collection('bookings').doc(data.bookingId).get();
    const slotFreed = bookingDoc.exists ? (bookingDoc.data() as BookingDocument).slotId : 'bay';

    return {
      success: true,
      bookingId: data.bookingId,
      paymentRef: data.paymentRef,
      totalCharged: data.amountPaid,
      amountPaid: data.amountPaid,
      status: 'completed',
      slotFreed,
      receiptNo: data.receiptNo,
      isIdempotentReplay: true,
    };
  }

  // 2. Transactional Billing Settlement
  const bookingRef = db.collection('bookings').doc(bookingId);

  return await db.runTransaction(async (transaction) => {
    const bookingDoc = await transaction.get(bookingRef);
    if (!bookingDoc.exists) {
      throw new Error(`BOOKING_NOT_FOUND: Booking ${bookingId} does not exist.`);
    }

    const bookingData = bookingDoc.data() as BookingDocument;

    if (bookingData.status === 'completed') {
      throw new Error(`ALREADY_SETTLED: Booking ${bookingId} has already been settled and completed.`);
    }

    const lotRef = db.collection('parking_lots').doc(bookingData.lotId);
    const slotRef = lotRef.collection('slots').doc(bookingData.slotId);

    const [lotDoc, slotDoc] = await Promise.all([
      transaction.get(lotRef),
      transaction.get(slotRef),
    ]);

    if (!lotDoc.exists) {
      throw new Error(`LOT_NOT_FOUND: Parking lot ${bookingData.lotId} not found.`);
    }

    const lotData = lotDoc.data() as ParkingLotDocument;
    const slotData = slotDoc.exists ? (slotDoc.data() as ParkingSlotDocument) : null;

    // 3. Server-Side Final Fee Computation
    // Duration between checkedInAt (or bookedAt fallback) and exit time, rounded up to hourly blocks
    const checkInDate = bookingData.checkedInAt
      ? new Date(bookingData.checkedInAt)
      : new Date(bookingData.bookedAt);

    const elapsedMs = Math.max(0, exitDate.getTime() - checkInDate.getTime());
    // 1-hour billing block (round up)
    const billedHours = Math.max(1, Math.ceil(elapsedMs / (60 * 60 * 1000)));
    const baseParkingFee = billedHours * (lotData.hourlyRate || 100);
    const extensionFee = bookingData.extensionFee || 0;
    const totalCharges = baseParkingFee + extensionFee;

    if (amountPaid < totalCharges) {
      throw new Error(
        `INSUFFICIENT_PAYMENT: Amount paid (LKR ${amountPaid}) is less than total charges (LKR ${totalCharges}).`
      );
    }

    // Itemized charges array
    const charges: BookingChargeDocument[] = [
      {
        id: `CHG-${bookingId}-PARK`,
        type: 'parking',
        amount: baseParkingFee,
        currency: 'LKR',
        timestamp: exitDate.toISOString(),
        description: `Parking stay (${billedHours} hr @ LKR ${lotData.hourlyRate || 100}/hr)`,
      },
    ];

    if (extensionFee > 0) {
      charges.push({
        id: `CHG-${bookingId}-EXT`,
        type: 'extension',
        amount: extensionFee,
        currency: 'LKR',
        timestamp: exitDate.toISOString(),
        description: `Hold arrival extension fees (${bookingData.extensionsCount || 1} extension(s))`,
      });
    }

    const receiptNo = `REC-${Date.now()}-${bookingId.slice(-4)}`;

    // 4. Atomic Updates
    // Update booking status
    transaction.update(bookingRef, {
      status: 'completed',
      completedAt: exitDate.toISOString(),
      finalFee: totalCharges,
      charges,
    });

    // Free the slot
    if (slotDoc && slotDoc.exists) {
      transaction.update(slotRef, {
        state: 'available',
        bookingId: null,
        conflictFlag: false,
        updatedAt: exitDate.toISOString(),
        updatedBy: 'payment',
      });
    }

    // Increment free slots counter only on confirmed state transition
    if (slotData && slotData.state !== 'available') {
      const newFreeSlots = Math.min(lotData.totalSlots, lotData.freeSlots + 1);
      transaction.update(lotRef, {
        freeSlots: newFreeSlots,
        updatedAt: exitDate.toISOString(),
      });
    }

    // Record processed payment for idempotency
    const processedDoc: ProcessedPaymentDocument = {
      paymentRef,
      bookingId,
      amountPaid,
      paymentMethod,
      processedAt: exitDate.toISOString(),
      receiptNo,
    };
    transaction.set(processedRef, processedDoc);

    // Log completed parking event
    const eventRef = db.collection('parking_events').doc(`EVT-${Date.now()}`);
    const eventDoc: ParkingEventDocument = {
      id: eventRef.id,
      bookingId,
      userId: bookingData.userId,
      lotId: bookingData.lotId,
      slotId: bookingData.slotId,
      eventType: 'completed',
      timestamp: exitDate.toISOString(),
      description: `Payment settled via ${paymentMethod} (LKR ${amountPaid}). Bay ${bookingData.slotId} freed.`,
      metadata: { paymentRef, receiptNo, totalCharges, billedHours, serviceDeviceId },
    };
    transaction.set(eventRef, eventDoc);

    return {
      success: true,
      bookingId,
      paymentRef,
      totalCharged: totalCharges,
      amountPaid,
      status: 'completed',
      slotFreed: bookingData.slotId,
      receiptNo,
    };
  });
}
