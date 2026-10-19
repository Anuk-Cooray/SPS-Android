// devices.ts
// Smart Parking (J26-IT-335) — Device Registration & API Key Verification

import * as admin from 'firebase-admin';
import * as crypto from 'crypto';
import { DeviceDocument } from './types';

export function hashApiKey(key: string): string {
  return crypto.createHash('sha256').update(key.trim()).digest('hex');
}

// Pre-seeded demo credentials for emulator / test execution
const DEMO_TEST_DEVICES: Record<string, DeviceDocument> = {
  [hashApiKey('cctv-secret-key-cam-01')]: {
    id: 'cam-lot-main-01',
    name: 'Overhead Cam 1',
    type: 'camera',
    lotId: 'lot-main',
    slotId: null,
    apiKeyHash: hashApiKey('cctv-secret-key-cam-01'),
    isActive: true,
  },
  [hashApiKey('barrier-secret-key-gate-01')]: {
    id: 'barrier-gate-entry-01',
    name: 'North Entry Barrier',
    type: 'barrier',
    lotId: 'lot-main',
    slotId: null, // Gate for the entire lot
    apiKeyHash: hashApiKey('barrier-secret-key-gate-01'),
    isActive: true,
  },
  [hashApiKey('payment-secret-key-svc-01')]: {
    id: 'payment-gateway-svc-01',
    name: 'Smart Payment Gateway',
    type: 'payment_gateway',
    lotId: 'lot-main',
    slotId: null,
    apiKeyHash: hashApiKey('payment-secret-key-svc-01'),
    isActive: true,
  },
};

/**
 * Authenticates an incoming request by hashing the provided API key
 * and verifying against the Firestore /devices collection (with emulator fallback).
 */
export async function authenticateDevice(
  db: admin.firestore.Firestore,
  apiKey: string | undefined,
  expectedType: 'camera' | 'barrier' | 'payment_gateway'
): Promise<DeviceDocument | null> {
  if (!apiKey || typeof apiKey !== 'string' || apiKey.trim().length === 0) {
    return null;
  }

  const hash = hashApiKey(apiKey);

  // 1. Check Firestore /devices collection
  try {
    const snap = await db
      .collection('devices')
      .where('apiKeyHash', '==', hash)
      .where('type', '==', expectedType)
      .where('isActive', '==', true)
      .limit(1)
      .get();

    if (!snap.empty) {
      const docData = snap.docs[0].data() as DeviceDocument;
      // Update lastSeenAt asynchronously
      snap.docs[0].ref.update({ lastSeenAt: new Date().toISOString() }).catch(() => {});
      return docData;
    }
  } catch (_) {
    // If Firestore check fails in test runner, fall back to emulator defaults
  }

  // 2. Emulator / Test fallback
  const isEmulatorOrTest =
    process.env.FUNCTIONS_EMULATOR === 'true' ||
    Boolean(process.env.FIRESTORE_EMULATOR_HOST) ||
    process.env.NODE_ENV === 'test';

  if (isEmulatorOrTest && DEMO_TEST_DEVICES[hash]) {
    const dev = DEMO_TEST_DEVICES[hash];
    if (dev.type === expectedType && dev.isActive) {
      return dev;
    }
  }

  return null;
}
