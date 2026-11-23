// hmac_token.ts
// Smart Parking (J26-IT-335) — Server-Side Cryptographic QR Token Signing & Verification
// Single-use, time-windowed HMAC-SHA256 tokens with timing-attack defense

import * as crypto from 'crypto';
import { defineSecret } from 'firebase-functions/params';

// Firebase Secret Manager declaration
export const hmacSecretParam = defineSecret('HMAC_SECRET_KEY');

const DEMO_TEST_SECRET = 'sps_research_hmac_secret_2026';

/**
 * Retrieves the cryptographic secret key.
 * Enforces production fail-fast: throws if secret is missing unless running under emulator or test.
 */
export function getHmacSecret(): string {
  try {
    const val = hmacSecretParam.value();
    if (val && val.trim().length > 0) {
      return val;
    }
  } catch (_) {
    // Secret access via .value() throws if secret not bound
  }

  const isEmulatorOrTest =
    process.env.FUNCTIONS_EMULATOR === 'true' ||
    Boolean(process.env.FIRESTORE_EMULATOR_HOST) ||
    process.env.NODE_ENV === 'test';

  if (isEmulatorOrTest) {
    return DEMO_TEST_SECRET;
  }

  throw new Error(
    'CRITICAL: HMAC_SECRET_KEY secret is required in deployed environment but is missing or unbound.'
  );
}

export interface SignedQrTokenPayload {
  version: string;
  bookingId: string;
  slotId: string;
  validFromSec: number;
  validUntilSec: number;
  nonce: string;
}

export interface VerificationResult {
  valid: boolean;
  code: 'OK' | 'INVALID_FORMAT' | 'INVALID_SIGNATURE' | 'EXPIRED_OR_PREMATURE';
  reason?: string;
  payload?: SignedQrTokenPayload;
}

/**
 * Generates an authoritative, tamper-proof HMAC-SHA256 signed QR token string.
 * Format: SPS.v1.<bookingId>.<slotId>.<validFromSec>.<validUntilSec>.<nonce>.<sigHex>
 */
export function generateSignedQrToken(params: {
  bookingId: string;
  slotId: string;
  arrivalTime: Date;
  holdExpiresAt: Date;
  secretOverride?: string;
}): string {
  const { bookingId, slotId, arrivalTime, holdExpiresAt, secretOverride } = params;
  const secret = secretOverride || getHmacSecret();

  // Token valid starting 30 minutes before arrival through hold expiration
  const validFromSec = Math.floor((arrivalTime.getTime() - 30 * 60 * 1000) / 1000);
  const validUntilSec = Math.floor(holdExpiresAt.getTime() / 1000);
  const nonce = crypto.randomBytes(4).toString('hex');

  const unsignedBody = `SPS.v1.${bookingId}.${slotId}.${validFromSec}.${validUntilSec}.${nonce}`;
  const signatureHex = crypto
    .createHmac('sha256', secret)
    .update(unsignedBody)
    .digest('hex');

  return `${unsignedBody}.${signatureHex}`;
}

/**
 * Cryptographically verifies an HMAC-signed QR token using timingSafeEqual.
 * Validates format, signature integrity, and active time-window.
 */
export function verifySignedQrToken(
  token: string,
  options?: { secretOverride?: string; referenceTime?: Date }
): VerificationResult {
  if (!token || typeof token !== 'string') {
    return {
      valid: false,
      code: 'INVALID_FORMAT',
      reason: 'Token is empty or invalid type.',
    };
  }

  const parts = token.trim().split('.');
  // Expect: ['SPS', 'v1', bookingId, slotId, validFromSec, validUntilSec, nonce, sigHex]
  if (parts.length !== 8 || parts[0] !== 'SPS' || parts[1] !== 'v1') {
    return {
      valid: false,
      code: 'INVALID_FORMAT',
      reason: 'Token does not match SPS v1 format specification.',
    };
  }

  const [prefix, version, bookingId, slotId, validFromStr, validUntilStr, nonce, receivedSigHex] = parts;
  const unsignedBody = `${prefix}.${version}.${bookingId}.${slotId}.${validFromStr}.${validUntilStr}.${nonce}`;

  const secret = options?.secretOverride || getHmacSecret();
  const expectedSigHex = crypto
    .createHmac('sha256', secret)
    .update(unsignedBody)
    .digest('hex');

  const receivedSigBuf = Buffer.from(receivedSigHex, 'hex');
  const expectedSigBuf = Buffer.from(expectedSigHex, 'hex');

  // Constant-time comparison preventing timing attacks
  if (
    receivedSigBuf.length !== expectedSigBuf.length ||
    !crypto.timingSafeEqual(receivedSigBuf, expectedSigBuf)
  ) {
    return {
      valid: false,
      code: 'INVALID_SIGNATURE',
      reason: 'Cryptographic signature mismatch. Token is forged or invalid.',
    };
  }

  const validFromSec = parseInt(validFromStr, 10);
  const validUntilSec = parseInt(validUntilStr, 10);
  if (isNaN(validFromSec) || isNaN(validUntilSec)) {
    return {
      valid: false,
      code: 'INVALID_FORMAT',
      reason: 'Invalid timestamp encodings in token payload.',
    };
  }

  const nowSec = Math.floor((options?.referenceTime || new Date()).getTime() / 1000);
  if (nowSec < validFromSec || nowSec > validUntilSec) {
    return {
      valid: false,
      code: 'EXPIRED_OR_PREMATURE',
      reason: `Current time (${new Date(nowSec * 1000).toISOString()}) is outside valid window [${new Date(
        validFromSec * 1000
      ).toISOString()} - ${new Date(validUntilSec * 1000).toISOString()}].`,
      payload: { version, bookingId, slotId, validFromSec, validUntilSec, nonce },
    };
  }

  return {
    valid: true,
    code: 'OK',
    payload: {
      version,
      bookingId,
      slotId,
      validFromSec,
      validUntilSec,
      nonce,
    },
  };
}
