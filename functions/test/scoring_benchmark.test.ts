// scoring_benchmark.test.ts
// Smart Parking (J26-IT-335) — Algorithmic Scoring Latency Benchmark (Node.js / TypeScript)

import { expect } from 'chai';
import {
  scoreSlot,
  ParkingSlotData,
  ParkingLotData,
  VehicleData,
  UserPreferencesData,
} from '../src/scoring';

describe('Scoring Engine Latency Benchmark (TypeScript)', function () {
  this.timeout(30000);

  it('measures p50, p95, p99 scoring latency over 10,000 iterations', () => {
    const slot: ParkingSlotData = {
      id: 'slot-bench-01',
      row: 'A',
      number: 1,
      size: 'medium',
      type: 'covered',
      walkingDistanceMeters: 45.0,
      state: 'available',
    };

    const lot: ParkingLotData = {
      totalSlots: 72,
      freeSlots: 18,
    };

    const vehicle: VehicleData = {
      size: 'medium',
      type: 'car',
    };

    const preferences: UserPreferencesData = {
      preferNearEntrance: true,
      coveredParkingOnly: true,
    };

    const iterations = 10000;
    const latenciesMs: number[] = new Array(iterations);

    // Warm-up JIT
    for (let i = 0; i < 500; i++) {
      scoreSlot(slot, lot, vehicle, preferences);
    }

    // Benchmark loop with high-resolution timer
    for (let i = 0; i < iterations; i++) {
      const t0 = process.hrtime.bigint();
      scoreSlot(slot, lot, vehicle, preferences);
      const t1 = process.hrtime.bigint();
      const elapsedNs = Number(t1 - t0);
      latenciesMs[i] = elapsedNs / 1_000_000.0; // convert to ms
    }

    latenciesMs.sort((a, b) => a - b);

    const p50 = latenciesMs[Math.floor(iterations * 0.50)];
    const p95 = latenciesMs[Math.floor(iterations * 0.95)];
    const p99 = latenciesMs[Math.floor(iterations * 0.99)];
    const avg = latenciesMs.reduce((a, b) => a + b, 0) / iterations;

    console.log('\n--- TypeScript Scoring Engine Latency Benchmark ---');
    console.log(`Iterations: ${iterations}`);
    console.log(`Average:    ${(avg * 1000).toFixed(2)} µs (${avg.toFixed(4)} ms)`);
    console.log(`p50:        ${(p50 * 1000).toFixed(2)} µs (${p50.toFixed(4)} ms)`);
    console.log(`p95:        ${(p95 * 1000).toFixed(2)} µs (${p95.toFixed(4)} ms)`);
    console.log(`p99:        ${(p99 * 1000).toFixed(2)} µs (${p99.toFixed(4)} ms)`);
    console.log('---------------------------------------------------\n');

    // Assert real-time guarantee: p99 latency must be under 1ms
    expect(p99).to.be.lessThan(1.0);
  });
});
