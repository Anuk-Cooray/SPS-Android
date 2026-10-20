// otp.ts
// Smart Parking (J26-IT-335) — Server-Side Email OTP Issuance & Verification
// Codes are generated with a CSPRNG, stored only as HMAC digests in /email_verifications
// (client access denied by rules), attempt-limited, single-use, and time-boxed.

import * as admin from 'firebase-admin';
import * as crypto from 'crypto';
import { HttpsError } from 'firebase-functions/v2/https';
import { getHmacSecret } from './hmac_token';

export const OTP_TTL_MS = 5 * 60 * 1000;
export const OTP_MAX_ATTEMPTS = 5;
export const OTP_RESEND_COOLDOWN_MS = 30 * 1000;

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function normalizeEmail(raw: unknown): string {
  if (typeof raw !== 'string') {
    throw new HttpsError('invalid-argument', 'A valid email address is required.');
  }
  const email = raw.trim().toLowerCase();
  if (email.length > 254 || !EMAIL_PATTERN.test(email)) {
    throw new HttpsError('invalid-argument', 'A valid email address is required.');
  }
  return email;
}

export function hashOtp(email: string, code: string, secretOverride?: string): string {
  return crypto
    .createHmac('sha256', secretOverride || getHmacSecret())
    .update(`otp:${email}:${code}`)
    .digest('hex');
}

export interface VerificationRecord {
  email: string;
  otpHash: string;
  createdAt: string;
  expiresAt: string;
  attempts: number;
  consumed: boolean;
}

/**
 * Issues a fresh 6-digit code for the email and hands it to `deliver`.
 * Returns the code so callers may expose it in emulator demo mode only.
 */
export async function requestEmailOtpLogic(
  db: admin.firestore.Firestore,
  rawEmail: unknown,
  deliver: (email: string, code: string) => Promise<void>,
  now: Date = new Date()
): Promise<{ email: string; code: string; expiresAt: string }> {
  const email = normalizeEmail(rawEmail);
  const ref = db.collection('email_verifications').doc(email);
  const code = crypto.randomInt(0, 1_000_000).toString().padStart(6, '0');
  const expiresAt = new Date(now.getTime() + OTP_TTL_MS).toISOString();

  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (snap.exists) {
      const existing = snap.data() as VerificationRecord;
      const createdMs = Date.parse(existing.createdAt);
      if (!isNaN(createdMs) && now.getTime() - createdMs < OTP_RESEND_COOLDOWN_MS) {
        throw new HttpsError('resource-exhausted', 'Please wait before requesting another code.');
      }
    }

    const record: VerificationRecord = {
      email,
      otpHash: hashOtp(email, code),
      createdAt: now.toISOString(),
      expiresAt,
      attempts: 0,
      consumed: false,
    };
    transaction.set(ref, record);
  });

  await deliver(email, code);
  return { email, code, expiresAt };
}

type VerifyOutcome = 'OK' | 'NOT_FOUND' | 'CONSUMED' | 'EXPIRED' | 'LOCKED' | 'MISMATCH';

/**
 * Verifies a code. Wrong guesses are counted atomically; after OTP_MAX_ATTEMPTS
 * the record is locked. A successful verification consumes the code.
 */
export async function verifyEmailOtpLogic(
  db: admin.firestore.Firestore,
  rawEmail: unknown,
  rawCode: unknown,
  now: Date = new Date()
): Promise<{ email: string }> {
  const email = normalizeEmail(rawEmail);
  if (typeof rawCode !== 'string' || !/^\d{6}$/.test(rawCode.trim())) {
    throw new HttpsError('invalid-argument', 'Verification code must be 6 digits.');
  }
  const code = rawCode.trim();
  const ref = db.collection('email_verifications').doc(email);

  // Outcome is returned (not thrown) so the attempt counter update commits
  const outcome = await db.runTransaction<VerifyOutcome>(async (transaction) => {
    const snap = await transaction.get(ref);
    if (!snap.exists) return 'NOT_FOUND';

    const record = snap.data() as VerificationRecord;
    if (record.consumed) return 'CONSUMED';
    if (now.getTime() > Date.parse(record.expiresAt)) return 'EXPIRED';
    if ((record.attempts ?? 0) >= OTP_MAX_ATTEMPTS) return 'LOCKED';

    const expected = Buffer.from(record.otpHash ?? '', 'hex');
    const received = Buffer.from(hashOtp(email, code), 'hex');
    const matches = expected.length === received.length && crypto.timingSafeEqual(expected, received);

    if (!matches) {
      transaction.update(ref, { attempts: (record.attempts ?? 0) + 1 });
      return 'MISMATCH';
    }

    transaction.update(ref, { consumed: true, verifiedAt: now.toISOString() });
    return 'OK';
  });

  switch (outcome) {
    case 'OK':
      return { email };
    case 'LOCKED':
      throw new HttpsError('resource-exhausted', 'Too many incorrect attempts. Request a new code.');
    case 'MISMATCH':
      throw new HttpsError('permission-denied', 'Incorrect verification code.');
    default:
      throw new HttpsError('failed-precondition', 'Verification code is invalid or expired. Request a new code.');
  }
}

/**
 * Queues the code for delivery via the Firebase "Trigger Email" extension (/mail collection).
 * The /mail collection is server-only under the Firestore rules.
 */
export async function queueOtpEmail(
  db: admin.firestore.Firestore,
  email: string,
  code: string
): Promise<void> {
  await db.collection('mail').add({
    to: email,
    message: {
      subject: 'Your Smart Parking verification code',
      text: `Your Smart Parking verification code is ${code}. It expires in 5 minutes.`,
    },
  });
}
