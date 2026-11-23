// scoring.test.ts
// Smart Parking (J26-IT-335) — Shared Scoring Test Vectors Parity Test (TypeScript / Mocha)

import { expect } from 'chai';
import * as fs from 'fs';
import * as path from 'path';
import {
  scoreSlot,
  ParkingSlotData,
  ParkingLotData,
  VehicleData,
  UserPreferencesData,
} from '../src/scoring';

interface TestVector {
  id: string;
  description: string;
  slot: {
    id: string;
    row: string;
    number: number;
    size: 'small' | 'medium' | 'large';
    type: 'normal' | 'disabled' | 'ev' | 'covered';
    walkingDistanceMeters: number;
    state: 'available' | 'reserved' | 'held' | 'occupied' | 'blocked';
  };
  lot: {
    totalSlots: number;
    freeSlots: number;
  };
  vehicle: {
    size: 'small' | 'medium' | 'large';
    type: string;
  };
  preferences: {
    preferNearEntrance: boolean;
    coveredParkingOnly: boolean;
  };
  expected: {
    isEligible: boolean;
    distanceScore: number;
    sizeFitScore: number;
    preferenceScore: number;
    demandPenalty: number;
    totalScore: number;
  };
}

describe('Scoring Engine Shared Test Vectors Parity (TypeScript)', () => {
  let testVectors: TestVector[];

  before(() => {
    let vectorFilePath = path.resolve(process.cwd(), 'test_vectors/scoring_test_vectors.json');
    if (!fs.existsSync(vectorFilePath)) {
      vectorFilePath = path.resolve(process.cwd(), '../test_vectors/scoring_test_vectors.json');
    }
    expect(fs.existsSync(vectorFilePath)).to.be.true;
    const raw = fs.readFileSync(vectorFilePath, 'utf-8');
    testVectors = JSON.parse(raw);
  });

  it('proves 100% mathematical parity against Dart ReoptimizationEngine calculations', () => {
    for (const vec of testVectors) {
      const slot: ParkingSlotData = {
        id: vec.slot.id,
        row: vec.slot.row,
        number: vec.slot.number,
        size: vec.slot.size,
        type: vec.slot.type,
        walkingDistanceMeters: vec.slot.walkingDistanceMeters,
        state: vec.slot.state,
      };

      const lot: ParkingLotData = {
        totalSlots: vec.lot.totalSlots,
        freeSlots: vec.lot.freeSlots,
      };

      const vehicle: VehicleData = {
        size: vec.vehicle.size,
        type: vec.vehicle.type,
      };

      const preferences: UserPreferencesData = {
        preferNearEntrance: vec.preferences.preferNearEntrance,
        coveredParkingOnly: vec.preferences.coveredParkingOnly,
      };

      const result = scoreSlot(slot, lot, vehicle, preferences);

      expect(result.isEligible).to.equal(
        vec.expected.isEligible,
        `[${vec.id}] isEligible mismatch`
      );

      if (vec.expected.isEligible) {
        expect(result.distanceScore).to.be.closeTo(
          vec.expected.distanceScore,
          0.001,
          `[${vec.id}] distanceScore mismatch`
        );
        expect(result.sizeFitScore).to.be.closeTo(
          vec.expected.sizeFitScore,
          0.001,
          `[${vec.id}] sizeFitScore mismatch`
        );
        expect(result.preferenceScore).to.be.closeTo(
          vec.expected.preferenceScore,
          0.001,
          `[${vec.id}] preferenceScore mismatch`
        );
        expect(result.demandPenalty).to.be.closeTo(
          vec.expected.demandPenalty,
          0.001,
          `[${vec.id}] demandPenalty mismatch`
        );
        expect(result.totalScore).to.be.closeTo(
          vec.expected.totalScore,
          0.001,
          `[${vec.id}] totalScore mismatch`
        );
      }
    }
  });
});
