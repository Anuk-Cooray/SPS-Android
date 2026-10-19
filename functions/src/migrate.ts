// migrate.ts
// Smart Parking (J26-IT-335) — Firestore Schema Migration & Seed Utility

import * as admin from 'firebase-admin';
import { ParkingSlotDocument, ParkingLotDocument } from './types';

export const SEED_LOTS: Array<ParkingLotDocument & { slots: ParkingSlotDocument[] }> = [
  {
    id: 'lot-main',
    name: 'Main Building Lot',
    campusZone: 'SLIIT Malabe Campus',
    latitude: 6.9147,
    longitude: 79.9729,
    distanceMeters: 80,
    hourlyRate: 100,
    totalSlots: 24,
    freeSlots: 12,
    openingHours: '06:00 AM - 10:00 PM',
    updatedAt: new Date().toISOString(),
    slots: [
      // Row A
      { id: 'A-01', lotId: 'lot-main', row: 'A', number: 1, size: 'medium', type: 'normal', walkingDistanceMeters: 160, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'A-02', lotId: 'lot-main', row: 'A', number: 2, size: 'medium', type: 'normal', walkingDistanceMeters: 140, state: 'available', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'A-03', lotId: 'lot-main', row: 'A', number: 3, size: 'medium', type: 'normal', walkingDistanceMeters: 110, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'A-04', lotId: 'lot-main', row: 'A', number: 4, size: 'medium', type: 'normal', walkingDistanceMeters: 80, state: 'blocked', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'A-05', lotId: 'lot-main', row: 'A', number: 5, size: 'medium', type: 'normal', walkingDistanceMeters: 60, state: 'available', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'A-06', lotId: 'lot-main', row: 'A', number: 6, size: 'medium', type: 'normal', walkingDistanceMeters: 40, state: 'available', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      // Row B
      { id: 'B-01', lotId: 'lot-main', row: 'B', number: 1, size: 'medium', type: 'normal', walkingDistanceMeters: 40, state: 'available', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'B-02', lotId: 'lot-main', row: 'B', number: 2, size: 'medium', type: 'normal', walkingDistanceMeters: 65, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'B-03', lotId: 'lot-main', row: 'B', number: 3, size: 'medium', type: 'normal', walkingDistanceMeters: 85, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'B-04', lotId: 'lot-main', row: 'B', number: 4, size: 'medium', type: 'normal', walkingDistanceMeters: 90, state: 'available', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'B-05', lotId: 'lot-main', row: 'B', number: 5, size: 'medium', type: 'normal', walkingDistanceMeters: 105, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'B-06', lotId: 'lot-main', row: 'B', number: 6, size: 'medium', type: 'normal', walkingDistanceMeters: 110, state: 'available', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      // Row C
      { id: 'C-01', lotId: 'lot-main', row: 'C', number: 1, size: 'medium', type: 'normal', walkingDistanceMeters: 120, state: 'available', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'C-02', lotId: 'lot-main', row: 'C', number: 2, size: 'medium', type: 'normal', walkingDistanceMeters: 130, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'C-03', lotId: 'lot-main', row: 'C', number: 3, size: 'medium', type: 'normal', walkingDistanceMeters: 135, state: 'available', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'C-04', lotId: 'lot-main', row: 'C', number: 4, size: 'medium', type: 'normal', walkingDistanceMeters: 140, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'C-05', lotId: 'lot-main', row: 'C', number: 5, size: 'medium', type: 'normal', walkingDistanceMeters: 145, state: 'available', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'C-06', lotId: 'lot-main', row: 'C', number: 6, size: 'medium', type: 'normal', walkingDistanceMeters: 150, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      // Row D
      { id: 'D-01', lotId: 'lot-main', row: 'D', number: 1, size: 'large', type: 'normal', walkingDistanceMeters: 155, state: 'available', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'D-02', lotId: 'lot-main', row: 'D', number: 2, size: 'large', type: 'normal', walkingDistanceMeters: 160, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'D-03', lotId: 'lot-main', row: 'D', number: 3, size: 'large', type: 'normal', walkingDistanceMeters: 165, state: 'available', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'D-04', lotId: 'lot-main', row: 'D', number: 4, size: 'large', type: 'normal', walkingDistanceMeters: 170, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'D-05', lotId: 'lot-main', row: 'D', number: 5, size: 'large', type: 'normal', walkingDistanceMeters: 175, state: 'available', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'D-06', lotId: 'lot-main', row: 'D', number: 6, size: 'large', type: 'normal', walkingDistanceMeters: 180, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
    ],
  },
  {
    id: 'lot-new-p2',
    name: 'New Building P2',
    campusZone: 'SLIIT Malabe Campus',
    latitude: 6.9135,
    longitude: 79.9715,
    distanceMeters: 240,
    hourlyRate: 80,
    totalSlots: 24,
    freeSlots: 4,
    openingHours: '06:00 AM - 10:00 PM',
    updatedAt: new Date().toISOString(),
    slots: [
      { id: 'A-01', lotId: 'lot-new-p2', row: 'A', number: 1, size: 'medium', type: 'normal', walkingDistanceMeters: 55, state: 'available', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'A-02', lotId: 'lot-new-p2', row: 'A', number: 2, size: 'medium', type: 'normal', walkingDistanceMeters: 75, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'A-03', lotId: 'lot-new-p2', row: 'A', number: 3, size: 'medium', type: 'normal', walkingDistanceMeters: 95, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'A-04', lotId: 'lot-new-p2', row: 'A', number: 4, size: 'medium', type: 'normal', walkingDistanceMeters: 115, state: 'blocked', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'A-05', lotId: 'lot-new-p2', row: 'A', number: 5, size: 'medium', type: 'normal', walkingDistanceMeters: 135, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'A-06', lotId: 'lot-new-p2', row: 'A', number: 6, size: 'medium', type: 'normal', walkingDistanceMeters: 155, state: 'available', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'B-01', lotId: 'lot-new-p2', row: 'B', number: 1, size: 'medium', type: 'normal', walkingDistanceMeters: 65, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'B-02', lotId: 'lot-new-p2', row: 'B', number: 2, size: 'medium', type: 'normal', walkingDistanceMeters: 85, state: 'available', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'B-03', lotId: 'lot-new-p2', row: 'B', number: 3, size: 'medium', type: 'normal', walkingDistanceMeters: 105, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'B-04', lotId: 'lot-new-p2', row: 'B', number: 4, size: 'medium', type: 'normal', walkingDistanceMeters: 125, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'B-05', lotId: 'lot-new-p2', row: 'B', number: 5, size: 'medium', type: 'normal', walkingDistanceMeters: 145, state: 'available', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'B-06', lotId: 'lot-new-p2', row: 'B', number: 6, size: 'medium', type: 'normal', walkingDistanceMeters: 165, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'C-01', lotId: 'lot-new-p2', row: 'C', number: 1, size: 'large', type: 'normal', walkingDistanceMeters: 90, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'C-02', lotId: 'lot-new-p2', row: 'C', number: 2, size: 'large', type: 'normal', walkingDistanceMeters: 110, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'C-03', lotId: 'lot-new-p2', row: 'C', number: 3, size: 'large', type: 'normal', walkingDistanceMeters: 130, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'C-04', lotId: 'lot-new-p2', row: 'C', number: 4, size: 'large', type: 'normal', walkingDistanceMeters: 150, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'C-05', lotId: 'lot-new-p2', row: 'C', number: 5, size: 'large', type: 'normal', walkingDistanceMeters: 170, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'C-06', lotId: 'lot-new-p2', row: 'C', number: 6, size: 'large', type: 'normal', walkingDistanceMeters: 190, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'D-01', lotId: 'lot-new-p2', row: 'D', number: 1, size: 'small', type: 'normal', walkingDistanceMeters: 120, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'D-02', lotId: 'lot-new-p2', row: 'D', number: 2, size: 'small', type: 'normal', walkingDistanceMeters: 140, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'D-03', lotId: 'lot-new-p2', row: 'D', number: 3, size: 'small', type: 'normal', walkingDistanceMeters: 160, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'D-04', lotId: 'lot-new-p2', row: 'D', number: 4, size: 'small', type: 'normal', walkingDistanceMeters: 180, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'D-05', lotId: 'lot-new-p2', row: 'D', number: 5, size: 'small', type: 'normal', walkingDistanceMeters: 200, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'D-06', lotId: 'lot-new-p2', row: 'D', number: 6, size: 'small', type: 'normal', walkingDistanceMeters: 220, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
    ],
  },
  {
    id: 'lot-sports',
    name: 'Sports Complex',
    campusZone: 'SLIIT Malabe Campus',
    latitude: 6.9160,
    longitude: 79.9745,
    distanceMeters: 450,
    hourlyRate: 50,
    totalSlots: 18,
    freeSlots: 0,
    openingHours: '06:00 AM - 10:00 PM',
    updatedAt: new Date().toISOString(),
    slots: [
      { id: 'A-01', lotId: 'lot-sports', row: 'A', number: 1, size: 'medium', type: 'normal', walkingDistanceMeters: 210, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'A-02', lotId: 'lot-sports', row: 'A', number: 2, size: 'medium', type: 'normal', walkingDistanceMeters: 230, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'A-03', lotId: 'lot-sports', row: 'A', number: 3, size: 'medium', type: 'normal', walkingDistanceMeters: 250, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'A-04', lotId: 'lot-sports', row: 'A', number: 4, size: 'medium', type: 'normal', walkingDistanceMeters: 270, state: 'blocked', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'A-05', lotId: 'lot-sports', row: 'A', number: 5, size: 'medium', type: 'normal', walkingDistanceMeters: 290, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'A-06', lotId: 'lot-sports', row: 'A', number: 6, size: 'medium', type: 'normal', walkingDistanceMeters: 310, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'B-01', lotId: 'lot-sports', row: 'B', number: 1, size: 'medium', type: 'normal', walkingDistanceMeters: 220, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'B-02', lotId: 'lot-sports', row: 'B', number: 2, size: 'medium', type: 'normal', walkingDistanceMeters: 240, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'B-03', lotId: 'lot-sports', row: 'B', number: 3, size: 'medium', type: 'normal', walkingDistanceMeters: 260, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'B-04', lotId: 'lot-sports', row: 'B', number: 4, size: 'medium', type: 'normal', walkingDistanceMeters: 280, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'B-05', lotId: 'lot-sports', row: 'B', number: 5, size: 'medium', type: 'normal', walkingDistanceMeters: 300, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'B-06', lotId: 'lot-sports', row: 'B', number: 6, size: 'medium', type: 'normal', walkingDistanceMeters: 320, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'C-01', lotId: 'lot-sports', row: 'C', number: 1, size: 'large', type: 'normal', walkingDistanceMeters: 250, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'C-02', lotId: 'lot-sports', row: 'C', number: 2, size: 'large', type: 'normal', walkingDistanceMeters: 270, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'C-03', lotId: 'lot-sports', row: 'C', number: 3, size: 'large', type: 'normal', walkingDistanceMeters: 290, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'C-04', lotId: 'lot-sports', row: 'C', number: 4, size: 'large', type: 'normal', walkingDistanceMeters: 310, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'C-05', lotId: 'lot-sports', row: 'C', number: 5, size: 'large', type: 'normal', walkingDistanceMeters: 330, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
      { id: 'C-06', lotId: 'lot-sports', row: 'C', number: 6, size: 'large', type: 'normal', walkingDistanceMeters: 350, state: 'occupied', bookingId: null, updatedAt: new Date().toISOString(), updatedBy: 'system' },
    ],
  },
];

/**
 * Migrates existing `slots` arrays or seeds default parking lots and their `slots` subcollections.
 */
export async function migrateOrSeedLots(db: admin.firestore.Firestore): Promise<{
  migratedLots: number;
  migratedSlots: number;
}> {
  let migratedLots = 0;
  let migratedSlots = 0;

  // Check existing lots in `parking_lots` (or legacy `lots`)
  const lotsSnap = await db.collection('parking_lots').get();

  if (!lotsSnap.empty) {
    // Migration: extract slots array to subcollections
    for (const lotDoc of lotsSnap.docs) {
      const data = lotDoc.data();
      const slotsArray = data.slots as Array<any> | undefined;

      if (Array.isArray(slotsArray) && slotsArray.length > 0) {
        const batch = db.batch();
        let freeCount = 0;

        for (const slot of slotsArray) {
          const slotId = slot.id || `${slot.row}-${slot.number}`;
          const subSlotRef = db
            .collection('parking_lots')
            .doc(lotDoc.id)
            .collection('slots')
            .doc(slotId);

          const slotState = (slot.state === 'free' || slot.state === 'available')
            ? 'available'
            : (slot.state === 'blocked' ? 'blocked' : 'occupied');

          if (slotState === 'available') {
            freeCount++;
          }

          const slotDocData: ParkingSlotDocument = {
            id: slotId,
            lotId: lotDoc.id,
            row: slot.row || 'A',
            number: Number(slot.number || 1),
            size: slot.size || 'medium',
            type: slot.type || 'normal',
            walkingDistanceMeters: Number(slot.walkingDistanceMeters || 100),
            state: slotState,
            bookingId: null,
            updatedAt: new Date().toISOString(),
            updatedBy: 'system',
          };

          batch.set(subSlotRef, slotDocData, { merge: true });
          migratedSlots++;
        }

        // Update lot doc, remove embedded slots array, keep counters
        batch.update(lotDoc.ref, {
          slots: admin.firestore.FieldValue.delete(),
          freeSlots: freeCount,
          totalSlots: slotsArray.length,
          updatedAt: new Date().toISOString(),
        });

        await batch.commit();
        migratedLots++;
      }
    }
  } else {
    // Seed new structure directly
    for (const seedLot of SEED_LOTS) {
      const { slots, ...lotData } = seedLot;
      const lotRef = db.collection('parking_lots').doc(seedLot.id);
      await lotRef.set(lotData);

      const batch = db.batch();
      for (const slot of slots) {
        const slotRef = lotRef.collection('slots').doc(slot.id);
        batch.set(slotRef, slot);
        migratedSlots++;
      }
      await batch.commit();
      migratedLots++;
    }
  }

  return { migratedLots, migratedSlots };
}

// Standalone execution if run via CLI
if (require.main === module) {
  if (admin.apps.length === 0) {
    admin.initializeApp();
  }
  const db = admin.firestore();
  console.log('Starting Firestore parking_lots subcollection migration...');
  migrateOrSeedLots(db)
    .then((result) => {
      console.log(`Migration successful: ${result.migratedLots} lots and ${result.migratedSlots} subcollection slots updated.`);
      process.exit(0);
    })
    .catch((err) => {
      console.error('Migration failed:', err);
      process.exit(1);
    });
}
