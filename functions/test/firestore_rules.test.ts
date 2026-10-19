// firestore_rules.test.ts
// Smart Parking (J26-IT-335) — Security Rules Verification against Firebase Firestore Emulator

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import type { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import * as fs from 'fs';
import * as path from 'path';

describe('Firestore Security Rules Unit Tests', () => {
  let testEnv: RulesTestEnvironment;
  const PROJECT_ID = 'demo-sps-rules-test';

  before(async () => {
    let rulesPath = path.resolve(process.cwd(), 'firestore.rules');
    if (!fs.existsSync(rulesPath)) {
      rulesPath = path.resolve(process.cwd(), '../firestore.rules');
    }
    const rulesContent = fs.readFileSync(rulesPath, 'utf8');

    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: rulesContent,
        host: '127.0.0.1',
        port: 8080,
      },
    });
  });

  after(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  beforeEach(async () => {
    if (testEnv) {
      await testEnv.clearFirestore();
    }
  });

  describe('Parking Lots & Subcollection Slots', () => {
    it('allows anyone to read parking lots and slots', async () => {
      // Setup lot and slot using admin context
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.collection('parking_lots').doc('lot-main').set({
          name: 'Main Building Lot',
          freeSlots: 10,
          totalSlots: 24,
        });
        await db
          .collection('parking_lots')
          .doc('lot-main')
          .collection('slots')
          .doc('A-01')
          .set({
            state: 'available',
            walkingDistanceMeters: 40,
            size: 'medium',
          });
      });

      const unauthenticatedDb = testEnv.unauthenticatedContext().firestore();
      await assertSucceeds(
        unauthenticatedDb.collection('parking_lots').doc('lot-main').get()
      );
      await assertSucceeds(
        unauthenticatedDb
          .collection('parking_lots')
          .doc('lot-main')
          .collection('slots')
          .doc('A-01')
          .get()
      );
    });

    it('denies clients from modifying parking lots or slot state directly', async () => {
      const clientDb = testEnv.authenticatedContext('user-001').firestore();

      // Attempt direct write to lot
      await assertFails(
        clientDb.collection('parking_lots').doc('lot-main').set({
          name: 'Hacked Lot',
          freeSlots: 99,
        })
      );

      // Attempt direct state mutation on slot
      await assertFails(
        clientDb
          .collection('parking_lots')
          .doc('lot-main')
          .collection('slots')
          .doc('A-01')
          .update({
            state: 'reserved',
            bookingId: 'BK-HACK',
          })
      );
    });
  });

  describe('Bookings Authority & Privacy', () => {
    it('allows a driver to read only their own booking document', async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db.collection('bookings').doc('BK-USER-1').set({
          userId: 'user-001',
          slotId: 'A-01',
          status: 'reserved',
        });
        await db.collection('bookings').doc('BK-USER-2').set({
          userId: 'user-002',
          slotId: 'B-02',
          status: 'reserved',
        });
      });

      const user1Db = testEnv.authenticatedContext('user-001').firestore();
      const user2Db = testEnv.authenticatedContext('user-002').firestore();

      // User 1 reads their own booking -> Succeeds
      await assertSucceeds(user1Db.collection('bookings').doc('BK-USER-1').get());

      // User 1 reads User 2's booking -> Fails
      await assertFails(user1Db.collection('bookings').doc('BK-USER-2').get());

      // User 2 reads their own booking -> Succeeds
      await assertSucceeds(user2Db.collection('bookings').doc('BK-USER-2').get());
    });

    it('denies clients from creating or updating booking documents directly', async () => {
      const clientDb = testEnv.authenticatedContext('user-001').firestore();

      await assertFails(
        clientDb.collection('bookings').doc('BK-CLIENT-WRITE').set({
          userId: 'user-001',
          slotId: 'A-01',
          status: 'reserved',
        })
      );
    });
  });

  describe('Audit Telemetry Events', () => {
    it('denies clients from forging or writing audit events directly', async () => {
      const clientDb = testEnv.authenticatedContext('user-001').firestore();

      await assertFails(
        clientDb.collection('parking_events').doc('EVT-FAKE').set({
          userId: 'user-001',
          eventType: 'checked_in',
          timestamp: new Date().toISOString(),
        })
      );
    });
  });
});
