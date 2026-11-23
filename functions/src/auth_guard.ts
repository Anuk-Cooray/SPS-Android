// auth_guard.ts
// Smart Parking (J26-IT-335) — Caller Identity Resolution for Callable Functions
// Identity comes only from the verified Firebase Auth token. The demo fallback
// (caller-supplied userId) is honoured strictly under the emulator / test runner.

import { HttpsError } from 'firebase-functions/v2/https';

export interface CallerContext {
  uid: string;
  isAdmin: boolean;
}

/** Minimal shape of a callable request needed for identity resolution. */
export interface AuthLikeRequest {
  auth?: { uid: string; token?: Record<string, unknown> } | null;
  data?: any;
}

// Identities that must never be claimable through the demo fallback
const RESERVED_UIDS = new Set(['admin', 'system', 'cctv-gate', 'emulator-admin']);

export function isEmulatorOrTest(): boolean {
  return (
    process.env.FUNCTIONS_EMULATOR === 'true' ||
    Boolean(process.env.FIRESTORE_EMULATOR_HOST) ||
    process.env.NODE_ENV === 'test'
  );
}

/**
 * Resolves the calling user's uid and admin status.
 * Deployed: requires a verified Firebase Auth token; request.data.userId is ignored.
 * Emulator: unauthenticated calls may claim a non-reserved userId (defaults to 'demo-user').
 */
export function resolveCaller(
  request: AuthLikeRequest,
  allowDemoFallback: boolean = isEmulatorOrTest()
): CallerContext {
  const auth = request.auth;
  if (auth && typeof auth.uid === 'string' && auth.uid.length > 0) {
    const token = auth.token || {};
    return {
      uid: auth.uid,
      isAdmin: token.admin === true || token.role === 'admin',
    };
  }

  if (!allowDemoFallback) {
    throw new HttpsError('unauthenticated', 'Sign-in is required to call this function.');
  }

  const claimed = request.data?.userId;
  const uid =
    typeof claimed === 'string' && claimed.trim().length > 0 && !RESERVED_UIDS.has(claimed.trim())
      ? claimed.trim()
      : 'demo-user';
  return { uid, isAdmin: false };
}

/**
 * Requires an admin caller (custom claim admin == true or role == 'admin').
 * Under the emulator, unauthenticated calls are treated as admin so demo tooling keeps working.
 */
export function requireAdmin(
  request: AuthLikeRequest,
  allowDemoFallback: boolean = isEmulatorOrTest()
): CallerContext {
  if (!request.auth?.uid && allowDemoFallback) {
    return { uid: 'emulator-admin', isAdmin: true };
  }

  const caller = resolveCaller(request, false);
  if (!caller.isAdmin) {
    throw new HttpsError('permission-denied', 'Administrator privileges are required.');
  }
  return caller;
}
